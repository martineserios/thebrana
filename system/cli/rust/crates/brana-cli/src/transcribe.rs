//! Audio transcription via whisper.cpp (whisper-cli binary)
//!
//! Shells out to whisper-cli for fast CPU inference.
//! Handles format conversion via ffmpeg when needed.

use anyhow::{bail, Context, Result};
use std::path::{Path, PathBuf};
use std::process::Command;

/// Which whisper model size to use
#[derive(Clone, Debug)]
pub enum ModelSize {
    Tiny,
    Base,
    Small,
}

impl ModelSize {
    fn ggml_filename(&self) -> &str {
        match self {
            ModelSize::Tiny => "ggml-tiny.bin",
            ModelSize::Base => "ggml-base.bin",
            ModelSize::Small => "ggml-small.bin",
        }
    }

    fn download_url(&self) -> String {
        format!(
            "https://huggingface.co/ggerganov/whisper.cpp/resolve/main/{}",
            self.ggml_filename()
        )
    }
}

impl std::str::FromStr for ModelSize {
    type Err = anyhow::Error;
    fn from_str(s: &str) -> Result<Self> {
        match s.to_lowercase().as_str() {
            "tiny" => Ok(ModelSize::Tiny),
            "base" => Ok(ModelSize::Base),
            "small" => Ok(ModelSize::Small),
            _ => bail!("unknown model size: {s}. Use: tiny, base, small"),
        }
    }
}

/// Get the model file path, downloading if needed.
/// Checks .brana-files.json manifest first, falls back to HuggingFace.
fn ensure_model(size: &ModelSize) -> Result<PathBuf> {
    if let Some(path) = try_manifest_model(size) {
        return Ok(path);
    }

    let home = std::env::var("HOME").unwrap_or_else(|_| ".".into());
    let dir = PathBuf::from(home).join(".cache").join("whisper-models");
    std::fs::create_dir_all(&dir)?;

    let model_path = dir.join(size.ggml_filename());
    if model_path.exists() && std::fs::metadata(&model_path).map(|m| m.len() > 1000).unwrap_or(false) {
        return Ok(model_path);
    }

    let url = size.download_url();
    eprintln!("Downloading {}...", size.ggml_filename());
    let status = Command::new("curl")
        .args(["-L", "-o"])
        .arg(&model_path)
        .arg(&url)
        .status()
        .context("curl not found — install curl or manually download model")?;
    if !status.success() {
        bail!("failed to download model from {url}");
    }
    Ok(model_path)
}

fn try_manifest_model(size: &ModelSize) -> Option<PathBuf> {
    use crate::files;
    use crate::util::find_project_root;

    let root = find_project_root()?;
    let manifest = files::Manifest::load(&root).ok()?;
    let model_name = size.ggml_filename();

    for (_name, entry) in &manifest.files {
        if entry.path.contains(model_name) {
            let full_path = if Path::new(&entry.path).is_absolute() {
                PathBuf::from(&entry.path)
            } else {
                root.join(&entry.path)
            };

            if full_path.exists() {
                if let Ok(hash) = files::file_sha256(&full_path) {
                    if hash == entry.sha256 {
                        eprintln!("Using manifest-tracked model: {}", entry.path);
                        return Some(full_path);
                    }
                }
            } else if let Some(url) = &entry.url {
                eprintln!("Downloading tracked model: {}", entry.path);
                if files::download_file(url, &full_path).is_ok() {
                    if let Ok(hash) = files::file_sha256(&full_path) {
                        if hash == entry.sha256 {
                            return Some(full_path);
                        }
                    }
                }
            }
        }
    }
    None
}

/// Convert audio to WAV 16kHz mono if needed (whisper-cli needs wav for some formats).
fn ensure_wav(path: &Path) -> Result<PathBuf> {
    let ext = path.extension().and_then(|e| e.to_str()).unwrap_or("");

    // whisper-cli handles wav, mp3, and ogg/vorbis natively
    // But Opus-in-ogg and m4a need conversion
    match ext.to_lowercase().as_str() {
        "wav" | "mp3" => Ok(path.to_path_buf()),
        _ => {
            // Convert to wav via ffmpeg
            let tmp = std::env::temp_dir().join("brana-transcribe.wav");
            let status = Command::new("ffmpeg")
                .args([
                    "-i",
                    path.to_str().ok_or_else(|| anyhow::anyhow!("invalid path"))?,
                    "-ar", "16000",
                    "-ac", "1",
                    "-c:a", "pcm_s16le",
                    "-y",
                    "-v", "error",
                ])
                .arg(&tmp)
                .status()
                .context("ffmpeg not found — install ffmpeg for this audio format")?;
            if !status.success() {
                bail!("ffmpeg conversion failed");
            }
            Ok(tmp)
        }
    }
}

/// Transcribe an audio file to text.
pub fn transcribe(audio_path: &Path, model_size: &ModelSize) -> Result<String> {
    // 1. Check whisper-cli is available
    let whisper = which_whisper_cli()?;

    // 2. Ensure model is downloaded
    let model_path = ensure_model(model_size)?;

    // 3. Convert audio if needed
    eprintln!("Preparing audio...");
    let wav_path = ensure_wav(audio_path)?;

    // 4. Run whisper-cli
    eprintln!("Transcribing...");
    let output = Command::new(&whisper)
        .args([
            "-m",
            model_path.to_str().unwrap(),
            "-f",
            wav_path.to_str().unwrap(),
            "--no-timestamps",
            "-t", "4",
            "-l", "auto",
            "--print-special", "false",
            "-otxt",         // output as text
            "-of", "/dev/stdout", // to stdout
        ])
        .output()
        .context("failed to run whisper-cli")?;

    // Clean up temp file
    if wav_path != audio_path {
        let _ = std::fs::remove_file(&wav_path);
    }

    if !output.status.success() {
        let stderr = String::from_utf8_lossy(&output.stderr);
        bail!("whisper-cli failed: {stderr}");
    }

    // whisper-cli outputs to stderr (model info) and stdout (text)
    // With -otxt -of /dev/stdout, text goes to the output file
    // But let's try parsing stdout first
    let text = String::from_utf8_lossy(&output.stdout)
        .replace("[_EOT_]", "")
        .trim()
        .to_string();

    if text.is_empty() {
        // whisper-cli might have written to stderr with the text mixed in
        let stderr = String::from_utf8_lossy(&output.stderr);
        // Extract text lines (lines not starting with whisper_ or system_info or main:)
        let text: String = stderr
            .lines()
            .filter(|l| {
                !l.starts_with("whisper_")
                    && !l.starts_with("system_info")
                    && !l.starts_with("main:")
                    && !l.is_empty()
                    && !l.starts_with("error:")
            })
            .collect::<Vec<_>>()
            .join(" ")
            .replace("[_EOT_]", "")
            .trim()
            .to_string();
        Ok(text)
    } else {
        Ok(text)
    }
}

fn which_whisper_cli() -> Result<PathBuf> {
    // Check common locations
    for name in ["whisper-cli", "whisper"] {
        if let Ok(output) = Command::new("which").arg(name).output() {
            if output.status.success() {
                let path = String::from_utf8_lossy(&output.stdout).trim().to_string();
                return Ok(PathBuf::from(path));
            }
        }
    }

    // Check ~/.local/bin explicitly
    let local_bin = PathBuf::from(std::env::var("HOME").unwrap_or_default())
        .join(".local/bin/whisper-cli");
    if local_bin.exists() {
        return Ok(local_bin);
    }

    bail!(
        "whisper-cli not found. Install it:\n\
         \n\
         # Build from source:\n\
         git clone https://github.com/ggerganov/whisper.cpp\n\
         cd whisper.cpp && cmake -B build && cmake --build build\n\
         cp build/bin/whisper-cli ~/.local/bin/"
    )
}

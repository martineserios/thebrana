//! Audio transcription via whisper.cpp (whisper-cli binary)
//!
//! Shells out to whisper-cli for fast CPU inference.
//! Handles format conversion via ffmpeg when needed.

use anyhow::{bail, Context, Result};
use std::path::{Path, PathBuf};
use std::process::Command;

/// An installed whisper ggml model.
#[derive(Clone, Debug)]
pub struct Model {
    /// Name without the `ggml-` prefix and `.bin` suffix (e.g. `large-v3`).
    pub name: String,
    pub path: PathBuf,
    pub size: u64,
}

/// Model used when none is installed and none is requested.
const FALLBACK_MODEL: &str = "small";

/// Options for a transcription run.
#[derive(Clone, Debug)]
pub struct Options {
    /// Model name (`large-v3`) or path to a ggml file; `None` = largest installed.
    pub model: Option<String>,
    /// Video only: extract frames into this directory.
    pub frames_dir: Option<PathBuf>,
    /// Seconds between extracted frames.
    pub every: u32,
}

/// First 4 bytes of every whisper.cpp ggml model file ("ggml" as a little-endian u32).
const GGML_MAGIC: [u8; 4] = *b"lmgg";

/// True if the file starts with the ggml magic — rejects error pages, captive-portal bodies
/// and other non-model files that happen to be named `ggml-*.bin`.
fn has_ggml_magic(path: &Path) -> bool {
    use std::io::Read;
    let mut head = [0u8; 4];
    std::fs::File::open(path)
        .and_then(|mut f| f.read_exact(&mut head))
        .map(|_| head == GGML_MAGIC)
        .unwrap_or(false)
}

const VIDEO_EXTS: [&str; 6] = ["mp4", "mkv", "mov", "webm", "avi", "m4v"];

fn ggml_filename(name: &str) -> String {
    format!("ggml-{name}.bin")
}

fn download_url(name: &str) -> String {
    format!(
        "https://huggingface.co/ggerganov/whisper.cpp/resolve/main/{}",
        ggml_filename(name)
    )
}

/// Model names become file names and URL segments — keep them to a safe charset.
fn validate_model_name(name: &str) -> Result<()> {
    let ok = !name.is_empty()
        && !name.starts_with('.')
        && name.chars().all(|c| c.is_ascii_alphanumeric() || matches!(c, '.' | '-' | '_'));
    if !ok {
        bail!("invalid model name: {name:?} (use e.g. tiny, base, small, medium, large-v3)");
    }
    Ok(())
}

/// A `--model` value is a path when it contains a separator or names an existing file.
fn is_model_path(spec: &str) -> bool {
    spec.contains('/') || Path::new(spec).is_file()
}

/// Directories searched for installed models, in priority order.
fn model_dirs() -> Vec<PathBuf> {
    let mut dirs: Vec<PathBuf> = std::env::var("BRANA_WHISPER_MODELS")
        .map(|v| v.split(':').filter(|s| !s.is_empty()).map(PathBuf::from).collect())
        .unwrap_or_default();
    let home = std::env::var("HOME").unwrap_or_else(|_| ".".into());
    dirs.push(PathBuf::from(home).join(".cache").join("whisper-models"));
    dirs
}

/// List every `ggml-<name>.bin` in `dirs` (earlier dir wins for a repeated name).
/// Files of 1000 bytes or less are treated as failed downloads and skipped.
fn discover_models_in(dirs: &[PathBuf]) -> Vec<Model> {
    let mut found: Vec<Model> = Vec::new();
    for dir in dirs {
        let Ok(rd) = std::fs::read_dir(dir) else { continue };
        for entry in rd.flatten() {
            let file = entry.file_name().to_string_lossy().into_owned();
            let Some(name) = file.strip_prefix("ggml-").and_then(|n| n.strip_suffix(".bin")) else {
                continue;
            };
            // Path::metadata follows symlinks (DirEntry::metadata does not).
            let Ok(meta) = entry.path().metadata() else { continue };
            let size = meta.len();
            if !meta.is_file() || size <= 1000 || found.iter().any(|m| m.name == name) {
                continue;
            }
            if !has_ggml_magic(&entry.path()) {
                eprintln!("warning: skipping {} (not a ggml model file)", entry.path().display());
                continue;
            }
            found.push(Model { name: name.to_string(), path: entry.path(), size });
        }
    }
    found
}

/// Largest model on disk is "best"; ties broken by name for determinism.
/// English-only (`.en`) models are skipped while a multilingual one exists — the run uses
/// `-l auto`, and an `.en` model would force-decode other languages as English.
fn pick_default(models: &[Model]) -> Option<&Model> {
    fn largest<'a>(it: impl Iterator<Item = &'a Model>) -> Option<&'a Model> {
        it.max_by(|a, b| a.size.cmp(&b.size).then_with(|| b.name.cmp(&a.name)))
    }
    largest(models.iter().filter(|m| !is_english_only(&m.name))).or_else(|| largest(models.iter()))
}

/// `base.en`, `medium.en-q5_0`, ... — models that only transcribe English.
fn is_english_only(name: &str) -> bool {
    name.ends_with(".en") || name.contains(".en-")
}

fn resolve_installed(name: &str, dirs: &[PathBuf]) -> Option<PathBuf> {
    discover_models_in(dirs).into_iter().find(|m| m.name == name).map(|m| m.path)
}

/// Resolve the model to run: explicit path/name, else largest installed, else download small.
fn resolve_model(spec: Option<&str>) -> Result<PathBuf> {
    resolve_model_with(spec, &model_dirs(), ensure_model)
}

/// `resolve_model` with the search dirs and downloader injected (testable without network).
fn resolve_model_with(
    spec: Option<&str>,
    dirs: &[PathBuf],
    download: impl Fn(&str) -> Result<PathBuf>,
) -> Result<PathBuf> {
    match spec {
        Some(s) if is_model_path(s) => {
            let p = PathBuf::from(s);
            if !p.is_file() {
                bail!("model file not found: {s}");
            }
            Ok(p)
        }
        Some(name) => {
            let name = name.to_lowercase();
            validate_model_name(&name)?;
            match resolve_installed(&name, dirs) {
                Some(p) => Ok(p),
                None => download(&name),
            }
        }
        None => match pick_default(&discover_models_in(dirs)) {
            Some(m) => {
                if is_english_only(&m.name) {
                    eprintln!(
                        "warning: only English-only models are installed ({}) — non-English audio \
                         will be transcribed as English. Use --model small for other languages.",
                        m.name
                    );
                }
                Ok(m.path.clone())
            }
            None => download(FALLBACK_MODEL),
        },
    }
}

/// Get a model file path by name, downloading if needed.
/// Checks .brana-files.json manifest first, falls back to HuggingFace.
fn ensure_model(name: &str) -> Result<PathBuf> {
    if let Some(path) = try_manifest_model(name) {
        return Ok(path);
    }

    let home = std::env::var("HOME").unwrap_or_else(|_| ".".into());
    let dir = PathBuf::from(home).join(".cache").join("whisper-models");
    std::fs::create_dir_all(&dir)?;

    let model_path = dir.join(ggml_filename(name));
    if std::fs::metadata(&model_path).map(|m| m.len() > 1000).unwrap_or(false) && has_ggml_magic(&model_path) {
        return Ok(model_path);
    }

    let url = download_url(name);
    eprintln!("Downloading {} to {}...", ggml_filename(name), dir.display());
    // Download to a per-process .part file and rename on success: an interrupted or
    // concurrent download never leaves a truncated `ggml-*.bin` for discovery to pick up.
    // -f: fail on HTTP errors instead of saving the error page as the model.
    let part = part_path(&model_path);
    let status = Command::new("curl")
        .args(["-fL", "-o"])
        .arg(&part)
        .arg(&url)
        .status()
        .context("curl not found — install curl or manually download model")?;
    if !status.success() {
        let _ = std::fs::remove_file(&part);
        bail!("failed to download model from {url}");
    }
    // A 200 OK can still be a non-model body (captive portal, proxy error page).
    if !has_ggml_magic(&part) {
        let _ = std::fs::remove_file(&part);
        bail!("downloaded {url} is not a ggml model file");
    }
    std::fs::rename(&part, &model_path).context("failed to move downloaded model into place")?;
    Ok(model_path)
}

/// In-progress download path for `target` — never matches `ggml-*.bin` discovery.
fn part_path(target: &Path) -> PathBuf {
    let mut name = target.file_name().unwrap_or_default().to_os_string();
    name.push(format!(".part-{}", std::process::id()));
    target.with_file_name(name)
}

fn try_manifest_model(name: &str) -> Option<PathBuf> {
    use crate::files;
    use crate::util::find_project_root;

    let root = find_project_root()?;
    let manifest = files::Manifest::load(&root).ok()?;
    let model_name = ggml_filename(name);

    for (_name, entry) in &manifest.files {
        if entry.path.contains(&model_name) {
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

/// Audio handed to whisper-cli: the input itself, or a converted temp file that is
/// removed when dropped (on every return path, including errors).
enum Wav {
    Original(PathBuf),
    Temp(tempfile::TempPath),
}

impl Wav {
    fn path(&self) -> &Path {
        match self {
            Wav::Original(p) => p,
            Wav::Temp(t) => t,
        }
    }
}

/// Convert audio (or a video's audio track) to WAV 16kHz mono if needed.
fn ensure_wav(path: &Path) -> Result<Wav> {
    let ext = path.extension().and_then(|e| e.to_str()).unwrap_or("");

    // whisper-cli handles wav, mp3, and ogg/vorbis natively
    // But Opus-in-ogg, m4a and video containers need conversion
    match ext.to_lowercase().as_str() {
        "wav" | "mp3" => Ok(Wav::Original(path.to_path_buf())),
        _ => {
            // Unique per run (created exclusively), so concurrent runs never share a file.
            let tmp = tempfile::Builder::new()
                .prefix("brana-transcribe-")
                .suffix(".wav")
                .tempfile()
                .context("failed to create temp wav")?
                .into_temp_path();
            let status = Command::new("ffmpeg")
                .args(["-nostdin", "-v", "error", "-y", "-i"])
                .arg(path)
                .args(["-vn", "-ar", "16000", "-ac", "1", "-c:a", "pcm_s16le"])
                .arg(&*tmp)
                .status()
                .context("ffmpeg not found — install ffmpeg for this audio format")?;
            if !status.success() {
                bail!("ffmpeg conversion failed (no audio track?)");
            }
            Ok(Wav::Temp(tmp))
        }
    }
}

/// whisper-cli arguments. Transcript goes to stdout; segment timestamps only when asked.
fn whisper_args(model: &Path, wav: &Path, timestamps: bool) -> Result<Vec<String>> {
    let utf8 = |p: &Path| {
        p.to_str()
            .map(str::to_string)
            .ok_or_else(|| anyhow::anyhow!("path is not valid UTF-8: {}", p.display()))
    };
    let mut args = vec!["-m".to_string(), utf8(model)?, "-f".to_string(), utf8(wav)?];
    if !timestamps {
        args.push("--no-timestamps".into());
    }
    args.extend(["-t", "4", "-l", "auto"].map(String::from));
    Ok(args)
}

/// True for container formats that carry a video stream.
fn is_video(path: &Path) -> bool {
    path.extension()
        .and_then(|e| e.to_str())
        .map(|e| VIDEO_EXTS.contains(&e.to_lowercase().as_str()))
        .unwrap_or(false)
}

/// ffmpeg arguments that sample one JPEG every `every` seconds into `dir`.
/// `showinfo` logs each kept frame's real `pts_time` (at info level, hence `-loglevel info`),
/// which labels the frames — sampling never decides the label.
/// Requires ffmpeg >= 5.1 (`-fps_mode`).
fn frames_ffmpeg_args(input: &Path, dir: &Path, every: u32) -> Vec<String> {
    vec![
        "-hide_banner".into(),
        "-nostdin".into(),
        "-loglevel".into(), "info".into(),
        "-y".into(),
        "-i".into(), input.display().to_string(),
        // `select` keeps the first frame, then the first frame >= N s after the last kept one.
        // (`fps=1/N` rounds to the nearest tick and was measured shifting frames by seconds.)
        "-vf".into(),
        format!("select='isnan(prev_selected_t)+gte(t-prev_selected_t\\,{every})',showinfo"),
        "-fps_mode".into(), "vfr".into(),
        "-q:v".into(), "2".into(),
        // `%` is ffmpeg's image2 pattern char — escape it in the directory part.
        format!("{}/frame_%06d.jpg", dir.display().to_string().replace('%', "%%")),
    ]
}

/// `pts_time` of every frame `showinfo` reported, in output order.
fn parse_pts_times(stderr: &str) -> Vec<f64> {
    stderr
        .lines()
        .filter(|l| l.contains("Parsed_showinfo"))
        .filter_map(|l| l.split("pts_time:").nth(1))
        .filter_map(|rest| rest.split_whitespace().next()?.parse().ok())
        .collect()
}

fn format_ts(secs: u64) -> String {
    format!("{:02}:{:02}:{:02}", secs / 3600, (secs % 3600) / 60, secs % 60)
}

/// One `<file> @ HH:MM:SS` line per frame, labelled with the frame's real time.
fn frame_index(files: &[String], times: &[f64]) -> Vec<String> {
    files
        .iter()
        .zip(times)
        .map(|(f, t)| format!("{f} @ {}", format_ts(t.max(0.0) as u64)))
        .collect()
}

/// Frames written by this run; removed on drop unless `keep()` is called, so a run that
/// fails after extraction leaves the directory as it found it (and the retry isn't refused).
struct FramesGuard {
    files: Vec<PathBuf>,
}

impl FramesGuard {
    fn new(files: Vec<PathBuf>) -> Self {
        FramesGuard { files }
    }

    fn keep(mut self) {
        self.files.clear();
    }
}

impl Drop for FramesGuard {
    fn drop(&mut self) {
        for f in &self.files {
            let _ = std::fs::remove_file(f);
        }
    }
}

fn validate_options(opts: &Options, input: &Path) -> Result<()> {
    if opts.frames_dir.is_some() {
        if !is_video(input) {
            bail!("--frames needs a video input ({})", VIDEO_EXTS.join(", "));
        }
        if opts.every == 0 {
            bail!("--every must be at least 1 second");
        }
    }
    Ok(())
}

/// Refuse a frames dir that already holds frames: the index is built from the directory,
/// so leftovers from an earlier run would be listed with timestamps they don't have.
fn check_frames_dir(dir: &Path) -> Result<()> {
    let Ok(rd) = std::fs::read_dir(dir) else { return Ok(()) };
    let stale = rd
        .flatten()
        .any(|e| e.file_name().to_string_lossy().starts_with("frame_"));
    if stale {
        bail!("{} already contains frame_* files — use an empty or new --frames directory", dir.display());
    }
    Ok(())
}

/// Extract frames; returns the index lines and a guard owning the written files.
fn extract_frames(input: &Path, dir: &Path, every: u32) -> Result<(Vec<String>, FramesGuard)> {
    check_frames_dir(dir)?;
    std::fs::create_dir_all(dir)?;
    let output = Command::new("ffmpeg")
        .args(frames_ffmpeg_args(input, dir, every))
        .output()
        .context("ffmpeg not found — install ffmpeg (>= 5.1) to extract frames")?;
    let mut files: Vec<String> = std::fs::read_dir(dir)?
        .flatten()
        .map(|e| e.file_name().to_string_lossy().into_owned())
        .filter(|n| n.starts_with("frame_") && n.ends_with(".jpg"))
        .collect();
    files.sort();
    let guard = FramesGuard::new(files.iter().map(|f| dir.join(f)).collect());
    if !output.status.success() {
        let stderr = String::from_utf8_lossy(&output.stderr);
        let last = stderr.lines().rev().find(|l| !l.trim().is_empty()).unwrap_or("");
        bail!("ffmpeg frame extraction failed: {last}");
    }
    let times = parse_pts_times(&String::from_utf8_lossy(&output.stderr));
    if times.len() != files.len() {
        bail!("ffmpeg reported {} frame times for {} frames", times.len(), files.len());
    }
    Ok((frame_index(&files, &times), guard))
}

/// whisper-cli failed: name the model it was given (it may have been picked by default) and
/// how to recover — a truncated model file passes discovery but fails to load.
fn whisper_failure_message(model: &Path, stderr: &str) -> String {
    format!(
        "whisper-cli failed with model {}.\n\
         If the model file is damaged (e.g. an interrupted download), delete it or pick another \
         with --model <name|path>.\n{stderr}",
        model.display()
    )
}

/// Transcribe an audio or video file to text. With `frames_dir` set, segment timestamps are
/// kept and a frame index is appended so speech and frames line up.
pub fn transcribe(audio_path: &Path, opts: &Options) -> Result<String> {
    validate_options(opts, audio_path)?;

    // 1. Check whisper-cli is available
    let whisper = which_whisper_cli()?;

    // 2. Resolve model
    let model_path = resolve_model(opts.model.as_deref())?;
    eprintln!("Using model: {}", model_path.display());

    // 3. Frames first — cheap, and fails fast (e.g. no video stream) before a long transcription.
    let frames = match &opts.frames_dir {
        Some(dir) => {
            eprintln!("Extracting frames...");
            Some(extract_frames(audio_path, dir, opts.every)?)
        }
        None => None,
    };

    // 4. Convert audio if needed (video → wav via ffmpeg)
    eprintln!("Preparing audio...");
    let wav = ensure_wav(audio_path)?;

    // 5. Run whisper-cli
    eprintln!("Transcribing...");
    let output = Command::new(&whisper)
        .env("LD_LIBRARY_PATH", whisper_ld_library_path())
        .args(whisper_args(&model_path, wav.path(), frames.is_some())?)
        .output()
        .context("failed to run whisper-cli")?;
    drop(wav);

    if !output.status.success() {
        bail!("{}", whisper_failure_message(&model_path, &String::from_utf8_lossy(&output.stderr)));
    }

    // whisper-cli prints model info to stderr and the transcript to stdout
    let text = String::from_utf8_lossy(&output.stdout)
        .replace("[_EOT_]", "")
        .trim()
        .to_string();

    let text = if text.is_empty() {
        // whisper-cli might have written to stderr with the text mixed in
        let stderr = String::from_utf8_lossy(&output.stderr);
        // Extract text lines (lines not starting with whisper_ or system_info or main:)
        stderr
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
            .to_string()
    } else {
        text
    };

    match (frames, &opts.frames_dir) {
        (Some((index, guard)), Some(dir)) => {
            guard.keep();
            Ok(format!(
            "{text}\n\nFrames ({} every {}s):\n{}",
            dir.display(),
            opts.every,
            index.join("\n")
            ))
        }
        _ => Ok(text),
    }
}

/// Build LD_LIBRARY_PATH that includes ~/.local/lib for libwhisper.so.1.
/// Prepends to any existing LD_LIBRARY_PATH so the caller's env is preserved.
fn whisper_ld_library_path() -> String {
    let home = std::env::var("HOME").unwrap_or_default();
    let existing = std::env::var("LD_LIBRARY_PATH").ok();
    whisper_ld_library_path_from(&home, existing.as_deref())
}

fn whisper_ld_library_path_from(home: &str, existing_ld: Option<&str>) -> String {
    let local_lib = format!("{home}/.local/lib");
    match existing_ld {
        Some(e) if !e.is_empty() => format!("{local_lib}:{e}"),
        _ => local_lib,
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

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn test_ld_library_path_standalone() {
        let result = whisper_ld_library_path_from("/home/user", None);
        assert_eq!(result, "/home/user/.local/lib");
    }

    #[test]
    fn test_ld_library_path_standalone_empty_existing() {
        let result = whisper_ld_library_path_from("/home/user", Some(""));
        assert_eq!(result, "/home/user/.local/lib");
    }

    #[test]
    fn test_ld_library_path_prepends_existing() {
        let result = whisper_ld_library_path_from("/home/user", Some("/usr/lib:/other/lib"));
        assert_eq!(result, "/home/user/.local/lib:/usr/lib:/other/lib");
    }

    // ── t-3470: model discovery / selection ─────────────────────────────

    fn write_model(dir: &Path, name: &str, bytes: usize) {
        let mut data = vec![0u8; bytes];
        data[..4].copy_from_slice(&GGML_MAGIC);
        std::fs::write(dir.join(name), data).unwrap();
    }

    #[test]
    fn discover_finds_any_ggml_model_and_ignores_stubs() {
        let d = tempfile::tempdir().unwrap();
        write_model(d.path(), "ggml-base.bin", 2000);
        write_model(d.path(), "ggml-large-v3.bin", 5000);
        write_model(d.path(), "ggml-tiny.bin", 10); // truncated stub
        write_model(d.path(), "notes.txt", 9000);
        let mut names: Vec<String> = discover_models_in(&[d.path().to_path_buf()])
            .into_iter()
            .map(|m| m.name)
            .collect();
        names.sort();
        assert_eq!(names, vec!["base", "large-v3"]);
    }

    #[test]
    fn default_is_largest_installed_model() {
        let d = tempfile::tempdir().unwrap();
        write_model(d.path(), "ggml-base.bin", 2000);
        write_model(d.path(), "ggml-medium.bin", 8000);
        write_model(d.path(), "ggml-small.bin", 4000);
        let models = discover_models_in(&[d.path().to_path_buf()]);
        assert_eq!(pick_default(&models).unwrap().name, "medium");
    }

    #[test]
    fn default_is_none_when_nothing_installed() {
        let d = tempfile::tempdir().unwrap();
        assert!(pick_default(&discover_models_in(&[d.path().to_path_buf()])).is_none());
    }

    #[test]
    fn earlier_dir_wins_for_same_model_name() {
        let a = tempfile::tempdir().unwrap();
        let b = tempfile::tempdir().unwrap();
        write_model(a.path(), "ggml-base.bin", 2000);
        write_model(b.path(), "ggml-base.bin", 3000);
        let models = discover_models_in(&[a.path().to_path_buf(), b.path().to_path_buf()]);
        assert_eq!(models.len(), 1);
        assert!(models[0].path.starts_with(a.path()));
    }

    #[test]
    fn model_name_validation_rejects_traversal() {
        assert!(validate_model_name("large-v3").is_ok());
        assert!(validate_model_name("medium.en").is_ok());
        assert!(validate_model_name("small-q5_0").is_ok());
        assert!(validate_model_name("../evil").is_err());
        assert!(validate_model_name("a/b").is_err());
        assert!(validate_model_name("").is_err());
    }

    #[test]
    fn model_spec_path_detection() {
        assert!(is_model_path("/tmp/x/ggml-base.bin"));
        assert!(is_model_path("./m.bin"));
        assert!(!is_model_path("large-v3"));
        assert!(!is_model_path("medium.en"));
    }

    #[test]
    fn resolve_named_model_uses_installed_file() {
        let d = tempfile::tempdir().unwrap();
        write_model(d.path(), "ggml-medium.bin", 8000);
        let p = resolve_installed("medium", &[d.path().to_path_buf()]).unwrap();
        assert_eq!(p, d.path().join("ggml-medium.bin"));
        assert!(resolve_installed("large", &[d.path().to_path_buf()]).is_none());
    }

    // ── t-3470: video + frames ──────────────────────────────────────────

    #[test]
    fn video_detection_by_extension() {
        for f in ["a.mp4", "a.MKV", "a.mov", "a.webm", "a.avi", "a.m4v"] {
            assert!(is_video(Path::new(f)), "{f}");
        }
        for f in ["a.mp3", "a.wav", "a.m4a", "a"] {
            assert!(!is_video(Path::new(f)), "{f}");
        }
    }

    #[test]
    fn frames_args_sample_every_n_seconds() {
        let args = frames_ffmpeg_args(Path::new("in.mp4"), Path::new("out"), 5);
        let joined = args.join(" ");
        assert!(joined.contains("-i in.mp4"));
        assert!(joined.contains("gte(t-prev_selected_t\\,5)',showinfo"));
        assert!(joined.ends_with("out/frame_%06d.jpg"));
        assert!(!args.contains(&"-vn".to_string()));
    }

    #[test]
    fn timestamp_formatting() {
        assert_eq!(format_ts(0), "00:00:00");
        assert_eq!(format_ts(75), "00:01:15");
        assert_eq!(format_ts(3725), "01:02:05");
    }

    #[test]
    fn frame_index_labels_use_real_frame_times() {
        let lines = frame_index(&["frame_000001.jpg".into(), "frame_000002.jpg".into()], &[0.0, 12.4]);
        assert_eq!(lines, vec!["frame_000001.jpg @ 00:00:00", "frame_000002.jpg @ 00:00:12"]);
    }

    #[test]
    fn showinfo_pts_times_are_parsed_in_order() {
        let stderr = "frame=    0 fps=0.0\n\
[Parsed_showinfo_1 @ 0x5] n:   0 pts:      0 pts_time:0       duration:1\n\
[Parsed_showinfo_1 @ 0x5] color_range:tv\n\
[Parsed_showinfo_1 @ 0x5] n:   1 pts:  61440 pts_time:12.2    duration:1\n";
        assert_eq!(parse_pts_times(stderr), vec![0.0, 12.2]);
    }

    #[test]
    fn frames_guard_removes_frames_unless_kept() {
        let d = tempfile::tempdir().unwrap();
        let f = d.path().join("frame_000001.jpg");
        std::fs::write(&f, "x").unwrap();
        drop(FramesGuard::new(vec![f.clone()]));
        assert!(!f.exists(), "failed run must not leave frames behind");
        std::fs::write(&f, "x").unwrap();
        FramesGuard::new(vec![f.clone()]).keep();
        assert!(f.exists());
    }

    #[test]
    fn options_validate_rejects_bad_combinations() {
        let ok = Options { model: None, frames_dir: None, every: 10 };
        assert!(validate_options(&ok, Path::new("a.mp3")).is_ok());
        let frames_audio = Options { model: None, frames_dir: Some("o".into()), every: 10 };
        assert!(validate_options(&frames_audio, Path::new("a.mp3")).is_err());
        assert!(validate_options(&frames_audio, Path::new("a.mp4")).is_ok());
        let zero = Options { model: None, frames_dir: Some("o".into()), every: 0 };
        assert!(validate_options(&zero, Path::new("a.mp4")).is_err());
    }

    // ── t-3470: fallback download + real frame extraction ───────────────

    #[test]
    fn no_model_installed_downloads_small() {
        let d = tempfile::tempdir().unwrap();
        let asked = std::cell::RefCell::new(Vec::new());
        let p = resolve_model_with(None, &[d.path().to_path_buf()], |n| {
            asked.borrow_mut().push(n.to_string());
            Ok(PathBuf::from(format!("/m/ggml-{n}.bin")))
        })
        .unwrap();
        assert_eq!(asked.into_inner(), vec!["small"]);
        assert_eq!(p, PathBuf::from("/m/ggml-small.bin"));
    }

    #[test]
    fn installed_default_never_downloads() {
        let d = tempfile::tempdir().unwrap();
        write_model(d.path(), "ggml-base.bin", 2000);
        let p = resolve_model_with(None, &[d.path().to_path_buf()], |_| panic!("no download"))
            .unwrap();
        assert_eq!(p, d.path().join("ggml-base.bin"));
    }

    #[test]
    fn missing_named_model_is_downloaded_by_name() {
        let d = tempfile::tempdir().unwrap();
        let p = resolve_model_with(Some("large-v3"), &[d.path().to_path_buf()], |n| {
            Ok(PathBuf::from(format!("/m/ggml-{n}.bin")))
        })
        .unwrap();
        assert_eq!(p, PathBuf::from("/m/ggml-large-v3.bin"));
        assert!(resolve_model_with(Some("../x"), &[], |_| panic!("no download")).is_err());
    }

    #[test]
    fn extract_frames_from_real_video() {
        if !ffmpeg_available() {
            return;
        }
        let d = tempfile::tempdir().unwrap();
        let video = d.path().join("t.mp4");
        let ok = Command::new("ffmpeg")
            .args(["-v", "error", "-y", "-f", "lavfi", "-i", "testsrc=d=25:s=64x48:r=5"])
            .arg(&video)
            .status()
            .unwrap()
            .success();
        assert!(ok, "fixture video generation failed");
        let out = d.path().join("frames");
        let (index, guard) = extract_frames(&video, &out, 10).unwrap();
        guard.keep();
        assert!(index.len() >= 2, "expected >=2 frames, got {index:?}");
        assert_eq!(index[0], "frame_000001.jpg @ 00:00:00");
        assert_eq!(index[1], "frame_000002.jpg @ 00:00:10");
        assert!(out.join("frame_000001.jpg").is_file());
    }

    // ── t-3470 challenger repair (iteration 1) ──────────────────────────

    #[cfg(unix)]
    #[test]
    fn discover_follows_symlinked_models() {
        let real = tempfile::tempdir().unwrap();
        let d = tempfile::tempdir().unwrap();
        write_model(real.path(), "ggml-large-v3.bin", 5000);
        std::os::unix::fs::symlink(real.path().join("ggml-large-v3.bin"), d.path().join("ggml-large-v3.bin"))
            .unwrap();
        let models = discover_models_in(&[d.path().to_path_buf()]);
        assert_eq!(models.len(), 1);
        assert_eq!(models[0].size, 5000);
    }

    #[test]
    fn default_skips_english_only_when_multilingual_exists() {
        let d = tempfile::tempdir().unwrap();
        write_model(d.path(), "ggml-small.bin", 4000);
        write_model(d.path(), "ggml-medium.en.bin", 8000);
        let models = discover_models_in(&[d.path().to_path_buf()]);
        assert_eq!(pick_default(&models).unwrap().name, "small");
    }

    #[test]
    fn default_uses_english_only_when_nothing_else() {
        let d = tempfile::tempdir().unwrap();
        write_model(d.path(), "ggml-base.en.bin", 2000);
        let models = discover_models_in(&[d.path().to_path_buf()]);
        assert_eq!(pick_default(&models).unwrap().name, "base.en");
    }

    #[test]
    fn partial_downloads_are_not_models() {
        let d = tempfile::tempdir().unwrap();
        let target = d.path().join("ggml-large-v3.bin");
        let part = part_path(&target);
        assert_ne!(part, target);
        std::fs::write(&part, vec![0u8; 5000]).unwrap();
        assert!(discover_models_in(&[d.path().to_path_buf()]).is_empty());
    }

    #[test]
    fn model_name_is_case_insensitive() {
        let d = tempfile::tempdir().unwrap();
        write_model(d.path(), "ggml-base.bin", 2000);
        let p = resolve_model_with(Some("Base"), &[d.path().to_path_buf()], |_| panic!("no download"))
            .unwrap();
        assert_eq!(p, d.path().join("ggml-base.bin"));
    }

    #[test]
    fn whisper_args_have_no_stray_print_special_value() {
        let a = whisper_args(Path::new("m.bin"), Path::new("a.wav"), false).unwrap();
        assert!(!a.iter().any(|x| x == "--print-special" || x == "false"));
        assert!(a.iter().any(|x| x == "--no-timestamps"));
        let t = whisper_args(Path::new("m.bin"), Path::new("a.wav"), true).unwrap();
        assert!(!t.iter().any(|x| x == "--no-timestamps"));
    }

    #[test]
    fn frames_dir_with_old_frames_is_refused() {
        let d = tempfile::tempdir().unwrap();
        assert!(check_frames_dir(d.path()).is_ok());
        std::fs::write(d.path().join("notes.txt"), "x").unwrap();
        assert!(check_frames_dir(d.path()).is_ok());
        std::fs::write(d.path().join("frame_000001.jpg"), "x").unwrap();
        assert!(check_frames_dir(d.path()).is_err());
    }

    #[test]
    fn frames_pattern_escapes_percent() {
        let args = frames_ffmpeg_args(Path::new("in.mp4"), Path::new("out%d"), 5);
        assert!(args.last().unwrap().ends_with("out%%d/frame_%06d.jpg"));
    }

    /// Real-ffmpeg tests skip when ffmpeg is absent; BRANA_REQUIRE_FFMPEG=1 turns the skip
    /// into a failure (same pattern as BRANA_REQUIRE_MCP_BIN) so CI can't skip silently.
    fn ffmpeg_available() -> bool {
        let present = Command::new("ffmpeg").arg("-version").output().is_ok();
        if !present {
            assert!(
                std::env::var("BRANA_REQUIRE_FFMPEG").as_deref() != Ok("1"),
                "ffmpeg required (BRANA_REQUIRE_FFMPEG=1) but not installed"
            );
            eprintln!("SKIP: ffmpeg not installed — frame tests not run");
        }
        present
    }

    /// Mean RGB of a JPEG, decoded by ffmpeg to a single pixel.
    fn jpg_rgb(path: &Path) -> (u8, u8, u8) {
        let out = Command::new("ffmpeg")
            .args(["-v", "error", "-i"])
            .arg(path)
            .args(["-vf", "scale=1:1", "-f", "rawvideo", "-pix_fmt", "rgb24", "-"])
            .output()
            .unwrap();
        (out.stdout[0], out.stdout[1], out.stdout[2])
    }

    #[test]
    fn frame_labels_match_frame_content_time() {
        if !ffmpeg_available() {
            return;
        }
        // 1s lime, 9s red, 1s blue, 9s white: the frame stamped 00:00:00 must come from
        // [0,1) (lime) and the one stamped 00:00:10 from [10,11) (blue) — a 1s window.
        let d = tempfile::tempdir().unwrap();
        let video = d.path().join("c.mp4");
        let ok = Command::new("ffmpeg")
            .args([
                "-v", "error", "-y",
                "-f", "lavfi", "-i", "color=c=lime:s=64x48:r=5:d=1",
                "-f", "lavfi", "-i", "color=c=red:s=64x48:r=5:d=9",
                "-f", "lavfi", "-i", "color=c=blue:s=64x48:r=5:d=1",
                "-f", "lavfi", "-i", "color=c=white:s=64x48:r=5:d=9",
                "-filter_complex", "[0][1][2][3]concat=n=4:v=1[v]", "-map", "[v]",
            ])
            .arg(&video)
            .status()
            .unwrap()
            .success();
        assert!(ok, "fixture video generation failed");
        let out = d.path().join("frames");
        let (index, guard) = extract_frames(&video, &out, 10).unwrap();
        guard.keep();
        assert_eq!(index[1], "frame_000002.jpg @ 00:00:10");
        let (r, g, b) = jpg_rgb(&out.join("frame_000001.jpg"));
        assert!(g > 200 && r < 60 && b < 60, "frame @0s should be lime, got {r},{g},{b}");
        let (r, g, b) = jpg_rgb(&out.join("frame_000002.jpg"));
        assert!(b > 200 && r < 60 && g < 60, "frame @10s should be blue, got {r},{g},{b}");
    }

    #[test]
    fn sparse_vfr_frames_are_labelled_with_their_real_time() {
        if !ffmpeg_available() {
            return;
        }
        // Frames exist only in [0,1) (lime) and [12,20) (white): the second sampled frame
        // comes from t=12, so it must be labelled 00:00:12, not 00:00:10.
        let d = tempfile::tempdir().unwrap();
        let video = d.path().join("vfr.mp4");
        let ok = Command::new("ffmpeg")
            .args([
                "-v", "error", "-y",
                "-f", "lavfi", "-i", "color=c=lime:s=64x48:r=5:d=1",
                "-f", "lavfi", "-i", "color=c=red:s=64x48:r=5:d=11",
                "-f", "lavfi", "-i", "color=c=white:s=64x48:r=5:d=8",
                "-filter_complex",
                "[0][1][2]concat=n=3:v=1,select='lt(t\\,1)+gte(t\\,12)'[v]",
                "-map", "[v]", "-fps_mode", "vfr",
            ])
            .arg(&video)
            .status()
            .unwrap()
            .success();
        assert!(ok, "fixture video generation failed");
        let out = d.path().join("frames");
        let (index, guard) = extract_frames(&video, &out, 10).unwrap();
        guard.keep();
        assert_eq!(index[0], "frame_000001.jpg @ 00:00:00");
        assert_eq!(index[1], "frame_000002.jpg @ 00:00:12");
        let (r, g, b) = jpg_rgb(&out.join("frame_000002.jpg"));
        assert!(r > 200 && g > 200 && b > 200, "frame @12s should be white, got {r},{g},{b}");
    }

    // ── t-3470 Gate 3: model file integrity ─────────────────────────────

    #[test]
    fn discovery_skips_files_without_ggml_magic() {
        let d = tempfile::tempdir().unwrap();
        write_model(d.path(), "ggml-base.bin", 2000);
        // e.g. an HTML error page or captive-portal body saved as a model
        std::fs::write(d.path().join("ggml-large-v3.bin"), vec![b'<'; 9000]).unwrap();
        let names: Vec<String> = discover_models_in(&[d.path().to_path_buf()]).into_iter().map(|m| m.name).collect();
        assert_eq!(names, vec!["base"]);
    }

    #[test]
    fn whisper_failure_names_model_and_recovery() {
        let msg = whisper_failure_message(Path::new("/m/ggml-small.bin"), "error: failed to load model");
        assert!(msg.contains("/m/ggml-small.bin"));
        assert!(msg.contains("--model"));
        assert!(msg.contains("failed to load model"));
    }
}

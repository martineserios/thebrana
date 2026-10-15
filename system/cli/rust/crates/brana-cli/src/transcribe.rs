//! Audio transcription via whisper.cpp (whisper-cli binary)
//!
//! Shells out to whisper-cli for fast CPU inference.
//! Handles format conversion via ffmpeg when needed.

use crate::files;
use anyhow::{bail, Context, Result};
use std::ffi::OsString;
use std::io::BufRead as _;
use std::path::{Path, PathBuf};
use std::process::{Command, Stdio};

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
    /// Seconds between extracted frames (ignored when `scene` is set).
    pub every: u32,
    /// Sample on scene changes above this ffmpeg scene score (0 < x < 1) instead of every N s.
    pub scene: Option<f64>,
}

/// Which frames `--frames` keeps: one every N seconds, or the first frame plus every
/// scene change above a threshold. Only the selection differs — labels always come from
/// `showinfo` `pts_time` (t-3471).
#[derive(Clone, Copy, Debug, PartialEq)]
pub enum Sampling {
    Every(u32),
    Scene(f64),
}

impl Sampling {
    fn from_options(opts: &Options) -> Self {
        match opts.scene {
            Some(t) => Sampling::Scene(t),
            None => Sampling::Every(opts.every),
        }
    }

    /// ffmpeg `select` expression for this sampling mode.
    fn select_expr(self) -> String {
        match self {
            // Keeps the first frame, then the first frame >= N s after the last kept one.
            // (`fps=1/N` rounds to the nearest tick and was measured shifting frames by seconds.)
            Sampling::Every(n) => format!("isnan(prev_selected_t)+gte(t-prev_selected_t\\,{n})"),
            // The first frame (scene score is undefined there) plus every frame whose scene
            // score — ffmpeg's 0..1 change-vs-previous-frame measure — exceeds the threshold.
            Sampling::Scene(t) => format!("eq(n\\,0)+gt(scene\\,{t})"),
        }
    }

    /// Short label for the frame-index header.
    fn describe(self) -> String {
        match self {
            Sampling::Every(n) => format!("every {n}s"),
            Sampling::Scene(t) => format!("scene>{t}"),
        }
    }
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
/// Syntactic only (t-3480): a spec is a path when it contains `/` or ends with `.bin`.
/// It used to consult the filesystem, so a stray file named like a model in cwd turned a
/// model *name* into a path.
fn is_model_path(spec: &str) -> bool {
    spec.contains('/') || spec.ends_with(".bin")
}

/// The user's home as an absolute path, or an error. Never a cwd fallback: with `HOME`
/// unset (cron, `env -i`) the old `"."` default made the model cache, the download dir
/// and even the `whisper-cli` lookup resolve against — and execute from — the current
/// directory (t-3480 challenger F6).
fn home_dir() -> Result<PathBuf> {
    home_dir_from(std::env::var("HOME").ok().as_deref())
}

fn home_dir_from(home: Option<&str>) -> Result<PathBuf> {
    match home {
        Some(h) if Path::new(h).is_absolute() => Ok(PathBuf::from(h)),
        Some(h) if !h.is_empty() => bail!("HOME must be an absolute path (got {h:?})"),
        _ => bail!("HOME is not set — brana transcribe needs it for the model cache"),
    }
}

/// Directories searched for installed models, in priority order.
fn model_dirs() -> Result<Vec<PathBuf>> {
    let env = std::env::var("BRANA_WHISPER_MODELS").ok();
    let (dirs, ignored) = model_dirs_from(env.as_deref(), &home_dir()?);
    for e in ignored {
        eprintln!("warning: ignoring relative BRANA_WHISPER_MODELS entry {e:?} (must be absolute)");
    }
    Ok(dirs)
}

/// `model_dirs` with the inputs injected. Relative `BRANA_WHISPER_MODELS` entries are
/// ignored and reported: they would resolve against whatever cwd the command runs in.
fn model_dirs_from(env: Option<&str>, home: &Path) -> (Vec<PathBuf>, Vec<String>) {
    let mut dirs = Vec::new();
    let mut ignored = Vec::new();
    for e in env.unwrap_or_default().split(':').filter(|s| !s.is_empty()) {
        if Path::new(e).is_absolute() {
            dirs.push(PathBuf::from(e));
        } else {
            ignored.push(e.to_string());
        }
    }
    dirs.push(home.join(".cache").join("whisper-models"));
    (dirs, ignored)
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

/// Refuse a missing, non-file or unreadable input before anything expensive runs: the
/// model lookup can be a multi-GB download, and a typo'd path used to trigger it first
/// (t-3485).
fn check_input(path: &Path) -> Result<()> {
    let meta = std::fs::metadata(path)
        .with_context(|| format!("input file not found: {}", path.display()))?;
    if !meta.is_file() {
        bail!("input is not a file: {}", path.display());
    }
    std::fs::File::open(path).with_context(|| format!("input file is not readable: {}", path.display()))?;
    Ok(())
}

/// Everything cheap and local, in the order that fails fastest, before anything slow: the
/// input file, the `--frames` dir preconditions, the whisper-cli lookup, then the model
/// (possibly a download). The two lookups are injected so the ordering is testable; this
/// is the only path `transcribe()` uses. Creates nothing.
fn preflight(
    input: &Path,
    frames_dir: Option<&Path>,
    spec: Option<&str>,
    which: impl FnOnce() -> Result<PathBuf>,
    resolve: impl FnOnce(Option<&str>) -> Result<PathBuf>,
) -> Result<(PathBuf, PathBuf)> {
    check_input(input)?;
    if let Some(dir) = frames_dir {
        check_frames_dir(dir)?;
        check_existing_frames_dir(dir)?;
    }
    let whisper = which()?;
    let model = resolve(spec)?;
    Ok((whisper, model))
}

/// Resolve the model to run: explicit path/name, else largest installed, else download small.
fn resolve_model(spec: Option<&str>) -> Result<PathBuf> {
    let dirs = model_dirs_for(spec, model_dirs)?;
    resolve_model_with(spec, &dirs, ensure_model)
}

/// The search dirs a spec needs: none for an explicit path (so `--model /abs/x.bin` on a
/// wav works without HOME), otherwise `dirs()` — evaluated only then.
fn model_dirs_for(spec: Option<&str>, dirs: impl FnOnce() -> Result<Vec<PathBuf>>) -> Result<Vec<PathBuf>> {
    match spec {
        Some(s) if is_model_path(s) => Ok(Vec::new()),
        _ => dirs(),
    }
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

    let dir = home_dir()?.join(".cache").join("whisper-models");
    std::fs::create_dir_all(&dir)?;
    // A download killed mid-stream (SIGINT) leaves its .part-<pid> behind; reclaim the disk.
    files::sweep_stale_parts(&dir);

    let model_path = dir.join(ggml_filename(name));
    if std::fs::metadata(&model_path).map(|m| m.len() > 1000).unwrap_or(false) && has_ggml_magic(&model_path) {
        return Ok(model_path);
    }

    let url = download_url(name);
    eprintln!("Downloading {} to {}...", ggml_filename(name), dir.display());
    // One shared atomic download (brana-core, t-3473): the part is created exclusively,
    // curl is https-pinned with a stall timeout, the part is verified, then renamed — an
    // interrupted or concurrent download never leaves a truncated `ggml-*.bin` for
    // discovery. HuggingFace pins no hash, so the check is the ggml magic: a 200 OK can
    // still be a non-model body (captive portal, proxy error page).
    files::download_file_verified(&url, &model_path, |part| {
        if has_ggml_magic(part) {
            Ok(())
        } else {
            bail!("downloaded {url} is not a ggml model file")
        }
    })
    .with_context(|| format!("failed to download model from {url} (install curl if missing, or download the model manually)"))?;
    Ok(model_path)
}

/// `entry` as a usable path for `model_file`, or None when it is not that model (exact file
/// name — `contains` used to match `ggml-base.bin.bak` too) or when it would escape the
/// project / use a non-https URL (`files::validate_entry`, t-3473). Writes nothing.
fn tracked_model_path(root: &Path, entry: &files::FileEntry, model_file: &str) -> Option<PathBuf> {
    if Path::new(&entry.path).file_name()?.to_str()? != model_file {
        return None;
    }
    let checked = files::validate_entry(root, entry)
        .and_then(|p| match &entry.url { Some(u) => files::validate_url(u).map(|()| p), None => Ok(p) });
    match checked {
        Ok(p) => Some(p),
        Err(e) => {
            // Say why a matching entry is ignored instead of silently falling back to a
            // HuggingFace download of the same model (t-3473 challenger F5).
            eprintln!("warning: ignoring manifest entry {} for {model_file}: {e}", entry.path);
            None
        }
    }
}

fn try_manifest_model(name: &str) -> Option<PathBuf> {
    use crate::util::find_project_root;

    let root = find_project_root()?;
    let manifest = files::Manifest::load(&root).ok()?;
    let model_name = ggml_filename(name);

    for entry in manifest.files.values() {
        let Some(full_path) = tracked_model_path(&root, entry, &model_name) else { continue };
        if full_path.exists() {
            if files::file_sha256(&full_path).ok().as_deref() == Some(entry.sha256.as_str()) {
                eprintln!("Using manifest-tracked model: {}", entry.path);
                return Some(full_path);
            }
            eprintln!(
                "warning: tracked model {} does not match its manifest hash — run `brana files pull` to repair it; falling back",
                entry.path
            );
        } else if let Some(url) = &entry.url {
            eprintln!("Downloading tracked model: {}", entry.path);
            // Atomic: hash is checked on the .part, so a mismatch never lands at full_path.
            match files::download_file(url, &full_path, Some(&entry.sha256)) {
                Ok(()) => return Some(full_path),
                Err(e) => eprintln!("warning: tracked model download failed ({e:#}); falling back"),
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

/// How long a `brana-transcribe-*.wav` may sit untouched before it counts as leaked by a
/// run that died without running `Drop` (SIGKILL/SIGTERM). Age-based, no `/proc`.
const STALE_WAV_AGE: std::time::Duration = std::time::Duration::from_secs(60 * 60);

/// Remove this command's own leaked temp wavs in `dir` older than `STALE_WAV_AGE`.
fn sweep_stale_wavs(dir: &Path) -> usize {
    let Ok(rd) = std::fs::read_dir(dir) else { return 0 };
    let now = std::time::SystemTime::now();
    let mut swept = 0;
    for e in rd.flatten() {
        let name = e.file_name().to_string_lossy().into_owned();
        if !(name.starts_with("brana-transcribe-") && name.ends_with(".wav")) {
            continue;
        }
        let stale = e
            .metadata()
            .and_then(|m| m.modified())
            .ok()
            .and_then(|t| now.duration_since(t).ok())
            .is_some_and(|age| age > STALE_WAV_AGE);
        if stale && std::fs::remove_file(e.path()).is_ok() {
            swept += 1;
        }
    }
    swept
}

/// `file:` + the absolute path, as raw bytes (a non-UTF-8 file name reaches ffmpeg intact).
/// Only a RELATIVE name can look like a scheme to ffmpeg (`concat:…`, `data:…`); an
/// absolute `file:` URL plus `-protocol_whitelist file` means a media file is always
/// opened as a file and never parsed as a protocol (t-3480).
fn file_url(path: &Path) -> Result<OsString> {
    let abs = std::path::absolute(path).with_context(|| format!("bad path {}", path.display()))?;
    let mut url = OsString::from("file:");
    url.push(abs.as_os_str());
    Ok(url)
}

fn ffmpeg_input(path: &Path) -> Result<OsString> {
    file_url(path)
}

/// `%` is ffmpeg's image2 pattern char — escape it in a directory that becomes part of an
/// output pattern. Byte-wise on unix so non-UTF-8 names survive.
fn escape_percent(dir: &Path) -> OsString {
    #[cfg(unix)]
    {
        use std::os::unix::ffi::{OsStrExt, OsStringExt};
        let mut out = Vec::with_capacity(dir.as_os_str().len() + 4);
        for &b in dir.as_os_str().as_bytes() {
            out.push(b);
            if b == b'%' {
                out.push(b'%');
            }
        }
        OsString::from_vec(out)
    }
    #[cfg(not(unix))]
    {
        OsString::from(dir.to_string_lossy().replace('%', "%%"))
    }
}

fn os(s: &str) -> OsString {
    OsString::from(s)
}

/// ffmpeg arguments that convert `input`'s audio to 16 kHz mono PCM wav at `out`.
fn wav_ffmpeg_args(input: &Path, out: &Path) -> Result<Vec<OsString>> {
    Ok(vec![
        os("-nostdin"), os("-v"), os("error"), os("-y"),
        os("-protocol_whitelist"), os("file"),
        os("-i"), ffmpeg_input(input)?,
        os("-protocol_whitelist"), os("file"),
        os("-vn"), os("-ar"), os("16000"), os("-ac"), os("1"), os("-c:a"), os("pcm_s16le"),
        file_url(out)?,
    ])
}

/// Convert audio (or a video's audio track) to WAV 16kHz mono if needed.
fn ensure_wav(path: &Path) -> Result<Wav> {
    let ext = path.extension().and_then(|e| e.to_str()).unwrap_or("");

    // whisper-cli handles wav, mp3, and ogg/vorbis natively
    // But Opus-in-ogg, m4a and video containers need conversion
    match ext.to_lowercase().as_str() {
        "wav" | "mp3" => Ok(Wav::Original(path.to_path_buf())),
        _ => {
            let tmp_dir = std::env::temp_dir();
            sweep_stale_wavs(&tmp_dir);
            // Unique per run (created exclusively), so concurrent runs never share a file.
            let tmp = tempfile::Builder::new()
                .prefix("brana-transcribe-")
                .suffix(".wav")
                .tempfile_in(&tmp_dir)
                .context("failed to create temp wav")?
                .into_temp_path();
            let status = Command::new("ffmpeg")
                .args(wav_ffmpeg_args(path, &tmp)?)
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

/// ffmpeg arguments that write the frames `sampling` selects as JPEGs into `dir`.
/// `showinfo` logs each kept frame's real `pts_time` (at info level, hence `-loglevel info`),
/// which labels the frames — sampling never decides the label.
/// Requires ffmpeg >= 5.1 (`-fps_mode`).
fn frames_ffmpeg_args(input: &Path, dir: &Path, sampling: Sampling) -> Result<Vec<OsString>> {
    // The output is a `file:` URL too: `-protocol_whitelist` before `-i` binds to the
    // input only, so a `--frames` dir spelled like `udp://host/x` would otherwise be
    // created locally by our checks and then written to over the network by ffmpeg.
    let mut output = OsString::from("file:");
    output.push(escape_percent(&std::path::absolute(dir)?));
    output.push("/frame_%06d.jpg");
    Ok(vec![
        os("-hide_banner"),
        os("-nostdin"),
        os("-nostats"), // the \r-terminated progress line is the only unbounded log line
        os("-loglevel"), os("info"),
        os("-y"),
        os("-protocol_whitelist"), os("file"),
        os("-i"), ffmpeg_input(input)?,
        os("-protocol_whitelist"), os("file"),
        os("-vf"),
        os(&format!("select='{}',showinfo", sampling.select_expr())),
        os("-fps_mode"), os("vfr"),
        os("-q:v"), os("2"),
        output,
    ])
}

/// Longest stderr line kept; the rest of an over-long line is dropped, never buffered.
const STDERR_LINE_CAP: usize = 64 * 1024;

/// Read ffmpeg's stderr to the end, byte-wise, splitting on `\n` AND `\r` (progress
/// reports are `\r`-terminated and would otherwise glue onto the next showinfo line):
/// each segment is capped and decoded lossily, so a Latin-1 title tag the file carries
/// (ffmpeg echoes metadata before the first showinfo line) never ends the read —
/// `BufRead::lines()` would stop at the first invalid UTF-8 and silently lose every
/// later frame time (t-3480 challenger F4). Memory is bounded by the cap.
fn read_ffmpeg_stderr(r: impl std::io::Read) -> (Vec<f64>, String) {
    let mut reader = std::io::BufReader::new(r);
    let mut reducer = StderrReducer::default();
    let mut buf: Vec<u8> = Vec::new();
    loop {
        let (consumed, terminated) = match reader.fill_buf() {
            Ok(chunk) if chunk.is_empty() => break,
            Ok(chunk) => match chunk.iter().position(|&b| b == b'\n' || b == b'\r') {
                Some(i) => {
                    append_capped(&mut buf, &chunk[..i]);
                    (i + 1, true)
                }
                None => {
                    append_capped(&mut buf, chunk);
                    (chunk.len(), false)
                }
            },
            Err(e) if e.kind() == std::io::ErrorKind::Interrupted => continue,
            Err(_) => break,
        };
        reader.consume(consumed);
        if terminated {
            reducer.push(&String::from_utf8_lossy(&buf));
            buf.clear();
        }
    }
    if !buf.is_empty() {
        reducer.push(&String::from_utf8_lossy(&buf));
    }
    (reducer.times, reducer.last)
}

/// Streaming reduction of ffmpeg's stderr: keeps the `showinfo` frame times and the last
/// non-empty line (the error, when there is one) — never the whole log, which grows by one
/// block per frame (t-3480).
#[derive(Default)]
struct StderrReducer {
    times: Vec<f64>,
    last: String,
}

impl StderrReducer {
    fn push(&mut self, line: &str) {
        self.times.extend(parse_pts_times(line));
        if !line.trim().is_empty() {
            self.last = line.to_string();
        }
    }
}

#[cfg(test)]
fn reduce_ffmpeg_stderr<'a>(lines: impl Iterator<Item = &'a str>) -> (Vec<f64>, String) {
    let mut r = StderrReducer::default();
    for l in lines {
        r.push(l);
    }
    (r.times, r.last)
}

fn append_capped(buf: &mut Vec<u8>, bytes: &[u8]) {
    let room = STDERR_LINE_CAP.saturating_sub(buf.len());
    buf.extend_from_slice(&bytes[..bytes.len().min(room)]);
}

/// `pts_time` of every frame `showinfo` reported, in output order.
fn parse_pts_times(stderr: &str) -> Vec<f64> {
    stderr
        .lines()
        // Anchored: ffmpeg also echoes the file's tags, and a crafted title containing the
        // marker must not count as a frame.
        .filter(|l| l.trim_start().starts_with("[Parsed_showinfo"))
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
        match opts.scene {
            // NaN fails both comparisons, so it is rejected by the negated range check.
            // 1 is excluded: a hard cut scores exactly 1.0 and `gt` is strict, so
            // gt(scene,1) can never select a frame (measured on a lime|blue cut).
            Some(t) if !(t > 0.0 && t < 1.0) => {
                bail!("--scene must be a scene score in (0, 1), e.g. 0.3 (got {t})")
            }
            Some(_) => {}
            None if opts.every == 0 => bail!("--every must be at least 1 second"),
            None => {}
        }
    } else if opts.scene.is_some() {
        bail!("--scene requires --frames");
    }
    Ok(())
}

/// Create the frames dir private to the user (0o700) when this run creates it: frames of a
/// private recording should not land world-readable in a shared location (t-3480). An
/// existing dir keeps its mode.
/// Is a pre-existing `--frames` dir acceptable? `Ok(true)` = exists and is a real directory
/// nobody else can write (otherwise another user could plant a `frame_*` entry while ffmpeg
/// runs — the check-then-use window lasts the whole run); `Ok(false)` = does not exist yet;
/// `Err` = symlink, not a directory, group/other-writable, or uninspectable. Creates nothing.
fn check_existing_frames_dir(dir: &Path) -> Result<bool> {
    match std::fs::symlink_metadata(dir) {
        Ok(m) if m.file_type().is_symlink() => {
            bail!("--frames {} is a symlink — use a real directory", dir.display())
        }
        Ok(m) if m.is_dir() => {
            #[cfg(unix)]
            {
                use std::os::unix::fs::PermissionsExt;
                if m.permissions().mode() & 0o022 != 0 {
                    bail!(
                        "--frames {} is writable by other users — use a private directory",
                        dir.display()
                    );
                }
            }
            Ok(true)
        }
        Ok(_) => bail!("--frames {} exists and is not a directory", dir.display()),
        Err(e) if e.kind() == std::io::ErrorKind::NotFound => Ok(false),
        Err(e) => Err(e).with_context(|| format!("cannot inspect frames dir {}", dir.display())),
    }
}

fn create_private_dir(dir: &Path) -> Result<()> {
    if check_existing_frames_dir(dir)? {
        return Ok(());
    }
    // Parents get the default mode — only the leaf holding the frames is private, so
    // `--frames /srv/share/newproj/frames` does not lock `newproj` to one user.
    if let Some(parent) = dir.parent() {
        std::fs::create_dir_all(parent)?;
    }
    #[cfg(unix)]
    let created = {
        use std::os::unix::fs::DirBuilderExt;
        std::fs::DirBuilder::new().mode(0o700).create(dir)
    };
    #[cfg(not(unix))]
    let created = std::fs::create_dir(dir);
    created.with_context(|| format!("cannot create frames dir {}", dir.display()))
}

/// Refuse a frames dir that already holds frames: the index is built from the directory,
/// so leftovers from an earlier run would be listed with timestamps they don't have — and
/// a planted `frame_*` symlink in a shared dir would be followed by ffmpeg's `-y` (t-3480),
/// so any `frame_*` entry, file or link, refuses the run before ffmpeg starts.
fn check_frames_dir(dir: &Path) -> Result<()> {
    // Fail closed: only "does not exist yet" means there is nothing to check. A dir we
    // cannot list (EACCES, ELOOP, ENOTDIR) could hold exactly the planted entry we refuse.
    let rd = match std::fs::read_dir(dir) {
        Ok(rd) => rd,
        Err(e) if e.kind() == std::io::ErrorKind::NotFound => return Ok(()),
        Err(e) => return Err(e).with_context(|| format!("cannot inspect frames dir {}", dir.display())),
    };
    let stale = rd
        .flatten()
        .any(|e| e.file_name().to_string_lossy().starts_with("frame_"));
    if stale {
        bail!("{} already contains frame_* files — use an empty or new --frames directory", dir.display());
    }
    Ok(())
}

/// Above this many frames a run is almost certainly sampling too densely (`--every 1`
/// crosses it at ~8 minutes of video: 500 JPEGs and 500 index lines). Documented in
/// docs/architecture/features/transcribe-models-video.md (t-3485).
const FRAME_WARN_THRESHOLD: usize = 500;

/// The warning printed after extraction when the frame count exceeds the threshold, with
/// advice for the sampler actually in use (`--every` conflicts with `--scene`).
fn frame_count_note(n: usize, sampling: Sampling) -> Option<String> {
    (n > FRAME_WARN_THRESHOLD).then(|| {
        let advice = match sampling {
            Sampling::Every(_) => "a larger --every, or --scene to sample on cuts,",
            Sampling::Scene(_) => "a higher --scene threshold",
        };
        format!("warning: {n} frames extracted (more than {FRAME_WARN_THRESHOLD}) — {advice} keeps the frame index usable")
    })
}

/// Extract frames; returns the index lines and a guard owning the written files.
fn extract_frames(input: &Path, dir: &Path, sampling: Sampling) -> Result<(Vec<String>, FramesGuard)> {
    check_frames_dir(dir)?;
    create_private_dir(dir)?;
    let args = frames_ffmpeg_args(input, dir, sampling)?;
    let mut child = Command::new("ffmpeg")
        .args(args)
        .stdin(Stdio::null())
        .stdout(Stdio::null())
        .stderr(Stdio::piped())
        .spawn()
        .context("ffmpeg not found — install ffmpeg (>= 5.1) to extract frames")?;
    // Stream stderr: one showinfo block per frame would otherwise be buffered whole.
    let (times, last) = match child.stderr.take() {
        Some(stderr) => read_ffmpeg_stderr(stderr),
        None => (Vec::new(), String::new()),
    };
    let status = child.wait().context("ffmpeg did not exit")?;
    let mut files: Vec<String> = std::fs::read_dir(dir)?
        .flatten()
        .map(|e| e.file_name().to_string_lossy().into_owned())
        .filter(|n| n.starts_with("frame_") && n.ends_with(".jpg"))
        .collect();
    files.sort();
    let guard = FramesGuard::new(files.iter().map(|f| dir.join(f)).collect());
    if !status.success() {
        bail!("ffmpeg frame extraction failed: {last}");
    }
    if times.len() != files.len() {
        bail!("ffmpeg reported {} frame times for {} frames", times.len(), files.len());
    }
    // Scene mode has no duration/N bound — a very low threshold can keep nearly every frame —
    // so say how many were written, and warn when the index is too dense to be useful.
    eprintln!("Extracted {} frames into {}", files.len(), dir.display());
    if let Some(note) = frame_count_note(files.len(), sampling) {
        eprintln!("{note}");
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

    // 1-2. Input, --frames dir preconditions, whisper-cli, then the model — fastest failure
    // first, and nothing slow or written before the cheap checks pass (t-3485).
    let (whisper, model_path) = preflight(
        audio_path,
        opts.frames_dir.as_deref(),
        opts.model.as_deref(),
        which_whisper_cli,
        resolve_model,
    )?;
    eprintln!("Using model: {}", model_path.display());

    // 3. Frames first — cheap, and fails fast (e.g. no video stream) before a long transcription.
    let frames = match &opts.frames_dir {
        Some(dir) => {
            eprintln!("Extracting frames...");
            Some(extract_frames(audio_path, dir, Sampling::from_options(opts))?)
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
            "{text}\n\nFrames ({} {}):\n{}",
            dir.display(),
            Sampling::from_options(opts).describe(),
            index.join("\n")
            ))
        }
        _ => Ok(text),
    }
}

/// Build LD_LIBRARY_PATH that includes ~/.local/lib for libwhisper.so.1.
/// Prepends to any existing LD_LIBRARY_PATH so the caller's env is preserved.
fn whisper_ld_library_path() -> String {
    let home = home_dir().ok();
    let existing = std::env::var("LD_LIBRARY_PATH").ok();
    whisper_ld_library_path_from(home.as_deref(), existing.as_deref())
}

/// `$HOME/.local/lib` (only for a usable, absolute HOME — never a cwd-relative entry)
/// prepended to the existing LD_LIBRARY_PATH.
fn whisper_ld_library_path_from(home: Option<&Path>, existing_ld: Option<&str>) -> String {
    let local_lib = home.map(|h| h.join(".local/lib").display().to_string());
    match (local_lib, existing_ld.filter(|e| !e.is_empty())) {
        (Some(l), Some(e)) => format!("{l}:{e}"),
        (Some(l), None) => l,
        (None, Some(e)) => e.to_string(),
        (None, None) => String::new(),
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

    // Check ~/.local/bin explicitly — only under a real, absolute HOME: a relative
    // `.local/bin/whisper-cli` would be executed from cwd (t-3480).
    if let Ok(home) = home_dir() {
        let local_bin = home.join(".local/bin/whisper-cli");
        if local_bin.exists() {
            return Ok(local_bin);
        }
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
    use std::ffi::OsString;

    fn lossy_join(args: &[OsString]) -> String {
        args.iter().map(|a| a.to_string_lossy().into_owned()).collect::<Vec<_>>().join(" ")
    }

    fn pos(args: &[OsString], s: &str) -> Option<usize> {
        args.iter().position(|a| a.to_str() == Some(s))
    }

    /// chdir for the duration of a test; restores the previous cwd on drop. Only used by
    /// `#[serial_test::serial]` tests — cwd is process-global.
    struct Cwd(PathBuf);
    impl Cwd {
        fn enter(dir: &Path) -> Self {
            let prev = std::env::current_dir().unwrap();
            std::env::set_current_dir(dir).unwrap();
            Cwd(prev)
        }
    }
    impl Drop for Cwd {
        fn drop(&mut self) {
            let _ = std::env::set_current_dir(&self.0);
        }
    }

    #[test]
    fn test_ld_library_path_standalone() {
        let result = whisper_ld_library_path_from(Some(Path::new("/home/user")), None);
        assert_eq!(result, "/home/user/.local/lib");
    }

    #[test]
    fn test_ld_library_path_standalone_empty_existing() {
        let result = whisper_ld_library_path_from(Some(Path::new("/home/user")), Some(""));
        assert_eq!(result, "/home/user/.local/lib");
    }

    #[test]
    fn test_ld_library_path_prepends_existing() {
        let result = whisper_ld_library_path_from(Some(Path::new("/home/user")), Some("/usr/lib:/other/lib"));
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
        // t-3480: purely syntactic — a same-named file in cwd no longer turns a name into a path
        assert!(is_model_path("ggml-base.bin"), "ends with .bin is a path");
        assert!(!is_model_path("Cargo.toml"), "exists in cwd but is neither / nor .bin");
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
        let args = frames_ffmpeg_args(Path::new("in.mp4"), Path::new("out"), Sampling::Every(5)).unwrap();
        let joined = lossy_join(&args);
        assert!(joined.contains("-i file:/") && joined.contains("/in.mp4 -protocol_whitelist file -vf"), "{joined}");
        assert!(joined.contains("gte(t-prev_selected_t\\,5)',showinfo"));
        assert!(joined.ends_with("out/frame_%06d.jpg"));
        assert!(pos(&args, "-vn").is_none());
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
        let ok = Options { model: None, frames_dir: None, every: 10, scene: None };
        assert!(validate_options(&ok, Path::new("a.mp3")).is_ok());
        let frames_audio = Options { model: None, frames_dir: Some("o".into()), every: 10, scene: None };
        assert!(validate_options(&frames_audio, Path::new("a.mp3")).is_err());
        assert!(validate_options(&frames_audio, Path::new("a.mp4")).is_ok());
        let zero = Options { model: None, frames_dir: Some("o".into()), every: 0, scene: None };
        assert!(validate_options(&zero, Path::new("a.mp4")).is_err());
    }

    // ── t-3471: scene-change sampling (--scene <threshold>) ─────────────

    #[test]
    fn frames_args_scene_select_keeps_first_frame_and_cuts() {
        let args = frames_ffmpeg_args(Path::new("in.mp4"), Path::new("out"), Sampling::Scene(0.3)).unwrap();
        let joined = lossy_join(&args);
        assert!(joined.contains("select='eq(n\\,0)+gt(scene\\,0.3)',showinfo"), "{joined}");
        assert!(!joined.contains("prev_selected_t"), "scene mode must not use the interval selector");
        assert!(joined.contains("-fps_mode vfr"));
        assert!(joined.ends_with("out/frame_%06d.jpg"));
    }

    #[test]
    fn sampling_prefers_scene_over_every_and_names_itself() {
        let every = Options { model: None, frames_dir: Some("o".into()), every: 5, scene: None };
        assert_eq!(Sampling::from_options(&every), Sampling::Every(5));
        let scene = Options { model: None, frames_dir: Some("o".into()), every: 10, scene: Some(0.4) };
        assert_eq!(Sampling::from_options(&scene), Sampling::Scene(0.4));
        assert_eq!(Sampling::Every(5).describe(), "every 5s");
        assert_eq!(Sampling::Scene(0.4).describe(), "scene>0.4");
    }

    #[test]
    fn options_validate_rejects_bad_scene_thresholds() {
        let mk = |scene| Options { model: None, frames_dir: Some("o".into()), every: 10, scene };
        assert!(validate_options(&mk(Some(0.3)), Path::new("a.mp4")).is_ok());
        assert!(validate_options(&mk(Some(0.999)), Path::new("a.mp4")).is_ok());
        assert!(validate_options(&mk(Some(0.0)), Path::new("a.mp4")).is_err(), "0 selects nearly every frame");
        assert!(validate_options(&mk(Some(-0.1)), Path::new("a.mp4")).is_err());
        // A hard cut scores exactly 1.0 and `gt` is strict (measured 2026-10-14: gt(scene,1)
        // selected 0 frames on a lime|blue cut), so 1 can never fire — reject it.
        assert!(validate_options(&mk(Some(1.0)), Path::new("a.mp4")).is_err(), "1 can never select a cut");
        assert!(validate_options(&mk(Some(1.5)), Path::new("a.mp4")).is_err(), "scene score is 0..1");
        assert!(validate_options(&mk(Some(f64::NAN)), Path::new("a.mp4")).is_err());
        // --scene is a frames sampler: without --frames it is a usage error (clap enforces this
        // too, but Options is a public API).
        let no_frames = Options { model: None, frames_dir: None, every: 10, scene: Some(0.3) };
        assert!(validate_options(&no_frames, Path::new("a.mp4")).is_err());
        // scene mode ignores --every, so every=0 must not be rejected there
        let scene_zero_every = Options { model: None, frames_dir: Some("o".into()), every: 0, scene: Some(0.3) };
        assert!(validate_options(&scene_zero_every, Path::new("a.mp4")).is_ok());
    }

    #[test]
    fn scene_cut_yields_frame_at_cut_time() {
        if !ffmpeg_available() {
            return;
        }
        // 3s lime then 3s blue: one hard cut at t=3. Scene sampling keeps the first frame
        // (t=0, lime) and the cut frame (t=3, blue) — nothing else — and labels them by
        // showinfo pts_time, not by index.
        let d = tempfile::tempdir().unwrap();
        let video = d.path().join("cut.mp4");
        let ok = Command::new("ffmpeg")
            .args([
                "-v", "error", "-y",
                "-f", "lavfi", "-i", "color=c=lime:s=64x48:r=5:d=3",
                "-f", "lavfi", "-i", "color=c=blue:s=64x48:r=5:d=3",
                "-filter_complex", "[0][1]concat=n=2:v=1[v]", "-map", "[v]",
            ])
            .arg(&video)
            .status()
            .unwrap()
            .success();
        assert!(ok, "fixture video generation failed");
        let out = d.path().join("frames");
        let (index, guard) = extract_frames(&video, &out, Sampling::Scene(0.3)).unwrap();
        guard.keep();
        assert_eq!(index, vec!["frame_000001.jpg @ 00:00:00", "frame_000002.jpg @ 00:00:03"]);
        let (r, g, b) = jpg_rgb(&out.join("frame_000001.jpg"));
        assert!(g > 200 && r < 60 && b < 60, "frame @0s should be lime, got {r},{g},{b}");
        let (r, g, b) = jpg_rgb(&out.join("frame_000002.jpg"));
        assert!(b > 200 && r < 60 && g < 60, "frame @3s (the cut) should be blue, got {r},{g},{b}");
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
        let (index, guard) = extract_frames(&video, &out, Sampling::Every(10)).unwrap();
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
        let part = files::part_path(&target);
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
        let args = frames_ffmpeg_args(Path::new("in.mp4"), Path::new("out%d"), Sampling::Every(5)).unwrap();
        assert!(args.last().unwrap().to_string_lossy().ends_with("out%%d/frame_%06d.jpg"));
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
        let (index, guard) = extract_frames(&video, &out, Sampling::Every(10)).unwrap();
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
        let (index, guard) = extract_frames(&video, &out, Sampling::Every(10)).unwrap();
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

    // ── t-3480: hardening (protocol whitelist, private frames dir, https curl, ...) ──

    #[test]
    fn frames_args_whitelist_file_protocol_and_prefix_input() {
        let args = frames_ffmpeg_args(Path::new("concat:a.mp4|b.mp4"), Path::new("out"), Sampling::Every(5)).unwrap();
        let wl = pos(&args, "-protocol_whitelist").expect("whitelist present");
        assert_eq!(args[wl + 1].to_str(), Some("file"));
        let i = pos(&args, "-i").unwrap();
        assert!(wl < i, "whitelist must precede -i");
        let input = args[i + 1].to_string_lossy().into_owned();
        assert!(input.starts_with("file:/"), "input is an absolute file: URL, got {input}");
        assert!(input.ends_with("concat:a.mp4|b.mp4"));
    }

    #[test]
    fn wav_args_whitelist_file_protocol_and_prefix_input() {
        let args = wav_ffmpeg_args(Path::new("data:text/plain,hi.m4a"), Path::new("/tmp/o.wav")).unwrap();
        let wl = pos(&args, "-protocol_whitelist").expect("whitelist present");
        assert_eq!(args[wl + 1].to_str(), Some("file"));
        let i = pos(&args, "-i").unwrap();
        assert!(wl < i);
        let input = args[i + 1].to_string_lossy().into_owned();
        assert!(input.starts_with("file:/") && input.ends_with("data:text/plain,hi.m4a"), "{input}");
        assert!(lossy_join(&args).ends_with("/tmp/o.wav"));
    }

    #[test]
    #[serial_test::serial]
    fn odd_input_name_is_a_file_not_a_protocol() {
        if !ffmpeg_available() {
            return;
        }
        // A media file whose NAME looks like a protocol URL must be opened as a file, never
        // parsed as concat:/data:/playlist. ffmpeg only sees a scheme in a RELATIVE name
        // (an absolute path starts with '/', not a scheme char), so this must run from cwd
        // with the bare name — the whitelist + file: prefix are what make it a file.
        let d = tempfile::tempdir().unwrap();
        let video = d.path().join("concat:evil.mp4");
        let ok = Command::new("ffmpeg")
            .args(["-v", "error", "-y", "-f", "lavfi", "-i", "testsrc=d=3:s=64x48:r=5"])
            .arg(format!("file:{}", video.display()))
            .status()
            .unwrap()
            .success();
        assert!(ok, "fixture video generation failed");
        let _cwd = Cwd::enter(d.path());
        let out = d.path().join("frames");
        let (index, guard) = extract_frames(Path::new("concat:evil.mp4"), &out, Sampling::Every(10)).unwrap();
        guard.keep();
        assert_eq!(index[0], "frame_000001.jpg @ 00:00:00");
    }

    #[cfg(unix)]
    #[test]
    fn non_utf8_metadata_does_not_lose_frame_times() {
        if !ffmpeg_available() {
            return;
        }
        // ffmpeg echoes the file's own tags on stderr before the first showinfo line; a
        // Latin-1 title must not end the stderr reader (challenger F4, sev 4 regression).
        use std::os::unix::ffi::OsStrExt;
        let d = tempfile::tempdir().unwrap();
        let video = d.path().join("tagged.avi");
        let ok = Command::new("ffmpeg")
            .args(["-v", "error", "-y", "-f", "lavfi", "-i", "testsrc=d=2:s=64x48:r=5", "-metadata"])
            .arg(std::ffi::OsStr::from_bytes(b"title=caf\xe9 latin-1"))
            .arg(&video)
            .status()
            .unwrap()
            .success();
        assert!(ok, "fixture video generation failed");
        let out = d.path().join("frames");
        let (index, guard) = extract_frames(&video, &out, Sampling::Every(10)).unwrap();
        guard.keep();
        assert_eq!(index[0], "frame_000001.jpg @ 00:00:00");
    }

    #[test]
    fn ffmpeg_stderr_reader_tolerates_non_utf8_and_caps_lines() {
        let mut bytes: Vec<u8> = Vec::new();
        bytes.extend_from_slice(b"[Parsed_showinfo_1 @ 0x5] n:   0 pts:      0 pts_time:0       duration:1\n");
        bytes.extend_from_slice(b"    title           : caf\xe9\n");
        bytes.extend_from_slice(b"[Parsed_showinfo_1 @ 0x5] n:   1 pts:  61440 pts_time:1.5    duration:1\n");
        bytes.extend(std::iter::repeat_n(b'x', 1 << 20)); // one absurd line, no newline
        bytes.extend_from_slice(b"\nerr\xff tail");
        let (times, last) = read_ffmpeg_stderr(std::io::Cursor::new(bytes));
        assert_eq!(times, vec![0.0, 1.5], "a non-UTF-8 line must not end the read");
        assert!(last.starts_with("err"), "last line survives lossy decoding: {last:?}");
    }

    #[cfg(unix)]
    #[test]
    fn unlistable_frames_dir_is_refused() {
        use std::os::unix::fs::PermissionsExt;
        let d = tempfile::tempdir().unwrap();
        let dir = d.path().join("opaque");
        std::fs::create_dir(&dir).unwrap();
        std::fs::set_permissions(&dir, std::fs::Permissions::from_mode(0o300)).unwrap();
        if std::fs::read_dir(&dir).is_ok() {
            return; // root can list anything; nothing to prove here
        }
        let r = check_frames_dir(&dir);
        std::fs::set_permissions(&dir, std::fs::Permissions::from_mode(0o700)).unwrap();
        assert!(r.is_err(), "a dir we cannot inspect must fail closed, not open");
        assert!(check_frames_dir(&d.path().join("missing")).is_ok(), "only NotFound means nothing to check");
    }

    #[test]
    fn frames_args_output_is_a_file_url_with_its_own_whitelist() {
        let args = frames_ffmpeg_args(Path::new("in.mp4"), Path::new("udp://h/x"), Sampling::Every(5)).unwrap();
        let out = args.last().unwrap().to_string_lossy().into_owned();
        assert!(out.starts_with("file:/") && out.ends_with("udp:/h/x/frame_%06d.jpg"), "output must be a file: URL, got {out}");
        let i = pos(&args, "-i").unwrap();
        let wls: Vec<usize> = args.iter().enumerate().filter(|(_, a)| a.to_str() == Some("-protocol_whitelist")).map(|(n, _)| n).collect();
        assert_eq!(wls.len(), 2, "one whitelist for the input, one for the output: {}", lossy_join(&args));
        assert!(wls[0] < i && wls[1] > i);
    }

    #[cfg(unix)]
    #[test]
    fn ffmpeg_args_keep_non_utf8_names() {
        use std::os::unix::ffi::{OsStrExt, OsStringExt};
        let name = std::ffi::OsStr::from_bytes(b"caf\xe9.m4a");
        let args = wav_ffmpeg_args(Path::new(name), Path::new("/tmp/o.wav")).unwrap();
        let i = pos(&args, "-i").unwrap();
        let bytes = args[i + 1].clone().into_vec();
        assert!(bytes.ends_with(b"caf\xe9.m4a"), "the raw bytes must reach ffmpeg, not U+FFFD");
    }

    #[cfg(unix)]
    #[test]
    fn frames_dir_is_created_private() {
        if !ffmpeg_available() {
            return;
        }
        use std::os::unix::fs::PermissionsExt;
        let d = tempfile::tempdir().unwrap();
        let video = d.path().join("t.mp4");
        assert!(Command::new("ffmpeg").args(["-v", "error", "-y", "-f", "lavfi", "-i", "testsrc=d=2:s=64x48:r=5"]).arg(&video).status().unwrap().success());
        let out = d.path().join("new").join("frames");
        let (_, guard) = extract_frames(&video, &out, Sampling::Every(10)).unwrap();
        guard.keep();
        let mode = std::fs::metadata(&out).unwrap().permissions().mode() & 0o777;
        assert_eq!(mode, 0o700, "a frames dir the run creates is private to the user");
        let sibling = d.path().join("plain");
        std::fs::create_dir(&sibling).unwrap();
        let parent_mode = std::fs::metadata(out.parent().unwrap()).unwrap().permissions().mode() & 0o777;
        let plain_mode = std::fs::metadata(&sibling).unwrap().permissions().mode() & 0o777;
        assert_eq!(parent_mode, plain_mode, "only the leaf is private; created parents keep the default mode");
    }

    #[cfg(unix)]
    #[test]
    fn planted_frame_symlink_is_refused_not_followed() {
        if !ffmpeg_available() {
            return;
        }
        let d = tempfile::tempdir().unwrap();
        let video = d.path().join("t.mp4");
        assert!(Command::new("ffmpeg").args(["-v", "error", "-y", "-f", "lavfi", "-i", "testsrc=d=2:s=64x48:r=5"]).arg(&video).status().unwrap().success());
        let out = d.path().join("shared");
        std::fs::create_dir(&out).unwrap();
        let target = d.path().join("victim.txt");
        std::fs::write(&target, b"keep me").unwrap();
        std::os::unix::fs::symlink(&target, out.join("frame_000001.jpg")).unwrap();
        let r = extract_frames(&video, &out, Sampling::Every(10));
        assert!(r.is_err(), "a dir with a planted frame_* entry is refused before ffmpeg runs");
        assert_eq!(std::fs::read(&target).unwrap(), b"keep me", "the symlink target must be untouched");
    }

    #[test]
    fn model_download_curl_is_https_pinned() {
        // ensure_model → files::download_file_verified → curl_fetch → curl_args (t-3473);
        // pin the contract from this crate so a brana-core change cannot silently drop it.
        let args: Vec<String> = files::curl_args("https://h/m.bin", Path::new("/tmp/p"))
            .iter().map(|a| a.to_string_lossy().into_owned()).collect();
        let joined = args.join(" ");
        assert!(joined.contains("--proto =https"), "{joined}");
        assert!(joined.contains("--proto-redir =https"), "{joined}");
        assert!(files::validate_url("http://h/m.bin").is_err(), "plain http never reaches curl");
    }

    #[test]
    fn relative_model_dirs_are_ignored() {
        let (dirs, ignored) = model_dirs_from(Some("rel/models:/abs/models::./dot"), Path::new("/home/u"));
        assert_eq!(dirs, vec![PathBuf::from("/abs/models"), PathBuf::from("/home/u/.cache/whisper-models")]);
        assert_eq!(ignored, vec!["rel/models".to_string(), "./dot".to_string()], "ignored entries are reported, never silently dropped");
        assert_eq!(model_dirs_from(None, Path::new("/home/u")).0, vec![PathBuf::from("/home/u/.cache/whisper-models")]);
    }

    #[test]
    fn home_dir_must_be_absolute() {
        assert!(home_dir_from(None).is_err(), "no HOME: never fall back to cwd");
        assert!(home_dir_from(Some("")).is_err());
        assert!(home_dir_from(Some("rel/home")).is_err(), "a relative HOME resolves against cwd");
        assert_eq!(home_dir_from(Some("/home/u")).unwrap(), PathBuf::from("/home/u"));
    }

    #[test]
    fn stale_temp_wavs_are_swept() {
        let d = tempfile::tempdir().unwrap();
        let old = d.path().join("brana-transcribe-abc123.wav");
        let fresh = d.path().join("brana-transcribe-def456.wav");
        let other = d.path().join("other-tool.wav");
        for p in [&old, &fresh, &other] {
            std::fs::write(p, b"x").unwrap();
        }
        let two_h_ago = std::time::SystemTime::now() - STALE_WAV_AGE * 2;
        std::fs::File::options().write(true).open(&old).unwrap().set_modified(two_h_ago).unwrap();
        std::fs::File::options().write(true).open(&other).unwrap().set_modified(two_h_ago).unwrap();
        assert_eq!(sweep_stale_wavs(d.path()), 1);
        assert!(!old.exists(), "leaked by a SIGKILLed run — swept");
        assert!(fresh.exists(), "in-flight wav kept");
        assert!(other.exists(), "not ours");
        assert_eq!(sweep_stale_wavs(&d.path().join("missing")), 0);
    }

    #[test]
    fn ffmpeg_stderr_reducer_keeps_only_pts_and_tail() {
        // 100k noisy lines must reduce to the frame times plus the last non-empty line —
        // the whole stderr is never held in memory.
        let mut lines: Vec<String> = Vec::new();
        for n in 0..100_000u32 {
            lines.push(format!("frame={n} fps=0.0 q=2.0 size=N/A time=00:00:{} bitrate=N/A", n % 60));
            if n % 1000 == 0 {
                lines.push(format!("[Parsed_showinfo_1 @ 0x5] n:{} pts:{} pts_time:{}.5    duration:1", n / 1000, n, n / 1000));
                lines.push("[Parsed_showinfo_1 @ 0x5] color_range:tv".into());
            }
        }
        lines.push("".into());
        lines.push("Conversion failed!".into());
        let (times, last) = reduce_ffmpeg_stderr(lines.iter().map(|l| l.as_str()));
        assert_eq!(times.len(), 100);
        assert_eq!(times[0], 0.5);
        assert_eq!(times[99], 99.5);
        assert_eq!(last, "Conversion failed!");
    }

    // ── t-3480 iteration-2 changes ──────────────────────────────────────

    #[test]
    fn frames_args_disable_progress_stats() {
        let args = frames_ffmpeg_args(Path::new("in.mp4"), Path::new("out"), Sampling::Every(5)).unwrap();
        assert!(pos(&args, "-nostats").is_some(), "\\r-terminated progress is the only unbounded line source: {}", lossy_join(&args));
    }

    #[test]
    fn stderr_reader_splits_on_carriage_return() {
        // Even with -nostats, treat \r as a line break: 100 KiB of \r-joined progress glued in
        // front of a showinfo line must not push the time past the per-line cap.
        let mut bytes: Vec<u8> = Vec::new();
        for n in 0..1200u32 {
            bytes.extend_from_slice(format!("frame={n} fps=0.0 q=2.0 size=N/A time=00:00:01 bitrate=N/A speed=1x    \r").as_bytes());
        }
        bytes.extend_from_slice(b"[Parsed_showinfo_1 @ 0x5] n:   0 pts:      0 pts_time:7.5     duration:1\n");
        let (times, last) = read_ffmpeg_stderr(std::io::Cursor::new(bytes));
        assert_eq!(times, vec![7.5]);
        assert!(last.starts_with("[Parsed_showinfo"), "{last:?}");
    }

    #[test]
    fn pts_times_only_from_showinfo_lines_not_echoed_tags() {
        // ffmpeg echoes the file's tags on stderr; a crafted title must not count as a frame.
        let stderr = "    title           : Parsed_showinfo pts_time:9 evil\n\
[Parsed_showinfo_1 @ 0x5] n:   0 pts:      0 pts_time:0       duration:1\n";
        assert_eq!(parse_pts_times(stderr), vec![0.0]);
    }

    #[test]
    fn explicit_model_path_needs_no_home() {
        // --model /abs/ggml-x.bin on a wav never touches the cache; HOME must not be required.
        let d = tempfile::tempdir().unwrap();
        let m = d.path().join("ggml-x.bin");
        write_model(d.path(), "ggml-x.bin", 2000);
        let dirs = model_dirs_for(Some(m.to_str().unwrap()), || bail!("HOME is not set")).unwrap();
        assert!(dirs.is_empty(), "a path spec resolves without any search dir");
        assert!(model_dirs_for(Some("small"), || bail!("HOME is not set")).is_err(), "a name needs the search dirs");
        assert!(model_dirs_for(None, || bail!("HOME is not set")).is_err());
    }

    #[test]
    fn ld_library_path_ignores_unusable_home() {
        assert_eq!(whisper_ld_library_path_from(Some(Path::new("/home/u")), None), "/home/u/.local/lib");
        assert_eq!(whisper_ld_library_path_from(None, Some("/opt/lib")), "/opt/lib", "no cwd-relative entry from a relative or unset HOME");
        assert_eq!(whisper_ld_library_path_from(None, None), "");
    }

    #[test]
    fn wav_args_output_is_a_file_url() {
        let args = wav_ffmpeg_args(Path::new("a.m4a"), Path::new("/tmp/o.wav")).unwrap();
        assert_eq!(args.last().unwrap().to_str(), Some("file:/tmp/o.wav"));
    }

    #[cfg(unix)]
    #[test]
    fn preexisting_frames_dir_must_be_private_and_real() {
        use std::os::unix::fs::PermissionsExt;
        let d = tempfile::tempdir().unwrap();
        let shared = d.path().join("shared");
        std::fs::create_dir(&shared).unwrap();
        std::fs::set_permissions(&shared, std::fs::Permissions::from_mode(0o777)).unwrap();
        assert!(create_private_dir(&shared).is_err(), "a group/other-writable dir lets another user plant frame_* mid-run");
        let mine = d.path().join("mine");
        std::fs::create_dir(&mine).unwrap();
        std::fs::set_permissions(&mine, std::fs::Permissions::from_mode(0o755)).unwrap();
        assert!(create_private_dir(&mine).is_ok(), "a pre-existing dir only I can write is fine");
        let target = d.path().join("elsewhere");
        std::fs::create_dir(&target).unwrap();
        std::os::unix::fs::symlink(&target, d.path().join("link")).unwrap();
        assert!(create_private_dir(&d.path().join("link")).is_err(), "a symlink leaf is not a private dir");
    }

    // ── t-3485: input first, frame-count warning ─────────────────────────

    #[test]
    fn missing_input_never_reaches_whisper_lookup_or_the_model_resolver() {
        // A typo'd path must fail before any lookup — the model one may be a multi-GB download.
        let which_called = std::cell::Cell::new(false);
        let resolve_called = std::cell::Cell::new(false);
        let r = preflight(
            Path::new("/nonexistent/talk.mp3"),
            None,
            Some("small"),
            || { which_called.set(true); Ok(PathBuf::from("/usr/bin/whisper-cli")) },
            |_| { resolve_called.set(true); Ok(PathBuf::from("/m/ggml-small.bin")) },
        );
        assert!(r.is_err(), "missing input is an error");
        assert!(!which_called.get() && !resolve_called.get(), "nothing runs for a missing input");
        let msg = r.unwrap_err().to_string();
        assert!(msg.contains("/nonexistent/talk.mp3"), "names the path: {msg}");

        let d = tempfile::tempdir().unwrap();
        let dir_input = d.path().join("adir");
        std::fs::create_dir(&dir_input).unwrap();
        assert!(preflight(&dir_input, None, Some("small"), || Ok(PathBuf::from("w")), |_| Ok(PathBuf::from("x"))).is_err(), "a directory is not an input file");

        // the order is input, whisper-cli, model: a missing whisper-cli never starts a download
        let f = d.path().join("talk.mp3");
        std::fs::write(&f, b"x").unwrap();
        let resolve_called = std::cell::Cell::new(false);
        let r = preflight(&f, None, Some("small"), || bail!("whisper-cli not found"), |_| { resolve_called.set(true); Ok(PathBuf::from("x")) });
        assert!(r.is_err() && !resolve_called.get(), "no model resolution without whisper-cli");

        let spec_seen = std::cell::RefCell::new(None);
        let (w, m) = preflight(&f, None, Some("small"), || Ok(PathBuf::from("/usr/bin/whisper-cli")), |spec| {
            *spec_seen.borrow_mut() = spec.map(String::from);
            Ok(PathBuf::from("/m/ggml-small.bin"))
        })
        .unwrap();
        assert_eq!((w, m), (PathBuf::from("/usr/bin/whisper-cli"), PathBuf::from("/m/ggml-small.bin")));
        assert_eq!(spec_seen.borrow().as_deref(), Some("small"), "an existing input goes on to the resolver");
    }

    #[test]
    fn bad_frames_dir_is_refused_before_the_model_resolver() {
        // --frames preconditions are local and cheap: they belong before any download too.
        let d = tempfile::tempdir().unwrap();
        let f = d.path().join("talk.mp4");
        std::fs::write(&f, b"x").unwrap();
        let out = d.path().join("frames");
        std::fs::create_dir(&out).unwrap();
        std::fs::write(out.join("frame_000001.jpg"), b"old").unwrap();
        let resolve_called = std::cell::Cell::new(false);
        let r = preflight(&f, Some(&out), None, || Ok(PathBuf::from("w")), |_| { resolve_called.set(true); Ok(PathBuf::from("x")) });
        assert!(r.is_err() && !resolve_called.get(), "a dir with frame_* leftovers fails before the model");
        assert!(!out.join("frame_000002.jpg").exists());
        let fresh = d.path().join("new");
        assert!(preflight(&f, Some(&fresh), None, || Ok(PathBuf::from("w")), |_| Ok(PathBuf::from("x"))).is_ok(), "a not-yet-existing dir is fine (created later)");
        assert!(!fresh.exists(), "preflight never creates anything");
    }

    #[cfg(unix)]
    #[test]
    fn unreadable_input_is_refused_before_the_resolver() {
        use std::os::unix::fs::PermissionsExt;
        let d = tempfile::tempdir().unwrap();
        let f = d.path().join("locked.mp3");
        std::fs::write(&f, b"x").unwrap();
        std::fs::set_permissions(&f, std::fs::Permissions::from_mode(0o000)).unwrap();
        if std::fs::File::open(&f).is_ok() {
            return; // root reads anything
        }
        let called = std::cell::Cell::new(false);
        let r = preflight(&f, None, None, || Ok(PathBuf::from("w")), |_| { called.set(true); Ok(PathBuf::from("x")) });
        std::fs::set_permissions(&f, std::fs::Permissions::from_mode(0o600)).unwrap();
        assert!(r.is_err() && !called.get());
    }

    #[test]
    fn frame_count_note_warns_above_the_threshold_with_mode_aware_advice() {
        assert!(frame_count_note(0, Sampling::Every(1)).is_none());
        assert!(frame_count_note(FRAME_WARN_THRESHOLD, Sampling::Every(1)).is_none(), "at the threshold: no warning");
        let note = frame_count_note(FRAME_WARN_THRESHOLD + 1, Sampling::Every(1)).expect("over the threshold warns");
        assert!(note.contains(&(FRAME_WARN_THRESHOLD + 1).to_string()) && note.contains("--every"), "{note}");
        assert!(note.contains("--scene"), "interval mode: suggests the sampler that bounds output by content: {note}");
        let note = frame_count_note(900, Sampling::Scene(0.05)).unwrap();
        assert!(note.contains("--scene") && note.contains("higher") && !note.contains("--every"), "scene mode: the user is already on --scene and --every conflicts with it: {note}");
    }

    // ── t-3473: manifest-tracked model containment ─────────────────────

    #[test]
    fn tracked_model_path_requires_exact_name_and_contained_path() {
        let d = tempfile::tempdir().unwrap();
        let root = d.path();
        let mk = |p: &str, url: &str| files::FileEntry {
            path: p.into(), sha256: "x".into(), size: 0, url: Some(url.into()), r2_key: None,
        };
        assert_eq!(
            tracked_model_path(root, &mk("models/ggml-base.bin", "https://h/m"), "ggml-base.bin"),
            Some(root.join("models/ggml-base.bin"))
        );
        // substring matches used to pass: a `.bak` or `ggml-base.bin-old` entry is not the model
        assert!(tracked_model_path(root, &mk("models/ggml-base.bin.bak", "https://h/m"), "ggml-base.bin").is_none());
        assert!(tracked_model_path(root, &mk("models/xggml-base.bin", "https://h/m"), "ggml-base.bin").is_none());
        // a hostile checkout cannot point the download at an attacker-chosen path or a plain-http URL
        assert!(tracked_model_path(root, &mk("/tmp/ggml-base.bin", "https://h/m"), "ggml-base.bin").is_none());
        assert!(tracked_model_path(root, &mk("../ggml-base.bin", "https://h/m"), "ggml-base.bin").is_none());
        assert!(tracked_model_path(root, &mk("models/ggml-base.bin", "http://h/m"), "ggml-base.bin").is_none());
    }

    #[test]
    fn whisper_failure_names_model_and_recovery() {
        let msg = whisper_failure_message(Path::new("/m/ggml-small.bin"), "error: failed to load model");
        assert!(msg.contains("/m/ggml-small.bin"));
        assert!(msg.contains("--model"));
        assert!(msg.contains("failed to load model"));
    }
}

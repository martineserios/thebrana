//! Large file tracking via manifest (.brana-files.json)
//!
//! Tracks binary assets, models, and datasets per project.
//! Manifest stores hashes + remote URLs. Files live outside git.

use anyhow::{bail, Context, Result};
use serde::{Deserialize, Serialize};
use std::collections::BTreeMap;
use std::io::Read as _;
use std::path::{Path, PathBuf};

pub const MANIFEST_NAME: &str = ".brana-files.json";

/// A single tracked file entry
#[derive(Debug, Clone, Serialize, Deserialize, PartialEq)]
pub struct FileEntry {
    /// Relative path from project root where the file should live
    pub path: String,
    /// SHA-256 hash of the file contents
    pub sha256: String,
    /// Size in bytes
    pub size: u64,
    /// Remote URL to download from (HTTP/HTTPS)
    #[serde(skip_serializing_if = "Option::is_none")]
    pub url: Option<String>,
    /// R2 bucket key (for push/pull via rclone)
    #[serde(skip_serializing_if = "Option::is_none")]
    pub r2_key: Option<String>,
}

/// The manifest file: maps logical names to file entries
#[derive(Debug, Clone, Serialize, Deserialize, Default, PartialEq)]
pub struct Manifest {
    #[serde(flatten)]
    pub files: BTreeMap<String, FileEntry>,
}

impl Manifest {
    /// Load manifest from a project directory. Returns empty if not found.
    pub fn load(project_dir: &Path) -> Result<Self> {
        let path = project_dir.join(MANIFEST_NAME);
        if !path.exists() {
            return Ok(Self::default());
        }
        let content = std::fs::read_to_string(&path)
            .with_context(|| format!("reading {}", path.display()))?;
        let manifest: Self = serde_json::from_str(&content)
            .with_context(|| format!("parsing {}", path.display()))?;
        Ok(manifest)
    }

    /// Save manifest to a project directory
    pub fn save(&self, project_dir: &Path) -> Result<()> {
        let path = project_dir.join(MANIFEST_NAME);
        let content = serde_json::to_string_pretty(self)?;
        std::fs::write(&path, content + "\n")
            .with_context(|| format!("writing {}", path.display()))?;
        Ok(())
    }

    /// Add or update an entry
    pub fn add(&mut self, name: String, entry: FileEntry) {
        self.files.insert(name, entry);
    }

    /// Check status of all tracked files against the filesystem
    pub fn status(&self, project_dir: &Path) -> Vec<FileStatus> {
        self.files
            .iter()
            .map(|(name, entry)| {
                let full_path = if Path::new(&entry.path).is_absolute() {
                    PathBuf::from(&entry.path)
                } else {
                    project_dir.join(&entry.path)
                };
                let state = if !full_path.exists() {
                    FileState::Missing
                } else {
                    match file_sha256(&full_path) {
                        Ok(hash) if hash == entry.sha256 => FileState::Ok,
                        Ok(hash) => FileState::Modified { actual_hash: hash },
                        Err(_) => FileState::Error,
                    }
                };
                FileStatus {
                    name: name.clone(),
                    entry: entry.clone(),
                    state,
                }
            })
            .collect()
    }
}

#[derive(Debug, Clone, PartialEq)]
pub enum FileState {
    Ok,
    Missing,
    Modified { actual_hash: String },
    Error,
}

#[derive(Debug, Clone)]
pub struct FileStatus {
    pub name: String,
    pub entry: FileEntry,
    pub state: FileState,
}

/// Compute SHA-256 of a file
pub fn file_sha256(path: &Path) -> Result<String> {
    use std::io::BufReader;
    let file = std::fs::File::open(path)?;
    let mut reader = BufReader::new(file);
    let mut hasher = Sha256::new();
    let mut buf = [0u8; 8192];
    loop {
        let n = reader.read(&mut buf)?;
        if n == 0 {
            break;
        }
        hasher.update(&buf[..n]);
    }
    Ok(hasher.finalize_hex())
}

/// Minimal SHA-256 implementation (no external crate needed)
struct Sha256 {
    state: [u32; 8],
    buffer: Vec<u8>,
    total_len: u64,
}

impl Sha256 {
    fn new() -> Self {
        Self {
            state: [
                0x6a09e667, 0xbb67ae85, 0x3c6ef372, 0xa54ff53a,
                0x510e527f, 0x9b05688c, 0x1f83d9ab, 0x5be0cd19,
            ],
            buffer: Vec::new(),
            total_len: 0,
        }
    }

    fn update(&mut self, data: &[u8]) {
        self.buffer.extend_from_slice(data);
        self.total_len += data.len() as u64;

        while self.buffer.len() >= 64 {
            let block: [u8; 64] = self.buffer[..64].try_into().unwrap();
            self.process_block(&block);
            self.buffer.drain(..64);
        }
    }

    fn process_block(&mut self, block: &[u8; 64]) {
        const K: [u32; 64] = [
            0x428a2f98, 0x71374491, 0xb5c0fbcf, 0xe9b5dba5,
            0x3956c25b, 0x59f111f1, 0x923f82a4, 0xab1c5ed5,
            0xd807aa98, 0x12835b01, 0x243185be, 0x550c7dc3,
            0x72be5d74, 0x80deb1fe, 0x9bdc06a7, 0xc19bf174,
            0xe49b69c1, 0xefbe4786, 0x0fc19dc6, 0x240ca1cc,
            0x2de92c6f, 0x4a7484aa, 0x5cb0a9dc, 0x76f988da,
            0x983e5152, 0xa831c66d, 0xb00327c8, 0xbf597fc7,
            0xc6e00bf3, 0xd5a79147, 0x06ca6351, 0x14292967,
            0x27b70a85, 0x2e1b2138, 0x4d2c6dfc, 0x53380d13,
            0x650a7354, 0x766a0abb, 0x81c2c92e, 0x92722c85,
            0xa2bfe8a1, 0xa81a664b, 0xc24b8b70, 0xc76c51a3,
            0xd192e819, 0xd6990624, 0xf40e3585, 0x106aa070,
            0x19a4c116, 0x1e376c08, 0x2748774c, 0x34b0bcb5,
            0x391c0cb3, 0x4ed8aa4a, 0x5b9cca4f, 0x682e6ff3,
            0x748f82ee, 0x78a5636f, 0x84c87814, 0x8cc70208,
            0x90befffa, 0xa4506ceb, 0xbef9a3f7, 0xc67178f2,
        ];

        let mut w = [0u32; 64];
        for i in 0..16 {
            w[i] = u32::from_be_bytes(block[i * 4..(i + 1) * 4].try_into().unwrap());
        }
        for i in 16..64 {
            let s0 = w[i - 15].rotate_right(7) ^ w[i - 15].rotate_right(18) ^ (w[i - 15] >> 3);
            let s1 = w[i - 2].rotate_right(17) ^ w[i - 2].rotate_right(19) ^ (w[i - 2] >> 10);
            w[i] = w[i - 16]
                .wrapping_add(s0)
                .wrapping_add(w[i - 7])
                .wrapping_add(s1);
        }

        let [mut a, mut b, mut c, mut d, mut e, mut f, mut g, mut h] = self.state;

        for i in 0..64 {
            let s1 = e.rotate_right(6) ^ e.rotate_right(11) ^ e.rotate_right(25);
            let ch = (e & f) ^ ((!e) & g);
            let temp1 = h
                .wrapping_add(s1)
                .wrapping_add(ch)
                .wrapping_add(K[i])
                .wrapping_add(w[i]);
            let s0 = a.rotate_right(2) ^ a.rotate_right(13) ^ a.rotate_right(22);
            let maj = (a & b) ^ (a & c) ^ (b & c);
            let temp2 = s0.wrapping_add(maj);

            h = g;
            g = f;
            f = e;
            e = d.wrapping_add(temp1);
            d = c;
            c = b;
            b = a;
            a = temp1.wrapping_add(temp2);
        }

        self.state[0] = self.state[0].wrapping_add(a);
        self.state[1] = self.state[1].wrapping_add(b);
        self.state[2] = self.state[2].wrapping_add(c);
        self.state[3] = self.state[3].wrapping_add(d);
        self.state[4] = self.state[4].wrapping_add(e);
        self.state[5] = self.state[5].wrapping_add(f);
        self.state[6] = self.state[6].wrapping_add(g);
        self.state[7] = self.state[7].wrapping_add(h);
    }

    fn finalize_hex(mut self) -> String {
        let bit_len = self.total_len * 8;
        self.buffer.push(0x80);
        while self.buffer.len() % 64 != 56 {
            self.buffer.push(0);
        }
        self.buffer.extend_from_slice(&bit_len.to_be_bytes());

        while self.buffer.len() >= 64 {
            let block: [u8; 64] = self.buffer[..64].try_into().unwrap();
            self.process_block(&block);
            self.buffer.drain(..64);
        }

        self.state
            .iter()
            .map(|s| format!("{s:08x}"))
            .collect::<String>()
    }
}

/// How long an in-flight `.part-<pid>` may go untouched before it counts as abandoned.
/// Age-based rather than pid-liveness so it needs no `/proc` (macOS portable): a live
/// download keeps writing its part file, an interrupted one never touches it again.
pub const STALE_PART_AGE: std::time::Duration = std::time::Duration::from_secs(60 * 60);

/// In-progress download path for `dest`: `<dest>.part-<pid>`. Never matches the final
/// name, so discovery and hash checks never see a half-written file (t-3473).
pub fn part_path(dest: &Path) -> PathBuf {
    let mut name = dest.file_name().unwrap_or_default().to_os_string();
    name.push(format!(".part-{}", std::process::id()));
    dest.with_file_name(name)
}

/// Remove `*.part-*` files in `dir` untouched for longer than `STALE_PART_AGE`
/// (left by a killed download). Missing dir is a no-op. Returns how many were removed.
pub fn sweep_stale_parts(dir: &Path) -> usize {
    let Ok(rd) = std::fs::read_dir(dir) else { return 0 };
    let now = std::time::SystemTime::now();
    let mut swept = 0;
    for e in rd.flatten() {
        if !e.file_name().to_string_lossy().contains(".part-") {
            continue;
        }
        let stale = e
            .metadata()
            .and_then(|m| m.modified())
            .ok()
            .and_then(|t| now.duration_since(t).ok())
            .map(|age| age > STALE_PART_AGE)
            .unwrap_or(false);
        if stale && std::fs::remove_file(e.path()).is_ok() {
            swept += 1;
        }
    }
    swept
}

/// Only `https://` downloads. The manifest is checked into the project, so a hostile
/// checkout must not be able to point curl at `file://` or a plaintext mirror.
pub fn validate_url(url: &str) -> Result<()> {
    if !url.starts_with("https://") || url.len() == "https://".len() || url.trim() != url {
        bail!("refusing non-https download URL: {url:?}");
    }
    Ok(())
}

/// Resolve a manifest entry to a path inside `project_dir`, refusing anything a hostile
/// manifest could use to write elsewhere: absolute paths, `..` (or any non-plain)
/// components, empty paths. Validates the URL when present. Writes nothing.
pub fn validate_entry(project_dir: &Path, entry: &FileEntry) -> Result<PathBuf> {
    use std::path::Component;
    if entry.path.is_empty() {
        bail!("manifest entry has an empty path");
    }
    let rel = Path::new(&entry.path);
    if rel.is_absolute() {
        bail!("manifest path must be relative to the project: {:?}", entry.path);
    }
    if rel.components().any(|c| !matches!(c, Component::Normal(_))) {
        bail!("manifest path must stay inside the project (no '..'): {:?}", entry.path);
    }
    if let Some(url) = &entry.url {
        validate_url(url)?;
    }
    Ok(project_dir.join(rel))
}

/// Download `url` to `dest` atomically: curl writes `<dest>.part-<pid>`, the hash is
/// checked there when `expected_sha256` is given, and only then is it renamed into place.
/// A failed, interrupted or mismatched download leaves nothing at `dest`. Non-https URLs
/// are refused before the filesystem is touched.
pub fn download_file(url: &str, dest: &Path, expected_sha256: Option<&str>) -> Result<()> {
    validate_url(url)?;
    download_file_with(url, dest, expected_sha256, curl_fetch)
}

fn curl_fetch(url: &str, part: &Path) -> Result<()> {
    let status = std::process::Command::new("curl")
        .args(["-fSL", "-o"])
        .arg(part)
        .arg(url)
        .status()
        .context("curl not found")?;
    if !status.success() {
        bail!("download failed: {url}");
    }
    Ok(())
}

/// `download_file` with the transfer injected (testable without network).
fn download_file_with(
    url: &str,
    dest: &Path,
    expected_sha256: Option<&str>,
    fetch: impl Fn(&str, &Path) -> Result<()>,
) -> Result<()> {
    if let Some(parent) = dest.parent() {
        std::fs::create_dir_all(parent)?;
        sweep_stale_parts(parent);
    }
    let part = part_path(dest);
    let result = fetch(url, &part).and_then(|()| match expected_sha256 {
        None => Ok(()),
        Some(expected) => {
            let got = file_sha256(&part)?;
            if got != expected {
                bail!("hash mismatch after download (got {got})");
            }
            Ok(())
        }
    });
    if let Err(e) = result {
        let _ = std::fs::remove_file(&part);
        return Err(e);
    }
    std::fs::rename(&part, dest)
        .with_context(|| format!("failed to move download into place: {}", dest.display()))
}

/// Push a file to R2 via rclone
pub fn push_to_r2(local_path: &Path, r2_key: &str, remote_name: &str) -> Result<()> {
    let dest = format!("{remote_name}:{r2_key}");
    let status = std::process::Command::new("rclone")
        .args(["copyto", "--progress"])
        .arg(local_path)
        .arg(&dest)
        .status()
        .context("rclone not found — install rclone and configure R2 remote")?;
    if !status.success() {
        bail!("rclone push failed: {dest}");
    }
    Ok(())
}

/// Pull all missing/modified files from their remote sources
pub fn pull(manifest: &Manifest, project_dir: &Path) -> Result<PullResult> {
    let mut downloaded = 0;
    let mut skipped = 0;
    let mut failed = Vec::new();

    for (name, entry) in &manifest.files {
        // Containment first (t-3473): a hostile manifest never gets a write anywhere.
        let full_path = match validate_entry(project_dir, entry) {
            Ok(p) => p,
            Err(e) => {
                failed.push(format!("{name}: {e}"));
                continue;
            }
        };
        if full_path.exists() {
            if let Ok(hash) = file_sha256(&full_path) {
                if hash == entry.sha256 {
                    skipped += 1;
                    continue;
                }
            }
        }

        if let Some(url) = &entry.url {
            // sha256 is verified on the .part before the rename, so a mismatch never
            // reaches full_path.
            match download_file(url, &full_path, Some(&entry.sha256)) {
                Ok(()) => downloaded += 1,
                Err(e) => failed.push(format!("{name}: {e}")),
            }
        } else {
            failed.push(format!("{name}: no download URL configured"));
        }
    }

    Ok(PullResult { downloaded, skipped, failed })
}

#[derive(Debug)]
pub struct PullResult {
    pub downloaded: usize,
    pub skipped: usize,
    pub failed: Vec<String>,
}

/// Push all tracked files that have an r2_key to the R2 remote
pub fn push(manifest: &Manifest, project_dir: &Path, remote_name: &str) -> Result<PushResult> {
    let mut uploaded = 0;
    let mut skipped = Vec::new();
    let mut failed = Vec::new();

    for (name, entry) in &manifest.files {
        let r2_key = match &entry.r2_key {
            Some(k) => k,
            None => {
                skipped.push(format!("{name}: no r2_key"));
                continue;
            }
        };

        let full_path = if Path::new(&entry.path).is_absolute() {
            PathBuf::from(&entry.path)
        } else {
            project_dir.join(&entry.path)
        };
        if !full_path.exists() {
            failed.push(format!("{name}: file not found at {}", entry.path));
            continue;
        }

        match push_to_r2(&full_path, r2_key, remote_name) {
            Ok(()) => uploaded += 1,
            Err(e) => failed.push(format!("{name}: {e}")),
        }
    }

    Ok(PushResult { uploaded, skipped, failed })
}

#[derive(Debug)]
pub struct PushResult {
    pub uploaded: usize,
    pub skipped: Vec<String>,
    pub failed: Vec<String>,
}

/// Add a file to the manifest by computing its hash
pub fn add_file(
    manifest: &mut Manifest,
    name: &str,
    file_path: &Path,
    project_dir: &Path,
    url: Option<String>,
    r2_key: Option<String>,
) -> Result<()> {
    if !file_path.exists() {
        bail!("file not found: {}", file_path.display());
    }
    let metadata = std::fs::metadata(file_path)?;
    let sha256 = file_sha256(file_path)?;

    let rel_path = file_path
        .strip_prefix(project_dir)
        .unwrap_or(file_path)
        .to_string_lossy()
        .to_string();

    manifest.add(
        name.to_string(),
        FileEntry {
            path: rel_path,
            sha256,
            size: metadata.len(),
            url,
            r2_key,
        },
    );

    Ok(())
}

// ── Tests ───────────────────────────────────────────────────────────────

#[cfg(test)]
mod tests {
    use super::*;
    use std::fs;

    #[test]
    fn test_sha256_known_value() {
        let dir = std::env::temp_dir().join("brana-test-sha256");
        fs::create_dir_all(&dir).unwrap();
        let path = dir.join("empty.bin");
        fs::write(&path, b"").unwrap();
        let hash = file_sha256(&path).unwrap();
        assert_eq!(hash, "e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855");

        let path2 = dir.join("hello.bin");
        fs::write(&path2, b"hello").unwrap();
        let hash2 = file_sha256(&path2).unwrap();
        assert_eq!(hash2, "2cf24dba5fb0a30e26e83b2ac5b9e29e1b161e5c1fa7425e73043362938b9824");
        fs::remove_dir_all(&dir).unwrap();
    }

    #[test]
    fn test_manifest_roundtrip() {
        let dir = std::env::temp_dir().join("brana-test-manifest-rt");
        let _ = fs::remove_dir_all(&dir);
        fs::create_dir_all(&dir).unwrap();

        let mut manifest = Manifest::default();
        manifest.add(
            "whisper-base".into(),
            FileEntry {
                path: "models/ggml-base.bin".into(),
                sha256: "abc123".into(),
                size: 142_000_000,
                url: Some("https://example.com/model.bin".into()),
                r2_key: Some("models/ggml-base.bin".into()),
            },
        );

        manifest.save(&dir).unwrap();
        let loaded = Manifest::load(&dir).unwrap();
        assert_eq!(manifest, loaded);
        fs::remove_dir_all(&dir).unwrap();
    }

    #[test]
    fn test_manifest_empty_if_missing() {
        let dir = std::env::temp_dir().join("brana-test-no-manifest2");
        let _ = fs::remove_dir_all(&dir);
        fs::create_dir_all(&dir).unwrap();
        let manifest = Manifest::load(&dir).unwrap();
        assert!(manifest.files.is_empty());
        fs::remove_dir_all(&dir).unwrap();
    }

    #[test]
    fn test_status_detects_missing() {
        let dir = std::env::temp_dir().join("brana-test-status2");
        let _ = fs::remove_dir_all(&dir);
        fs::create_dir_all(&dir).unwrap();

        let mut manifest = Manifest::default();
        manifest.add("model".into(), FileEntry {
            path: "models/test.bin".into(),
            sha256: "abc".into(),
            size: 100,
            url: None,
            r2_key: None,
        });

        let statuses = manifest.status(&dir);
        assert_eq!(statuses.len(), 1);
        assert_eq!(statuses[0].state, FileState::Missing);
        fs::remove_dir_all(&dir).unwrap();
    }

    #[test]
    fn test_status_detects_ok() {
        let dir = std::env::temp_dir().join("brana-test-status-ok2");
        let _ = fs::remove_dir_all(&dir);
        fs::create_dir_all(&dir).unwrap();

        let model_dir = dir.join("models");
        fs::create_dir_all(&model_dir).unwrap();
        fs::write(model_dir.join("test.bin"), b"hello").unwrap();

        let mut manifest = Manifest::default();
        manifest.add("model".into(), FileEntry {
            path: "models/test.bin".into(),
            sha256: "2cf24dba5fb0a30e26e83b2ac5b9e29e1b161e5c1fa7425e73043362938b9824".into(),
            size: 5,
            url: None,
            r2_key: None,
        });

        let statuses = manifest.status(&dir);
        assert_eq!(statuses.len(), 1);
        assert_eq!(statuses[0].state, FileState::Ok);
        fs::remove_dir_all(&dir).unwrap();
    }

    #[test]
    fn test_status_detects_modified() {
        let dir = std::env::temp_dir().join("brana-test-status-mod2");
        let _ = fs::remove_dir_all(&dir);
        fs::create_dir_all(&dir).unwrap();

        let model_dir = dir.join("models");
        fs::create_dir_all(&model_dir).unwrap();
        fs::write(model_dir.join("test.bin"), b"changed").unwrap();

        let mut manifest = Manifest::default();
        manifest.add("model".into(), FileEntry {
            path: "models/test.bin".into(),
            sha256: "original_hash".into(),
            size: 5,
            url: None,
            r2_key: None,
        });

        let statuses = manifest.status(&dir);
        assert_eq!(statuses.len(), 1);
        assert!(matches!(statuses[0].state, FileState::Modified { .. }));
        fs::remove_dir_all(&dir).unwrap();
    }

    #[test]
    fn test_add_file_computes_hash() {
        let dir = std::env::temp_dir().join("brana-test-add2");
        let _ = fs::remove_dir_all(&dir);
        fs::create_dir_all(&dir).unwrap();
        fs::write(dir.join("data.bin"), b"test data").unwrap();

        let mut manifest = Manifest::default();
        add_file(&mut manifest, "test-data", &dir.join("data.bin"), &dir, Some("https://example.com/data.bin".into()), None).unwrap();

        assert_eq!(manifest.files.len(), 1);
        let entry = &manifest.files["test-data"];
        assert_eq!(entry.path, "data.bin");
        assert_eq!(entry.size, 9);
        assert!(!entry.sha256.is_empty());
        fs::remove_dir_all(&dir).unwrap();
    }

    // ── t-3473: atomic .part download, stale-part sweep, manifest containment ──

    fn entry(path: &str, url: Option<&str>) -> FileEntry {
        FileEntry { path: path.into(), sha256: "x".into(), size: 0, url: url.map(String::from), r2_key: None }
    }

    fn part_files(dir: &Path) -> Vec<String> {
        fs::read_dir(dir)
            .map(|rd| {
                rd.flatten()
                    .map(|e| e.file_name().to_string_lossy().into_owned())
                    .filter(|n| n.contains(".part-"))
                    .collect()
            })
            .unwrap_or_default()
    }

    #[test]
    fn download_writes_to_part_then_renames() {
        let d = tempfile::tempdir().unwrap();
        let dest = d.path().join("models").join("m.bin");
        let seen = std::cell::RefCell::new(None);
        download_file_with("https://x/m.bin", &dest, None, |url, tmp: &Path| {
            assert_eq!(url, "https://x/m.bin");
            assert!(!dest.exists(), "dest must not exist while the download is in flight");
            let name = tmp.file_name().unwrap().to_string_lossy().into_owned();
            assert!(name.starts_with("m.bin.part-"), "got {name}");
            *seen.borrow_mut() = Some(tmp.to_path_buf());
            fs::write(tmp, b"hello")?;
            Ok(())
        })
        .unwrap();
        assert_eq!(fs::read(&dest).unwrap(), b"hello");
        assert!(!seen.borrow().as_ref().unwrap().exists(), "part file must be renamed away");
        assert!(part_files(dest.parent().unwrap()).is_empty());
        let pid = std::process::id();
        assert!(part_path(&dest).to_string_lossy().ends_with(&format!("m.bin.part-{pid}")));
    }

    #[test]
    fn failed_download_leaves_nothing_at_dest() {
        let d = tempfile::tempdir().unwrap();
        let dest = d.path().join("m.bin");
        let r = download_file_with("https://x/m.bin", &dest, None, |_, tmp: &Path| {
            fs::write(tmp, b"half")?; // interrupted mid-stream
            bail!("connection reset")
        });
        assert!(r.is_err());
        assert!(!dest.exists(), "a failed download must leave no file at dest");
        assert!(part_files(d.path()).is_empty(), "and no partial behind");
    }

    #[test]
    fn sha_is_verified_before_rename() {
        let d = tempfile::tempdir().unwrap();
        let dest = d.path().join("m.bin");
        let hello = "2cf24dba5fb0a30e26e83b2ac5b9e29e1b161e5c1fa7425e73043362938b9824";
        let other = "0000000000000000000000000000000000000000000000000000000000000000";
        let fetch = |_: &str, tmp: &Path| { fs::write(tmp, b"hello")?; Ok(()) };
        let r = download_file_with("https://x/m.bin", &dest, Some(other), fetch);
        assert!(r.is_err(), "hash mismatch must fail");
        assert!(!dest.exists(), "mismatched content must never reach dest");
        assert!(part_files(d.path()).is_empty());
        download_file_with("https://x/m.bin", &dest, Some(hello), fetch).unwrap();
        assert!(dest.exists());
    }

    #[test]
    fn stale_parts_are_swept_fresh_ones_kept() {
        let d = tempfile::tempdir().unwrap();
        let old = d.path().join("old.bin.part-1");
        let fresh = d.path().join("fresh.bin.part-2");
        let keep = d.path().join("keep.bin");
        for p in [&old, &fresh, &keep] {
            fs::write(p, b"x").unwrap();
        }
        let two_h_ago = std::time::SystemTime::now() - STALE_PART_AGE * 2;
        fs::File::options().write(true).open(&old).unwrap().set_modified(two_h_ago).unwrap();
        assert_eq!(sweep_stale_parts(d.path()), 1);
        assert!(!old.exists(), "stale partial swept");
        assert!(fresh.exists(), "in-flight partial kept");
        assert!(keep.exists(), "non-partials untouched");
        assert_eq!(sweep_stale_parts(&d.path().join("missing")), 0, "missing dir is a no-op");
    }

    #[test]
    fn validate_entry_rejects_hostile_paths_and_urls() {
        let d = tempfile::tempdir().unwrap();
        let root = d.path();
        for bad in ["/etc/passwd", "../escape.bin", "models/../../escape.bin", ""] {
            assert!(validate_entry(root, &entry(bad, Some("https://h/x"))).is_err(), "path {bad:?} must be rejected");
        }
        for bad in ["http://h/x", "file:///etc/passwd", "ftp://h/x", "HTTPS://h/x "] {
            assert!(validate_entry(root, &entry("models/m.bin", Some(bad))).is_err(), "url {bad:?} must be rejected");
        }
        assert_eq!(
            validate_entry(root, &entry("models/m.bin", Some("https://h/x"))).unwrap(),
            root.join("models/m.bin")
        );
        assert!(validate_entry(root, &entry("models/m.bin", None)).is_ok(), "url is optional");
    }

    #[test]
    fn download_file_refuses_non_https_before_any_write() {
        let d = tempfile::tempdir().unwrap();
        let dest = d.path().join("sub").join("x.bin");
        assert!(download_file("http://127.0.0.1:9/x", &dest, None).is_err());
        assert!(!d.path().join("sub").exists(), "no directory or file may be created for a rejected URL");
    }

    #[test]
    fn pull_rejects_hostile_manifest_entries_without_writing() {
        let d = tempfile::tempdir().unwrap();
        let proj = d.path().join("proj");
        fs::create_dir_all(&proj).unwrap();
        let abs = d.path().join("abs.bin");
        let mut m = Manifest::default();
        m.add("esc".into(), entry("../escape.bin", Some("https://127.0.0.1:9/x")));
        m.add("abs".into(), entry(abs.to_str().unwrap(), Some("https://127.0.0.1:9/x")));
        m.add("plain".into(), entry("ok.bin", Some("http://127.0.0.1:9/x")));
        let r = pull(&m, &proj).unwrap();
        assert_eq!(r.downloaded, 0);
        assert_eq!(r.failed.len(), 3, "{:?}", r.failed);
        assert!(!d.path().join("escape.bin").exists());
        assert!(!abs.exists());
        assert!(!proj.join("ok.bin").exists());
        assert!(part_files(d.path()).is_empty() && part_files(&proj).is_empty());
    }
}

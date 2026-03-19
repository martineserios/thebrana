//! Command handlers for `brana files` subcommands

use crate::cli::FilesCmd;
use crate::files;
use crate::util::find_project_root;
use std::path::PathBuf;

pub fn cmd_files(cmd: FilesCmd) {
    let project_dir = find_project_root().unwrap_or_else(|| {
        eprintln!("Not in git repo");
        std::process::exit(1);
    });
    let manifest = match files::Manifest::load(&project_dir) {
        Ok(m) => m,
        Err(e) => {
            eprintln!("Error loading manifest: {e:#}");
            std::process::exit(1);
        }
    };

    match cmd {
        FilesCmd::List => cmd_list(&manifest),
        FilesCmd::Status => cmd_status(&manifest, &project_dir),
        FilesCmd::Add { name, path, url, r2_key } => cmd_add(manifest, &project_dir, &name, &path, url, r2_key),
        FilesCmd::Pull => cmd_pull(&manifest, &project_dir),
        FilesCmd::Push { remote } => cmd_push(&manifest, &project_dir, &remote),
    }
}

fn cmd_list(manifest: &files::Manifest) {
    if manifest.files.is_empty() {
        println!("No tracked files. Use `brana files add` to register files.");
        return;
    }
    println!("{:<20} {:<40} {:>10}  {}", "NAME", "PATH", "SIZE", "REMOTE");
    println!("{}", "-".repeat(90));
    for (name, entry) in &manifest.files {
        let size = humanize_bytes(entry.size);
        let remote = entry.url.as_deref().or(entry.r2_key.as_deref()).unwrap_or("-");
        println!("{:<20} {:<40} {:>10}  {}", name, entry.path, size, remote);
    }
}

fn cmd_status(manifest: &files::Manifest, project_dir: &PathBuf) {
    if manifest.files.is_empty() {
        println!("No tracked files.");
        return;
    }
    for s in manifest.status(project_dir) {
        let icon = match &s.state {
            files::FileState::Ok => "\x1b[32m✓\x1b[0m",
            files::FileState::Missing => "\x1b[31m✗\x1b[0m",
            files::FileState::Modified { .. } => "\x1b[33m~\x1b[0m",
            files::FileState::Error => "\x1b[31m!\x1b[0m",
        };
        let detail = match &s.state {
            files::FileState::Ok => "ok".to_string(),
            files::FileState::Missing => "missing".to_string(),
            files::FileState::Modified { actual_hash } => {
                format!("modified (hash: {}...)", &actual_hash[..8.min(actual_hash.len())])
            }
            files::FileState::Error => "error reading file".to_string(),
        };
        println!("{} {:<20} {}", icon, s.name, detail);
    }
}

fn cmd_add(
    mut manifest: files::Manifest,
    project_dir: &PathBuf,
    name: &str,
    path: &PathBuf,
    url: Option<String>,
    r2_key: Option<String>,
) {
    let abs_path = if path.is_absolute() {
        path.clone()
    } else {
        std::env::current_dir().unwrap_or_default().join(path)
    };
    match files::add_file(&mut manifest, name, &abs_path, project_dir, url, r2_key) {
        Ok(()) => {
            if let Err(e) = manifest.save(project_dir) {
                eprintln!("Error saving manifest: {e:#}");
                std::process::exit(1);
            }
            let entry = &manifest.files[name];
            println!("Added {} → {} ({})", name, entry.path, humanize_bytes(entry.size));
            println!("SHA-256: {}", entry.sha256);
        }
        Err(e) => {
            eprintln!("Error: {e:#}");
            std::process::exit(1);
        }
    }
}

fn cmd_pull(manifest: &files::Manifest, project_dir: &PathBuf) {
    if manifest.files.is_empty() {
        println!("No tracked files to pull.");
        return;
    }
    match files::pull(manifest, project_dir) {
        Ok(result) => {
            if result.downloaded > 0 {
                println!("Downloaded: {}", result.downloaded);
            }
            if result.skipped > 0 {
                println!("Up to date: {}", result.skipped);
            }
            for f in &result.failed {
                eprintln!("Failed: {f}");
            }
            if !result.failed.is_empty() {
                std::process::exit(1);
            }
        }
        Err(e) => {
            eprintln!("Error: {e:#}");
            std::process::exit(1);
        }
    }
}

fn cmd_push(manifest: &files::Manifest, project_dir: &PathBuf, remote: &str) {
    if manifest.files.is_empty() {
        println!("No tracked files to push.");
        return;
    }
    match files::push(manifest, project_dir, remote) {
        Ok(result) => {
            if result.uploaded > 0 {
                println!("Uploaded: {}", result.uploaded);
            }
            for s in &result.skipped {
                println!("Skipped: {s}");
            }
            for f in &result.failed {
                eprintln!("Failed: {f}");
            }
            if !result.failed.is_empty() {
                std::process::exit(1);
            }
        }
        Err(e) => {
            eprintln!("Error: {e:#}");
            std::process::exit(1);
        }
    }
}

fn humanize_bytes(bytes: u64) -> String {
    if bytes >= 1_073_741_824 {
        format!("{:.1} GB", bytes as f64 / 1_073_741_824.0)
    } else if bytes >= 1_048_576 {
        format!("{:.1} MB", bytes as f64 / 1_048_576.0)
    } else if bytes >= 1024 {
        format!("{:.1} KB", bytes as f64 / 1024.0)
    } else {
        format!("{} B", bytes)
    }
}

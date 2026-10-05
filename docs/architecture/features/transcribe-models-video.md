# Feature: `brana transcribe` — any whisper model, video + frames

**Date:** 2026-10-05
**Status:** implemented — unit + real-ffmpeg tests; e2e verified 2026-10-05 (video+frames via whisper-cli, real `--model tiny` download, no-audio rollback)
**Task:** t-3470

## Problem

`brana transcribe` is pinned to a three-value `ModelSize` enum (tiny/base/small), defaults to
`base` even when a better model is installed, and only handles audio. Users with `medium`/`large`
models, or with video sources, cannot use them.

## Decision Record (frozen 2026-10-05)

**Context:** whisper.cpp ships many ggml models (`tiny`…`large-v3-turbo`, `.en`, quantized `-q5_0`…).
**Decision:** treat a model as *any* `ggml-<name>.bin`; rank "best" by file size on disk (larger =
better, robust to unknown/quantized names). Default = largest installed; none installed → `small`.
**Consequences:** no hard-coded model list to maintain; a quantized large model can rank below an
unquantized medium only if it is smaller on disk — accepted, `--model` overrides.
English-only (`.en`) models are skipped by the default pick while a multilingual model exists:
the run uses `-l auto`, and an `.en` model would force-decode other languages as English
(challenger F6, 2026-10-05).

## Scope (v1)

- `--model <name|path>` (optional, no default string). `name` → `ggml-<name>.bin`; a value that
  exists as a file or contains `/` is a path.
- Discovery dirs: `$BRANA_WHISPER_MODELS` (colon-separated, optional) then `~/.cache/whisper-models`.
- Default: largest installed model. None installed → download `ggml-small.bin` (manifest first, then
  HuggingFace, existing `ensure_model` flow).
- A named model that is not installed is downloaded from HuggingFace (name validated to
  `[A-Za-z0-9._-]`).
- Video input (`mp4 mkv mov webm avi m4v`): audio extracted via ffmpeg (existing `ensure_wav`).
- `--frames <DIR>`: extract JPEG frames with ffmpeg every `--every <SECS>` (default 10; `--every`
  requires `--frames`) into DIR. Frames are sampled with a `select` filter (first frame, then the
  first frame ≥ N s after the last kept one), not `fps=1/N` — `fps` rounds to the nearest tick and was
  measured shifting frames by several seconds. Each frame is **labelled with its real `pts_time`**
  from ffmpeg's `showinfo`, never `index × N`, so sparse/variable-frame-rate sources (screen
  recordings, static slides) stay correctly labelled. Requires ffmpeg ≥ 5.1 (`-fps_mode`).
  Frames are opt-in: a video without `--frames` yields the transcript only.
  Transcript is then printed with segment timestamps, followed by a frame index
  (`frame_000001.jpg @ 00:00:00`) so frames and speech align.

## Non-goals (v1)

- Scene-change frame detection (task text mentioned "scene detect") — deferred to t-3471. Real per-frame timestamps (its prerequisite) are already in place.
- Sweeping `*.part-<pid>` files left by a killed download (they are ignored by discovery but use
  disk) — t-3473 (with the sibling `brana-core` `download_file` atomic-download fix); a ggml
  magic-byte check in discovery — not tracked.

## Assumptions

- largest installed: chose file size as the ranking because it generalises to any model name — confirmed by user ("largest = better").
- no model installed: chose auto-download of small — confirmed by user.
- frames via ffmpeg: confirmed by user.
- frames are opt-in (`--frames DIR`), not produced for every video: chose opt-in because frame
  extraction writes many files — confirmed by user 2026-10-05.
- scene detect deferred to a follow-up task (t-3471) — confirmed by user 2026-10-05.
- when only `.en` models are installed they are used (with a stderr warning) rather than
  auto-downloading `small` — confirmed by user 2026-10-05.

## Behavior

- `brana transcribe a.mp3` with base+small installed → uses small (prints which model on stderr).
- `brana transcribe a.mp3 --model large-v3` → uses/downloads `ggml-large-v3.bin`.
- `brana transcribe talk.mp4 --frames out/ --every 5` → `out/frame_%06d.jpg` + timestamped transcript.

## Edge Cases

- `--frames` on an audio-only file → error ("--frames needs a video input").
- `--every 0` → error.
- Model files of 1000 bytes or less, and in-progress `*.part-<pid>` downloads, are ignored by discovery.
  Downloads go to a `.part` file and are renamed on success.
- Symlinked model files are followed (size and file type are the target's).
- `--frames DIR` that already contains `frame_*` files → error (the index is built from the directory).
  A run that fails after extracting frames removes the frames it wrote, so the retry is not refused.
- Video input is detected by extension; frames are extracted before transcription, so a container
  with no video stream fails fast. Model names are case-insensitive.
- The converted temp wav is unique per run and removed on every exit path.
- Unsafe model name (`../x`) → error.

## Design

All in `system/cli/rust/crates/brana-cli/src/transcribe.rs`; CLI args in `cli.rs`; handler in
`commands/misc.rs`. Pure, testable helpers: `discover_models_in(dirs)`, `pick_default(&[Model])`,
`resolve_model_with(spec, dirs, download)` (downloader injected), `whisper_args(...)`,
`frames_ffmpeg_args(...)`, `parse_pts_times(stderr)`, `frame_index(files, times)`, `check_frames_dir(dir)`,
`part_path(target)`, `is_video(path)`, `format_ts(secs)`. Side-effecting: `ensure_model` (manifest →
`.part` download → rename), `ensure_wav` → `Wav` (input or a drop-cleaned `tempfile::TempPath`, `-vn`),
`extract_frames` → `FramesGuard` (rollback on error). `tempfile` moved from dev- to runtime dependency.
`--print-special false` was dropped from the whisper-cli call: `-ps` is a boolean flag, so `false`
was being passed as a stray input file.

## Boundaries

| Always | Ask First | Never |
|--------|-----------|-------|
| Print chosen model to stderr | — | Download without `curl -f` (HTML 404 saved as model) |
| Validate model names | | Touch `tasks.json` / non-transcribe commands |

## Testing Strategy

- **Unit (most):** discovery over a temp dir, ordering, name validation, ffmpeg arg building, timestamp format, video detection.
- **Integration (real ffmpeg; skipped if absent, `BRANA_REQUIRE_FFMPEG=1` makes the skip fail):**
  colour-segment video (frame colour must match its label to within 1 s) and a sparse-VFR video
  (second frame comes from t=12 and must be labelled `00:00:12`). Note: CI's `rust` job does not
  run `cargo test -p brana-cli` today — t-3472.
- **E2E:** manual smoke with a real mp4 through whisper-cli.

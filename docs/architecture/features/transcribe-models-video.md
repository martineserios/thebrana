# Feature: `brana transcribe` — any whisper model, video + frames

**Date:** 2026-10-05
**Status:** implemented (unit-tested; e2e smoke pending)
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

## Scope (v1)

- `--model <name|path>` (optional, no default string). `name` → `ggml-<name>.bin`; a value that
  exists as a file or contains `/` is a path.
- Discovery dirs: `$BRANA_WHISPER_MODELS` (colon-separated, optional) then `~/.cache/whisper-models`.
- Default: largest installed model. None installed → download `ggml-small.bin` (manifest first, then
  HuggingFace, existing `ensure_model` flow).
- A named model that is not installed is downloaded from HuggingFace (name validated to
  `[A-Za-z0-9._-]`).
- Video input (`mp4 mkv mov webm avi m4v`): audio extracted via ffmpeg (existing `ensure_wav`).
- `--frames <DIR>`: extract JPEG frames with ffmpeg every `--every <SECS>` (default 10) into DIR.
  Transcript is then printed with segment timestamps, followed by a frame index
  (`frame_000001.jpg @ 00:00:00`) so frames and speech align.

## Assumptions

- largest installed: chose file size as the ranking because it generalises to any model name — confirmed by user ("largest = better").
- no model installed: chose auto-download of small — confirmed by user.
- frames via ffmpeg: confirmed by user.

## Behavior

- `brana transcribe a.mp3` with base+small installed → uses small (prints which model on stderr).
- `brana transcribe a.mp3 --model large-v3` → uses/downloads `ggml-large-v3.bin`.
- `brana transcribe talk.mp4 --frames out/ --every 5` → `out/frame_%06d.jpg` + timestamped transcript.

## Edge Cases

- `--frames` on an audio-only file → error ("--frames needs a video input").
- `--every 0` → error.
- Truncated/tiny model files (<1000 bytes) are ignored by discovery.
- Unsafe model name (`../x`) → error.

## Design

All in `system/cli/rust/crates/brana-cli/src/transcribe.rs`; CLI args in `cli.rs`; handler in
`commands/misc.rs`. Pure, testable helpers: `discover_models_in(dirs)`, `pick_default(&[Model])`,
`resolve_model_spec(spec)`, `frames_ffmpeg_args(...)`, `is_video(path)`, `format_ts(secs)`.

## Boundaries

| Always | Ask First | Never |
|--------|-----------|-------|
| Print chosen model to stderr | — | Download without `curl -f` (HTML 404 saved as model) |
| Validate model names | | Touch `tasks.json` / non-transcribe commands |

## Testing Strategy

- **Unit (most):** discovery over a temp dir, ordering, name validation, ffmpeg arg building, timestamp format, video detection.
- **E2E:** manual smoke with a real mp4 (ffmpeg installed).

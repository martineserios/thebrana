# Feature: `brana transcribe` — any whisper model, video + frames

**Date:** 2026-10-05
**Status:** implemented — unit + real-ffmpeg tests; e2e verified 2026-10-05 (video+frames via whisper-cli, real `--model tiny` download, no-audio rollback); `--scene` verified 2026-10-14 (real-ffmpeg cut fixture + CLI boundary probes; no whisper e2e re-run)
**Task:** t-3470; `--scene` added by t-3471

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
- `--scene <THRESHOLD>` (t-3471): sample on scene changes instead of a fixed interval —
  `select='eq(n\,0)+gt(scene\,X)',showinfo`, i.e. the first frame plus every frame whose ffmpeg
  scene score exceeds X (0 < X < 1; 0.3–0.5 is a typical cut detector — a hard cut scores exactly 1.0
  and `gt` is strict, so 1 is rejected; very low values keep nearly every frame, and the frame count is
  printed on stderr). Requires `--frames`;
  mutually exclusive with `--every` (clap `conflicts_with`). Labels still come from `showinfo`
  `pts_time` via `parse_pts_times`, never from an index — the sampling mode only decides *which*
  frames are kept. The frame-index header reads `Frames (DIR scene>X)` instead of `every Ns`.

## Non-goals (v1)


## Assumptions

- largest installed: chose file size as the ranking because it generalises to any model name — confirmed by user ("largest = better").
- no model installed: chose auto-download of small — confirmed by user.
- frames via ffmpeg: confirmed by user.
- frames are opt-in (`--frames DIR`), not produced for every video: chose opt-in because frame
  extraction writes many files — confirmed by user 2026-10-05.
- scene detect deferred to a follow-up task (t-3471) — confirmed by user 2026-10-05; shipped by t-3471.
- `--scene` always keeps the first frame (`eq(n,0)`): chose parity with `--every` (which keeps the
  first frame) because a cut-less video would otherwise yield zero frames — needs confirmation.
- `--scene` threshold domain: `0 < X < 1`, rejecting the rest as a usage error rather than clamping.
  Measured 2026-10-14 (t-3471 challenger F4): a hard cut scores exactly 1.0 and `gt` is strict, so
  `gt(scene,1)` selected 0 frames on a lime|blue cut — 1 is excluded, not an assumption.
- when only `.en` models are installed they are used (with a stderr warning) rather than
  auto-downloading `small` — confirmed by user 2026-10-05.

## Behavior

- `brana transcribe a.mp3` with base+small installed → uses small (prints which model on stderr).
- `brana transcribe a.mp3 --model large-v3` → uses/downloads `ggml-large-v3.bin`.
- `brana transcribe talk.mp4 --frames out/ --every 5` → `out/frame_%06d.jpg` + timestamped transcript.
- `brana transcribe talk.mp4 --frames out/ --scene 0.3` → one frame at t=0 plus one per detected cut, each labelled with its real time.

## Edge Cases

- `--frames` on an audio-only file → error ("--frames needs a video input").
- `--every 0` → error.
- `--scene` without `--frames`, `--scene` together with `--every`, or `--scene 0` / `--scene 1` / `--scene 1.5` → usage error.
- Model files of 1000 bytes or less, and in-progress `*.part-<pid>` downloads, are ignored by discovery.
  Downloads go to a `.part` file and are renamed on success.
- `brana-core` `download_file` (manifest-tracked models, `brana files pull`) is atomic too (t-3473):
  curl writes `<dest>.part-<pid>`, sha256 is verified there, then it is renamed; a failed or
  mismatched download leaves nothing at the final path. `*.part-*` files untouched for an hour
  are swept (age-based, no `/proc`, macOS portable). Manifest entries are validated before any
  write: relative path with no `..`, https URL only, exact model file name (no substring match).
- Symlinked model files are followed (size and file type are the target's).
- Files without the ggml magic (`lmgg`) are not models: skipped by discovery (with a warning), not
  trusted as an existing download, and a fresh download without it is discarded before the rename.
  A truncated file with a valid header still passes; whisper's failure then names the model and the
  recovery (`--model`, or delete the file) — Gate 3, 2026-10-05.
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
- `Sampling` enum (`Every(u32)` | `Scene(f64)`, t-3471) is the single seam between the two
  `--frames` modes: `from_options` picks it, `select_expr` owns the ffmpeg `select` string,
  `describe` names the mode in the frame-index header. `extract_frames` and the label path are
  mode-agnostic.

## Boundaries

| Always | Ask First | Never |
|--------|-----------|-------|
| Print chosen model to stderr | — | Download without `curl -f` (HTML 404 saved as model) |
| Validate model names | | Touch `tasks.json` / non-transcribe commands |

## Testing Strategy

- **Unit (most):** discovery over a temp dir, ordering, name validation, ffmpeg arg building, timestamp format, video detection.
- **Integration (real ffmpeg; skipped if absent, `BRANA_REQUIRE_FFMPEG=1` makes the skip fail):**
  colour-segment video (frame colour must match its label to within 1 s) and a sparse-VFR video
  (second frame comes from t=12 and must be labelled `00:00:12`). CI's `rust` job runs
  `cargo test --workspace` with ffmpeg (≥ 5.1, asserted) and `BRANA_REQUIRE_FFMPEG=1` (t-3472).
- **E2E:** manual smoke with a real mp4 through whisper-cli.
- **Integration (t-3471):** `scene_cut_yields_frame_at_cut_time` — 3 s lime | 3 s blue, `Scene(0.3)`
  must yield exactly `@ 00:00:00` (lime) and `@ 00:00:03` (blue); real ffmpeg, `BRANA_REQUIRE_FFMPEG=1`.
- **Unit (t-3471):** select-expression shape, `(0, 1)` threshold validation incl. NaN and 1.0, clap
  `conflicts_with`/`requires` parse.

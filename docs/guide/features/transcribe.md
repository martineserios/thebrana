# brana transcribe — audio/video to text, with frames

**Since:** t-3470 (2026-10-05); `--scene` added by t-3471 (2026-10-14)
**Tech doc:** [transcribe-models-video.md](../../architecture/features/transcribe-models-video.md)

## Quick Start

```bash
brana transcribe talk.mp3                       # largest installed whisper model
brana transcribe talk.mp4 --frames out/         # transcript + one frame every 10 s
brana transcribe talk.mp4 --frames out/ --scene 0.3   # transcript + one frame per cut
```

Needs `whisper-cli` (whisper.cpp) and, for video or frames, `ffmpeg` ≥ 5.1. No model installed?
`small` is downloaded on first use.

## How It Works

- **Model:** the largest model in `~/.cache/whisper-models` (or the absolute directories in
  `$BRANA_WHISPER_MODELS`; relative entries are ignored with a warning) is used unless you pass
  `--model <name|path>`. The argument is a path only when it contains `/` or ends with `.bin`;
  anything else is a model name, and a name that is not installed is downloaded. `HOME` must
  be set. The model in use is printed on stderr.
- **Video input** (`mp4 mkv mov webm avi m4v`): audio is extracted with ffmpeg first.
- **`--frames DIR`** (video only): JPEG frames land in `DIR/frame_000001.jpg …` and the
  transcript gets segment timestamps plus a frame index (`frame_000002.jpg @ 00:00:10`) so
  speech and frames line up. `DIR` must not already hold `frame_*` files. Every frame is
  labelled with its real time, so sparse or variable-frame-rate sources stay correct.
- **Sampling** — pick one:
  - `--every N` (default 10): the first frame, then one every N seconds.
  - `--scene X` (0 < X < 1): the first frame, then every frame whose ffmpeg scene score
    exceeds X. 0.3–0.5 catches hard cuts; lower values keep more frames of a busy video.
    `--scene 1` is refused because a hard cut scores exactly 1.0 and can never exceed it.
  - The two are mutually exclusive, and both need `--frames`. The number of frames written
    is printed on stderr, with a warning above 500 frames (`--every 1` on a long video) that
    points at a larger `--every` or `--scene`.
- **Input first:** a missing or unreadable input fails at once, before any model is looked up or
  downloaded.

## Examples

```
$ brana transcribe demo.mp4 --frames fr/ --scene 0.3
Using model: /home/me/.cache/whisper-models/ggml-small.bin
Extracting frames...
Extracted 4 frames into fr/
Preparing audio...
Transcribing...
[00:00:00.000 --> 00:00:04.200]  Welcome to the demo.
…

Frames (fr/ scene>0.3):
frame_000001.jpg @ 00:00:00
frame_000002.jpg @ 00:00:12
frame_000003.jpg @ 00:00:31
frame_000004.jpg @ 00:00:58
```

```
$ brana transcribe demo.mp4 --frames fr/ --every 5 --scene 0.3
error: the argument '--every <EVERY>' cannot be used with '--scene <THRESHOLD>'

$ brana transcribe demo.mp4 --frames fr/ --scene 1
Transcription failed: --scene must be a scene score in (0, 1), e.g. 0.3 (got 1)

$ brana transcribe voice.mp3 --frames fr/
Transcription failed: --frames needs a video input (mp4, mkv, mov, webm, avi, m4v)
```

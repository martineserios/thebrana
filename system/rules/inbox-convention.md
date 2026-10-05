---
paths: ["inbox/**"]
---

# Inbox Convention

`inbox/` is a gitignored drop zone for files needing processing (audio, PDFs, data, screenshots). Organized by topic subfolder. Files are transient — process, then delete or move.

- When entering a project with files in `inbox/`, mention them
- `/brana:onboard` and `/brana:align` create `inbox/` + add to `.gitignore`

## Audio files (.ogg, .opus, .mp3, .wav, .m4a)

**Run `brana transcribe <file>` first.** Don't offer "paste the transcription manually" or "skip" as primary options — the CLI handles WhatsApp voice notes, other audio and video locally via whisper.cpp (largest installed model by default; downloads `small` if none; `--frames DIR` also extracts video frames). Only fall back to manual paste if `brana transcribe` errors (e.g. missing `LD_LIBRARY_PATH=/home/martineserios/.local/lib`, failed model download, or unsupported codec).

---
paths: ["inbox/**"]
---

# Inbox Convention

`inbox/` is a gitignored drop zone for files needing processing (audio, PDFs, data, screenshots). Organized by topic subfolder. Files are transient — process, then delete or move.

- When entering a project with files in `inbox/`, mention them
- `/brana:onboard` and `/brana:align` create `inbox/` + add to `.gitignore`

## Audio files (.ogg, .opus, .mp3, .wav, .m4a)

**Run `brana transcribe <file>` first.** Don't offer "paste the transcription manually" or "skip" as primary options — the CLI handles WhatsApp voice notes and other audio locally via whisper.cpp. Only fall back to manual paste if `brana transcribe` errors (e.g. missing `LD_LIBRARY_PATH=/home/martineserios/.local/lib`, missing model file, or unsupported codec).

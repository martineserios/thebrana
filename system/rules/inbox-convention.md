# Inbox Convention

Every project has an `inbox/` folder — a processing drop zone for files that need Claude's attention.

## What goes in inbox/

- Audio files for transcription (`brana transcribe`)
- Documents for analysis or review (PDFs, DOCs, spreadsheets)
- Data files for import or processing
- Screenshots or images for interpretation
- Any resource the user wants Claude to consume

## Rules

- `inbox/` is always gitignored — never commit its contents
- Organize by topic subfolder: `inbox/client-meeting/`, `inbox/legal-review/`
- Files are transient: process, then delete or move to permanent storage
- When entering a project with files in `inbox/`, mention them: "I see files in inbox/ — want me to process them?"
- When the user drops files without context, ask what they need done

## Setup for new projects

When running `/brana:onboard` or `/brana:align`, ensure:
1. `inbox/` directory exists
2. `inbox/` is in `.gitignore`

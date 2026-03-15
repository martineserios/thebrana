---
name: export-pdf
description: "Convert a markdown file to PDF using mdpdf. Use when exporting proposals, SOPs, or any markdown document to PDF."
argument-hint: "[file.md]"
group: utility
allowed-tools:
  - Bash
  - Read
  - Glob
  - AskUserQuestion
---

# Export PDF — Markdown to PDF Converter

Convert a markdown file to a styled PDF using mdpdf.

## Process

### 1. Parse arguments

If `$ARGUMENTS` is empty, ask the user for the markdown file path. If provided, use it directly (e.g., `/brana:export-pdf propuesta-integracion-payway.md`).

### 2. Resolve path

Resolve the file path:
- If relative, resolve against `$PWD`
- Validate the file exists and has `.md` extension
- If the file doesn't exist, suggest matches using `Glob` with `**/*{slug}*.md`

### 3. Check for project CSS

Look for a custom stylesheet in the project:

```bash
# Check for pdf-style.css in project root, then docs/
project_root=$(git rev-parse --show-toplevel 2>/dev/null || echo "$PWD")
```

Search order:
1. `{project_root}/pdf-style.css`
2. `{project_root}/docs/pdf-style.css`
3. Same directory as the source file: `{source_dir}/pdf-style.css`

If found, tell the user and use it with `--style={path}`. If not found, proceed without custom styling.

### 4. Run mdpdf

```bash
/home/martineserios/.nvm/versions/node/v20.19.0/bin/mdpdf "{source_file}" --style="{css_path}"
```

If no CSS was found, omit the `--style` flag:

```bash
/home/martineserios/.nvm/versions/node/v20.19.0/bin/mdpdf "{source_file}"
```

The output PDF is placed in the same directory as the source, with `.pdf` extension.

### 5. Report

Show:
- Output file path
- File size (`ls -lh`)
- Offer to open: "Open with `xdg-open`?"

If the user says yes:

```bash
xdg-open "{output_pdf}" &
```

## Rules

- Always use the full nvm path for mdpdf — it's not on the default PATH
- Never overwrite a PDF without confirming if the user wants to replace it
- If mdpdf fails, check that the markdown file is valid and report the error clearly

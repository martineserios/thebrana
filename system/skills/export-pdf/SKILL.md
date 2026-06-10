---
name: export-pdf
description: "Convert a markdown file to PDF using mdpdf. Use when exporting proposals, SOPs, or any markdown document to PDF."
effort: low
keywords: [pdf, export, markdown, document, proposal, sop]
task_strategies: [feature]
stream_affinity: [docs]
argument-hint: "[file.md]"
group: utility
model: haiku
allowed-tools:
  - Bash
  - Read
  - Glob
  - AskUserQuestion
status: stable
growth_stage: evergreen
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

### 3. Pre-render Mermaid blocks

Check if the source file contains any Mermaid code blocks:

```bash
grep -c '```mermaid' "{source_file}"
```

**If count is 0:** skip this step — no Mermaid blocks found. `render_source` = `{source_file}`.

**If count > 0:**

1. Resolve `mmdc`:
   ```bash
   mmdc_bin=$(which mmdc 2>/dev/null)
   ```
   If empty, warn the user: "Mermaid blocks found but `mmdc` is not installed — they will render as raw code. Install with: `npm install -g @mermaid-js/mermaid-cli` then `ln -sf $(which mmdc) ~/.local/bin/mmdc`". Set `render_source` = `{source_file}` and skip to step 4.

2. Create a temp workspace and copy the source:
   ```bash
   tmp_dir=$(mktemp -d)
   tmp_md="${tmp_dir}/$(basename '{source_file}')"
   cp "{source_file}" "$tmp_md"
   ```

3. Write Puppeteer config — required on Ubuntu 23.10+ due to AppArmor namespace restrictions:
   ```bash
   cat > "${tmp_dir}/puppeteer.json" <<'EOF'
   {"args":["--no-sandbox","--disable-setuid-sandbox"]}
   EOF
   ```

4. Extract and render each block, replacing it with an image reference. Pass `$mmdc_bin` as a third argument so the Python subprocess uses the resolved path:
   ```bash
   uv run python3 - "$tmp_md" "$tmp_dir" "$mmdc_bin" <<'PYEOF'
   import re, subprocess, sys
   from pathlib import Path

   src = Path(sys.argv[1])
   tmp = Path(sys.argv[2])
   mmdc_cmd = sys.argv[3]  # resolved from PATH
   content = src.read_text()
   puppeteer_cfg = tmp / "puppeteer.json"
   pattern = re.compile(r'```mermaid\n(.*?)```', re.DOTALL)

   def render_block(match, idx):
       diagram = match.group(1).strip()
       mmd = tmp / f"diagram_{idx}.mmd"
       png = tmp / f"diagram_{idx}.png"
       mmd.write_text(diagram)
       r = subprocess.run(
           [mmdc_cmd, "-i", str(mmd), "-o", str(png), "-p", str(puppeteer_cfg)],
           capture_output=True, text=True
       )
       if r.returncode != 0:
           print(f"[warn] mmdc failed for block {idx}: {r.stderr.strip()}", file=sys.stderr)
           return match.group(0)  # keep original block on failure
       return f"![]({png})"

   counter = [0]
   def repl(m):
       counter[0] += 1
       return render_block(m, counter[0])

   new_content = pattern.sub(repl, content)
   src.write_text(new_content)
   print(f"Rendered {counter[0]} Mermaid block(s)")
   PYEOF
   ```

5. Set `render_source` = `$tmp_md`. The output PDF must be written back to the **original source directory** (not temp), so the mdpdf step must specify the output path explicitly:
   ```
   output_pdf="{source_dir}/{source_basename_no_ext}.pdf"
   ```

6. After the PDF is generated (step 5), clean up: `rm -rf "$tmp_dir"`.

### 4. Check for project CSS

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

### 5. Run mdpdf

Use `render_source` (from step 3) as input.

**Important:** `mdpdf --dest` is silently ignored — the output PDF always lands beside the source file (same directory, `.pdf` extension). When using a temp copy (`render_source` ≠ `{source_file}`), mdpdf writes the PDF into `$tmp_dir`. After it completes, copy manually to the original source directory:

```bash
# Run mdpdf (output lands in same dir as render_source)
mdpdf "{render_source}" --style="{css_path}"   # with CSS
mdpdf "{render_source}"                        # without CSS

# If Mermaid pre-render was used, copy PDF to original location
tmp_pdf="${tmp_dir}/{source_basename_no_ext}.pdf"
output_pdf="{source_dir}/{source_basename_no_ext}.pdf"
cp "$tmp_pdf" "$output_pdf"
```

If no Mermaid pre-rendering occurred (`render_source` == `{source_file}`), no copy is needed — the PDF is already in the right place.

### 6. Report

Show:
- Output file path
- File size (`ls -lh`)
- Offer to open: "Open with `xdg-open`?"

If the user says yes:

```bash
xdg-open "{output_pdf}" &
```

## Rules

- Use `which mmdc` and `which mdpdf` to resolve binaries — both are symlinked to `~/.local/bin/` and are on PATH. If `which` returns empty, report the install command.
- Never overwrite a PDF without confirming if the user wants to replace it
- If mdpdf fails, check that the markdown file is valid and report the error clearly

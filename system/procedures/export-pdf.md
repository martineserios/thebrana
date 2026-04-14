
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

1. Check that `mmdc` is available:
   ```bash
   which mmdc 2>/dev/null
   ```
   If not found, warn the user: "Mermaid blocks found but `mmdc` is not installed — they will render as raw code. Install with: `npm install -g @mermaid-js/mermaid-cli`". Set `render_source` = `{source_file}` and skip to step 4.

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

4. Extract and render each block, replacing it with an image reference:
   ```bash
   uv run python3 - "$tmp_md" "$tmp_dir" <<'PYEOF'
   import re, subprocess, sys
   from pathlib import Path

   src = Path(sys.argv[1])
   tmp = Path(sys.argv[2])
   content = src.read_text()
   puppeteer_cfg = tmp / "puppeteer.json"
   pattern = re.compile(r'```mermaid\n(.*?)```', re.DOTALL)

   def render_block(match, idx):
       diagram = match.group(1).strip()
       mmd = tmp / f"diagram_{idx}.mmd"
       png = tmp / f"diagram_{idx}.png"
       mmd.write_text(diagram)
       r = subprocess.run(
           ["mmdc", "-i", str(mmd), "-o", str(png), "-p", str(puppeteer_cfg)],
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

Use `render_source` (from step 3) as input. If Mermaid blocks were pre-rendered, specify the output path explicitly so the PDF lands next to the original file:

```bash
mdpdf "{render_source}" "{output_pdf}" --style="{css_path}"
```

If no CSS was found, omit `--style`:

```bash
mdpdf "{render_source}" "{output_pdf}"
```

If no Mermaid pre-rendering occurred (`render_source` == original file), omit the explicit output path — mdpdf places it next to the source automatically:

```bash
mdpdf "{source_file}" --style="{css_path}"
```

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

- Always use the full nvm path for mdpdf — it's not on the default PATH
- Never overwrite a PDF without confirming if the user wants to replace it
- If mdpdf fails, check that the markdown file is valid and report the error clearly

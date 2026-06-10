---
name: web-design
description: UI review against Web Interface Guidelines. Use when asked to review UI, check accessibility, or audit design.
group: brana
keywords: [ux, ui, design, accessibility, web-guidelines, vercel, a11y, css, html]
allowed-tools: [Read, Glob, Grep, WebFetch, AskUserQuestion]
status: experimental
source: "https://skills.sh/vercel-labs/agent-skills/web-design-guidelines"
acquired: "2026-05-17"
quarantine: false
---
# Web Interface Guidelines

Review files for compliance with Web Interface Guidelines.

## How It Works

1. Fetch the latest guidelines from the source URL below
2. Read the specified files (or prompt user for files/pattern)
3. Check against all rules in the fetched guidelines
4. Output findings in the terse `file:line` format

## Guidelines Source

Fetch fresh guidelines before each review:

```
https://raw.githubusercontent.com/vercel-labs/web-interface-guidelines/main/command.md
```

Use WebFetch to retrieve the latest rules. The fetched content contains all the rules and output format instructions.

## Usage

When a user provides a file or pattern argument:
1. Fetch guidelines from the source URL above
2. Read the specified files
3. Apply all rules from the fetched guidelines
4. Output findings using the format specified in the guidelines

If no files specified, ask the user which files to review.

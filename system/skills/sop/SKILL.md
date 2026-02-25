---
name: sop
description: "Create a structured, versioned Standard Operating Procedure from a described process. Use when a repeatable process needs formal documentation."
group: venture
allowed-tools:
  - Bash
  - Read
  - Write
  - Glob
  - Grep
---

# SOP — Standard Operating Procedure Creator

Create a structured, versioned SOP from a described process. The business equivalent of writing a spec. Mirrors `/decide` in structure — auto-increment numbering, slug generation, template application, ReasoningBank storage.

## When to use

Whenever a repeatable process needs documenting. Key principle from [28-startup-smb-management.md](~/enter_thebrana/brana-knowledge/dimensions/28-startup-smb-management.md): don't systematize too early — wait until a process repeats 3+ times. But when you do systematize, do it well.

---

## Process

### 1. Parse arguments

If `$ARGUMENTS` is empty, ask the user for the process name. If provided, use it directly (e.g., `/sop customer onboarding`).

### 2. Locate project root

Run `git rev-parse --show-toplevel` in the current directory. Fall back to `$PWD` if not a git repo.

### 3. Ensure docs/sops/ exists

If `docs/sops/` doesn't exist, ask the user: "This project doesn't have `docs/sops/` yet. Create it?" If yes, create with `mkdir -p docs/sops/`. If no, abort.

### 4. Interview

Ask the user about the process (skip what's already clear from `$ARGUMENTS` or conversation context):

1. **What's the process?** — describe it in a sentence.
2. **Who owns it?** — who is responsible for this process? (role, not person name)
3. **What triggers it?** — what event starts this process? (customer request, calendar date, metric threshold, manual decision)
4. **How often?** — daily, weekly, per-event, as-needed?
5. **What are the steps?** — walk through the process start to finish. Note any decision points (if X, do A; if Y, do B).
6. **What's the output?** — what artifact or state change does this process produce?
7. **What commonly goes wrong?** — known failure modes, common mistakes, edge cases.
8. **How do you know it worked?** — success criteria, quality checks.

### 5. Auto-increment SOP number

Scan `docs/sops/SOP-*.md` files. Extract the highest NNN from `SOP-NNN-*.md` filenames. New number = highest + 1. If no SOPs exist, start at 001. Zero-pad to 3 digits.

```bash
# Find the highest SOP number
highest=$(ls docs/sops/SOP-*.md 2>/dev/null | sed 's/.*SOP-\([0-9]*\).*/\1/' | sort -n | tail -1)
next=$(printf "%03d" $(( ${highest:-0} + 1 )))
echo "Next SOP number: $next"
```

### 6. Slugify title

Convert title to lowercase, replace spaces and special characters with hyphens, collapse multiple hyphens, truncate to 50 characters.

### 7. Create SOP file

Write to `docs/sops/SOP-NNN-slug.md`:

```markdown
# SOP-NNN: {Title}

**Version:** 1.0
**Owner:** {role}
**Last updated:** {today}
**Next review:** {today + 6 months}

## Purpose

{One-sentence description of why this process exists and what it achieves.}

## Trigger

{What event starts this process.}

## Prerequisites

{What must be true before starting. Tools needed, access required, information on hand.}

## Steps

1. **{Step name}**
   {Description of what to do.}

2. **{Step name}**
   {Description of what to do.}

   > **Decision point:** If {condition A}, proceed to step 3. If {condition B}, skip to step 4.

3. **{Step name}**
   {Description of what to do.}

{Continue for all steps...}

## Exit Criteria

- [ ] {How to verify the process completed successfully}
- [ ] {Output artifact exists / state change confirmed}

## Common Issues

| Issue | Cause | Resolution |
|-------|-------|------------|
| {What goes wrong} | {Why} | {How to fix it} |

## Resilience

{Include this section for processes involving deployed systems or automated workflows. Remove for purely manual processes.}

| Aspect | Design | Notes |
|--------|--------|-------|
| **Restartability** | {Can the process resume from any step without manual intervention?} | {What state must be preserved?} |
| **Data isolation** | {Are immutable records (audit trail) separated from mutable working state?} | {Where does each layer live?} |
| **Degradation** | {What happens when a dependency fails? Which steps can proceed independently?} | {Fallback behavior per step} |

## Metrics

| Metric | Target | How to Measure |
|--------|--------|---------------|
| {e.g., Completion time} | {e.g., < 30 min} | {e.g., Track start/end time} |
| {e.g., Error rate} | {e.g., < 5%} | {e.g., Count rework instances} |

---

*Created: {today} | Review cycle: 6 months*
```

### 8. Pre-populate from interview

Fill in all sections from the interview answers. Don't leave placeholder text where you have real content. For steps, include specific details — a good SOP should be followable by someone unfamiliar with the process.

### 9. Update SOP index

If `docs/sops/README.md` exists, add the new SOP to it. If not, create:

```markdown
# Standard Operating Procedures

| SOP | Title | Owner | Trigger | Last Updated |
|-----|-------|-------|---------|-------------|
| SOP-NNN | {Title} | {Owner} | {Trigger} | {today} |
```

### 10. Store in ReasoningBank

```bash
source "$HOME/.claude/scripts/cf-env.sh"
```

If `$CF` is found:
```bash
cd "$HOME" && $CF memory store \
  -k "sop:{PROJECT}:{slug}" \
  -v '{"type": "sop", "title": "...", "owner": "...", "trigger": "...", "steps": N, "confidence": 0.5, "transferable": false}' \
  --namespace business \
  --tags "project:{PROJECT},type:sop,domain:{DOMAIN}"
```

### 11. Fallback (claude-flow unavailable)

Append to `~/.claude/projects/{project-hash}/memory/MEMORY.md`:
```
## SOP: {title}
- File: docs/sops/SOP-NNN-slug.md
- Owner: {owner}
- Trigger: {trigger}
- Date: {today}
```

### 12. Report

Show the user:
- File created and path
- SOP number
- Summary of the process documented
- Reminder: "Review this SOP in 6 months. SOPs decay faster than code docs — business processes change frequently."

---

## Rules

- **Interview thoroughly.** A vague SOP is worse than no SOP — it gives false confidence that a process is documented when it isn't really.
- **Steps must include decision points.** Real processes branch. "If the customer says X, do A. If they say Y, do B." Omitting decision points makes the SOP useless for edge cases.
- **Never overwrite an existing SOP.** If a SOP with that slug exists, ask if the user wants to update it (increment version) or create a new one.
- **Don't systematize too early.** If the user describes a process they've only done once, gently suggest: "Has this repeated 3+ times? SOPs work best for validated processes. We can create a draft and revisit after more repetitions."
- **Ask for clarification whenever you need it.** If the process has unclear steps, you're not sure about decision points, or the trigger is ambiguous — ask.

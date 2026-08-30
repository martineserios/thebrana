---
name: provisioning-wizard
description: "Bash wizard for human-only setup."
keywords: [wizard, provisioning, credentials, onboarding, secrets, dashboard, migration, cutover]
task_strategies: [feature, chore]
group: core
allowed-tools: [Read, Bash, Skill, Write]
status: experimental
vendored_from: mattpocock/skills@v1.2.3
---

# Provisioning Wizard (adapter)

ADR-084 vendor+wrap, expanded per ADR-084 §7a on t-2834's pilot (t-2836). Thin adapter, not a copy — the discipline lives in the vendored organ, read fresh every invocation:

1. **Read the vendored skill**: `Skill(skill: "wizard")` — `.agents/skills/wizard/SKILL.md`, verbatim upstream, pinned `v1.2.3`, tracked in `skills-lock.json`. Follow its four-step process (scope → map each stage's journey → author → verify and hand off) as written.
2. **While following it, remap:**
   - "Read the repo first" (upstream §1) → for a brana provisioning flow this usually means a skill's own SKILL.md "Prerequisites" section (e.g. `system/skills/meta-templates/SKILL.md`'s WhatsApp BSP onboarding), a client's `docs/` under `clients/<slug>/`, or `.github/workflows/*` `secrets.*`/`vars.*` references — read whichever the caller names, don't invent a scope.
   - The example Stripe procedure in `template.sh` → always replaced; never ship the example stage.
   - "scratch or `scripts/` path" (upstream §1's ephemeral-by-default framing) → **build-composable step**: call `system/scripts/wizard-scaffold.sh` to get the scaffolded, executable script instead of hand-copying the template. With no `--out`, it writes to a fresh `/tmp/wizard-<rand>.sh` (per `system/rules/cwd-discipline.md`'s "`/tmp/` is the only handoff zone" convention) — ephemeral by default. Pass `--out <path-under-scripts/>` only when the human has explicitly said they want a repeatable, in-repo setup path; pass `--title "<Setup name>"` to seed the banner.
3. **Author stages** by editing the scaffolded file directly (it's a plain, already-executable bash file) — replace the example stage block between the `STAGES` marker and `finish` with one `stage` per step, using the vendored library helpers (`stage`, `say`/`step`, `open_url`, `ask`/`ask_secret`, `write_env`, `set_secret`/`set_var`, `pause`/`confirm`) exactly as the vendored `SKILL.md` §3 describes. Never hand-edit anything above the `STAGES` marker — that's the pinned library; changes belong upstream.
4. **Verify before hand-off** (upstream §4, non-negotiable): `bash -n <script>` — and `shellcheck <script>` if it's installed — before telling the human it's ready. **Never execute the generated script yourself** — by design it blocks on human input and opens a browser; trace it statically instead (walk the stages, confirm every captured value from step 1 lands where step 1 said, and every `set_secret`/`set_var` name matches something the target actually consumes).
5. **Hand off**: tell the human the script's path and how to run it (`bash <path>` or `./<path>` after the `chmod +x` the scaffold already applied). If it was scaffolded to a scratch path and the human now wants it repeatable, move/commit it under `scripts/` and link it from the relevant README or client doc — don't leave that as an unstated follow-up.

## Build-composable entry point

`/brana:build` or another skill invokes this by calling `system/scripts/wizard-scaffold.sh` directly (steps 2-4 above) rather than going through a slash command — the same "thin adapter, not a new command" pattern as `diagnose-hard-bug`. This skill's job is the scoping/authoring discipline around that script, not a UI of its own.

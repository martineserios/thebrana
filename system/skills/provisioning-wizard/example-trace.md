# Example trace — WhatsApp BSP client onboarding (t-2836 acceptance proof)

Static trace only. **This script was never executed** — by design it blocks on
human input and opens a browser (Meta Business Manager / WhatsApp Manager),
which no automated verification can drive. What follows is the stage-by-stage
walkthrough proving the generated script does what the real flow needs.

## Real flow traced

`system/skills/meta-templates/SKILL.md`'s "Prerequisites — first-time setup
per client" section: onboarding a new WhatsApp BSP client requires a human to
generate a Meta System User token and look up a WABA ID in the Meta Business
Manager / WhatsApp Manager UI — a dashboard-driven, credential-capture flow
only a human can walk (t-2836's exact target class).

## How it was generated

```
system/scripts/wizard-scaffold.sh \
  --out /tmp/wizard-whatsapp-bsp-onboarding.sh \
  --title "WhatsApp BSP client onboarding"
```

The scaffold call copies the vendored `.agents/skills/wizard/template.sh`
library verbatim and seeds the banner title — everything below the `STAGES`
marker was then hand-authored per `system/skills/provisioning-wizard/SKILL.md`
step 3, following the vendored `SKILL.md`'s Process §§1-3 against
`meta-templates/SKILL.md`'s Prerequisites text (the "read the repo first"
remap in the adapter's step 2).

## Stages authored

| # | Stage | Opens | Captures | Written to |
|---|-------|-------|----------|------------|
| 1 | Client identifier | — | `CLIENT_SLUG` | sets `ENV_FILE=~/.config/brana/meta/<slug>.env`, `mkdir -p` the dir |
| 2 | Meta Business Manager — System User token | `business.facebook.com/settings/system-users` | `META_SYSTEM_TOKEN` (hidden — `ask_secret`) | `write_env` → `$ENV_FILE` |
| 3 | WhatsApp Manager — WABA ID | `business.facebook.com/wa/manage/home` | `META_WABA_ID` (visible — `ask`) | `write_env` → `$ENV_FILE`, then `chmod 600 "$ENV_FILE"` |
| 4 | Verify — pull baseline templates | — (CLI call, not a dashboard) | none | runs `brana-meta-templates pull --client <slug>` on confirm; on 400/401 tells the human which of stage 2/3's values to recheck, per `meta-templates/SKILL.md`'s documented error mapping |

Trace checks (walking step 1's plan against the authored stages):

- Every value step 1 named (`META_SYSTEM_TOKEN`, `META_WABA_ID`) is captured exactly once and lands in the one place `meta-templates/SKILL.md` says the CLI looks (`~/.config/brana/meta/<client>.env`), not the project `.env` — the scaffold's default `ENV_FILE=.env` is deliberately overridden in stage 1 before either `write_env` call fires.
- The secret/non-secret split matches upstream's own framing: the System User token is a credential (`ask_secret`, hidden entry); the WABA ID is an account identifier shown in a UI panel, not a secret (`ask`, visible, matching how `meta-templates/SKILL.md` itself treats it).
- `chmod 600` on the config file matches the exact instruction `meta-templates/SKILL.md`'s Prerequisites section gives for this file.
- No `set_secret`/`set_var` (GitHub Actions) calls — this flow's target is a local per-client config file, not CI, so those upstream helpers are correctly unused rather than force-fit.
- Stage 4 mirrors `meta-templates/SKILL.md`'s own documented verification step (`pull` before any `submit`) and its documented error-to-cause mapping (400 → wrong WABA ID, 401 → bad/under-permissioned token), so a human hitting either error is pointed back at the exact stage to redo.

## Verification (upstream Process §4 / t-2836 AC 4)

```
$ bash -n /tmp/wizard-whatsapp-bsp-onboarding.sh
(no output — syntax OK)
```

`shellcheck` is not installed on this machine (`command -v shellcheck` → not
found); per the task's "if available" condition this step was skipped rather
than faked. Re-run `shellcheck /tmp/wizard-whatsapp-bsp-onboarding.sh` once it
is installed, before handing a real generated script like this one to a human.

## Disposition

This trace script was scaffolded to `/tmp/` (the default, ephemeral path) and
was not committed or moved under `scripts/` — per the vendored skill's "commit
only when the user wants a repeatable setup path" rule, nobody has asked for
this particular onboarding script to become a permanent, repeatable artifact
yet. This document is the acceptance evidence in its place.

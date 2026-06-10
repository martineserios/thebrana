# Meta Templates — Programmatic Management

Wraps the local CLI `brana-meta-templates` (installed at `~/.local/bin/brana-meta-templates`). Each subcommand passes through to the CLI with the client autodetected from the current working directory.

Source: `~/enter_thebrana/tools/brana-meta-templates/`
ADR: `clients/somos_mirada/decisions/2026-05-meta-template-tooling.md`
API reference: `brana-knowledge/dimensions/54-meta-whatsapp-template-api.md`

## When to use

- Submit a new WhatsApp template to Meta from a YAML definition
- Check current status of one or all templates for a client's WABA
- Pull a snapshot of all templates (baseline for drift detection)
- Audit drift since last pull — detects silent reclassifications, status changes, quality drops
- Prepare an appeal for a reclassified template (URLs + paste-ready copy)

## Prerequisites — first-time setup per client

The CLI looks up auth at `~/.config/brana/meta/<client>.env`. Onboarding a client requires creating that file once:

The env file must define two keys: `META_SYSTEM_TOKEN` (System User token from
Meta Business Manager — Users → System Users → Generate Token, with permissions
`whatsapp_business_management`, `whatsapp_business_messaging`, `business_management`)
and `META_WABA_ID` (WhatsApp Account id, visible in the WhatsApp Account info
panel of Business Manager).

Once you have both values, write the file:

```bash
mkdir -p ~/.config/brana/meta
$EDITOR ~/.config/brana/meta/<client>.env
chmod 600 ~/.config/brana/meta/<client>.env
```

If the file is missing, the CLI prints a config error pointing at the expected path.

**Verify immediately after provisioning** — run `pull` to confirm the WABA ID and token are correct before any `submit` attempt. A wrong WABA ID surfaces as a Graph API 400 on `pull`, not on `submit`, making diagnosis much faster:

```bash
brana-meta-templates pull --client <client>
```

If `pull` returns a 400 "does not exist or missing permissions", the WABA ID is wrong — correct `META_WABA_ID` in the env file. If it returns a 401, the token is invalid or lacks permissions.

## Procedure

### 1. Parse arguments

If `$ARGUMENTS` is empty, ask the user which subcommand to run:

- `submit <yaml-file>` — POST a template defined in YAML to the Graph API
- `pull` — refresh the local snapshot (baseline for audit)
- `status [--name X]` — show current Meta state, single template or all
- `audit [--save]` — diff cached snapshot vs current — detect drift
- `appeal <name>` — print URLs + paste-ready appeal copy

### 2. Resolve client

Auto-detect from CWD:

```bash
client=$(git rev-parse --show-toplevel 2>/dev/null | xargs -I{} basename {})
```

If the CWD is not a git repo, ask the user for `--client <slug>` explicitly.

### 3. Invoke

Pass the subcommand and arguments through to the CLI:

```bash
brana-meta-templates <subcommand> [args] --client "$client"
```

The CLI handles its own output (rich tables, panels). Surface its stdout/stderr to the user verbatim.

### 4. Interpret exit codes

| Code | Meaning | Action |
|------|---------|--------|
| 0 | Success — no drift (audit) or operation completed | Done |
| 2 | Config error — missing/malformed `~/.config/brana/meta/<client>.env` | Guide user to create the file (see Prerequisites) |
| 3 | Graph API error (4xx/5xx, including 401 invalid token) | Show Meta's error message; if 401, suggest token rotation |
| 4 | Resource not found (template, baseline file, YAML file) | Verify the input |
| 5 | YAML parse / template validation error | Show error, suggest fix |
| 6 | Audit detected drift | Surface the drift report; suggest follow-up actions (appeal candidates, etc.) |

### 5. Subcommand-specific guidance

#### `submit`

If submitting a re-engagement template (cartera_pasiva variants, etc.), warn the user that Meta's ML may classify it as Marketing. To maintain UTILITY classification, the template body must include an explicit transactional anchor referencing a prior service interaction — e.g. "en seguimiento a tu consulta" or "en seguimiento a la información que te enviamos". Templates without this anchor (generic "retomo el contacto" phrasing) will typically be reclassified as MARKETING. Appeals for UTILITY reclassification are unreliable and slow — always have a UTILITY-framed backup variant ready before submitting. Suggest using `--dry-run` first to inspect the API body, then submit, then poll `status` for the verdict.

After successful submission, remind the user that approval/rejection arrives async — they can check with `status --name <name>` later.

#### `audit`

If drift is detected (exit code 6):
- For `category_changes` and `correct_category_mismatches` — these are appeal candidates. Suggest running `appeal <name>` for each.
- For `status_changes` to PAUSED/DISABLED/REJECTED — the template is no longer usable for sending. Investigate before fixing.
- For `quality_drops` — monitor; if reaches RED, the template will be auto-paused.

If no drift, suggest the user re-run `pull` to keep the baseline fresh.

#### `appeal`

Output is paste-ready text + URLs. Walk the user through the manual flow:
1. Open the template manager URL → confirm the template state matches what was reported
2. Open Business Support Home URL → start a new case → category Templates / Appeal
3. Paste the suggested copy into the form
4. Click Submit (this is the part that cannot be automated — Meta does not expose an API for appeals)

## Anti-patterns

- **Don't bypass `audit`.** If you suspect drift, run `audit` rather than asking the LLM to compare manually — it has structured logic for ranking quality drops, detecting `correct_category` mismatches, etc.
- **Don't edit approved templates.** Meta does not allow editing approved templates — you must create a new version with a new name. The CLI cannot do that for you.
- **Don't store tokens in the project repo.** They live at `~/.config/brana/meta/<client>.env` (chmod 600), never in tasks.json or any project file.

## Examples

```
/brana:meta-templates submit features/meta-template-mgmt/seeds/cartera_pasiva_0_procedimiento.yaml
/brana:meta-templates audit
/brana:meta-templates appeal cartera_pasiva_0_procedimiento
/brana:meta-templates status
/brana:meta-templates pull
```

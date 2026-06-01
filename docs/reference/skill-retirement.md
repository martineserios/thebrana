# Skill Retirement Checklist

When retiring a skill, touch all 10 locations below in one commit.
Learned from notebooklm-source retirement (2026-06-01).

## Checklist

| # | Location | What to do |
|---|----------|-----------|
| 1 | `system/skills/<name>/` | Delete the entire directory (SKILL.md + procedure symlink) |
| 2 | `system/procedures/<name>.md` | Delete the procedure file |
| 3 | `docs/reference/skills.md` | Remove the index row and the `### /brana:<name>` section |
| 4 | `system/plugin.json` `commands` array | Remove the command entry |
| 5 | `docs/reference/brana-cli.md` | Remove the command row |
| 6 | `docs/architecture/component-index.md` | Remove the component entry |
| 7 | Architecture docs (`docs/reflections/`, `docs/architecture/`) | Grep and remove skill references |
| 8 | Guide/workflow docs (`docs/reference/`, `docs/architecture/features/`) | Grep and remove skill references |
| 9 | `docs/ideas/` | Remove idea stubs that depend on the skill |
| 10 | `docs/reference/scripts.md` | Remove script entries tied to the skill |

## Discovery command

```bash
grep -r "<skill-name>" docs/ system/ --include="*.md" -l
```

Run before deleting to find all references. Sweep inbound links too — skills referencing the retiring one may need `depends_on` updates.

## Commit convention

```
chore(retire): remove <skill-name>
```

One commit for all 10 locations. No partial retirements.

## Reference

- Generator: `brana reference generate` — regenerates `docs/reference/skills.md` automatically
- Companion: [`docs/reference/skills.md`](skills.md) — the generated skill index

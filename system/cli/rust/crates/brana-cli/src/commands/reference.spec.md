# reference.rs — generator spec (skill frontmatter reference)

Task: t-1341
Related: docs/architecture/testing-validation.md (canonical enum source)

## Scope

The generated `docs/reference/skills.md` must surface the legal values for
the `group`, `growth_stage`, and `status` keys in skill SKILL.md frontmatter.
Today those enums live only in `docs/architecture/testing-validation.md`,
which users discovering "what's a valid group?" rarely think to check.

## Contract

`generate_skills` emits a "Skill Frontmatter Reference" section between the
top-level summary and the per-skill Index. The section is a static block
keyed off `SKILL_FRONTMATTER_REFERENCE` so the canonical enum list lives in
one place; if `testing-validation.md` adds a new value, this constant must be
updated in the same change.

The section must include:
- A `group` enum table mirroring `testing-validation.md` Check D
- A `growth_stage` enum table
- A `status` enum table

## Out of scope

- Validating frontmatter values at generation time (that's validate.sh's job)
- Generating the constant from `testing-validation.md` at runtime

#!/usr/bin/env bash
# t-1942: effective-body resolver for the big-four skills, layout-agnostic.
# A skill's full procedure body may live in (any combination that exists):
#   system/procedures/{name}.md          — stub layout (pre-t-1942)
#   system/skills/{name}/SKILL.md        — inline layout (t-1941 default)
#   system/skills/{name}/phases/*.md     — phase-split layout (t-1942)
# Usage:  source tests/lib/effective_body.sh
#         BODY_FILE=$(effective_body_file build "$REPO_ROOT")
# Returns a temp file containing the concatenated effective body.
effective_body_file() {
    local n="$1" root="$2" tmp
    tmp=$(mktemp "${TMPDIR:-/tmp}/effective-body-$n.XXXXXX")
    [ -f "$root/system/procedures/$n.md" ] && cat "$root/system/procedures/$n.md" >> "$tmp"
    [ -f "$root/system/skills/$n/SKILL.md" ] && cat "$root/system/skills/$n/SKILL.md" >> "$tmp"
    if [ -d "$root/system/skills/$n/phases" ]; then
        # Concatenate in PHASES-registry order (procedure order), not glob order
        local sk="$root/system/skills/$n/SKILL.md" listed="" pf rel
        if [ -f "$sk" ] && grep -q "<!-- PHASES -->" "$sk"; then
            listed=$(sed -n '/<!-- PHASES -->/,/<!-- \/PHASES -->/p' "$sk" \
                | grep -oE 'phases/[a-z0-9-]+\.md')
            while IFS= read -r rel; do
                [ -f "$root/system/skills/$n/$rel" ] && cat "$root/system/skills/$n/$rel" >> "$tmp"
            done <<< "$listed"
        fi
        # Any phase file not in the registry (or no registry): append in glob order
        for pf in "$root/system/skills/$n"/phases/*.md; do
            [ -f "$pf" ] || continue
            rel="phases/$(basename "$pf")"
            grep -qx "$rel" <<< "$listed" 2>/dev/null || cat "$pf" >> "$tmp"
        done
    fi
    echo "$tmp"
}

#!/usr/bin/env bash
# check-selector.sh — map changed files to relevant validate.sh check numbers
#
# Usage:
#   check-selector.sh file1 file2 ...
#   git diff --name-only HEAD~1 HEAD 2>/dev/null | check-selector.sh
#
# Output: newline-separated, deduplicated, sorted check numbers
# Used by /brana:build CLOSE step 10b to run targeted post-merge validation. (t-1485)
#
# Implementation note: validate.sh checks 1-14 run as a monolithic block — --check N
# for any N in 1-14 runs ALL of 1-14 (not just N). Any file trigger for a 1-14 check
# emits "1" here so sort -u collapses them into one core-block invocation.
# Checks 15+ are individually filterable and emitted by their own number.

set -uo pipefail

if [ $# -gt 0 ]; then
    files=("$@")
else
    mapfile -t files
fi

checks=()

core() { checks+=(1); }   # 1-14 block (not individually filterable)

for file in "${files[@]}"; do
    [ -z "$file" ] && continue
    case "$file" in
        system/skills/build/SKILL.md|system/skills/build/phases/*.md)
            core; checks+=(33 23 36 40 45 52 54 56)  # build effective body (t-1942 phase split)
            ;;
        system/skills/close/SKILL.md|system/skills/close/phases/*.md)
            core; checks+=(33 23 36 40 43 44 45 55)  # close effective body (t-1942 phase split)
            ;;
        system/skills/backlog/SKILL.md|system/skills/backlog/phases/*.md)
            core; checks+=(33 23 36 40 45)           # backlog effective body (t-1942 phase split)
            ;;
        system/skills/reconcile/SKILL.md|system/skills/reconcile/phases/*.md)
            core; checks+=(33 23 36 40 45)           # reconcile effective body (t-1942 phase split)
            ;;
        system/skills/*/SKILL.md)
            core; checks+=(33)       # core(1+5+7+12), SKILL.md keywords
            ;;
        system/skills/*)
            core                     # core(1+5+8+12)
            ;;
        system/rules/*)
            core                     # core(2)
            ;;
        system/settings.json)
            core                     # core(3)
            ;;
        system/agents/*.md)
            core; checks+=(42)       # core(4), debrief-analyst model
            ;;
        system/procedures/close.md)
            core; checks+=(23 36 40 43 44 45)  # core(8), routing, ruflo preamble, AskUserQ, close-weight, close-routing, mcp ToolSearch
            ;;
        system/procedures/build.md)
            core; checks+=(23 36 40 43 44 45)  # build.md contains CLOSE section inline
            ;;
        system/procedures/*.md)
            core; checks+=(23 36 40 45)
            ;;
        system/hooks/lib/*.sh)
            core                     # core(9+9b+11)
            ;;
        system/hooks/*.sh)
            core; checks+=(28 30 37 47)  # core(9), no-python3, brana-CLI-cd, stale-model, PreToolUse output
            ;;
        system/hooks/tests/*)
            checks+=(32)             # echo|grep-q pipefail (>14, individually filterable)
            ;;
        system/commands/*)
            core                     # core(10)
            ;;
        system/scripts/feed-summarize.sh)
            core; checks+=(41)
            ;;
        system/scripts/*.sh)
            core                     # core(11)
            ;;
        docs/spec-graph.json)
            checks+=(18 19 20 21)
            ;;
        .claude/tasks.json)
            checks+=(25 26)
            ;;
        system/plugin.json)
            checks+=(35)
            ;;
        .claude/hooks.json)
            checks+=(39 48)
            ;;
        docs/architecture/hooks.md)
            checks+=(48 49)
            ;;
        docs/*)
            core; checks+=(15 16)    # core(13), assumption freshness, changelog currency
            ;;
        system/*)
            core                     # core(14) undocumented system files
            ;;
    esac
done

if [ ${#checks[@]} -eq 0 ]; then
    exit 0
fi

printf '%s\n' "${checks[@]}" | sort -u

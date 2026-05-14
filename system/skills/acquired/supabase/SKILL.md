---
name: supabase
description: "Use when doing ANY task involving Supabase: Database, Auth, Edge Functions, Realtime, Storage, Vectors, Cron, Queues, supabase-js, @supabase/ssr, RLS, schema migrations, CLI, MCP server. Includes security checklist."
group: brana
keywords: [supabase, postgres, rls, auth, edge-functions, realtime, storage, migrations, supabase-js, nextjs]
allowed-tools: [Read, Glob, Grep, Bash, Edit, Write, AskUserQuestion]
status: experimental
source: "github.com/supabase/agent-skills/skills/supabase"
acquired: "2026-05-14"
quarantine: false
---

<!-- PROCEDURE_FILE: procedures/supabase.md -->
This skill's full procedure is in a separate file for startup performance (ADR-034).
Read and execute `system/procedures/supabase.md` from the plugin root directory.
If the path doesn't resolve, use Glob to find `**/procedures/supabase.md`.

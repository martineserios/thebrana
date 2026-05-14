---
name: supabase
description: "Use when doing ANY task involving Supabase. Triggers: Supabase products (Database, Auth, Edge Functions, Realtime, Storage, Vectors, Cron, Queues); client libraries and SSR integrations (supabase-js, @supabase/ssr) in Next.js, React, SvelteKit, Astro, Remix; auth issues (login, logout, sessions, JWT, cookies, getSession, getUser, getClaims, RLS); Supabase CLI or MCP server; schema changes, migrations, security audits, Postgres extensions (pg_graphql, pg_cron, pg_vector)."
metadata:
  author: supabase
  version: "0.1.2"
---

# Supabase

## Core Principles

**1. Supabase changes frequently — verify against changelog and current docs before implementing.**
Do not rely on training data for Supabase features. Function signatures, config.toml settings, and API conventions change between versions.

First, fetch `https://supabase.com/changelog.md` (a lightweight summary index — not a heavy pull), scan for `breaking-change` tags relevant to your task, and follow the linked page for any that apply. Then look up the relevant topic using the documentation access methods below.

**2. Verify your work.**
After implementing any fix, run a test query to confirm the change works. A fix without verification is incomplete.

**3. Recover from errors, don't loop.**
If an approach fails after 2-3 attempts, stop and reconsider. Try a different method, check documentation, inspect the error more carefully, and review relevant logs when available.

**4. Exposing tables to the Data API:** Depending on the user's Data API settings, newly created tables may not be automatically exposed via the Data (REST) API. If this is the case, `anon` and `authenticated` roles will need to be explicitly granted access.

**5. RLS in exposed schemas.**
Enable RLS on every table in any exposed schema, which includes `public` by default.

**6. Security checklist.**
When working on any Supabase task that touches auth, RLS, views, storage, or user data, run through this checklist:

- **Never use `user_metadata` claims in JWT-based authorization decisions.** Use `raw_app_meta_data` instead.
- **Deleting a user does not invalidate existing access tokens.**
- **Views bypass RLS by default.** Use `CREATE VIEW ... WITH (security_invoker = true)` in Postgres 15+.
- **UPDATE requires a SELECT policy.** Without it, updates silently return 0 rows.
- **Do not put `security definer` functions in an exposed schema.**
- **Storage upsert requires INSERT + SELECT + UPDATE.** Granting only INSERT allows new uploads but file replacement silently fails.
- **Never expose the `service_role` or secret key in public clients.**

## Supabase CLI

Always discover commands via `--help` — never guess.

**Known gotchas:**
- `supabase db query` requires **CLI v2.79.0+** → use MCP `execute_sql` or `psql` as fallback
- `supabase db advisors` requires **CLI v2.81.3+** → use MCP `get_advisors` as fallback
- Always create migration files with `supabase migration new <name>` — never invent filenames.

## Supabase MCP Server

For setup instructions, see the MCP setup guide at `https://supabase.com/docs/guides/getting-started/mcp`.

**Troubleshooting:**
1. `curl -so /dev/null -w "%{http_code}" https://mcp.supabase.com/mcp` — 401 = server up
2. Check `.mcp.json` in project root
3. If tools aren't visible, trigger OAuth 2.1 auth flow

## Documentation Access (priority order)

1. **MCP `search_docs` tool** (preferred)
2. **Fetch docs as markdown** — append `.md` to any docs URL
3. **Web search** for Supabase-specific topics

## Making and Committing Schema Changes

**To iterate:** use `execute_sql` (MCP) or `supabase db query` (CLI). Do NOT use `apply_migration` for iteration — it writes history entries on every call.

**To commit:**
1. Run `supabase db advisors` — fix any issues
2. Review Security Checklist
3. `supabase db pull <descriptive-name> --local --yes`
4. Verify: `supabase migration list --local`

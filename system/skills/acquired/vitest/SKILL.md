---
name: vitest
description: "Vitest unit testing — Vite-powered, Jest-compatible. Use when writing tests, mocking, configuring coverage, or working with test filtering and fixtures."
group: brana
keywords: [vitest, testing, vite, jest, mocking, coverage, typescript, esm, fixtures, snapshots]
allowed-tools: [Read, Write, Edit, Bash, Glob, Grep, Agent]
status: experimental
source: "https://github.com/supabase/supabase @vitest"
acquired: "2026-04-30"
quarantine: false
---
Vitest is a next-generation testing framework powered by Vite. It provides a Jest-compatible API with native ESM, TypeScript, and JSX support out of the box. Vitest shares the same config, transformers, resolvers, and plugins with your Vite app.

**Key Features:**
- Vite-native: Uses Vite's transformation pipeline for fast HMR-like test updates
- Jest-compatible: Drop-in replacement for most Jest test suites
- Smart watch mode: Only reruns affected tests based on module graph
- Native ESM, TypeScript, JSX support without configuration
- Multi-threaded workers for parallel test execution
- Built-in coverage via V8 or Istanbul
- Snapshot testing, mocking, and spy utilities

> The skill is based on Vitest 3.x, generated at 2026-01-28.

## Core

| Topic | Description | Reference |
|-------|-------------|-----------|
| Configuration | Vitest and Vite config integration, defineConfig usage | core-config (upstream `references/core-config.md`, not installed locally) |
| CLI | Command line interface, commands and options | core-cli (upstream `references/core-cli.md`, not installed locally) |
| Test API | test/it function, modifiers like skip, only, concurrent | core-test-api (upstream `references/core-test-api.md`, not installed locally) |
| Describe API | describe/suite for grouping tests and nested suites | core-describe (upstream `references/core-describe.md`, not installed locally) |
| Expect API | Assertions with toBe, toEqual, matchers and asymmetric matchers | core-expect (upstream `references/core-expect.md`, not installed locally) |
| Hooks | beforeEach, afterEach, beforeAll, afterAll, aroundEach | core-hooks (upstream `references/core-hooks.md`, not installed locally) |

## Features

| Topic | Description | Reference |
|-------|-------------|-----------|
| Mocking | Mock functions, modules, timers, dates with vi utilities | features-mocking (upstream `references/features-mocking.md`, not installed locally) |
| Snapshots | Snapshot testing with toMatchSnapshot and inline snapshots | features-snapshots (upstream `references/features-snapshots.md`, not installed locally) |
| Coverage | Code coverage with V8 or Istanbul providers | features-coverage (upstream `references/features-coverage.md`, not installed locally) |
| Test Context | Test fixtures, context.expect, test.extend for custom fixtures | features-context (upstream `references/features-context.md`, not installed locally) |
| Concurrency | Concurrent tests, parallel execution, sharding | features-concurrency (upstream `references/features-concurrency.md`, not installed locally) |
| Filtering | Filter tests by name, file patterns, tags | features-filtering (upstream `references/features-filtering.md`, not installed locally) |

## Advanced

| Topic | Description | Reference |
|-------|-------------|-----------|
| Vi Utilities | vi helper: mock, spyOn, fake timers, hoisted, waitFor | advanced-vi (upstream `references/advanced-vi.md`, not installed locally) |
| Environments | Test environments: node, jsdom, happy-dom, custom | advanced-environments (upstream `references/advanced-environments.md`, not installed locally) |
| Type Testing | Type-level testing with expectTypeOf and assertType | advanced-type-testing (upstream `references/advanced-type-testing.md`, not installed locally) |
| Projects | Multi-project workspaces, different configs per project | advanced-projects (upstream `references/advanced-projects.md`, not installed locally) |

## Project-specific notes (proyecto_anita)

- Run vitest from `services/frontend-v2/`, not repo root — `@/` alias resolves relative to `vitest.config.ts` directory (see `feedback_vitest_cwd_alias.md`)
- Mock `@/lib/supabase/client` before any import that transitively reaches it (see `feedback_supabase_mock_at_import.md`)

# knowledge_pipeline.rs — spec stub

Spec: docs/architecture/features/inbox-to-dimensions-pipeline.md
Tasks: t-1131 (core), t-1145 (claude shell-out spike)

## Public API (to be implemented)

- `PipelineState` / `UrlEntry` / `UrlStatus` — state types
- `pipeline_state_path()` → PathBuf
- `load_state(path)` / `save_state(path, state)` — atomic JSON R/W
- `parse_linkedin_url(url)` → Option<(author, title_signal)>
- `extract_tags_from_line(line)` → Vec<String>
- `parse_event_log(content, known_urls)` → Vec<UrlEventEntry>
- `find_event_log_files_in(projects_dir)` → Vec<PathBuf>
- `extract_unprocessed_urls(state)` → Result<Vec<UrlEventEntry>>
- `is_allowed_write_path(path, brana_knowledge_root)` → bool
- `assert_allowed_write(path, brana_knowledge_root)` → Result<()>
- `count_drafts(brana_knowledge_root)` → usize
- `resolve_claude_binary()` → Option<PathBuf>
- `call_claude_json(prompt)` → Result<serde_json::Value>
- `DRAFT_CAP: usize = 10`

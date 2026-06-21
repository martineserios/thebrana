//! brana — fast standalone CLI dispatcher
//!
//! Single static binary. 12ms startup. No Python dependency.
//! Handles high-frequency commands natively in Rust.
//! Delegates complex ops to existing shell scripts.

mod cli;
mod commands;
mod files;
mod sync;
mod sync_linear;
mod tasks;
mod themes;
mod transcribe;
mod util;

use clap::{Parser, ValueEnum};
use cli::*;

/// Run a command that returns `anyhow::Result<()>`, printing the error and
/// exiting with code 1 on failure.
fn run_or_exit(result: anyhow::Result<()>) {
    if let Err(e) = result {
        eprintln!("{e:#}");
        std::process::exit(1);
    }
}

fn main() {
    let args = Cli::parse();
    let theme_name = themes::load_theme_name();
    let theme = themes::Theme::load(&theme_name);

    match args.command {
        Commands::Version => run_or_exit(commands::misc::cmd_version()),
        Commands::Transcribe { file, model } => run_or_exit(commands::misc::cmd_transcribe(&file, &model)),
        Commands::Files { cmd } => run_or_exit(commands::files::cmd_files(cmd)),
        Commands::Doctor { validate } => commands::doctor::cmd_doctor(&theme, validate),
        Commands::Validate { file } => run_or_exit(commands::misc::cmd_validate(&file)),
        Commands::Portfolio => run_or_exit(commands::misc::cmd_portfolio()),
        Commands::Run { task_id, spawn } => run_or_exit(commands::run::cmd_run(&task_id, spawn)),
        Commands::Queue { max, auto } => run_or_exit(commands::run::cmd_queue(max, auto)),
        Commands::Agents { cmd } => match cmd {
            None => run_or_exit(commands::run::cmd_agents()),
            Some(AgentsCmd::Kill { agent_id }) => run_or_exit(commands::run::cmd_agents_kill(&agent_id)),
        },
        Commands::Backlog { cmd } => match cmd {
            BacklogCmd::Next { tag, kind, limit, priority, task_type, effort, parent, json } => run_or_exit(commands::backlog::cmd_next(&theme, tag, ve_str(&kind), limit, ve_str(&priority), ve_str(&task_type), ve_str(&effort), parent, json)),
            BacklogCmd::Query {
                tag, status, kind, priority, effort, search, count, mut output, json,
                task_type, parent, branch, work_type, epic,
            } => {
                if json { output = "json".to_string(); }
                run_or_exit(commands::backlog::cmd_query(tag, ve_str(&status), ve_str(&kind), ve_str(&priority), ve_str(&effort), search, count, output, &theme, ve_str(&task_type), parent, branch, ve_str(&work_type), epic))
            },
            BacklogCmd::Focus { top, json, work_type, epic } => run_or_exit(commands::backlog::cmd_focus(&theme, top, json, ve_str(&work_type).as_deref(), epic.as_deref())),
            BacklogCmd::Search { text, json } => run_or_exit(commands::backlog::cmd_search(&text, &theme, json)),
            BacklogCmd::Status { all, json } => run_or_exit(commands::backlog::cmd_status(&theme, all, json)),
            BacklogCmd::Blocked => run_or_exit(commands::backlog::cmd_blocked(&theme)),
            BacklogCmd::Stale { days } => run_or_exit(commands::backlog::cmd_stale(days, &theme)),
            BacklogCmd::TriageStale { dry_run, batch, yes, git_dir, file } => run_or_exit(commands::backlog::cmd_triage_stale(dry_run, batch, yes, git_dir, file)),
            BacklogCmd::Context { task_id } => run_or_exit(commands::backlog::cmd_context(&task_id, &theme)),
            BacklogCmd::Diff => run_or_exit(commands::backlog::cmd_diff(&theme)),
            BacklogCmd::Burndown { period } => run_or_exit(commands::backlog::cmd_burndown(&period.to_possible_value().unwrap().get_name().to_string(), &theme)),
            BacklogCmd::Rollup { file, dry_run } => run_or_exit(commands::backlog::cmd_rollup(file, dry_run)),
            BacklogCmd::Set { task_id, field, value, append, file } => run_or_exit(commands::backlog::cmd_set(&task_id, &field, &value, append, file)),
            BacklogCmd::SetActive { slug } => run_or_exit(commands::backlog::cmd_set_active(&slug)),
            BacklogCmd::Add { json, subject, kind, task_type, tags, description, effort, parent, priority, context, file, project, epic, work_type, acceptance_criteria } =>
                run_or_exit(commands::backlog::cmd_add(json, subject, kind, task_type, tags, description, effort, parent, priority, context, file, project, epic, work_type, acceptance_criteria)),
            BacklogCmd::Get { task_id, field } => run_or_exit(commands::backlog::cmd_get(&task_id, field)),
            BacklogCmd::Lint { task_id, json, file } => match commands::backlog::cmd_lint(&task_id, json, file) {
                Ok(true) => {}
                Ok(false) => std::process::exit(1),
                Err(e) => { eprintln!("{e:#}"); std::process::exit(1); }
            },
            BacklogCmd::Stats => run_or_exit(commands::backlog::cmd_stats()),
            BacklogCmd::Tags { filter, any, output } => run_or_exit(commands::backlog::cmd_tags(filter, any, output, &theme)),
            BacklogCmd::Roadmap { json } => run_or_exit(commands::backlog::cmd_roadmap(json, &theme)),
            BacklogCmd::Tree { root_id, json } => run_or_exit(commands::backlog::cmd_tree(&root_id, json, &theme)),
            BacklogCmd::Delete { task_id, cascade, file } => run_or_exit(commands::backlog::cmd_delete(&task_id, cascade, file)),
            BacklogCmd::Move { task_id, parent, file } => run_or_exit(commands::backlog::cmd_move(&task_id, &parent, file)),
            BacklogCmd::Archive { phase_id, file } => run_or_exit(commands::backlog::cmd_archive(phase_id, file)),
            BacklogCmd::Sync { dry_run, force, parallel, linear, project } => {
                if linear {
                    run_or_exit(sync_linear::cmd_sync_linear(dry_run, force, project.as_deref()))
                } else {
                    run_or_exit(sync::cmd_sync(dry_run, force, parallel))
                }
            }
            BacklogCmd::Complete { task_id, file } => run_or_exit(commands::backlog::cmd_set(&task_id, "status", "completed", false, file)),
            BacklogCmd::MigrateEpic { dry_run, file } => run_or_exit(commands::backlog::cmd_backlog_migrate_epic(dry_run, file)),
            BacklogCmd::Initiatives { json } => run_or_exit(commands::backlog::cmd_initiatives(&theme, json)),
            BacklogCmd::Epics { json } => run_or_exit(commands::backlog::cmd_epics(&theme, json)),
        },
        Commands::Ops { cmd } => match cmd {
            OpsCmd::Status { all } => run_or_exit(commands::ops::cmd_ops_status(&theme, all)),
            OpsCmd::Health => run_or_exit(commands::ops::cmd_ops_health(&theme)),
            OpsCmd::Collisions => run_or_exit(commands::ops::cmd_ops_collisions(&theme)),
            OpsCmd::Drift => run_or_exit(commands::ops::cmd_ops_drift(&theme)),
            OpsCmd::Logs { job_name, tail } => run_or_exit(commands::ops::cmd_ops_logs(&job_name, tail)),
            OpsCmd::History { job_name, last } => run_or_exit(commands::ops::cmd_ops_history(&job_name, last, &theme)),
            OpsCmd::Run { job_name } => run_or_exit(commands::ops::cmd_ops_run(&job_name)),
            OpsCmd::Enable { job_name } => run_or_exit(commands::ops::cmd_ops_toggle(&job_name, true)),
            OpsCmd::Disable { job_name } => run_or_exit(commands::ops::cmd_ops_toggle(&job_name, false)),
            OpsCmd::Sync { auto_commit, direction } => run_or_exit(commands::ops::cmd_ops_sync(&direction, auto_commit)),
            OpsCmd::Reindex => run_or_exit(commands::ops::cmd_ops_reindex()),
            OpsCmd::Metrics { session_file } => run_or_exit(commands::ops::cmd_ops_metrics(&session_file)),
        },
        Commands::Feed { cmd } => run_or_exit(commands::feed::cmd_feed(cmd)),
        Commands::Inbox { cmd } => run_or_exit(commands::inbox::cmd_inbox(cmd)),
        Commands::Skills { cmd } => match cmd {
            SkillsCmd::Suggest { task, query } => {
                run_or_exit(commands::skills::cmd_suggest(task.as_deref(), query.as_deref()))
            }
            SkillsCmd::Search { query } => run_or_exit(commands::skills::cmd_search(&query)),
            SkillsCmd::List { human } => run_or_exit(commands::skills::cmd_list(human)),
            SkillsCmd::Reindex { changed, force } => run_or_exit(commands::skills::cmd_reindex(changed, force)),
            SkillsCmd::Usage { days, cull_threshold, json } => {
                run_or_exit(commands::skills::cmd_usage(days, cull_threshold, json))
            }
            SkillsCmd::Graph => run_or_exit(commands::skills::cmd_graph()),
        },
        Commands::Handoff { cmd } => match cmd {
            Some(HandoffCmd::Last { n }) => run_or_exit(commands::handoff::cmd_handoff_last(n)),
            None => run_or_exit(commands::handoff::cmd_handoff_last(1)),
            Some(HandoffCmd::List) => run_or_exit(commands::handoff::cmd_handoff_list()),
            Some(HandoffCmd::Path) => run_or_exit(commands::handoff::cmd_handoff_path()),
        },
        Commands::Memory { cmd } => match cmd {
            MemoryCmd::Write { memory_type, scope, slug, content } => {
                run_or_exit(commands::memory::cmd_memory_write(&memory_type, &scope, &slug, &content))
            }
            MemoryCmd::Index { scope } => {
                run_or_exit(commands::memory::cmd_memory_index(&scope))
            }
            MemoryCmd::Reindex { db } => {
                run_or_exit(commands::memory::cmd_memory_reindex(db))
            }
            MemoryCmd::Search { query, limit, json, db } => {
                run_or_exit(commands::memory::cmd_memory_search(&query, limit, json, db))
            }
        },
        Commands::CloseQueue { cmd } => match cmd {
            CloseQueueCmd::Append {
                project, branch, git_root, git_range, snapshot_path,
                commit_count, snapshot_truncated, omitted_files, session_notes_path, propagate,
            } => run_or_exit(commands::close_queue::cmd_append(
                project, branch, git_root, git_range, snapshot_path,
                commit_count, snapshot_truncated, omitted_files, session_notes_path, propagate,
            )),
            CloseQueueCmd::List { unprocessed } => {
                run_or_exit(commands::close_queue::cmd_list(unprocessed))
            }
            CloseQueueCmd::MarkPropagated { project, branch, git_range } => {
                run_or_exit(commands::close_queue::cmd_mark_propagated(&project, &branch, &git_range))
            }
            CloseQueueCmd::MarkProcessed { id, summary_path } => {
                run_or_exit(commands::close_queue::cmd_mark_processed(&id, &summary_path))
            }
            CloseQueueCmd::MarkFailed { id, error } => {
                run_or_exit(commands::close_queue::cmd_mark_failed(&id, &error))
            }
            CloseQueueCmd::Prune => run_or_exit(commands::close_queue::cmd_prune()),
            CloseQueueCmd::ResetRetries { id } => {
                run_or_exit(commands::close_queue::cmd_reset_retries(id.as_deref()))
            }
        },
        Commands::Remind { cmd } => match cmd {
            RemindCmd::Write { text, action, priority, dedup_key, project, tags, at, channels, task_id } => {
                run_or_exit(commands::remind::cmd_write(&text, action, priority, dedup_key, project, tags, at, channels, task_id))
            }
            RemindCmd::List { status } => run_or_exit(commands::remind::cmd_list(status)),
            RemindCmd::Due { dispatch } => run_or_exit(commands::remind::cmd_due(dispatch)),
            RemindCmd::Resolve { id } => run_or_exit(commands::remind::cmd_resolve(&id)),
            RemindCmd::Snooze { id, duration } => run_or_exit(commands::remind::cmd_snooze(&id, &duration)),
        },
        Commands::Notify { cmd } => match cmd {
            NotifyCmd::Send { channel, message } => {
                run_or_exit(commands::notify::cmd_send(&channel, &message))
            }
            NotifyCmd::Channels => run_or_exit(commands::notify::cmd_channels()),
        },
        Commands::Session { cmd } => match cmd {
            SessionCmd::Write { file, minimal } => run_or_exit(commands::session::cmd_session_write(file, minimal)),
            SessionCmd::Read { json, all, since } => run_or_exit(commands::session::cmd_session_read(json, all, since)),
            SessionCmd::History { limit } => run_or_exit(commands::session::cmd_session_history(limit)),
            SessionCmd::Path => run_or_exit(commands::session::cmd_session_path()),
            SessionCmd::Migrate => run_or_exit(commands::session::cmd_session_migrate()),
            SessionCmd::MarkConsumed => run_or_exit((|| -> anyhow::Result<()> {
                let root = commands::session::require_project_root()?;
                commands::session::mark_consumed(&root)?;
                Ok(())
            })()),
            SessionCmd::Insights { limit, json } => run_or_exit(commands::session::cmd_session_insights(limit, json)),
            SessionCmd::Epic { cmd } => match cmd {
                EpicCmd::Upsert { slug, completed, resolved_texts } => run_or_exit(commands::session::cmd_epic_upsert(&slug, &completed, &resolved_texts)),
                EpicCmd::Read { slug, json } => run_or_exit(commands::session::cmd_epic_read(&slug, json)),
                EpicCmd::Archive { slug } => run_or_exit(commands::session::cmd_epic_archive(&slug)),
                EpicCmd::ReadMarker => run_or_exit(commands::session::cmd_epic_read_marker()),
                EpicCmd::ClearMarker => run_or_exit(commands::session::cmd_epic_clear_marker()),
                EpicCmd::Focus { slug } => run_or_exit(commands::session::cmd_epic_focus(&slug)),
                EpicCmd::Unfocus => run_or_exit(commands::session::cmd_epic_unfocus()),
                EpicCmd::Status { json } => run_or_exit(commands::session::cmd_epic_status(json)),
            },
        },
        Commands::Knowledge { cmd } => match cmd {
            KnowledgeCmd::Reindex { changed, patterns, files } => {
                if patterns {
                    run_or_exit(commands::knowledge::cmd_reindex_patterns(files));
                } else {
                    run_or_exit(commands::knowledge::cmd_reindex(changed, files));
                }
            }
            KnowledgeCmd::Status => commands::knowledge::cmd_status(),
            KnowledgeCmd::Search { query, limit, namespace, json } => {
                run_or_exit(commands::knowledge::cmd_search(&query, limit, &namespace, json))
            }
            KnowledgeCmd::Process { tier1, tier2, draft, report, status, reset_url, dry_run, limit } => {
                run_or_exit(commands::knowledge::cmd_process(
                    tier1, tier2, draft, report, status, reset_url, dry_run, limit,
                ))
            }
            KnowledgeCmd::Promote { draft_path, dry_run } => {
                run_or_exit(commands::knowledge::cmd_promote(draft_path, dry_run))
            }
            KnowledgeCmd::Ingest { sources, source, dry_run } => {
                run_or_exit(commands::knowledge::cmd_ingest(sources, source, dry_run))
            }
            KnowledgeCmd::Next => run_or_exit(commands::knowledge::cmd_next()),
            KnowledgeCmd::Run => run_or_exit(commands::knowledge::cmd_run()),
        },
        Commands::Graph { cmd } => run_or_exit(commands::graph::cmd_graph(cmd)),
        Commands::Reference { cmd } => run_or_exit(commands::reference::cmd_reference(cmd)),
        Commands::Decisions { cmd } => run_or_exit(commands::decisions::cmd_decisions(cmd)),
        Commands::Log { entries, tags } => {
            run_or_exit(commands::log::cmd_log(&entries, tags.as_deref()))
        }
        Commands::Deploy => {
            println!("brana deploy = ship dev->main, then ./bootstrap.sh from main  (ADR-060)");
            println!();
            println!("  git checkout main");
            println!("  git merge --ff-only dev      # promote the integration buffer to production");
            println!("  ./bootstrap.sh               # deploy production -> live ~/.claude");
            println!("  git push origin main dev");
            println!("  git checkout dev             # back to the integration branch");
            println!();
            println!("main is production (what bootstrap deploys); dev is the integration buffer,");
            println!("not live. main lagging dev is the safety buffer. No build step, no container.");
            println!();
            println!("Never merge a feature branch into main. See docs/guide/workflows/branching.md");
        }
        Commands::Ratings { last, json } => run_or_exit(commands::ratings::cmd_ratings(last, json)),
        Commands::Recall { query, top, json, db } => {
            run_or_exit(commands::recall::cmd_recall(&query, top, json, db))
        }
    }
}

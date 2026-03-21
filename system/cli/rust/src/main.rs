//! brana — fast standalone CLI dispatcher
//!
//! Single static binary. 12ms startup. No Python dependency.
//! Handles high-frequency commands natively in Rust.
//! Delegates complex ops to existing shell scripts.

mod cli;
mod commands;
mod files;
mod sync;
mod tasks;
mod themes;
mod transcribe;
mod util;

use clap::{Parser, ValueEnum};
use cli::*;

fn main() {
    let args = Cli::parse();
    let theme_name = themes::load_theme_name();
    let theme = themes::Theme::load(&theme_name);

    match args.command {
        Commands::Version => commands::misc::cmd_version(),
        Commands::Transcribe { file, model } => commands::misc::cmd_transcribe(&file, &model),
        Commands::Files { cmd } => commands::files::cmd_files(cmd),
        Commands::Doctor => commands::doctor::cmd_doctor(&theme),
        Commands::Validate { file } => commands::misc::cmd_validate(&file),
        Commands::Portfolio => commands::misc::cmd_portfolio(),
        Commands::Run { task_id, spawn } => commands::run::cmd_run(&task_id, spawn),
        Commands::Queue { max, auto } => commands::run::cmd_queue(max, auto),
        Commands::Agents { cmd } => match cmd {
            None => commands::run::cmd_agents(),
            Some(AgentsCmd::Kill { agent_id }) => commands::run::cmd_agents_kill(&agent_id),
        },
        Commands::Backlog { cmd } => match cmd {
            BacklogCmd::Next { tag, stream } => commands::backlog::cmd_next(&theme, tag, ve_str(&stream)),
            BacklogCmd::Query {
                tag, status, stream, priority, effort, search, count, output,
                task_type, parent, branch,
            } => commands::backlog::cmd_query(tag, ve_str(&status), ve_str(&stream), ve_str(&priority), ve_str(&effort), search, count, output, &theme, ve_str(&task_type), parent, branch),
            BacklogCmd::Focus => commands::backlog::cmd_focus(&theme),
            BacklogCmd::Search { text } => commands::backlog::cmd_search(&text, &theme),
            BacklogCmd::Status { all, json } => commands::backlog::cmd_status(&theme, all, json),
            BacklogCmd::Blocked => commands::backlog::cmd_blocked(&theme),
            BacklogCmd::Stale { days } => commands::backlog::cmd_stale(days, &theme),
            BacklogCmd::Context { task_id } => commands::backlog::cmd_context(&task_id, &theme),
            BacklogCmd::Diff => commands::backlog::cmd_diff(&theme),
            BacklogCmd::Burndown { period } => commands::backlog::cmd_burndown(&period.to_possible_value().unwrap().get_name().to_string(), &theme),
            BacklogCmd::Rollup { file, dry_run } => commands::backlog::cmd_rollup(file, dry_run),
            BacklogCmd::Set { task_id, field, value, append, file } => commands::backlog::cmd_set(&task_id, &field, &value, append, file),
            BacklogCmd::Add { json, file } => commands::backlog::cmd_add(&json, file),
            BacklogCmd::Get { task_id, field } => commands::backlog::cmd_get(&task_id, field),
            BacklogCmd::Stats => commands::backlog::cmd_stats(),
            BacklogCmd::Tags { filter, any, output } => commands::backlog::cmd_tags(filter, any, output, &theme),
            BacklogCmd::Roadmap { json } => commands::backlog::cmd_roadmap(json, &theme),
            BacklogCmd::Tree { root_id, json } => commands::backlog::cmd_tree(&root_id, json, &theme),
            BacklogCmd::Sync { dry_run, force, parallel } => sync::cmd_sync(dry_run, force, parallel),
        },
        Commands::Ops { cmd } => match cmd {
            OpsCmd::Status => commands::ops::cmd_ops_status(&theme),
            OpsCmd::Health => commands::ops::cmd_ops_health(&theme),
            OpsCmd::Collisions => commands::ops::cmd_ops_collisions(&theme),
            OpsCmd::Drift => commands::ops::cmd_ops_drift(&theme),
            OpsCmd::Logs { job_name, tail } => commands::ops::cmd_ops_logs(&job_name, tail),
            OpsCmd::History { job_name, last } => commands::ops::cmd_ops_history(&job_name, last, &theme),
            OpsCmd::Run { job_name } => commands::ops::cmd_ops_run(&job_name),
            OpsCmd::Enable { job_name } => commands::ops::cmd_ops_toggle(&job_name, true),
            OpsCmd::Disable { job_name } => commands::ops::cmd_ops_toggle(&job_name, false),
            OpsCmd::Sync { auto_commit, direction } => commands::ops::cmd_ops_sync(&direction, auto_commit),
            OpsCmd::Reindex => commands::ops::cmd_ops_reindex(),
            OpsCmd::Metrics { session_file } => commands::ops::cmd_ops_metrics(&session_file),
        },
        Commands::Feed { cmd } => commands::feed::cmd_feed(cmd),
        Commands::Inbox { cmd } => commands::inbox::cmd_inbox(cmd),
        Commands::Skills { cmd } => match cmd {
            SkillsCmd::Suggest { task, query } => {
                commands::skills::cmd_suggest(task.as_deref(), query.as_deref())
            }
            SkillsCmd::Search { query } => commands::skills::cmd_search(&query),
            SkillsCmd::List => commands::skills::cmd_list(),
        },
    }
}

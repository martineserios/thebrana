//! t-1770: idea-doc <-> backlog-task linking (`brana backlog ideas`).
//!
//! An idea doc is a top-level `docs/ideas/*.md`. `docs/ideas/drained/` holds docs
//! already drained into tasks and is deliberately NOT listed. A doc counts as
//! linked when any task's `context`, `notes` or `description` contains its
//! repo-relative path (`docs/ideas/<name>.md`).
use serde_json::Value;
use std::path::Path;

pub const IDEAS_REL_DIR: &str = "docs/ideas";
/// Line prefix the link verb writes into an idea doc.
pub const DOC_LINK_PREFIX: &str = "Backlog:";
const TASK_TEXT_FIELDS: [&str; 3] = ["context", "notes", "description"];

/// Outcome of a link operation; `false` means that side already held the reference.
#[derive(Debug, PartialEq, Eq)]
pub struct LinkOutcome {
    pub doc: String,
    pub task_id: String,
    pub task_updated: bool,
    pub doc_updated: bool,
}

/// Repo-relative paths (`docs/ideas/x.md`) of the top-level idea docs under `root`, sorted.
pub fn list_idea_docs(root: &Path) -> Result<Vec<String>, String> {
    let dir = root.join(IDEAS_REL_DIR);
    let mut out = Vec::new();
    for e in std::fs::read_dir(&dir).map_err(|e| format!("reading {}: {e}", dir.display()))? {
        let p = e.map_err(|e| e.to_string())?.path();
        if p.is_file() && p.extension().is_some_and(|x| x == "md") {
            if let Some(n) = p.file_name().and_then(|n| n.to_str()) {
                out.push(format!("{IDEAS_REL_DIR}/{n}"));
            }
        }
    }
    out.sort();
    Ok(out)
}

/// The subset of `docs` that no task references.
pub fn unlinked_ideas(docs: &[String], tasks: &[Value]) -> Vec<String> {
    docs.iter()
        .filter(|d| !tasks.iter().any(|t| task_references(t, d)))
        .cloned()
        .collect()
}

fn task_references(task: &Value, doc: &str) -> bool {
    TASK_TEXT_FIELDS
        .iter()
        .any(|f| task[*f].as_str().is_some_and(|s| s.contains(doc)))
}

/// Normalize `x.md`, `docs/ideas/x.md` or `./docs/ideas/x.md` to `docs/ideas/x.md`.
pub fn normalize_doc(doc: &str) -> String {
    let d = doc.trim().trim_start_matches("./");
    let name = d.strip_prefix(&format!("{IDEAS_REL_DIR}/")).unwrap_or(d);
    format!("{IDEAS_REL_DIR}/{name}")
}

/// Whole-token match, so `t-5` is not found inside `t-55`.
fn line_has_id(line: &str, task_id: &str) -> bool {
    line.split(|c: char| !(c.is_ascii_alphanumeric() || c == '-'))
        .any(|tok| tok == task_id)
}

/// Add the task id to the doc text. `None` when the doc already carries it on a
/// `Backlog:` line (idempotent). Extends an existing `Backlog:` line, else appends one.
pub fn link_doc_text(text: &str, task_id: &str) -> Option<String> {
    let is_link_line = |l: &str| l.trim_start().starts_with(DOC_LINK_PREFIX);
    if text.lines().any(|l| is_link_line(l) && line_has_id(l, task_id)) {
        return None;
    }
    if text.lines().any(is_link_line) {
        let mut done = false;
        let lines: Vec<String> = text
            .lines()
            .map(|l| {
                if !done && is_link_line(l) {
                    done = true;
                    format!("{}, {task_id}", l.trim_end())
                } else {
                    l.to_string()
                }
            })
            .collect();
        let mut out = lines.join("\n");
        if text.ends_with('\n') {
            out.push('\n');
        }
        return Some(out);
    }
    let mut out = text.trim_end_matches('\n').to_string();
    if !out.is_empty() {
        out.push_str("\n\n");
    }
    out.push_str(&format!("{DOC_LINK_PREFIX} {task_id}\n"));
    Some(out)
}

/// Add the doc path to the task's `context`. Returns whether it changed (idempotent).
pub fn link_task_context(task: &mut Value, doc: &str) -> bool {
    let cur = task["context"].as_str().unwrap_or("");
    if cur.contains(doc) {
        return false;
    }
    let line = format!("Idea doc: {doc}");
    let new = if cur.trim().is_empty() {
        line
    } else {
        format!("{}\n{line}", cur.trim_end())
    };
    task["context"] = Value::String(new);
    true
}

/// Wire `doc` <-> `task_id`: lock + write tasks file, and write the idea doc under `root`.
/// Validates both sides before writing either, so a bad doc/task id writes nothing.
pub fn perform_idea_link(
    tasks_path: &Path,
    root: &Path,
    doc: &str,
    task_id: &str,
) -> Result<LinkOutcome, String> {
    let doc = normalize_doc(doc);
    let doc_path = root.join(&doc);
    let doc_text = std::fs::read_to_string(&doc_path)
        .map_err(|e| format!("idea doc {doc} not readable under {}: {e}", root.display()))?;

    let _lock = super::lock_tasks(tasks_path)?;
    let mut val = super::load_raw(tasks_path)?;
    let tasks = val["tasks"].as_array_mut().ok_or("tasks is not an array")?;
    let task = tasks
        .iter_mut()
        .find(|t| t["id"].as_str() == Some(task_id))
        .ok_or_else(|| format!("task {task_id} not found"))?;

    let task_updated = link_task_context(task, &doc);
    let new_doc = link_doc_text(&doc_text, task_id);

    if task_updated {
        val["last_modified"] = Value::String(chrono::Local::now().to_rfc3339());
        super::save_tasks(tasks_path, &val).map_err(|e| format!("idea link write failed: {e}"))?;
    }
    let doc_updated = new_doc.is_some();
    if let Some(t) = new_doc {
        std::fs::write(&doc_path, t).map_err(|e| format!("writing {doc}: {e}"))?;
    }
    Ok(LinkOutcome { doc, task_id: task_id.to_string(), task_updated, doc_updated })
}

#[cfg(test)]
mod tests {
    use super::*;
    use serde_json::json;

    fn fixture() -> (tempfile::TempDir, std::path::PathBuf) {
        let d = tempfile::tempdir().unwrap();
        std::fs::create_dir_all(d.path().join("docs/ideas/drained")).unwrap();
        std::fs::create_dir_all(d.path().join(".claude")).unwrap();
        std::fs::write(d.path().join("docs/ideas/a.md"), "# A\n").unwrap();
        std::fs::write(d.path().join("docs/ideas/b.md"), "# B\n").unwrap();
        std::fs::write(d.path().join("docs/ideas/notes.txt"), "x").unwrap();
        std::fs::write(d.path().join("docs/ideas/drained/old.md"), "# old\n").unwrap();
        let tf = d.path().join(".claude/tasks.json");
        std::fs::write(
            &tf,
            serde_json::to_string(&json!({"version":"3","tasks":[
                {"id":"t-1","subject":"s","status":"pending","context":"see docs/ideas/a.md"},
                {"id":"t-2","subject":"s2","status":"pending","context":null}
            ]}))
            .unwrap(),
        )
        .unwrap();
        (d, tf)
    }

    #[test]
    fn list_is_top_level_md_only_sorted() {
        let (d, _) = fixture();
        assert_eq!(
            list_idea_docs(d.path()).unwrap(),
            vec!["docs/ideas/a.md", "docs/ideas/b.md"]
        );
    }

    #[test]
    fn unlinked_excludes_referenced_docs() {
        let docs = vec!["docs/ideas/a.md".to_string(), "docs/ideas/b.md".to_string()];
        let tasks = vec![json!({"id":"t-1","context":"see docs/ideas/a.md"})];
        assert_eq!(unlinked_ideas(&docs, &tasks), vec!["docs/ideas/b.md"]);
    }

    #[test]
    fn unlinked_counts_notes_and_description_refs() {
        let docs = vec!["docs/ideas/a.md".to_string(), "docs/ideas/b.md".to_string()];
        let tasks = vec![
            json!({"id":"t-1","notes":"from docs/ideas/a.md"}),
            json!({"id":"t-2","description":"docs/ideas/b.md"}),
        ];
        assert!(unlinked_ideas(&docs, &tasks).is_empty());
    }

    #[test]
    fn normalize_accepts_bare_name_and_full_path() {
        assert_eq!(normalize_doc("x.md"), "docs/ideas/x.md");
        assert_eq!(normalize_doc("docs/ideas/x.md"), "docs/ideas/x.md");
        assert_eq!(normalize_doc("./docs/ideas/x.md"), "docs/ideas/x.md");
    }

    #[test]
    fn doc_text_gets_backlog_line() {
        let out = link_doc_text("# A\n", "t-5").unwrap();
        assert!(out.lines().any(|l| l == "Backlog: t-5"), "{out}");
    }

    #[test]
    fn doc_text_link_is_idempotent() {
        let once = link_doc_text("# A\n", "t-5").unwrap();
        assert_eq!(link_doc_text(&once, "t-5"), None);
    }

    #[test]
    fn doc_text_extends_existing_backlog_line() {
        let out = link_doc_text("# A\n\nBacklog: t-5\n", "t-6").unwrap();
        assert!(out.contains("Backlog: t-5, t-6"), "{out}");
        assert_eq!(out.matches("Backlog:").count(), 1);
    }

    #[test]
    fn doc_text_id_prefix_is_not_a_match() {
        // t-5 must not be considered linked because t-55 is.
        assert!(link_doc_text("Backlog: t-55\n", "t-5").is_some());
    }

    #[test]
    fn task_context_appends_and_is_idempotent() {
        let mut t = json!({"id":"t-2","context":"existing"});
        assert!(link_task_context(&mut t, "docs/ideas/b.md"));
        assert_eq!(t["context"], "existing\nIdea doc: docs/ideas/b.md");
        assert!(!link_task_context(&mut t, "docs/ideas/b.md"));
        assert_eq!(t["context"].as_str().unwrap().matches("docs/ideas/b.md").count(), 1);
    }

    #[test]
    fn task_context_null_is_set() {
        let mut t = json!({"id":"t-2","context":null});
        assert!(link_task_context(&mut t, "docs/ideas/b.md"));
        assert_eq!(t["context"], "Idea doc: docs/ideas/b.md");
    }

    #[test]
    fn perform_link_writes_both_sides_twice_no_dupes() {
        let (d, tf) = fixture();
        let first = perform_idea_link(&tf, d.path(), "b.md", "t-2").unwrap();
        assert!(first.task_updated && first.doc_updated);
        let second = perform_idea_link(&tf, d.path(), "docs/ideas/b.md", "t-2").unwrap();
        assert!(!second.task_updated && !second.doc_updated);

        let doc = std::fs::read_to_string(d.path().join("docs/ideas/b.md")).unwrap();
        assert_eq!(doc.matches("t-2").count(), 1, "{doc}");
        let v: Value = serde_json::from_str(&std::fs::read_to_string(&tf).unwrap()).unwrap();
        let ctx = v["tasks"][1]["context"].as_str().unwrap();
        assert_eq!(ctx.matches("docs/ideas/b.md").count(), 1, "{ctx}");
        let tasks = v["tasks"].as_array().unwrap();
        let docs = list_idea_docs(d.path()).unwrap();
        assert!(unlinked_ideas(&docs, tasks).is_empty());
    }

    #[test]
    fn perform_link_unknown_task_errors_and_writes_nothing() {
        let (d, tf) = fixture();
        assert!(perform_idea_link(&tf, d.path(), "b.md", "t-999").is_err());
        let doc = std::fs::read_to_string(d.path().join("docs/ideas/b.md")).unwrap();
        assert_eq!(doc, "# B\n");
    }

    #[test]
    fn perform_link_missing_doc_errors() {
        let (d, tf) = fixture();
        assert!(perform_idea_link(&tf, d.path(), "nope.md", "t-2").is_err());
    }
}

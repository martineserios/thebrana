#!/usr/bin/env python3
"""Incremental tasks.json → GitHub Issues sync.

Called by task-sync.sh after any Write/Edit to .claude/tasks.json.
Compares current tasks against the issue map and syncs differences.

Usage: task-sync.py <project_slug> <tasks_json_path> <config_path>
"""
import json
import subprocess
import sys
import os
import time

def run(cmd, timeout=30):
    """Run shell command, return (stdout, error_string_or_None)."""
    try:
        r = subprocess.run(cmd, shell=True, capture_output=True, text=True, timeout=timeout)
        if r.returncode != 0:
            return None, r.stderr.strip()[:200]
        return r.stdout.strip(), None
    except subprocess.TimeoutExpired:
        return None, "timeout"


def ensure_label(repo, label):
    """Create a label if it doesn't exist."""
    color = "c5def5" if label.startswith("stream:") else "e4e669"
    run(f'gh label create "{label}" --repo {repo} --color "{color}" --force')


def build_labels(task):
    """Build label list for a task."""
    labels = []
    stream = task.get("stream")
    if stream:
        labels.append(f"stream:{stream}")
    for tag in (task.get("tags") or []):
        labels.append(f"tag:{tag}")
    if task.get("type") in ("phase", "milestone"):
        labels.append("enhancement")
    return labels


def build_body(task, task_map):
    """Build issue body markdown."""
    lines = []
    desc = task.get("description", "")
    if desc:
        lines.append(desc)
        lines.append("")

    lines.append("## Metadata")
    lines.append(f"- **Task ID:** `{task['id']}`")
    lines.append(f"- **Type:** {task.get('type', '—')}")
    lines.append(f"- **Stream:** {task.get('stream', '—')}")
    lines.append(f"- **Status:** {task.get('status', '—')}")

    for field, label in [("priority", "Priority"), ("effort", "Effort"),
                         ("strategy", "Strategy"), ("branch", "Branch"),
                         ("started", "Started"), ("completed", "Completed")]:
        val = task.get(field)
        if val:
            lines.append(f"- **{label}:** {'`' + val + '`' if field == 'branch' else val}")

    parent = task.get("parent")
    if parent and parent in task_map:
        lines.append(f"- **Parent:** #{task_map[parent]}")

    blocked = task.get("blocked_by") or []
    if blocked:
        refs = [f"#{task_map[b]}" if b in task_map else b for b in blocked]
        lines.append(f"- **Blocked by:** {', '.join(refs)}")

    ctx = task.get("context")
    if ctx:
        lines.append("\n## Context")
        lines.append(ctx)

    notes = task.get("notes")
    if notes:
        lines.append("\n## Notes")
        lines.append(notes)

    return "\n".join(lines)


def get_project_fields(owner, proj_num):
    """Get project field IDs and option IDs."""
    out, err = run(f'gh project field-list {proj_num} --owner {owner} --format json')
    if not out:
        return {}, None

    data = json.loads(out)
    fields = {}
    proj_id = None

    # Get project ID
    out2, _ = run(f'gh project view {proj_num} --owner {owner} --format json')
    if out2:
        proj_id = json.loads(out2).get("id")

    for f in data.get("fields", []):
        name = f["name"]
        if f.get("options"):
            opts = {o["name"]: o["id"] for o in f["options"]}
            # Normalize status options
            if name == "Status":
                opts_norm = {}
                for k, v in opts.items():
                    opts_norm[k.lower().replace(" ", "_")] = v
                fields["status"] = {"id": f["id"], "options": opts_norm}
            elif name == "Priority":
                fields["priority"] = {"id": f["id"], "options": opts}
            elif name == "Effort":
                fields["effort"] = {"id": f["id"], "options": opts}

    return fields, proj_id


def create_issue(task, task_map, repo, owner, proj_num, proj_id, fields):
    """Create a new GitHub issue for a task, add to project, set fields."""
    tid = task["id"]
    subj = task.get("subject", "Untitled")
    title = f"[{tid}] {subj}"

    # Ensure labels exist
    labels = build_labels(task)
    for label in labels:
        ensure_label(repo, label)

    # Write body to temp file
    body = build_body(task, task_map)
    body_file = f"/tmp/task-sync-body-{tid}.md"
    with open(body_file, "w") as f:
        f.write(body)

    cmd = f'gh issue create --repo {repo} --title "{title}" --body-file {body_file}'
    if labels:
        cmd += f' --label "{",".join(labels)}"'

    result, err = run(cmd)
    if os.path.exists(body_file):
        os.remove(body_file)

    if not result:
        return None

    try:
        issue_num = int(result.strip().split("/")[-1])
    except (ValueError, IndexError):
        return None

    # Add to project
    tmp = f"/tmp/task-sync-proj-{tid}.json"
    run(f'gh project item-add {proj_num} --owner {owner} --url https://github.com/{repo}/issues/{issue_num} --format json > {tmp} 2>/dev/null')

    item_id = None
    try:
        with open(tmp) as f:
            item_id = json.load(f).get("id")
        os.remove(tmp)
    except:
        if os.path.exists(tmp):
            os.remove(tmp)

    # Set project fields
    if item_id and proj_id:
        set_project_fields(task, item_id, proj_id, fields)

    # Close if completed/cancelled
    if task.get("status") in ("completed", "cancelled"):
        reason = "not_planned" if task.get("status") == "cancelled" else "completed"
        run(f'gh issue close {issue_num} --repo {repo} --reason {reason}')

    return issue_num


def set_project_fields(task, item_id, proj_id, fields):
    """Set status, priority, effort on project item."""
    status = task.get("status", "pending")
    if "status" in fields:
        if status == "completed":
            opt = fields["status"]["options"].get("done")
        elif status == "in_progress":
            opt = fields["status"]["options"].get("in_progress")
        else:
            opt = fields["status"]["options"].get("todo")
        if opt:
            run(f'gh project item-edit --project-id {proj_id} --id {item_id} --field-id {fields["status"]["id"]} --single-select-option-id {opt}')

    pri = task.get("priority")
    if pri and "priority" in fields and pri in fields["priority"]["options"]:
        run(f'gh project item-edit --project-id {proj_id} --id {item_id} --field-id {fields["priority"]["id"]} --single-select-option-id {fields["priority"]["options"][pri]}')

    eff = task.get("effort")
    if eff and "effort" in fields and eff in fields["effort"]["options"]:
        run(f'gh project item-edit --project-id {proj_id} --id {item_id} --field-id {fields["effort"]["id"]} --single-select-option-id {fields["effort"]["options"][eff]}')


def update_issue(task, issue_num, task_map, repo, owner, proj_num, proj_id, fields):
    """Update an existing issue if task changed."""
    tid = task["id"]
    status = task.get("status", "pending")

    # Update title
    subj = task.get("subject", "Untitled")
    run(f'gh issue edit {issue_num} --repo {repo} --title "[{tid}] {subj}"')

    # Update body
    body = build_body(task, task_map)
    body_file = f"/tmp/task-sync-body-{tid}.md"
    with open(body_file, "w") as f:
        f.write(body)
    run(f'gh issue edit {issue_num} --repo {repo} --body-file {body_file}')
    if os.path.exists(body_file):
        os.remove(body_file)

    # Update labels
    labels = build_labels(task)
    if labels:
        for label in labels:
            ensure_label(repo, label)
        run(f'gh issue edit {issue_num} --repo {repo} --add-label "{",".join(labels)}"')

    # Close/reopen based on status
    if status in ("completed", "cancelled"):
        reason = "not_planned" if status == "cancelled" else "completed"
        run(f'gh issue close {issue_num} --repo {repo} --reason {reason}')
    elif status in ("pending", "in_progress"):
        # Reopen if was closed
        run(f'gh issue reopen {issue_num} --repo {repo}')

    # Update project fields — need item ID
    tmp = f"/tmp/task-sync-find-{tid}.json"
    run(f'gh project item-list {proj_num} --owner {owner} --format json --limit 500 > {tmp} 2>/dev/null')
    item_id = None
    try:
        with open(tmp) as f:
            items = json.load(f).get("items", [])
        for item in items:
            content = item.get("content", {})
            if content.get("number") == issue_num:
                item_id = item.get("id")
                break
        os.remove(tmp)
    except:
        if os.path.exists(tmp):
            os.remove(tmp)

    if item_id and proj_id:
        set_project_fields(task, item_id, proj_id, fields)


def main():
    if len(sys.argv) < 4:
        print("Usage: task-sync.py <project_slug> <tasks_json_path> <config_path>")
        sys.exit(1)

    project_slug = sys.argv[1]
    tasks_path = sys.argv[2]
    config_path = sys.argv[3]

    # Load config
    with open(config_path) as f:
        config = json.load(f)

    project_config = config["projects"].get(project_slug)
    if not project_config:
        return

    repo = project_config["repo"]
    proj_num = project_config["project_number"]
    owner = config["owner"]
    keep_streams = set(config.get("keep_streams", ["roadmap", "tech-debt", "bugs"]))

    # Load tasks
    with open(tasks_path) as f:
        data = json.load(f)
    tasks = data if isinstance(data, list) else data.get("tasks", [])

    # Load issue map
    map_dir = os.path.dirname(tasks_path)
    map_file = os.path.join(map_dir, "task-issue-map.json")
    task_map = {}
    if os.path.exists(map_file):
        with open(map_file) as f:
            task_map = json.load(f)

    # Filter to qualifying tasks
    qualifying = {t["id"]: t for t in tasks if t.get("stream", "") in keep_streams}

    # Find new tasks (in qualifying but not in map)
    new_tasks = [tid for tid in qualifying if tid not in task_map]

    # Find changed tasks (in both — check if status/priority/effort changed)
    # We store a hash of key fields to detect changes
    hash_file = os.path.join(map_dir, "task-sync-hashes.json")
    hashes = {}
    if os.path.exists(hash_file):
        with open(hash_file) as f:
            hashes = json.load(f)

    changed_tasks = []
    for tid, task in qualifying.items():
        if tid not in task_map:
            continue
        current_hash = f"{task.get('status')}|{task.get('priority')}|{task.get('effort')}|{task.get('subject')}"
        if hashes.get(tid) != current_hash:
            changed_tasks.append(tid)

    if not new_tasks and not changed_tasks:
        return

    # Get project fields (only if we have work to do)
    fields, proj_id = get_project_fields(owner, proj_num)

    # Sort new tasks: phases first
    type_order = {"phase": 0, "milestone": 1, "task": 2, "subtask": 3}
    new_tasks.sort(key=lambda tid: (
        type_order.get(qualifying[tid].get("type", "task"), 2),
        qualifying[tid].get("order") or 999
    ))

    # Process new tasks
    for tid in new_tasks:
        task = qualifying[tid]
        issue_num = create_issue(task, task_map, repo, owner, proj_num, proj_id, fields)
        if issue_num:
            task_map[tid] = issue_num
            current_hash = f"{task.get('status')}|{task.get('priority')}|{task.get('effort')}|{task.get('subject')}"
            hashes[tid] = current_hash
            time.sleep(0.5)

    # Process changed tasks
    for tid in changed_tasks:
        task = qualifying[tid]
        issue_num = task_map[tid]
        update_issue(task, issue_num, task_map, repo, owner, proj_num, proj_id, fields)
        current_hash = f"{task.get('status')}|{task.get('priority')}|{task.get('effort')}|{task.get('subject')}"
        hashes[tid] = current_hash
        time.sleep(0.5)

    # Save map and hashes
    with open(map_file, "w") as f:
        json.dump(task_map, f, indent=2)
    with open(hash_file, "w") as f:
        json.dump(hashes, f, indent=2)

    total = len(new_tasks) + len(changed_tasks)
    print(f"[task-sync] {project_slug}: {len(new_tasks)} created, {len(changed_tasks)} updated")


if __name__ == "__main__":
    main()

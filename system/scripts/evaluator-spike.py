#!/usr/bin/env python3
"""Agent SDK Evaluator Spike (t-649).

Validates whether a completed build meets its feature spec by running
an adversarial evaluator agent via the Anthropic Python SDK.

Usage:
    uv run python system/scripts/evaluator-spike.py <spec-path> [--work-dir .] [--task-id t-NNN]
"""

import argparse
import json
import re
import subprocess
import sys
import time
from dataclasses import asdict, dataclass
from pathlib import Path

import anthropic

REPO_ROOT = Path(__file__).resolve().parent.parent.parent
MAX_TURNS = 20

# ---------------------------------------------------------------------------
# Spec parsing
# ---------------------------------------------------------------------------

@dataclass
class Criterion:
    id: str
    text: str
    section: str       # Constraints | Scope
    severity: str      # MUST | SHOULD
    check_type: str    # file_exists | grep_pattern | behavioral
    check_target: str | None


def parse_spec(spec_path: Path) -> list[Criterion]:
    """Extract testable criteria from ## Constraints and ## Scope sections."""
    text = spec_path.read_text()
    criteria: list[Criterion] = []
    counter = 0

    for section_name in ("Constraints", "Scope"):
        pattern = rf"^## {section_name}.*?\n(.*?)(?=\n## |\Z)"
        match = re.search(pattern, text, re.DOTALL | re.MULTILINE)
        if not match:
            continue

        for line in match.group(1).splitlines():
            line = line.strip()
            if not line.startswith("- "):
                continue

            bullet = line[2:].strip()
            if len(bullet) < 10:
                continue

            counter += 1
            cid = f"C-{counter:02d}"

            # Severity
            severity = "MUST" if re.search(r"\bMust\b|\bMUST\b", bullet) else "SHOULD"

            # Check type classification
            backtick_paths = re.findall(r"`([^`]*(?:system|docs|tests|scripts)/[^`]*)`", bullet)
            backtick_names = re.findall(r"`([a-z_\-]+\.[a-z]+)`", bullet)

            if backtick_paths:
                check_type = "file_exists"
                check_target = backtick_paths[0]
            elif backtick_names:
                check_type = "grep_pattern"
                check_target = backtick_names[0]
            else:
                check_type = "behavioral"
                check_target = None

            criteria.append(Criterion(
                id=cid, text=bullet, section=section_name,
                severity=severity, check_type=check_type,
                check_target=check_target,
            ))

    return criteria


def check_criterion(criterion: Criterion, work_dir: Path) -> dict:
    """Run a deterministic check for a single criterion."""
    result = {
        "id": criterion.id,
        "text": criterion.text,
        "severity": criterion.severity,
        "check_type": criterion.check_type,
    }

    if criterion.check_type == "file_exists" and criterion.check_target:
        target = work_dir / criterion.check_target
        exists = target.exists()
        result["verdict"] = "PASS" if exists else "FAIL"
        result["evidence"] = f"{'Found' if exists else 'Missing'}: {criterion.check_target}"

    elif criterion.check_type == "grep_pattern" and criterion.check_target:
        try:
            proc = subprocess.run(
                ["grep", "-r", "-l", criterion.check_target, str(work_dir)],
                capture_output=True, text=True, timeout=10,
            )
            matches = [p for p in proc.stdout.strip().splitlines() if p]
            if matches:
                result["verdict"] = "PASS"
                result["evidence"] = f"Found in {len(matches)} file(s): {', '.join(matches[:3])}"
            else:
                result["verdict"] = "FAIL"
                result["evidence"] = f"Pattern '{criterion.check_target}' not found"
        except subprocess.TimeoutExpired:
            result["verdict"] = "UNKNOWN"
            result["evidence"] = "Grep timed out"

    else:
        result["verdict"] = "UNKNOWN"
        result["evidence"] = "Behavioral criterion — requires LLM review"

    return result


# ---------------------------------------------------------------------------
# Anthropic SDK tool definitions
# ---------------------------------------------------------------------------

TOOLS = [
    {
        "name": "check_spec",
        "description": (
            "Parse a feature spec markdown file, extract acceptance criteria "
            "from Constraints and Scope sections, and run deterministic checks "
            "(file existence, grep patterns) against the implementation. "
            "Returns structured results per criterion."
        ),
        "input_schema": {
            "type": "object",
            "properties": {
                "spec_path": {"type": "string", "description": "Path to feature spec markdown"},
                "work_dir": {"type": "string", "description": "Working directory to check against"},
            },
            "required": ["spec_path", "work_dir"],
        },
    },
    {
        "name": "read_file",
        "description": "Read a file from the working directory (max 200 lines). Use to investigate UNKNOWN or FAIL criteria.",
        "input_schema": {
            "type": "object",
            "properties": {
                "path": {"type": "string", "description": "File path (absolute or relative to work_dir)"},
                "max_lines": {"type": "integer", "description": "Max lines to read (default 200)"},
            },
            "required": ["path"],
        },
    },
]


def execute_tool(name: str, input_data: dict, work_dir: Path) -> str:
    """Dispatch tool calls from the model."""
    if name == "check_spec":
        spec_path = Path(input_data["spec_path"])
        if not spec_path.is_absolute():
            spec_path = work_dir / spec_path
        wd = Path(input_data.get("work_dir", str(work_dir)))
        if not wd.is_absolute():
            wd = work_dir / wd
        criteria = parse_spec(spec_path)
        results = [check_criterion(c, wd) for c in criteria]
        return json.dumps(results, indent=2)

    elif name == "read_file":
        target = Path(input_data["path"])
        if not target.is_absolute():
            target = work_dir / target
        # Path traversal guard
        try:
            target.resolve().relative_to(work_dir.resolve())
        except ValueError:
            return json.dumps({"error": "Path outside work_dir"})
        max_lines = input_data.get("max_lines", 200)
        try:
            lines = target.read_text().splitlines()[:max_lines]
            return "\n".join(f"{i+1}: {line}" for i, line in enumerate(lines))
        except FileNotFoundError:
            return json.dumps({"error": f"File not found: {input_data['path']}"})
        except IsADirectoryError:
            return json.dumps({"error": f"Is a directory: {input_data['path']}"})

    return json.dumps({"error": f"Unknown tool: {name}"})


# ---------------------------------------------------------------------------
# Evaluator prompt
# ---------------------------------------------------------------------------

EVALUATOR_PROMPT = """You are a skeptical code reviewer evaluating whether a build meets its feature spec.

RULES:
1. FIRST call check_spec to get deterministic results for ALL criteria.
2. For each FAIL or UNKNOWN, investigate with read_file on relevant source files.
3. For UNKNOWN (behavioral) criteria, find CONCRETE evidence before marking PASS.
4. If you cannot find evidence, mark FAIL with reason "no evidence found".
5. List ALL FAILURES before any passes in your final report.
6. Your goal is to FIND BUGS, not approve. Assume defects exist.
7. Do NOT talk yourself into approving marginal cases. When in doubt, FAIL.

OUTPUT: Return a fenced JSON block (```json ... ```) with this structure:
{
  "spec": "<filename>",
  "criteria_count": N,
  "pass_count": N,
  "fail_count": N,
  "results": [
    {"id": "C-01", "text": "...", "verdict": "PASS|FAIL", "evidence": "...", "severity": "MUST|SHOULD"}
  ],
  "summary": "One paragraph summarizing key findings"
}"""


# ---------------------------------------------------------------------------
# Evaluator loop
# ---------------------------------------------------------------------------

def extract_json_report(text: str) -> dict | None:
    """Extract JSON from fenced block or raw text."""
    # Try fenced JSON block first
    m = re.search(r"```json\s*\n(.*?)\n```", text, re.DOTALL)
    if m:
        try:
            return json.loads(m.group(1))
        except json.JSONDecodeError:
            pass
    # Try raw JSON
    try:
        return json.loads(text)
    except json.JSONDecodeError:
        pass
    # Try finding JSON object in text
    m = re.search(r"\{.*\"results\".*\}", text, re.DOTALL)
    if m:
        try:
            return json.loads(m.group(0))
        except json.JSONDecodeError:
            pass
    return None


def run_evaluator(spec_path: str, work_dir: str, model: str) -> dict:
    """Run the evaluator agent loop."""
    import os
    if not os.environ.get("ANTHROPIC_API_KEY"):
        print("Error: ANTHROPIC_API_KEY not set. Export it before running.", file=sys.stderr)
        sys.exit(1)
    client = anthropic.Anthropic()
    work_dir_path = Path(work_dir).resolve()

    messages = [
        {"role": "user", "content": f"Evaluate: {spec_path}\nWorking directory: {work_dir}"}
    ]

    start = time.time()
    input_tokens = 0
    output_tokens = 0

    for turn in range(MAX_TURNS):
        response = client.messages.create(
            model=model,
            max_tokens=4096,
            system=EVALUATOR_PROMPT,
            tools=TOOLS,
            messages=messages,
        )

        input_tokens += response.usage.input_tokens
        output_tokens += response.usage.output_tokens

        if response.stop_reason == "end_turn":
            final_text = "".join(
                block.text for block in response.content if block.type == "text"
            )
            elapsed = time.time() - start
            return {
                "report": extract_json_report(final_text),
                "raw_text": final_text,
                "turns": turn + 1,
                "elapsed_seconds": round(elapsed, 1),
                "input_tokens": input_tokens,
                "output_tokens": output_tokens,
                "model": model,
                "spec_path": spec_path,
            }

        # Process tool calls
        messages.append({"role": "assistant", "content": response.content})
        tool_results = []
        for block in response.content:
            if block.type == "tool_use":
                result_str = execute_tool(block.name, block.input, work_dir_path)
                tool_results.append({
                    "type": "tool_result",
                    "tool_use_id": block.id,
                    "content": result_str,
                })
        messages.append({"role": "user", "content": tool_results})

    elapsed = time.time() - start
    return {
        "report": None,
        "raw_text": "Max turns reached",
        "turns": MAX_TURNS,
        "elapsed_seconds": round(elapsed, 1),
        "input_tokens": input_tokens,
        "output_tokens": output_tokens,
        "model": model,
        "spec_path": spec_path,
    }


# ---------------------------------------------------------------------------
# Logging and output
# ---------------------------------------------------------------------------

def log_results(result: dict, task_id: str) -> None:
    """Log findings via decisions.py."""
    sys.path.insert(0, str(REPO_ROOT / "system" / "scripts"))
    from decisions import log_entry

    report = result.get("report")
    if not report:
        log_entry("evaluator-spike", "error", "No report produced", refs=[task_id])
        return

    for r in report.get("results", []):
        if r.get("verdict") == "FAIL":
            log_entry(
                agent="evaluator-spike",
                entry_type="finding",
                content=f"[{r.get('severity', '?')}] {r['id']}: {r['text']} — {r.get('evidence', 'no evidence')}",
                severity="HIGH" if r.get("severity") == "MUST" else "MEDIUM",
                refs=[task_id],
            )

    log_entry(
        agent="evaluator-spike",
        entry_type="cost",
        content=(
            f"Evaluator: {result['turns']} turns, "
            f"{result['elapsed_seconds']}s, "
            f"{result['input_tokens']}+{result['output_tokens']} tokens, "
            f"model={result['model']}, "
            f"pass={report.get('pass_count', '?')}, fail={report.get('fail_count', '?')}"
        ),
        refs=[task_id],
    )


def print_human_report(result: dict) -> None:
    """Pretty-print the evaluation report."""
    report = result.get("report")
    print(f"\n{'='*60}")
    print(f"EVALUATOR SPIKE — {result['spec_path']}")
    print(f"{'='*60}")
    print(f"Model: {result['model']}")
    print(f"Turns: {result['turns']} | Time: {result['elapsed_seconds']}s")
    print(f"Tokens: {result['input_tokens']} in + {result['output_tokens']} out")
    print()

    if not report:
        print("ERROR: No structured report produced.")
        print(f"Raw output:\n{result.get('raw_text', '(empty)')[:500]}")
        return

    print(f"Criteria: {report.get('criteria_count', '?')}")
    print(f"PASS: {report.get('pass_count', '?')} | FAIL: {report.get('fail_count', '?')}")
    print(f"\n{'-'*60}")

    # Failures first
    for r in report.get("results", []):
        if r.get("verdict") == "FAIL":
            sev = "!!" if r.get("severity") == "MUST" else "! "
            print(f"  {sev} FAIL {r['id']}: {r['text'][:80]}")
            print(f"         Evidence: {r.get('evidence', 'none')[:100]}")

    # Then passes
    for r in report.get("results", []):
        if r.get("verdict") == "PASS":
            print(f"     PASS {r['id']}: {r['text'][:80]}")

    print(f"\n{'-'*60}")
    print(f"Summary: {report.get('summary', '(none)')}")
    print()


# ---------------------------------------------------------------------------
# CLI
# ---------------------------------------------------------------------------

def main():
    parser = argparse.ArgumentParser(
        description="Evaluator spike: grade a build against its feature spec (t-649)"
    )
    parser.add_argument("spec", help="Path to feature spec markdown file")
    parser.add_argument("--work-dir", default=".", help="Working directory to evaluate")
    parser.add_argument("--task-id", help="Task ID for decision log refs (e.g. t-649)")
    parser.add_argument("--model", default="claude-sonnet-4-20250514")
    parser.add_argument("--output-json", action="store_true", help="Output raw JSON")
    args = parser.parse_args()

    if not Path(args.spec).exists():
        print(f"Error: spec file not found: {args.spec}", file=sys.stderr)
        sys.exit(1)

    result = run_evaluator(args.spec, args.work_dir, args.model)

    if args.task_id:
        log_results(result, args.task_id)

    if args.output_json:
        print(json.dumps(result, indent=2, default=str))
    else:
        print_human_report(result)


if __name__ == "__main__":
    main()

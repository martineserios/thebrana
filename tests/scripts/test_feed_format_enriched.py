"""Tests for feed-format-enriched.py — title-echo detection and content priority."""

import importlib.util
import json
import sys
import textwrap
from io import StringIO
from pathlib import Path
from unittest.mock import patch

import pytest

SCRIPT = Path(__file__).parents[2] / "system" / "scripts" / "feed-format-enriched.py"

spec = importlib.util.spec_from_file_location("feed_format_enriched", SCRIPT)
mod = importlib.util.module_from_spec(spec)
spec.loader.exec_module(mod)


def _run(entries: list[dict], summaries: dict | None = None, tmp_path: Path | None = None) -> str:
    """Run main() with the given feed entries and return stdout."""
    summaries_path = ""
    if summaries and tmp_path:
        p = tmp_path / "summaries.jsonl"
        p.write_text(
            "\n".join(json.dumps({"link": k, "summary": v}) for k, v in summaries.items())
        )
        summaries_path = str(p)

    stdin_data = "\n".join(json.dumps(e) for e in entries)
    captured = StringIO()
    with (
        patch.object(sys, "argv", ["feed-format-enriched.py", summaries_path]),
        patch("sys.stdin", StringIO(stdin_data)),
        patch("sys.stdout", captured),
    ):
        mod.main()
    return captured.getvalue()


# ── title-echo detection ──────────────────────────────────────────────────

def test_title_echo_summary_is_skipped(tmp_path):
    """When RSS summary equals title, it should be treated as title-echo and skipped."""
    title = "Claude 4 Releases Today"
    entry = {
        "feed": "anthropic-news",
        "title": title,
        "link": "https://example.com/article",
        "published": "2026-01-01",
        "summary": title,  # summary == title → title-echo
    }
    out = _run([entry])
    assert "### 2026-01-01" in out
    assert title not in out.split("###")[1].split("\n", 2)[1:]  # body must not echo the title text


def test_title_echo_falls_back_to_content(tmp_path):
    """When summary == title, content field should be used as the body."""
    title = "Claude 4 Releases Today"
    entry = {
        "feed": "anthropic-news",
        "title": title,
        "link": "https://example.com/article",
        "published": "2026-01-01",
        "summary": title,
        "content": "The new Claude 4 model offers significant improvements in reasoning.",
    }
    out = _run([entry])
    assert "reasoning" in out


def test_title_echo_short_summary_is_skipped():
    """Short summary (<= 50 chars) must be skipped regardless of title match."""
    entry = {
        "feed": "anthropic-news",
        "title": "Some Article",
        "link": "https://example.com/a",
        "published": "2026-01-01",
        "summary": "Short.",  # len < 50
    }
    out = _run([entry])
    # body line should be absent (only header + blank line)
    lines = [l for l in out.splitlines() if l.strip()]
    assert len(lines) == 1  # only the ### header line


def test_real_summary_used_when_different_from_title():
    """When summary differs from title and is >50 chars, it should appear in output."""
    summary = "A" * 60  # length > 50, differs from title
    entry = {
        "feed": "anthropic-news",
        "title": "Some Article",
        "link": "https://example.com/a",
        "published": "2026-01-01",
        "summary": summary,
    }
    out = _run([entry])
    assert "A" * 10 in out  # summary content present


# ── summaries fallback (anthropic-news lookup) ────────────────────────────

def test_summaries_jsonl_fallback(tmp_path):
    """When entry has no summary or content, use the LLM summary from feed-summaries.jsonl."""
    link = "https://example.com/b"
    entry = {
        "feed": "anthropic-news",
        "title": "No Content Article",
        "link": link,
        "published": "2026-01-01",
    }
    out = _run([entry], summaries={link: "Anthropic released a new pricing tier."}, tmp_path=tmp_path)
    assert "pricing tier" in out


def test_missing_summaries_file_does_not_crash(tmp_path):
    """load_summaries on a nonexistent path returns empty dict without error."""
    result = mod.load_summaries("/nonexistent/path/summaries.jsonl")
    assert result == {}

#!/usr/bin/env python3
"""Tests for collapse-level-epic-v3.py epic-node resolution (t-2472).

Run: python3 system/scripts/migrate/test_collapse_level_epic_v3.py
"""
import importlib.util
import pathlib
import sys
import unittest

_SPEC = importlib.util.spec_from_file_location(
    "collapse_level_epic_v3",
    pathlib.Path(__file__).parent / "collapse-level-epic-v3.py",
)
mod = importlib.util.module_from_spec(_SPEC)
_SPEC.loader.exec_module(mod)


def _next_id(tasks):
    """Mirror next_id()'s max-numeric-suffix scheme for t- ids."""
    nums = [
        int(t["id"].split("-")[1])
        for t in tasks
        if t.get("id", "").startswith("t-") and t["id"].split("-")[1].isdigit()
    ]
    return f"t-{(max(nums) if nums else 0) + 1}"


class TestFindExistingEpicNodes(unittest.TestCase):
    def test_reuses_current_convention_type_epic_subject_node(self):
        """t-2472: a type:"epic" node whose subject is the slug must be reused,
        not duplicated. Before the fix only `in-` markers were detected, so a
        second "harness" epic was minted alongside the existing t-2344."""
        tasks = [
            {"id": "t-2344", "subject": "harness", "type": "epic", "status": "next"},
            {"id": "t-2464", "subject": "some work", "type": "task", "epic": "harness"},
        ]
        nodes = mod.find_existing_epic_nodes(tasks)
        self.assertEqual(nodes.get("harness"), "t-2344")

    def test_no_duplicate_node_created_for_existing_slug(self):
        tasks = [
            {"id": "t-2344", "subject": "harness", "type": "epic", "status": "next"},
            {"id": "t-2464", "subject": "some work", "type": "task", "epic": "harness"},
        ]
        _by_slug, new_nodes, reused, created = mod.plan_epic_nodes(
            tasks, _next_id, "2026-07-27"
        )
        self.assertEqual(new_nodes, [], "must not mint a node for an existing slug")
        self.assertEqual(reused, ["harness"])
        self.assertEqual(created, [])

    def test_still_creates_node_for_genuinely_new_slug(self):
        tasks = [
            {"id": "t-2344", "subject": "harness", "type": "epic", "status": "next"},
            {"id": "t-2454", "subject": "work", "type": "task", "epic": "scheduler"},
        ]
        by_slug, new_nodes, reused, created = mod.plan_epic_nodes(
            tasks, _next_id, "2026-07-27"
        )
        self.assertEqual(created, ["scheduler"])
        self.assertEqual(len(new_nodes), 1)
        self.assertEqual(new_nodes[0]["subject"], "scheduler")
        self.assertEqual(new_nodes[0]["type"], "epic")
        # ADR-065 epic-status vocabulary — "pending" would fail Check 26.
        self.assertEqual(new_nodes[0]["status"], "next")
        self.assertNotIn("scheduler", reused)
        # by_slug only maps slugs some task actually carries; no task here has
        # epic="harness", so the existing t-2344 node is correctly absent.
        self.assertNotIn("harness", by_slug)
        self.assertEqual(by_slug["scheduler"], new_nodes[0]["id"])

    def test_legacy_in_marker_wins_contested_slug(self):
        """Legacy `in-` markers keep first-match-wins precedence."""
        tasks = [
            {"id": "in-002", "subject": "CC Alignment", "type": "initiative",
             "epic": "cc-alignment"},
            {"id": "t-2400", "subject": "cc-alignment", "type": "epic", "status": "next"},
        ]
        nodes = mod.find_existing_epic_nodes(tasks)
        self.assertEqual(nodes.get("cc-alignment"), "in-002")


if __name__ == "__main__":
    unittest.main(verbosity=2)

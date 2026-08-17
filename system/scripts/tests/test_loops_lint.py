"""Unit tests for system/scripts/loops-lint.py (t-2930, loops-library catalog).

Loaded via importlib since the script's filename uses a dash -- not meant to
be imported as a module.
"""
import importlib.util
import pathlib
import subprocess
import sys

import yaml

SCRIPT_PATH = pathlib.Path(__file__).parent.parent / "loops-lint.py"
spec = importlib.util.spec_from_file_location("loops_lint", SCRIPT_PATH)
mod = importlib.util.module_from_spec(spec)
spec.loader.exec_module(mod)

lint_content = mod.lint_content

VALID_L0 = {
    "name": "session-status",
    "cadence": "30m",
    "autonomy": "L0",
    "supervised": True,
    "drains": [],
    "fills": [],
    "spawns": [],
    "records": "see docs/architecture/features/loops-library.md",
}

VALID_L1_BODY = "## Beat procedure\n...\n## Denied verbs\n| Verb | Why |\n"


def test_valid_l0_entry_passes():
    assert lint_content(VALID_L0, "## Beat procedure\n...") == []


def test_valid_l1_entry_with_denied_verbs_passes():
    fm = {**VALID_L0, "autonomy": "L1"}
    assert lint_content(fm, VALID_L1_BODY) == []


def test_missing_name_fails():
    fm = {k: v for k, v in VALID_L0.items() if k != "name"}
    errors = lint_content(fm, "body")
    assert any("name" in e for e in errors)


def test_missing_autonomy_fails():
    fm = {k: v for k, v in VALID_L0.items() if k != "autonomy"}
    errors = lint_content(fm, "body")
    assert any("autonomy" in e for e in errors)


def test_missing_supervised_fails():
    fm = {k: v for k, v in VALID_L0.items() if k != "supervised"}
    errors = lint_content(fm, "body")
    assert any("supervised" in e for e in errors)


def test_missing_drains_fails():
    fm = {k: v for k, v in VALID_L0.items() if k != "drains"}
    errors = lint_content(fm, "body")
    assert any("drains" in e for e in errors)


def test_missing_fills_fails():
    fm = {k: v for k, v in VALID_L0.items() if k != "fills"}
    errors = lint_content(fm, "body")
    assert any("fills" in e for e in errors)


def test_missing_spawns_fails():
    fm = {k: v for k, v in VALID_L0.items() if k != "spawns"}
    errors = lint_content(fm, "body")
    assert any("spawns" in e for e in errors)


def test_missing_records_fails():
    fm = {k: v for k, v in VALID_L0.items() if k != "records"}
    errors = lint_content(fm, "body")
    assert any("records" in e for e in errors)


def test_missing_cadence_and_pacing_fails():
    fm = {k: v for k, v in VALID_L0.items() if k != "cadence"}
    errors = lint_content(fm, "body")
    assert any("cadence" in e or "pacing" in e for e in errors)


def test_pacing_dict_satisfies_cadence_requirement():
    fm = {k: v for k, v in VALID_L0.items() if k != "cadence"}
    fm["pacing"] = {"active_delay": "90s", "waiting_delay": "20m", "empty_delay": "30m"}
    assert lint_content(fm, "## Beat procedure\n...") == []


def test_invalid_autonomy_value_fails():
    fm = {**VALID_L0, "autonomy": "L9"}
    errors = lint_content(fm, "body")
    assert any("autonomy" in e for e in errors)


def test_l0_entry_without_denied_verbs_table_passes():
    fm = {**VALID_L0, "autonomy": "L0"}
    assert lint_content(fm, "## Beat procedure\n...\nno denied verbs section here") == []


def test_l1_entry_without_denied_verbs_table_fails():
    fm = {**VALID_L0, "autonomy": "L1"}
    errors = lint_content(fm, "## Beat procedure\n...\njust a plain body, nothing else")
    assert any("denied" in e.lower() for e in errors)


def test_l2_entry_without_denied_verbs_table_fails():
    fm = {**VALID_L0, "autonomy": "L2"}
    errors = lint_content(fm, "## Beat procedure\n...")
    assert any("denied" in e.lower() for e in errors)


def test_records_field_redefining_schema_inline_fails():
    fm = {**VALID_L0, "records": {"loop": "x", "beat": 1, "state": "active"}}
    errors = lint_content(fm, "## Beat procedure\n...")
    assert any("records" in e for e in errors)


def test_records_field_as_string_reference_passes():
    fm = {**VALID_L0, "records": "single-sourced in docs/architecture/features/loops-library.md"}
    assert lint_content(fm, "## Beat procedure\n...") == []


def test_empty_frontmatter_dict_fails_all_required_keys():
    errors = lint_content({}, "body")
    assert len(errors) >= len(mod.REQUIRED_KEYS)


def test_file_with_no_frontmatter_block_fails_at_cli(tmp_path):
    no_fm = tmp_path / "no-frontmatter.md"
    no_fm.write_text("# Just a heading\nno frontmatter block at all\n")
    result = subprocess.run(
        [sys.executable, str(SCRIPT_PATH), str(no_fm)],
        capture_output=True,
        text=True,
    )
    assert result.returncode == 1
    assert "no YAML frontmatter" in result.stdout


def test_cli_reports_pass_fail_per_file(tmp_path):
    good = tmp_path / "good.md"
    good.write_text(
        "---\n" + yaml.dump(VALID_L0) + "---\n## Beat procedure\n..."
    )
    bad = tmp_path / "bad.md"
    bad.write_text("---\nname: incomplete\n---\nbody")

    result = subprocess.run(
        [sys.executable, str(SCRIPT_PATH), str(good), str(bad)],
        capture_output=True,
        text=True,
    )
    assert result.returncode == 1
    assert f"{good}: PASS" in result.stdout
    assert "FAIL" in result.stdout

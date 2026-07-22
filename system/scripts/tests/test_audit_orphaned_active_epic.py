"""Unit tests for the orphan-detection pure function in
system/scripts/migrate/audit-orphaned-active-epic.py (t-2298 / ADR-066).

Loaded via importlib since the script's filename uses dashes (matches this
repo's migrate/ naming convention -- not meant to be imported as a module).
"""
import importlib.util
import pathlib

SCRIPT_PATH = pathlib.Path(__file__).parent.parent / "migrate" / "audit-orphaned-active-epic.py"
spec = importlib.util.spec_from_file_location("audit_orphaned_active_epic", SCRIPT_PATH)
mod = importlib.util.module_from_spec(spec)
spec.loader.exec_module(mod)

orphaned_keys = mod.orphaned_keys


def test_orphaned_when_no_project_matches():
    global_cfg = {"active_epic": "identity-commerce-rebuild"}
    project_configs = [{"active_epic": "env-hardening"}, {"active_epic": "harness-v2"}]
    assert orphaned_keys(global_cfg, project_configs) == {"active_epic": "identity-commerce-rebuild"}


def test_not_orphaned_when_a_project_matches():
    global_cfg = {"active_epic": "env-hardening"}
    project_configs = [{"active_epic": "env-hardening"}]
    assert orphaned_keys(global_cfg, project_configs) == {}


def test_absent_global_key_ignored():
    global_cfg = {"theme": "emoji"}
    project_configs = [{"active_epic": "env-hardening"}]
    assert orphaned_keys(global_cfg, project_configs) == {}


def test_both_keys_evaluated_independently():
    global_cfg = {"active_epic": "orphan-epic", "active_initiative": "matched-init"}
    project_configs = [{"active_initiative": "matched-init"}]
    assert orphaned_keys(global_cfg, project_configs) == {"active_epic": "orphan-epic"}


def test_no_project_configs_at_all_is_orphaned():
    global_cfg = {"active_epic": "identity-commerce-rebuild"}
    assert orphaned_keys(global_cfg, []) == {"active_epic": "identity-commerce-rebuild"}


def test_null_value_in_project_config_does_not_falsely_match():
    global_cfg = {"active_epic": "real-epic"}
    project_configs = [{"active_epic": None}]
    assert orphaned_keys(global_cfg, project_configs) == {"active_epic": "real-epic"}

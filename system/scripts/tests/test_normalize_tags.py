"""Unit tests for the normalize_tags pure function in
system/scripts/migrate/normalize-tags.py (t-2309 / ADR-065).

Loaded via importlib since the script's filename uses dashes (matches this
repo's migrate/ naming convention -- not meant to be imported as a module).
"""
import importlib.util
import pathlib

SCRIPT_PATH = pathlib.Path(__file__).parent.parent / "migrate" / "normalize-tags.py"
spec = importlib.util.spec_from_file_location("normalize_tags", SCRIPT_PATH)
mod = importlib.util.module_from_spec(spec)
spec.loader.exec_module(mod)

normalize_tags = mod.normalize_tags


def test_comma_joined_string_splits_and_trims():
    assert normalize_tags("a, b,c") == (["a", "b", "c"], True)


def test_null_becomes_empty_array():
    assert normalize_tags(None) == ([], True)


def test_array_left_untouched():
    assert normalize_tags(["a", "b"]) == (["a", "b"], False)


def test_empty_array_left_untouched():
    assert normalize_tags([]) == ([], False)


def test_single_tag_string_no_comma():
    assert normalize_tags("parked") == (["parked"], True)


def test_empty_string_becomes_empty_array():
    assert normalize_tags("") == ([], True)


def test_comma_joined_string_drops_empty_elements():
    assert normalize_tags("a,,b,") == (["a", "b"], True)

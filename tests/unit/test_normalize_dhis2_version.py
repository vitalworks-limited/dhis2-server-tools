"""Unit tests for the version-resolver filter in
`deploy/filter_plugins/custom_filters.py`.

Covers the fix for the per-host minor-version pinning described in
`docs/CLI-Version-Pinning.md`.
"""

import importlib.util
import pathlib
import sys

import pytest


ROOT = pathlib.Path(__file__).resolve().parents[2]
SRC = ROOT / "deploy" / "filter_plugins" / "custom_filters.py"

# Load custom_filters without needing Ansible as an import dependency.
# AnsibleFilterError is raised on invalid input, so we need to stub
# the ansible.errors module.
sys.modules.setdefault("ansible", type(sys)("ansible"))
err_mod = type(sys)("ansible.errors")


class _AFE(Exception):
    pass


err_mod.AnsibleFilterError = _AFE  # type: ignore[attr-defined]
sys.modules["ansible.errors"] = err_mod

util_mod = type(sys)("ansible.module_utils")
compat_mod = type(sys)("ansible.module_utils.compat")
version_mod = type(sys)("ansible.module_utils.compat.version")


class _LV:
    def __init__(self, v):
        self.v = str(v)

    def __eq__(self, o):
        return self.v == getattr(o, "v", str(o))

    def __lt__(self, o):
        return self.v < getattr(o, "v", str(o))

    def __le__(self, o):
        return self.v <= getattr(o, "v", str(o))

    def __gt__(self, o):
        return self.v > getattr(o, "v", str(o))

    def __ge__(self, o):
        return self.v >= getattr(o, "v", str(o))


version_mod.LooseVersion = _LV  # type: ignore[attr-defined]
sys.modules["ansible.module_utils"] = util_mod
sys.modules["ansible.module_utils.compat"] = compat_mod
sys.modules["ansible.module_utils.compat.version"] = version_mod

text_mod = type(sys)("ansible.module_utils.common.text.converters")
text_mod.to_text = lambda x: str(x)  # type: ignore[attr-defined]
sys.modules["ansible.module_utils.common"] = type(sys)("ansible.module_utils.common")
sys.modules["ansible.module_utils.common.text"] = type(sys)(
    "ansible.module_utils.common.text"
)
sys.modules["ansible.module_utils.common.text.converters"] = text_mod


spec = importlib.util.spec_from_file_location("custom_filters", SRC)
cf = importlib.util.module_from_spec(spec)
spec.loader.exec_module(cf)  # type: ignore[union-attr]


# A trimmed releases.json fixture.
RELEASES = [
    {
        "name": "2.42",
        "latestStableUrl": "https://releases.dhis2.org/42/dhis2-stable-42.7.1.war",
        "patchVersions": [
            {"name": "2.42.6", "url": "https://releases.dhis2.org/42/dhis2-stable-42.6.0.war"},
            {"name": "2.42.7", "url": "https://releases.dhis2.org/42/dhis2-stable-42.7.0.war"},
            {"name": "2.42.7.1", "url": "https://releases.dhis2.org/42/dhis2-stable-42.7.1.war"},
        ],
    },
    {
        "name": "2.43",
        "latestStableUrl": "https://releases.dhis2.org/43/dhis2-stable-43.5.0.war",
        "patchVersions": [
            {"name": "2.43.1", "url": "https://releases.dhis2.org/43/dhis2-stable-43.1.0.war"},
            {"name": "2.43.2", "url": "https://releases.dhis2.org/43/dhis2-stable-43.2.0.war"},
        ],
    },
]


def test_float_major_returns_channel_without_pin():
    out = cf.normalize_dhis2_version(2.42, RELEASES)
    assert out == {
        "dhis2_version_major": "2.42",
        "dhis2_version_minor": None,
        "pinned_exact": False,
    }


def test_bare_major_string_returns_channel_without_pin():
    out = cf.normalize_dhis2_version("2.42", RELEASES)
    assert out["dhis2_version_major"] == "2.42"
    assert out["dhis2_version_minor"] is None
    assert out["pinned_exact"] is False


def test_three_part_patch_is_pinned():
    out = cf.normalize_dhis2_version("2.42.7", RELEASES)
    assert out == {
        "dhis2_version_major": "2.42",
        "dhis2_version_minor": "2.42.7",
        "pinned_exact": True,
    }


def test_four_part_patch_is_pinned():
    out = cf.normalize_dhis2_version("2.42.7.1", RELEASES)
    assert out == {
        "dhis2_version_major": "2.42",
        "dhis2_version_minor": "2.42.7.1",
        "pinned_exact": True,
    }


def test_unknown_channel_raises():
    with pytest.raises(_AFE):
        cf.normalize_dhis2_version("3.99", RELEASES)


def test_unknown_channel_as_float_raises():
    with pytest.raises(_AFE):
        cf.normalize_dhis2_version(3.99, RELEASES)


def test_invalid_format_raises():
    with pytest.raises(_AFE):
        cf.normalize_dhis2_version("2.43.b", RELEASES)


def test_whitespace_tolerated():
    out = cf.normalize_dhis2_version(" 2.43.2 ", RELEASES)
    assert out == {
        "dhis2_version_major": "2.43",
        "dhis2_version_minor": "2.43.2",
        "pinned_exact": True,
    }

"""Workspace configuration — identity + paths + targets, loaded at runtime.

Single source of truth: `state/config.json`. Written by `bin/setup.sh` on
first init (or by `/lsr-maintainer init`). The agent's hooks and sub-agents
read it instead of hard-coding usernames or namespaces — so the same
workspace works for any GitHub/OBS account once setup runs.

Schema is forward-compatible: new fields appear in `default_config()` and
existing user configs are upgraded on read via `_migrate()`.
"""
from __future__ import annotations

import json
import os
import shutil
import subprocess
import tempfile
from typing import Any

CONFIG_VERSION = 1


def default_config() -> dict[str, Any]:
    """Defaults intended to be REPLACED on first init. The empty strings
    for `github.user` and `obs.user` are deliberate — hooks treat empty as
    "block all writes" so a pre-init workspace is safe."""
    return {
        "version": CONFIG_VERSION,
        "github": {
            "user": "",                          # detected from `gh api user --jq .login`
            "fork_pattern": "{user}/{role}",
            "fork_branch": "fix/suse-support",
            "upstream_orgs": ["linux-system-roles"],
            "community_orgs": [
                "geerlingguy",
                "robertdebock",
                "bertvv",
                "mrlesmithjr",
            ],
            "suse_org": "SUSE",
        },
        "obs": {
            "user": "",                          # detected from `osc whois`
            "personal_project_root": "",         # computed: f"home:{user}"
            "branch_project_pattern": "home:{user}:branches:{source}",
            "source_project": "devel:sap:ansible",
            "package_name": "ansible-linux-system-roles",
            "api_url": "https://api.opensuse.org",
        },
        "paths": {
            "iso_dir": "~/iso",
            "ansible_root": "~/github/ansible",
            "lsr_clones_root": "~/github/linux-system-roles",
            "worktrees_root": "~/github/.lsr-maintainer-worktrees",
            "tox_venv": "~/github/ansible/testing/tox-lsr-venv",
            "host_scripts": "~/github/ansible/scripts",
            "obs_checkout_root": "~/github/ansible",
        },
        "test_targets": {
            "default_set": ["sle-16", "leap-16.0", "sle-15-sp7", "leap-15.6"],
            "fallback": {"sle-16": "leap-16.0"},
            "image_globs": {
                "sle-16":     ["SLES-16.0-*Minimal-VM*.x86_64*.qcow2"],
                "leap-16.0":  ["Leap-16.0-Minimal-VM*.x86_64*Cloud*.qcow2"],
                "sle-15-sp7": ["SLES15-SP7-Minimal-VM*.x86_64*.qcow2"],
                "leap-15.6":  ["openSUSE-Leap-15.6*.x86_64*.qcow2", "Leap-15.6-Minimal-VM*.x86_64*.qcow2"],
            },
            "ansible_core_versions": {
                "sle-16": "2.20", "leap-16.0": "2.20",
                "sle-15-sp7": "2.18", "leap-15.6": "2.18",
            },
            "auto_download": {
                "leap-16.0": {
                    "url": "https://download.opensuse.org/distribution/leap/16.0/appliances/Leap-16.0-Minimal-VM.x86_64-Cloud.qcow2",
                    "size_mb": 330,
                },
            },
        },
        "schedule": {
            "cron_time": "7 3 * * *",
            "time_budget_minutes": 90,
            "per_item_budgets": {
                "pr_feedback_min": 15,
                "obs_build_min": 30,
                "new_role_enablement_min": 60,
                "round_robin_min": 30,
            },
        },
        "review_board": {
            "max_concern_iterations": 2,
            "concurrent_cap": 6,
        },
    }


def load_config(path: str) -> dict[str, Any]:
    """Read config from path. Returns default_config() if missing. Migrates
    older versions on the fly and fills in missing keys from defaults."""
    if not os.path.exists(path):
        return default_config()
    with open(path) as f:
        try:
            data = json.load(f)
        except json.JSONDecodeError:
            os.rename(path, path + ".bak")
            return default_config()
    if data.get("version", 0) < CONFIG_VERSION:
        data = _migrate(data)
    # Fill in any missing keys from defaults (forward-compat).
    base = default_config()
    _merge_defaults(data, base)
    return data


def _merge_defaults(data: dict, defaults: dict) -> None:
    """Recursively fill in missing keys in `data` from `defaults`."""
    for k, v in defaults.items():
        if k not in data:
            data[k] = v
        elif isinstance(v, dict) and isinstance(data[k], dict):
            _merge_defaults(data[k], v)


def _migrate(data: dict[str, Any]) -> dict[str, Any]:
    data["version"] = CONFIG_VERSION
    return data


def save_config(path: str, data: dict[str, Any]) -> None:
    data = dict(data)
    data["version"] = CONFIG_VERSION
    dirpath = os.path.dirname(os.path.abspath(path)) or "."
    os.makedirs(dirpath, exist_ok=True)
    fd, tmp = tempfile.mkstemp(prefix=".config-", suffix=".json", dir=dirpath)
    try:
        with os.fdopen(fd, "w") as f:
            json.dump(data, f, indent=2, sort_keys=True)
            f.write("\n")
        os.replace(tmp, path)
    except Exception:
        if os.path.exists(tmp):
            os.unlink(tmp)
        raise


def detect_identity() -> dict[str, str]:
    """Run `gh api user` and `osc whois` non-interactively and return what
    they print. Does NOT print tokens — only the public login names.
    Returns empty strings for any that fail (e.g. unauthenticated)."""
    out = {"github_user": "", "obs_user": "", "git_email": "", "git_name": ""}

    # GitHub login
    if shutil.which("gh"):
        try:
            r = subprocess.run(
                ["gh", "api", "user", "--jq", ".login"],
                capture_output=True, text=True, timeout=10,
            )
            if r.returncode == 0:
                out["github_user"] = r.stdout.strip()
        except Exception:
            pass

    # OBS login
    if shutil.which("osc"):
        try:
            r = subprocess.run(
                ["osc", "whois"], capture_output=True, text=True, timeout=10,
            )
            if r.returncode == 0:
                # `osc whois` prints "login (Name <email>)"
                out["obs_user"] = r.stdout.strip().split()[0] if r.stdout.strip() else ""
        except Exception:
            pass

    # Git author
    try:
        r = subprocess.run(["git", "config", "--global", "user.email"], capture_output=True, text=True)
        out["git_email"] = r.stdout.strip()
        r = subprocess.run(["git", "config", "--global", "user.name"], capture_output=True, text=True)
        out["git_name"] = r.stdout.strip()
    except Exception:
        pass

    return out


def init_from_identity(detected: dict[str, str], existing: dict[str, Any] | None = None) -> dict[str, Any]:
    """Build a fresh config from detected identity, preserving any overrides
    in `existing` (e.g. user prefers a non-default source_project)."""
    cfg = existing or default_config()
    if detected.get("github_user"):
        cfg["github"]["user"] = detected["github_user"]
    if detected.get("obs_user"):
        cfg["obs"]["user"] = detected["obs_user"]
        cfg["obs"]["personal_project_root"] = f"home:{detected['obs_user']}"
    return cfg


# Convenience read helpers used by sub-agents that import this module.
def github_user(cfg: dict[str, Any]) -> str:
    return cfg.get("github", {}).get("user", "")


def fork_repo(cfg: dict[str, Any], role: str) -> str:
    """Return e.g. "Spectro34/sudo" for the configured GitHub user."""
    user = github_user(cfg)
    if not user:
        return ""
    return cfg["github"]["fork_pattern"].format(user=user, role=role)


def obs_personal_project(cfg: dict[str, Any]) -> str:
    """e.g. "home:spectro34"."""
    return cfg.get("obs", {}).get("personal_project_root", "")


def obs_branch_project(cfg: dict[str, Any]) -> str:
    """e.g. "home:spectro34:branches:devel:sap:ansible"."""
    user = cfg.get("obs", {}).get("user", "")
    source = cfg.get("obs", {}).get("source_project", "")
    if not user or not source:
        return ""
    return cfg["obs"]["branch_project_pattern"].format(user=user, source=source)


if __name__ == "__main__":
    # Self-test.
    tmpdir = tempfile.mkdtemp()
    p = os.path.join(tmpdir, "config.json")
    c = load_config(p)
    assert c["version"] == CONFIG_VERSION
    assert c["github"]["user"] == ""  # pre-init = empty = hooks block all writes
    detected = {"github_user": "alice", "obs_user": "alice123", "git_email": "a@b", "git_name": "A"}
    c = init_from_identity(detected, c)
    save_config(p, c)
    c2 = load_config(p)
    assert c2["github"]["user"] == "alice"
    assert c2["obs"]["personal_project_root"] == "home:alice123"
    assert fork_repo(c2, "sudo") == "alice/sudo"
    assert obs_branch_project(c2) == "home:alice123:branches:devel:sap:ansible"
    # Empty config → empty fork/project (so hooks know to block).
    assert fork_repo(default_config(), "sudo") == ""
    assert obs_branch_project(default_config()) == ""
    print("OK", p)

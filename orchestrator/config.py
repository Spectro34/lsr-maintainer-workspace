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

CONFIG_VERSION = 3  # v3: adds enablement.queue + fork_sync + security.enforce_host_lock.


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
            # Roles the user maintains on personal forks that AREN'T in the OBS
            # package manifest (fork-only roles, e.g. sudo, kernel_settings,
            # ansible-sshd, network, logging, metrics, plus hackweek community
            # roles like squid/apache/nfs/samba/kea-dhcp/bind/snapper/tftpd).
            # pr-status-poller and upstream-drift-watcher iterate over the union
            # of obs.managed_roles + tracked_extra_roles. Edit this list to
            # add/remove what the agent should watch beyond the OBS manifest.
            "tracked_extra_roles": [
                "sudo", "kernel_settings", "ansible-sshd", "network", "logging",
                "metrics", "postgresql", "ad_integration",
            ],
        },
        "obs": {
            "user": "",                          # detected from `osc whois`
            "personal_project_root": "",         # computed: f"home:{user}"
            "branch_project_pattern": "home:{user}:branches:{source}",
            "source_project": "devel:sap:ansible",
            "package_name": "ansible-linux-system-roles",
            "api_url": "https://api.opensuse.org",
        },
        # Runtime paths. `{workspace}` placeholder is substituted at resolution
        # time by get_path() so the workspace is self-contained — everything
        # lives under <workspace>/var/. Operators can override any value to an
        # absolute path (e.g. /mnt/big/iso) and that override is preserved
        # across re-runs of setup.sh.
        "paths": {
            "iso_dir":           "{workspace}/var/iso",
            "ansible_root":      "{workspace}/var/ansible",
            "lsr_clones_root":   "{workspace}/var/clones",
            "worktrees_root":    "{workspace}/var/worktrees",
            "tox_venv":          "{workspace}/var/venv/tox-lsr",
            "host_scripts":      "{workspace}/var/ansible/scripts",
            "obs_checkout_root": "{workspace}/var/ansible",
            "log_dir":           "{workspace}/var/log",
            "cache_dir":         "{workspace}/var/cache",
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
        # Anomaly detection (issue #17). Reads from state/metrics-history.jsonl.
        # Per-metric override: e.g. `"thresholds": {"commits_pushed": 5.0}` to
        # require 5σ for that metric.
        "anomaly": {
            "enabled": True,
            "default_sigma": 3.0,
            "min_samples": 7,        # need N nights of data before flagging
            "history_days": 14,
            "thresholds": {},        # per-metric overrides
            "auto_halt_on_anomaly": False,  # day-1: surface only; flip after calibration
        },
        # Out-of-band notifications (issue #18). Disabled by default — set
        # `backend` to enable. Falls back silently if backend unavailable.
        # The default `events` list gives a balanced live trickle:
        # - critical events always fire (reject/anomaly/halt/doctor_red/host_lock_mismatch)
        # - milestone events fire per action (commit_pushed/fork_created/enable_role_complete/human_action_needed)
        # - heartbeat events fire 1x/run (run_started/run_completed)
        # - summaries fire 1x/run (daily_summary, fork_sync_summary)
        # Trim this list to reduce noise; remove a kind to silence it.
        "notify": {
            "backend": "",
            "events": [
                "reject", "anomaly", "doctor_red", "halt", "host_lock_mismatch",
                "commit_pushed", "fork_created", "enable_role_complete", "human_action_needed",
                "run_started", "run_completed",
                "daily_summary", "fork_sync_summary",
            ],
            "ntfy":    {"url": "", "priority": "default"},
            "email":   {"to": ""},
            "webhook": {"url": ""},
        },
        # User-editable enablement queue. Add role names here to have the
        # nightly run enable them for SLE via `new-role-enabler`. The
        # orchestrator pops up to `auto_enqueue_per_run` per night and
        # surfaces "📋 Enablement queue" in PENDING_REVIEW.md. Entries are
        # removed only on `verdict: enabled` (success); failures stay so the
        # next run retries. Manual removal: `make ack-enablement ROLE=x`.
        "enablement": {
            "queue": [],
            "auto_enqueue_per_run": 1,
            "default_target": "sle16",
        },
        # Fork-sync policy. fork-sync-checker keeps managed-role forks in
        # sync with linux-system-roles upstream main. Only fast-forwards
        # auto-push; divergent forks surface to PENDING for human review.
        "fork_sync": {
            "auto_push": True,
            "max_per_run": 5,
        },
        # Opt-in host-lock enforcement. When True, runs abort if the host
        # fingerprint (hostname + primary MAC + /etc/os-release ID/VERSION)
        # differs from state.host.fingerprint. Recovery: `make ack-host-lock`.
        "security": {
            "enforce_host_lock": False,
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


# Old (pre-self-contained) defaults. _migrate() rewrites these to the new
# {workspace}-relative defaults so existing installs upgrade transparently.
# User-customized paths (anything not in this map) are left alone.
_LEGACY_PATH_DEFAULTS = {
    "iso_dir":           "~/iso",
    "ansible_root":      "~/github/ansible",
    "lsr_clones_root":   "~/github/linux-system-roles",
    "worktrees_root":    "~/github/.lsr-maintainer-worktrees",
    "tox_venv":          "~/github/ansible/testing/tox-lsr-venv",
    "host_scripts":      "~/github/ansible/scripts",
    "obs_checkout_root": "~/github/ansible",
}


def _migrate(data: dict[str, Any]) -> dict[str, Any]:
    data["version"] = CONFIG_VERSION
    # Self-containment migration: if a path still matches its legacy default,
    # rewrite it to the new {workspace}-relative default. Customized values
    # (anything that doesn't match the legacy literal) are preserved.
    paths = data.get("paths", {})
    new_defaults = default_config()["paths"]
    for key, legacy_value in _LEGACY_PATH_DEFAULTS.items():
        if paths.get(key) == legacy_value:
            paths[key] = new_defaults[key]
    return data


def workspace_root() -> str:
    """Workspace is the parent of the orchestrator/ directory that holds this file."""
    return os.path.dirname(os.path.dirname(os.path.abspath(__file__)))


def get_path(cfg: dict[str, Any], key: str, workspace: str | None = None) -> str:
    """Resolve cfg['paths'][key] to an absolute path.

    Substitutes the `{workspace}` placeholder, expands `~`, and returns the
    result. Returns "" if the key is missing or empty (hooks treat empty as
    "not configured" and fall back to safe defaults).
    """
    ws = workspace or workspace_root()
    raw = cfg.get("paths", {}).get(key, "")
    if not raw:
        return ""
    return os.path.expanduser(raw.format(workspace=ws))


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


_TRUSTED_BIN_DIRS = ("/usr/bin", "/usr/local/bin", "/usr/sbin", "/usr/local/sbin", "/bin", "/sbin")


def _trusted_binary(name: str) -> str | None:
    """Resolve `name` via shutil.which, then refuse it if it's not under
    a trusted system bindir. Closes the PATH-shim attack class
    (see issue #21): if `~/.local/bin/gh` shadows the real one, an
    attacker who can write to the user's local bin would otherwise steal
    identity at the next setup.sh run.

    Returns the absolute path or None if untrusted/missing.
    """
    p = shutil.which(name)
    if not p:
        return None
    # Resolve symlinks one level to catch e.g. /usr/local/bin/gh -> /opt/gh/bin/gh
    try:
        real = os.path.realpath(p)
    except Exception:
        real = p
    # Accept if EITHER the symlink-as-found OR the resolved path lives under
    # a trusted dir. (Some distros ship gh as /usr/bin/gh → /opt/.../gh.)
    if any(p.startswith(d + "/") for d in _TRUSTED_BIN_DIRS):
        return p
    if any(real.startswith(d + "/") for d in _TRUSTED_BIN_DIRS):
        return p
    return None


def detect_identity() -> dict[str, str]:
    """Run `gh api user` and `osc whois` non-interactively and return what
    they print. Does NOT print tokens — only the public login names.
    Returns empty strings for any that fail (e.g. unauthenticated).

    Binaries are resolved via `_trusted_binary` so a PATH-shim earlier in
    PATH (e.g. `~/.local/bin/gh`) cannot steal identity.
    """
    out = {"github_user": "", "obs_user": "", "git_email": "", "git_name": "",
           "warnings": []}  # operator surfaces these via setup.sh

    gh_bin = _trusted_binary("gh")
    if gh_bin:
        try:
            r = subprocess.run(
                [gh_bin, "api", "user", "--jq", ".login"],
                capture_output=True, text=True, timeout=10,
            )
            if r.returncode == 0:
                out["github_user"] = r.stdout.strip()
        except Exception:
            pass
    elif shutil.which("gh"):
        out["warnings"].append(
            f"gh found at {shutil.which('gh')} but NOT under a trusted system bindir; "
            "refusing to use it (PATH-shim defense). Install gh via your package manager."
        )

    osc_bin = _trusted_binary("osc")
    if osc_bin:
        try:
            r = subprocess.run(
                [osc_bin, "whois"], capture_output=True, text=True, timeout=10,
            )
            if r.returncode == 0:
                out["obs_user"] = r.stdout.strip().split()[0] if r.stdout.strip() else ""
        except Exception:
            pass
    elif shutil.which("osc"):
        out["warnings"].append(
            f"osc found at {shutil.which('osc')} but NOT under a trusted system bindir; "
            "refusing to use it. Install osc via your package manager."
        )

    git_bin = _trusted_binary("git")
    if git_bin:
        try:
            r = subprocess.run([git_bin, "config", "--global", "user.email"],
                               capture_output=True, text=True)
            out["git_email"] = r.stdout.strip()
            r = subprocess.run([git_bin, "config", "--global", "user.name"],
                               capture_output=True, text=True)
            out["git_name"] = r.stdout.strip()
        except Exception:
            pass

    return out


def init_from_identity(detected: dict[str, str], existing: dict[str, Any] | None = None) -> dict[str, Any]:
    """Build a fresh config from detected identity, preserving any overrides
    in `existing`.

    Merge policy:
    - github.user / obs.user are filled ONLY if empty in existing. Detected
      values are used as the initial seed; re-running setup against a
      DIFFERENT account will NOT overwrite. (Sanity guard against accidentally
      cross-wiring an account; the user must manually clear the field to
      re-detect.)
    - obs.personal_project_root is recomputed only if obs.user was just filled
      AND personal_project_root is still empty.
    - All other fields (source_project, paths, schedule, test_targets) are
      never touched by init — user customizations always preserved.

    The result is that `./bin/setup.sh` is safe to re-run idempotently.
    """
    cfg = existing or default_config()

    # GitHub user
    if detected.get("github_user") and not cfg["github"].get("user"):
        cfg["github"]["user"] = detected["github_user"]

    # OBS user — only fill if empty (preserve overrides on re-run).
    if detected.get("obs_user") and not cfg["obs"].get("user"):
        cfg["obs"]["user"] = detected["obs_user"]

    # personal_project_root — only auto-compute if user is set AND root is empty.
    # This lets a user manually set a non-default root (rare) and keep it.
    if cfg["obs"].get("user") and not cfg["obs"].get("personal_project_root"):
        cfg["obs"]["personal_project_root"] = f"home:{cfg['obs']['user']}"

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


# Enablement-queue helpers (v3) ---------------------------------------------

def pop_enablement_role(
    cfg: dict[str, Any],
    managed_role_names: set[str] | list[str],
    queued_role_names: set[str] | list[str],
) -> str | None:
    """Peek the next eligible role in `config.enablement.queue`, skipping
    roles already in the OBS manifest or already enqueued for this run.

    Does NOT remove the role from the list — `ack_enablement_role()` does
    that, and only on successful enablement. Failures leave the role in
    place so the next nightly run retries.
    """
    managed = set(managed_role_names)
    queued = set(queued_role_names)
    for role in cfg.get("enablement", {}).get("queue", []) or []:
        if not role:
            continue
        if role in managed:
            continue
        if role in queued:
            continue
        return role
    return None


def ack_enablement_role(cfg_path: str, role: str) -> bool:
    """Remove `role` from `config.enablement.queue` and save the config.

    Returns True if the role was present and removed, False otherwise.
    The caller is responsible for holding state_lock if cross-process
    safety matters (config and state share the same lock window).
    """
    cfg = load_config(cfg_path)
    queue = cfg.get("enablement", {}).get("queue", []) or []
    if role not in queue:
        return False
    cfg["enablement"]["queue"] = [r for r in queue if r != role]
    save_config(cfg_path, cfg)
    return True


if __name__ == "__main__":
    # Self-test.
    tmpdir = tempfile.mkdtemp()
    p = os.path.join(tmpdir, "config.json")
    c = load_config(p)
    assert c["version"] == CONFIG_VERSION
    assert c["github"]["user"] == ""  # pre-init = empty = hooks block all writes

    # First init populates from detection.
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

    # Re-init must PRESERVE existing identity, NOT overwrite with a different
    # detected user. Sanity guard against accidental cross-wiring.
    different = {"github_user": "bob", "obs_user": "bob42", "git_email": "b@b", "git_name": "B"}
    c3 = init_from_identity(different, c2)
    assert c3["github"]["user"] == "alice", "re-init must not overwrite github.user"
    assert c3["obs"]["user"] == "alice123", "re-init must not overwrite obs.user"
    assert c3["obs"]["personal_project_root"] == "home:alice123"

    # User customizes source_project; re-init preserves it.
    c3["obs"]["source_project"] = "devel:packman"
    c4 = init_from_identity(detected, c3)
    assert c4["obs"]["source_project"] == "devel:packman", "re-init must preserve user-customized source_project"

    # User clears github.user manually; re-init refills from detection.
    c3["github"]["user"] = ""
    c5 = init_from_identity(different, c3)
    assert c5["github"]["user"] == "bob", "init must fill empty github.user from new detection"

    # === Self-containment path resolution ===
    # Default paths resolve under workspace_root().
    ws = workspace_root()
    iso = get_path(default_config(), "iso_dir")
    assert iso == os.path.join(ws, "var/iso"), f"unexpected iso_dir: {iso}"
    assert get_path(default_config(), "log_dir").endswith("/var/log")
    assert get_path(default_config(), "cache_dir").endswith("/var/cache")

    # Explicit workspace override.
    iso2 = get_path(default_config(), "iso_dir", workspace="/tmp/ws")
    assert iso2 == "/tmp/ws/var/iso", iso2

    # Absolute override is preserved (no placeholder, no expanduser noise).
    custom = default_config()
    custom["paths"]["iso_dir"] = "/mnt/big/iso"
    assert get_path(custom, "iso_dir") == "/mnt/big/iso"

    # Missing key returns "".
    assert get_path(default_config(), "nonexistent") == ""

    # === Migration of legacy paths ===
    legacy = {
        "version": 1,
        "paths": {
            "iso_dir": "~/iso",
            "ansible_root": "~/github/ansible",
            "tox_venv": "/custom/override/venv",  # user-customized; must NOT migrate
        },
    }
    legacy_path = os.path.join(tmpdir, "legacy.json")
    with open(legacy_path, "w") as f:
        json.dump(legacy, f)
    migrated = load_config(legacy_path)
    assert migrated["paths"]["iso_dir"] == "{workspace}/var/iso", migrated["paths"]["iso_dir"]
    assert migrated["paths"]["ansible_root"] == "{workspace}/var/ansible"
    assert migrated["paths"]["tox_venv"] == "/custom/override/venv", "custom override must be preserved"

    # === v3 sections present in defaults ===
    d = default_config()
    assert d["enablement"] == {"queue": [], "auto_enqueue_per_run": 1, "default_target": "sle16"}
    assert d["fork_sync"]["auto_push"] is True
    assert d["fork_sync"]["max_per_run"] == 5
    assert d["security"]["enforce_host_lock"] is False
    assert "host_lock_mismatch" in d["notify"]["events"]

    # === v2 → v3 migration: new sections appear, existing fields preserved ===
    v2 = {
        "version": 2,
        "github": {"user": "carol"},
        "paths": {"iso_dir": "{workspace}/var/iso"},
    }
    v2_path = os.path.join(tmpdir, "v2.json")
    with open(v2_path, "w") as f:
        json.dump(v2, f)
    upgraded = load_config(v2_path)
    assert upgraded["github"]["user"] == "carol", "existing identity must be preserved"
    assert "enablement" in upgraded, "v3 migration must add enablement"
    assert upgraded["enablement"]["queue"] == []
    assert upgraded["fork_sync"]["auto_push"] is True
    assert upgraded["security"]["enforce_host_lock"] is False

    # === pop_enablement_role ===
    cfg_e = default_config()
    cfg_e["enablement"]["queue"] = ["logging", "kdump", "selinux"]
    # No roles managed yet → pop returns "logging".
    assert pop_enablement_role(cfg_e, [], []) == "logging"
    # `logging` already in OBS manifest → skip to kdump.
    assert pop_enablement_role(cfg_e, ["logging"], []) == "kdump"
    # `logging` queued this run → also skip.
    assert pop_enablement_role(cfg_e, [], ["logging"]) == "kdump"
    # All managed → None.
    assert pop_enablement_role(cfg_e, ["logging", "kdump", "selinux"], []) is None
    # Empty list → None.
    cfg_empty = default_config()
    assert pop_enablement_role(cfg_empty, [], []) is None

    # === ack_enablement_role: idempotent removal ===
    ack_cfg = default_config()
    ack_cfg["enablement"]["queue"] = ["logging", "kdump"]
    ack_cfg["github"]["user"] = "alice"  # avoid pre-init nuance in save
    ack_path = os.path.join(tmpdir, "ack.json")
    save_config(ack_path, ack_cfg)
    assert ack_enablement_role(ack_path, "logging") is True
    re_loaded = load_config(ack_path)
    assert re_loaded["enablement"]["queue"] == ["kdump"], re_loaded["enablement"]["queue"]
    # Ack-ing a role not in queue → False, no change.
    assert ack_enablement_role(ack_path, "logging") is False

    print("OK", p)

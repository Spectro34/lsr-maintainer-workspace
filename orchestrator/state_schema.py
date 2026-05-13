"""State schema + atomic-write helpers for state/.lsr-maintainer-state.json.

Pure-stdlib (no Pydantic dependency) — the orchestrator's hosts may not have
extra Python packages installed. JSON schema is enforced by load_state() which
fills in defaults for missing fields.

Concurrency: load_state + mutate + save_state runs are NOT atomic on their own.
Concurrent `claude -p` invocations (e.g. cron firing while user runs `make run`)
can race: both load, both mutate, both save — the second `os.replace` wins,
silently dropping the first's queue mutations.

Solution: wrap load→mutate→save blocks with `with state_lock("path"):` which
acquires an exclusive `fcntl.flock` on a sibling `.lock` file. The orchestrator
uses this around its entire run; the lock is released on context exit.

Self-test verifies atomicity. See workflow-run.md Phase 0 + Phase 5 for usage.
"""
from __future__ import annotations

import contextlib
import fcntl
import json
import os
import tempfile
from datetime import datetime, timezone
from typing import Any

STATE_VERSION = 1


@contextlib.contextmanager
def state_lock(state_path: str, timeout_sec: float = 30.0):
    """Exclusive advisory lock around a state-file read-modify-write block.

    Acquires fcntl.LOCK_EX on `<state_path>.lock`. Blocks up to `timeout_sec`
    if another process holds it. Raises TimeoutError on timeout (the caller
    should treat that as "another run is in progress; exit cleanly").
    """
    lock_path = state_path + ".lock"
    os.makedirs(os.path.dirname(os.path.abspath(state_path)) or ".", exist_ok=True)
    fd = os.open(lock_path, os.O_RDWR | os.O_CREAT, 0o600)
    try:
        # Non-blocking attempt with retry loop so we honor the timeout.
        import time
        deadline = time.monotonic() + timeout_sec
        while True:
            try:
                fcntl.flock(fd, fcntl.LOCK_EX | fcntl.LOCK_NB)
                break
            except BlockingIOError:
                if time.monotonic() >= deadline:
                    raise TimeoutError(f"state lock contended at {lock_path}")
                time.sleep(0.1)
        try:
            yield
        finally:
            fcntl.flock(fd, fcntl.LOCK_UN)
    finally:
        os.close(fd)


def _now() -> str:
    return datetime.now(timezone.utc).isoformat()


def default_role_entry(
    role: str,
    version: str | None = None,
    sle16_only: bool = False,
    github_user: str = "",
    fork_branch: str = "fix/suse-support",
) -> dict[str, Any]:
    """Per-role state structure. Every field that any sub-agent reads must
    have a default here so the first run never sees KeyError / None.

    `github_user` and `fork_branch` come from state/config.json (loaded by
    the caller via orchestrator.config). Pre-init or anonymous use leaves
    fork_repo empty — sub-agents that need it bail out with PENDING.
    """
    return {
        "role": role,
        "version": version,
        "sle16_only": sle16_only,
        "upstream_default_branch": "main",
        "last_seen_upstream_sha": None,
        "fork_branch": fork_branch,
        "fork_repo": f"{github_user}/{role}" if github_user else "",
        "upstream_repo": None,  # populated when first seen
        "patched_files": [],
        "last_local_test": {},  # keyed by target → {result, at, sha, image, via}
        "pr_cursors": {},       # keyed by PR number → {last_seen_*}
        "fix_attempts_by_pr": {},  # keyed by PR number → count (for retry caps)
        # Fork-sync state (v3). fork-sync-checker writes here.
        "fork_exists": False,
        "fork_last_sync_at": None,           # iso8601
        "fork_sync_status": "unknown",       # in_sync|behind|ahead|diverged|conflict|missing|unknown
        "fork_sync_compare": {},             # {behind_by, ahead_by}
    }


def seed_roles_from_manifest(
    state: dict[str, Any],
    managed_roles: list[dict[str, Any]],
    github_user: str = "",
    fork_branch: str = "fix/suse-support",
    tracked_extra_roles: list[str] | None = None,
) -> int:
    """Ensure every role in managed_roles[] and tracked_extra_roles has a
    per-role entry in state.roles. Returns the number of NEW entries created.

    Called by the orchestrator after manifest-syncer returns. The orchestrator
    reads github_user, fork_branch, and tracked_extra_roles from
    state/config.json (via orchestrator.config.load_config) and passes them
    here.

    `managed_roles` come from the OBS spec (with version + sle16_only metadata).
    `tracked_extra_roles` are bare role names — fork-only roles the user
    maintains beyond what the OBS package ships (sudo, kernel_settings,
    ansible-sshd, network, logging, metrics, plus community/hackweek roles).
    These get default_role_entry() with version=None, sle16_only=False.

    Existing entries are preserved; only missing fields are filled in.
    """
    created = 0
    # Build the combined list, manifest roles first (they have metadata).
    combined = list(managed_roles)
    seen_names = {r.get("name") for r in combined if r.get("name")}
    for name in (tracked_extra_roles or []):
        if name and name not in seen_names:
            combined.append({"name": name, "version": None, "sle16_only": False})
            seen_names.add(name)

    for r in combined:
        name = r.get("name")
        if not name:
            continue
        if name not in state["roles"]:
            state["roles"][name] = default_role_entry(
                name, r.get("version"), r.get("sle16_only", False),
                github_user=github_user, fork_branch=fork_branch,
            )
            created += 1
        else:
            # Fill in any missing fields from defaults (forward-compat).
            defaults = default_role_entry(name, github_user=github_user, fork_branch=fork_branch)
            for k, v in defaults.items():
                state["roles"][name].setdefault(k, v)
            # Keep version + sle16_only in sync with manifest.
            state["roles"][name]["version"] = r.get("version")
            state["roles"][name]["sle16_only"] = r.get("sle16_only", False)
            # Reconcile fork_repo on identity change. If config says
            # github_user=alice but state has fork_repo=bob/sudo, the agent
            # would push to the wrong account. Rewrite to alice/sudo.
            if github_user:
                current_fork = state["roles"][name].get("fork_repo", "")
                current_owner = current_fork.split("/", 1)[0] if "/" in current_fork else ""
                if current_owner != github_user:
                    state["roles"][name]["fork_repo"] = f"{github_user}/{name}"
                    # Identity changed — clear PR cursors. The old user's
                    # cursors don't apply to the new user's forks.
                    state["roles"][name]["pr_cursors"] = {}
    return created


def default_state() -> dict[str, Any]:
    return {
        "version": STATE_VERSION,
        "last_run_started_at": None,
        "last_run_completed_at": None,
        "last_run_aborted": False,
        "queue": [],
        "roles": {},
        "obs": {
            "ansible-linux-system-roles": {
                "last_check": None,
                "last_build_state": None,
            },
            "managed_roles": [],
            "manifest_last_synced": None,
        },
        "host": {
            "fingerprint": None,
            "bootstrapped_at": None,
            "components_ready": {},
        },
        "pending_review_count": 0,
    }


def load_state(path: str) -> dict[str, Any]:
    """Read state; return defaults if missing. Migrates older versions in-place."""
    if not os.path.exists(path):
        return default_state()
    with open(path) as f:
        try:
            data = json.load(f)
        except json.JSONDecodeError:
            # Corrupt — preserve old as .bak and start fresh.
            os.rename(path, path + ".bak")
            return default_state()
    if data.get("version", 0) < STATE_VERSION:
        data = _migrate(data)
    # Fill in any missing top-level keys from defaults.
    base = default_state()
    for k, v in base.items():
        data.setdefault(k, v)
    return data


def _migrate(data: dict[str, Any]) -> dict[str, Any]:
    """No migrations needed yet (v1 is the first). Place future migrations here."""
    data["version"] = STATE_VERSION
    return data


def save_state(path: str, data: dict[str, Any]) -> None:
    """Atomic write: temp file in same dir + rename."""
    data = dict(data)
    data["version"] = STATE_VERSION
    dirpath = os.path.dirname(os.path.abspath(path)) or "."
    os.makedirs(dirpath, exist_ok=True)
    fd, tmp = tempfile.mkstemp(prefix=".state-", suffix=".json", dir=dirpath)
    try:
        with os.fdopen(fd, "w") as f:
            json.dump(data, f, indent=2, sort_keys=True)
            f.write("\n")
        os.replace(tmp, path)
    except Exception:
        if os.path.exists(tmp):
            os.unlink(tmp)
        raise


# Queue helpers --------------------------------------------------------------

PRIORITY_RANK = {
    "reviewer_change_requested": 0,
    "ci_failed": 1,
    "obs_build_failure": 2,
    "upstream_drift_conflicting": 3,
    "enable_role": 3,
    "round_robin_health": 4,
}


def enqueue(state: dict[str, Any], item: dict[str, Any]) -> None:
    """Insert an item into the queue, sorted by priority. Dedup on id."""
    existing_ids = {q.get("id") for q in state["queue"] if q.get("id")}
    if item.get("id") in existing_ids:
        return
    item.setdefault("discovered_at", _now())
    item.setdefault("priority", PRIORITY_RANK.get(item.get("kind", ""), 9))
    state["queue"].append(item)
    state["queue"].sort(key=lambda q: (q.get("priority", 9), q.get("discovered_at", "")))


def pop_next(state: dict[str, Any]) -> dict[str, Any] | None:
    if not state["queue"]:
        return None
    return state["queue"].pop(0)


def remove(state: dict[str, Any], item_id: str) -> bool:
    before = len(state["queue"])
    state["queue"] = [q for q in state["queue"] if q.get("id") != item_id]
    return len(state["queue"]) != before


# Quick sanity check (not a pytest test — runs as `python -m orchestrator.state_schema`).
if __name__ == "__main__":
    import sys
    tmpdir = tempfile.mkdtemp()
    p = os.path.join(tmpdir, "test-state.json")
    s = load_state(p)
    assert s["version"] == STATE_VERSION
    enqueue(s, {"id": "test-1", "kind": "ci_failed", "pr": {"number": 1}})
    enqueue(s, {"id": "test-2", "kind": "reviewer_change_requested", "pr": {"number": 2}})
    save_state(p, s)
    s2 = load_state(p)
    assert s2["queue"][0]["id"] == "test-2", "priority sort broken"
    assert s2["queue"][1]["id"] == "test-1"

    # Seed-from-manifest sanity.
    manifest = [
        {"name": "sudo", "version": "1.5.2", "sle16_only": False},
        {"name": "certificate", "version": "1.3.11", "sle16_only": True},
    ]
    # Pre-init (no github_user) → fork_repo is empty.
    created = seed_roles_from_manifest(s2, manifest)
    assert created == 2, f"expected 2 new role entries, got {created}"
    assert s2["roles"]["sudo"]["fork_repo"] == "", "fork_repo should be empty pre-init"

    # With a github_user, fork_repo is populated.
    s3 = default_state()
    seed_roles_from_manifest(s3, manifest, github_user="alice")
    assert s3["roles"]["sudo"]["fork_repo"] == "alice/sudo"
    assert s3["roles"]["certificate"]["sle16_only"] is True

    # Re-seed: idempotent, returns 0 new.
    assert seed_roles_from_manifest(s3, manifest, github_user="alice") == 0
    # Existing entry preserved across re-seed.
    s3["roles"]["sudo"]["patched_files"] = ["library/scan_sudoers.py"]
    seed_roles_from_manifest(s3, manifest, github_user="alice")
    assert s3["roles"]["sudo"]["patched_files"] == ["library/scan_sudoers.py"]

    # Identity migration: github_user changes from alice → bob. fork_repo and
    # pr_cursors must reset; patched_files preserved (role-level state).
    s3["roles"]["sudo"]["pr_cursors"] = {"12": {"last_seen_comment_id": 999}}
    seed_roles_from_manifest(s3, manifest, github_user="bob")
    assert s3["roles"]["sudo"]["fork_repo"] == "bob/sudo", "fork_repo must follow identity change"
    assert s3["roles"]["sudo"]["pr_cursors"] == {}, "PR cursors must reset on identity change"
    assert s3["roles"]["sudo"]["patched_files"] == ["library/scan_sudoers.py"], "patched_files preserved"

    # tracked_extra_roles: roles not in the OBS manifest get seeded too.
    s4 = default_state()
    seed_roles_from_manifest(
        s4, manifest, github_user="alice",
        tracked_extra_roles=["kernel_settings", "ansible-sshd"],
    )
    # Manifest roles get manifest metadata.
    assert "sudo" in s4["roles"]
    assert s4["roles"]["sudo"]["version"] == "1.5.2"
    assert s4["roles"]["certificate"]["sle16_only"] is True
    # tracked_extra_roles get default metadata (no version).
    assert "kernel_settings" in s4["roles"], "tracked_extra_roles must seed bare names"
    assert s4["roles"]["kernel_settings"]["version"] is None
    assert s4["roles"]["kernel_settings"]["sle16_only"] is False
    assert s4["roles"]["kernel_settings"]["fork_repo"] == "alice/kernel_settings"
    assert "ansible-sshd" in s4["roles"]

    # state_lock concurrency: second acquisition with short timeout must fail.
    lockp = os.path.join(tmpdir, "concurrent.json")
    with state_lock(lockp, timeout_sec=1.0):
        # Another acquisition must time out.
        try:
            with state_lock(lockp, timeout_sec=0.2):
                raise AssertionError("nested lock should have timed out")
        except TimeoutError:
            pass

    # After release, lock is reacquirable.
    with state_lock(lockp, timeout_sec=1.0):
        pass

    print("OK", p)

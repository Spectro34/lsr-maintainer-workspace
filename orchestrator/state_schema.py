"""State schema + atomic-write helpers for state/.lsr-maintainer-state.json.

Pure-stdlib (no Pydantic dependency) — the orchestrator's hosts may not have
extra Python packages installed. JSON schema is enforced by load_state() which
fills in defaults for missing fields.
"""
from __future__ import annotations

import json
import os
import tempfile
from datetime import datetime, timezone
from typing import Any

STATE_VERSION = 1


def _now() -> str:
    return datetime.now(timezone.utc).isoformat()


def default_state() -> dict[str, Any]:
    return {
        "version": STATE_VERSION,
        "last_run_started_at": None,
        "last_run_completed_at": None,
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
    print("OK", p)

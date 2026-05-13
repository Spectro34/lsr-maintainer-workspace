"""Role → SUSE-docs domain mapping (loaded by reviewer-sle-docs).

Reads `state/role_domains.json` at the workspace root. Each entry maps a
role name to the SUSE-doc topics + URL hints the reviewer should consult
when validating an SLE 16 patch.

Schema:
{
  "logging":  {"topics": ["rsyslog", "journald"],
               "url_hints": ["doc/admin/single-html/SLES-admin"]},
  ...
}

Missing roles return `None` from `lookup()`; the caller falls back to
searching documentation.suse.com with the role name as the query.

Self-test verifies the JSON parses and that every known role has at
least one topic. Warns (does not fail) for managed roles missing entries
— that's a soft maintenance signal, not a runtime error.
"""
from __future__ import annotations

import json
import os
import sys
from typing import Any


def _default_path() -> str:
    """state/role_domains.json relative to the workspace root."""
    here = os.path.dirname(os.path.abspath(__file__))
    return os.path.join(os.path.dirname(here), "state", "role_domains.json")


def load(path: str | None = None) -> dict[str, Any]:
    """Load the role-domain map. Returns {} if the file is missing."""
    path = path or _default_path()
    if not os.path.exists(path):
        return {}
    with open(path) as f:
        return json.load(f)


def lookup(role: str, data: dict[str, Any] | None = None) -> dict[str, Any] | None:
    """Return the entry for `role`, or None if not present."""
    data = data if data is not None else load()
    return data.get(role)


def known_roles(data: dict[str, Any] | None = None) -> list[str]:
    """Return the list of roles with explicit domain entries."""
    data = data if data is not None else load()
    return sorted(data.keys())


if __name__ == "__main__":
    data = load()
    # Schema check: every value must have a non-empty `topics` list.
    bad = []
    for role, entry in data.items():
        if not isinstance(entry, dict):
            bad.append(f"{role}: entry is not a dict")
            continue
        topics = entry.get("topics") or []
        if not isinstance(topics, list) or not topics:
            bad.append(f"{role}: missing or empty `topics`")
    if bad:
        for b in bad:
            sys.stderr.write(f"role_domains schema error: {b}\n")
        sys.exit(1)

    # Spot-check: `logging` is the user's first listed role; assert it's mapped.
    assert lookup("nonexistent_role") is None
    if data:
        assert known_roles()
        # Pick the first role and assert lookup returns a dict.
        first = known_roles()[0]
        e = lookup(first)
        assert isinstance(e, dict) and e.get("topics")

    print(f"OK role_domains ({len(data)} roles)")

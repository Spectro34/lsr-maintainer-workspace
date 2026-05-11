"""Parse ansible-linux-system-roles.spec to extract the managed-role manifest.

Returns: list of {name, version, sle16_only} dicts.

The spec uses `%global <role>_version 1.2.3` for shipped roles and wraps
sle16-only roles in `%if %{sle16}` ... `%endif` blocks. We grep for both
patterns rather than parse RPM macros fully — this is enough for our needs
and avoids depending on a spec-parsing library.
"""
from __future__ import annotations

import re
import sys
from typing import Any

VERSION_RE = re.compile(
    r"^\s*%global\s+([a-z][a-z0-9_]*)_version\s+([0-9][0-9.]*[0-9a-z]*)\s*$",
    re.MULTILINE | re.IGNORECASE,
)

# Detect roles inside %if %{sle16} ... %endif blocks.
SLE16_BLOCK_RE = re.compile(
    r"%if\s+%\{sle16\}(.+?)%endif",
    re.DOTALL,
)


VERSION_MACRO_RE = re.compile(r"%\{([a-z][a-z0-9_]*)_version\}", re.IGNORECASE)


def parse_spec(spec_text: str) -> list[dict[str, Any]]:
    """Extract role list from spec content.

    Returns a list of dicts: [{"name": "firewall", "version": "1.11.6", "sle16_only": False}, ...]

    Strategy:
      - Roles are defined via `%global <role>_version X.Y.Z` (always defined).
      - sle16-only roles are those whose `%{<role>_version}` is referenced ONLY
        inside `%if %{sle16}` ... `%endif` blocks. We approximate by checking
        whether the role name appears at all in a Source* / files-list reference
        outside the sle16 block.
    """
    all_versions = {m.group(1).lower(): m.group(2) for m in VERSION_RE.finditer(spec_text)}

    # Find content inside sle16 blocks.
    sle16_blocks = [m.group(1) for m in SLE16_BLOCK_RE.finditer(spec_text)]
    sle16_text = "\n".join(sle16_blocks)

    # Names referenced only inside sle16 blocks.
    refs_in_sle16: set[str] = {m.group(1).lower() for m in VERSION_MACRO_RE.finditer(sle16_text)}

    # Build a copy of the spec with sle16 blocks redacted to see what's referenced outside.
    redacted = SLE16_BLOCK_RE.sub("", spec_text)
    refs_outside: set[str] = {m.group(1).lower() for m in VERSION_MACRO_RE.finditer(redacted)}

    sle16_only = refs_in_sle16 - refs_outside

    roles = [
        {"name": name, "version": version, "sle16_only": name in sle16_only}
        for name, version in sorted(all_versions.items())
    ]
    return roles


def diff_manifests(
    prev: list[dict[str, Any]],
    curr: list[dict[str, Any]],
) -> list[dict[str, Any]]:
    """Return a list of events describing how the manifest changed."""
    prev_by_name = {r["name"]: r for r in prev}
    curr_by_name = {r["name"]: r for r in curr}
    events = []
    for name, r in curr_by_name.items():
        if name not in prev_by_name:
            events.append({"kind": "obs_role_added", "role": name, "version": r["version"]})
        elif r["version"] != prev_by_name[name]["version"]:
            events.append(
                {
                    "kind": "obs_role_bumped",
                    "role": name,
                    "from": prev_by_name[name]["version"],
                    "to": r["version"],
                }
            )
    for name in prev_by_name:
        if name not in curr_by_name:
            events.append({"kind": "obs_role_removed", "role": name})
    return events


if __name__ == "__main__":
    if len(sys.argv) != 2:
        print("usage: manifest_parse.py <path-to-spec>", file=sys.stderr)
        sys.exit(2)
    with open(sys.argv[1]) as f:
        text = f.read()
    roles = parse_spec(text)
    for r in roles:
        marker = " (sle16-only)" if r["sle16_only"] else ""
        print(f"{r['name']:<30} {r['version']}{marker}")
    print(f"\n-- {len(roles)} roles --")

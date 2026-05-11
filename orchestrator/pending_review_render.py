"""Render state/PENDING_REVIEW.md from current state.

Sections (in order):
  🚀 Ready to ship — open the PR yourself
  👀 Upstream review needs your eyes
  🏗 OBS package status
  🆕 New role ready to ship
  🌊 Upstream drift detected (no action yet)
  🩺 Bootstrap status (this host)
  ❗ Manual triage needed
"""
from __future__ import annotations

from datetime import datetime, timezone
from typing import Any


def render(state: dict[str, Any]) -> str:
    now = datetime.now(timezone.utc).astimezone().strftime("%Y-%m-%d %H:%M %z")
    lines: list[str] = []
    lines.append(f"# Pending Review — generated {now}")
    lines.append("")

    queue = state.get("queue", [])

    ready = [q for q in queue if q.get("kind") == "ready_to_ship"]
    review_needed = [q for q in queue if q.get("kind") in ("reviewer_change_requested", "ci_failed")]
    new_roles = [q for q in queue if q.get("kind") == "new_role_ready"]
    drift = [q for q in queue if q.get("kind") == "upstream_drift_conflicting"]
    manual = [q for q in queue if q.get("kind") == "manual_triage"]

    lines.append("## 🚀 Ready to ship (open the PR yourself)")
    if not ready:
        lines.append("- _(nothing right now)_")
    else:
        for q in ready:
            pr = q.get("pr", {})
            summary = q.get("summary", "")
            lines.append(f"- [ ] **{q.get('role','?')}** — {summary}")
            cmd = q.get("suggested_command")
            if cmd:
                lines.append(f"  - Command: `{cmd}`")
    lines.append("")

    lines.append("## 👀 Upstream review needs your eyes")
    if not review_needed:
        lines.append("- _(none)_")
    else:
        for q in review_needed:
            pr = q.get("pr", {})
            label = f"{pr.get('repo','?')}#{pr.get('number','?')}"
            status = q.get("auto_fix_status", "not attempted")
            lines.append(f"- [ ] **{q.get('role','?')}** PR {label}")
            lines.append(f"  - Auto-fix status: {status}")
            if q.get("findings"):
                lines.append(f"  - Findings: {q['findings']}")
    lines.append("")

    lines.append("## 🏗 OBS package status")
    obs = state.get("obs", {})
    # The OBS project label is derived from config (see orchestrator.config.obs_branch_project).
    # The caller can pass it in via state["obs"]["_branch_project_label"]; if absent, render a generic note.
    branch_proj = obs.get("_branch_project_label") or "(home:<user>:branches:<source>)"
    pkg_name = obs.get("_package_name") or "ansible-linux-system-roles"
    pkg = obs.get(pkg_name, {})
    last = pkg.get("last_build_state", "(never checked)")
    lines.append(f"- {pkg_name} in `{branch_proj}` — last build state: {last}")
    lines.append("")

    lines.append("## 🆕 New role ready to ship")
    if not new_roles:
        lines.append("- _(none)_")
    else:
        for q in new_roles:
            lines.append(f"- [ ] **{q.get('role','?')}** — {q.get('summary','')}")
            for action in q.get("pending_actions", []):
                lines.append(f"  - {action}")
    lines.append("")

    lines.append("## 🌊 Upstream drift detected (no action yet)")
    if not drift:
        lines.append("- _(no conflicting drift)_")
    else:
        for q in drift:
            lines.append(f"- **{q.get('role','?')}** — new commits touching: {', '.join(q.get('conflicting_files', []))}")
    lines.append("")

    lines.append("## 🩺 Bootstrap status (this host)")
    host = state.get("host", {})
    cr = host.get("components_ready", {}) or {}
    if not cr:
        lines.append("- _(not bootstrapped yet — run `make install`)_")
    else:
        for comp, ok in cr.items():
            mark = "✓" if (ok is True or (isinstance(ok, dict) and all(ok.values()))) else "✗"
            extra = ""
            if isinstance(ok, dict):
                extra = " " + ", ".join(f"{k}={'✓' if v else '✗'}" for k, v in ok.items())
            lines.append(f"- {mark} {comp}{extra}")
    lines.append("")

    if manual:
        lines.append("## ❗ Manual triage needed")
        for q in manual:
            lines.append(f"- {q.get('summary', q.get('id','?'))}")
        lines.append("")

    return "\n".join(lines)


if __name__ == "__main__":
    import json, sys
    if len(sys.argv) != 2:
        print("usage: pending_review_render.py <state.json>", file=sys.stderr)
        sys.exit(2)
    with open(sys.argv[1]) as f:
        st = json.load(f)
    print(render(st))

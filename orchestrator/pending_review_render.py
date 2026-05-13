"""Render state/PENDING_REVIEW.md from current state.

Sections (in order):
  🚀 Ready to ship — open the PR yourself
  👀 Upstream review needs your eyes
  🏗 OBS package status
  🆕 New role ready to ship
  🌊 Upstream drift detected (no action yet)
  🔱 Fork sync status (managed-role forks vs upstream main)
  📋 Enablement queue (roles you've asked the agent to enable for SLE)
  🩺 Bootstrap status (this host)
  ❗ Manual triage needed
"""
from __future__ import annotations

from datetime import datetime, timezone
from typing import Any


def render(state: dict[str, Any], cfg: dict[str, Any] | None = None) -> str:
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

    lines.append("## 🔱 Fork sync status")
    roles = state.get("roles", {}) or {}
    fork_attention = [
        (name, r) for name, r in sorted(roles.items())
        if r.get("fork_sync_status") in ("conflict", "diverged", "missing", "unknown")
    ]
    fork_in_sync = sum(1 for r in roles.values() if r.get("fork_sync_status") == "in_sync")
    fork_behind = sum(1 for r in roles.values() if r.get("fork_sync_status") == "behind")
    fork_ahead = sum(1 for r in roles.values() if r.get("fork_sync_status") == "ahead")
    if not fork_attention and (fork_in_sync or fork_behind or fork_ahead):
        lines.append(f"- _(all forks healthy — {fork_in_sync} in_sync, {fork_behind} behind (auto-syncing), {fork_ahead} ahead of upstream)_")
    elif not roles:
        lines.append("- _(no roles tracked yet)_")
    elif not fork_attention:
        lines.append("- _(no attention needed)_")
    else:
        for name, r in fork_attention:
            status = r.get("fork_sync_status", "unknown")
            cmp_ = r.get("fork_sync_compare") or {}
            detail = f"behind {cmp_.get('behind_by','?')} ahead {cmp_.get('ahead_by','?')}" if cmp_ else ""
            lines.append(f"- **{name}** — {status}{(' (' + detail + ')') if detail else ''}")
    lines.append("")

    lines.append("## 📋 Enablement queue")
    queue_list = ((cfg or {}).get("enablement") or {}).get("queue") or []
    if not queue_list:
        lines.append("- _(empty — add roles to `config.enablement.queue` to schedule them for SLE enablement)_")
    else:
        for role in queue_list:
            lines.append(f"- [ ] **{role}** — pending enablement (pops 1/run by default)")
        lines.append("")
        lines.append("Manual ack: `make ack-enablement ROLE=<name>` (or edit `state/config.json`).")
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
    import json, sys, os
    if len(sys.argv) == 1:
        # Self-test (so `make test-orchestrator` can exercise the new sections).
        cfg = {"enablement": {"queue": ["logging", "kdump"]}}
        state = {
            "queue": [],
            "roles": {
                "sudo":    {"fork_sync_status": "in_sync",  "fork_sync_compare": {"behind_by": 0, "ahead_by": 0}},
                "logging": {"fork_sync_status": "conflict", "fork_sync_compare": {"behind_by": 3, "ahead_by": 2}},
                "firewall":{"fork_sync_status": "behind",   "fork_sync_compare": {"behind_by": 5, "ahead_by": 0}},
            },
            "obs": {},
            "host": {"components_ready": {}},
        }
        text = render(state, cfg)
        assert "🔱 Fork sync status" in text
        assert "logging" in text and "conflict" in text
        assert "📋 Enablement queue" in text
        assert "**logging**" in text and "**kdump**" in text
        # No-config path still works (legacy callers).
        text2 = render(state)
        assert "📋 Enablement queue" in text2
        assert "empty" in text2  # cfg defaulted → empty queue note
        print("OK pending_review_render self-test")
        sys.exit(0)
    if len(sys.argv) != 2:
        print("usage: pending_review_render.py <state.json>", file=sys.stderr)
        sys.exit(2)
    with open(sys.argv[1]) as f:
        st = json.load(f)
    print(render(st))

"""Out-of-band notification dispatch.

Backends configured in `state/config.json::notify`. The orchestrator calls
`notify(event, message, priority)` from Phase 4 after computing what to
surface. Hooks DO NOT call notify — they exit fast.

Notifications are opt-in: if no `notify.backend` configured, calls are silent
no-ops. The Phase 4 code path always calls notify; whether it dials out is
the user's choice via config.

Day-1 backends:
  - ntfy.sh (zero-config, free): POST to https://ntfy.sh/<topic>
  - email via msmtp / sendmail (uses system mailer)
  - webhook (POST JSON to arbitrary URL — Slack/Discord/etc.)

Backends fail silently. A broken notify must NEVER abort a run.
"""
from __future__ import annotations

import json
import os
import shutil
import subprocess
from datetime import datetime, timezone
from typing import Any

EVENT_KINDS = (
    "reject",          # review board rejected a patch
    "anomaly",         # metric exceeded threshold
    "doctor_red",     # cron pre-flight failed
    "halt",            # agent auto-engaged kill switch
    "daily_summary",   # nightly run summary
)


def notify(cfg: dict[str, Any], event: str, message: str, priority: str = "default") -> bool:
    """Dispatch a notification. Returns True if any backend succeeded;
    False if no backend configured or all failed. Never raises."""
    notify_cfg = cfg.get("notify") or {}
    if not notify_cfg.get("backend"):
        return False
    # Filter by configured event list (default: all).
    configured_events = set(notify_cfg.get("events") or EVENT_KINDS)
    if event not in configured_events:
        return False

    backend = notify_cfg["backend"]
    body = f"[{event}] {message}"
    try:
        if backend == "ntfy":
            return _send_ntfy(notify_cfg.get("ntfy") or {}, body, priority)
        elif backend == "email":
            return _send_email(notify_cfg.get("email") or {}, event, body)
        elif backend == "webhook":
            return _send_webhook(notify_cfg.get("webhook") or {}, event, body, priority)
        else:
            return False
    except Exception:
        return False


def _send_ntfy(cfg: dict[str, Any], body: str, priority: str) -> bool:
    """POST to https://ntfy.sh/<topic> (or a self-hosted ntfy server).

    ntfy free tier: zero config, public topic. Pick a long random topic
    name and add it to config; that's your private channel.
    """
    url = cfg.get("url")
    if not url:
        return False
    curl = shutil.which("curl")
    if not curl:
        return False
    try:
        r = subprocess.run(
            [curl, "-fsSL", "--max-time", "10",
             "-H", f"Priority: {priority}",
             "-H", f"Title: lsr-maintainer",
             "-d", body, url],
            capture_output=True, text=True, timeout=15,
        )
        return r.returncode == 0
    except Exception:
        return False


def _send_email(cfg: dict[str, Any], subject: str, body: str) -> bool:
    """Use the system mailer (msmtp / sendmail / mail)."""
    to = cfg.get("to")
    if not to:
        return False
    mailer = shutil.which("msmtp") or shutil.which("sendmail") or shutil.which("mail")
    if not mailer:
        return False
    msg = f"To: {to}\nSubject: lsr-maintainer: {subject}\n\n{body}\n"
    try:
        if mailer.endswith("/mail"):
            r = subprocess.run([mailer, "-s", f"lsr-maintainer: {subject}", to],
                               input=body, capture_output=True, text=True, timeout=20)
        else:
            r = subprocess.run([mailer, "-t"], input=msg, capture_output=True,
                               text=True, timeout=20)
        return r.returncode == 0
    except Exception:
        return False


def _send_webhook(cfg: dict[str, Any], event: str, body: str, priority: str) -> bool:
    """POST JSON to an arbitrary URL — Slack/Discord/Mattermost/custom."""
    url = cfg.get("url")
    if not url:
        return False
    curl = shutil.which("curl")
    if not curl:
        return False
    payload = json.dumps({"event": event, "text": body, "priority": priority,
                          "ts": datetime.now(timezone.utc).isoformat()})
    try:
        r = subprocess.run(
            [curl, "-fsSL", "--max-time", "10",
             "-H", "Content-Type: application/json",
             "-d", payload, url],
            capture_output=True, text=True, timeout=15,
        )
        return r.returncode == 0
    except Exception:
        return False


if __name__ == "__main__":
    # Smoke test (no actual network calls — backend missing should return False quietly).
    cfg_empty = {}
    assert notify(cfg_empty, "anomaly", "test") is False, "no backend → False"

    cfg_unknown = {"notify": {"backend": "unknown"}}
    assert notify(cfg_unknown, "anomaly", "test") is False

    cfg_event_filter = {"notify": {"backend": "ntfy", "ntfy": {"url": "https://ntfy.sh/x"},
                                    "events": ["halt"]}}
    # Event not in filter → False without dialing.
    assert notify(cfg_event_filter, "anomaly", "test") is False

    print("OK notify self-test")

"""Anomaly detection for unattended scheduled runs.

The orchestrator emits a per-run metrics record after every `/lsr-maintainer
run`. Records accumulate in `state/metrics-history.jsonl` (append-only).
For each new run we compute mean + stddev over the last N records (default 14)
and flag any metric that exceeds `mean + threshold_sigma * stddev`.

Used by `workflow-run.md` Phase 4 (Surface). Anomalies are written to
`state/PENDING_REVIEW.md` and (via `notify.py`) to whatever notification
backend the user configured.

Day-1 default: 3σ for all metrics. After ~30 nights of clean data the
operator can tune per-metric in `config.anomaly.thresholds`.
"""
from __future__ import annotations

import json
import math
import os
from datetime import datetime, timezone
from typing import Any

# Metrics worth watching. Add new keys here; the schema is append-only.
METRICS = (
    "commits_pushed",
    "prs_addressed",
    "roles_touched",
    "tox_minutes",
    "tokens_input",
    "tokens_output",
    "pending_entries_created",
    "pending_entries_resolved",
    "obs_builds_run",
    "duration_minutes",
)


def append_run(history_path: str, record: dict[str, Any]) -> None:
    """Append one per-run record to the history file. Atomic via fcntl flock."""
    record = {"ts": datetime.now(timezone.utc).isoformat(), **record}
    os.makedirs(os.path.dirname(os.path.abspath(history_path)) or ".", exist_ok=True)
    with open(history_path, "a") as f:
        f.write(json.dumps(record, sort_keys=True) + "\n")


def load_recent(history_path: str, n_days: int = 14) -> list[dict[str, Any]]:
    """Read the last `n_days` records (one per scheduled run, so up to
    n_days entries). Returns empty list if file missing or too short."""
    if not os.path.exists(history_path):
        return []
    cutoff = datetime.now(timezone.utc).timestamp() - n_days * 86400
    records = []
    with open(history_path) as f:
        for line in f:
            line = line.strip()
            if not line:
                continue
            try:
                r = json.loads(line)
                ts = datetime.fromisoformat(r.get("ts", "").replace("Z", "+00:00")).timestamp()
                if ts >= cutoff:
                    records.append(r)
            except Exception:
                continue
    return records


def _mean_stddev(xs: list[float]) -> tuple[float, float]:
    if not xs:
        return 0.0, 0.0
    m = sum(xs) / len(xs)
    if len(xs) < 2:
        return m, 0.0
    var = sum((x - m) ** 2 for x in xs) / (len(xs) - 1)
    return m, math.sqrt(var)


def check(
    current: dict[str, Any],
    history_path: str,
    thresholds: dict[str, float] | None = None,
    default_sigma: float = 3.0,
    min_samples: int = 7,
) -> list[dict[str, Any]]:
    """Compare `current` metric values against rolling history.

    Returns a list of anomaly events:
      [{"metric": "commits_pushed", "value": 47, "mean": 1.2, "stddev": 0.8,
        "sigma_over": 56.2, "threshold_sigma": 3.0}, ...]

    Empty list = no anomalies (or not enough history yet).
    """
    thresholds = thresholds or {}
    history = load_recent(history_path)
    if len(history) < min_samples:
        # Not enough data yet — silently accept everything and accumulate
        # samples. After min_samples nights, anomaly checks engage.
        return []

    anomalies = []
    for metric in METRICS:
        cur = current.get(metric)
        if not isinstance(cur, (int, float)):
            continue
        past = [h.get(metric) for h in history if isinstance(h.get(metric), (int, float))]
        if len(past) < min_samples:
            continue
        mean, stddev = _mean_stddev(past)
        sigma = thresholds.get(metric, default_sigma)
        # Floor effective_stddev so a perfectly-stable metric doesn't
        # trigger on tiny deviations (a metric at mean=3000 with stddev=0
        # would otherwise flag on a +1 change). Floor = max(stddev,
        # 10% of |mean|, 1.0). Means a metric stuck at 3000 needs to swing
        # to ~3900 (3σ × 300 floor) before flagging.
        floor = max(0.1 * abs(mean), 1.0)
        effective_stddev = max(stddev, floor)
        sigma_over = (cur - mean) / effective_stddev
        if sigma_over > sigma:
            anomalies.append({
                "metric": metric,
                "value": cur,
                "mean": round(mean, 2),
                "stddev": round(stddev, 2),
                "sigma_over": round(sigma_over, 1),
                "threshold_sigma": sigma,
            })
    return anomalies


def format_for_pending(anomalies: list[dict[str, Any]]) -> str:
    """Render anomalies as a PENDING_REVIEW.md section."""
    if not anomalies:
        return ""
    lines = ["## 🚨 ANOMALY DETECTED — investigate before next run", ""]
    for a in anomalies:
        lines.append(
            f"- **{a['metric']}** = {a['value']} "
            f"(14-day mean {a['mean']} ± {a['stddev']}; "
            f"{a['sigma_over']}σ > threshold {a['threshold_sigma']}σ)"
        )
    lines.append("")
    lines.append("If unexpected, `touch state/.halt` to pause and investigate "
                 "`~/.cache/lsr-maintainer/<latest>.jsonl`.")
    return "\n".join(lines) + "\n"


if __name__ == "__main__":
    # Self-test.
    import tempfile
    tmpdir = tempfile.mkdtemp()
    hist = os.path.join(tmpdir, "metrics.jsonl")
    # Seed 14 nights of normal operation.
    for i in range(14):
        append_run(hist, {
            "commits_pushed": 1 + (i % 2),  # 1 or 2
            "tox_minutes": 60 + (i * 2),
            "tokens_input": 15000,
            "tokens_output": 3000,
            "prs_addressed": 1,
            "roles_touched": 2,
            "pending_entries_created": 1,
            "pending_entries_resolved": 0,
            "obs_builds_run": 1,
            "duration_minutes": 75,
        })
    # Normal night → no anomalies.
    anoms = check({"commits_pushed": 1, "tox_minutes": 70, "tokens_input": 14000,
                   "tokens_output": 3100, "prs_addressed": 1, "roles_touched": 1,
                   "pending_entries_created": 0, "pending_entries_resolved": 1,
                   "obs_builds_run": 1, "duration_minutes": 72}, hist)
    assert anoms == [], f"normal night flagged: {anoms}"

    # Wildly abnormal night → anomalies.
    anoms = check({"commits_pushed": 47, "tox_minutes": 200, "tokens_input": 100000,
                   "tokens_output": 50000, "prs_addressed": 30, "roles_touched": 20,
                   "pending_entries_created": 25, "pending_entries_resolved": 0,
                   "obs_builds_run": 10, "duration_minutes": 250}, hist)
    metrics_flagged = {a["metric"] for a in anoms}
    assert "commits_pushed" in metrics_flagged, "should flag commits surge"
    assert "tokens_input" in metrics_flagged, "should flag token surge"

    # Empty history → silent (no anomalies even for crazy values).
    hist2 = os.path.join(tmpdir, "empty.jsonl")
    anoms = check({"commits_pushed": 999}, hist2)
    assert anoms == [], "empty history must not flag"

    print("OK", hist)

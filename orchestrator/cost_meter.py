"""Token cost metering for the cron wrapper (issue #19).

`bin/lsr-maintainer-run.sh` writes a stream-json transcript per run at
`~/.cache/lsr-maintainer/<ts>.jsonl`. Each message in the transcript
contains usage info (input_tokens, output_tokens, cache hits). This module
sums them, applies current Claude Opus pricing, and emits a one-line cost
summary.

Operator surfaces:
  - bin/lsr-maintainer-run.sh appends the cost summary to the run summary
  - state/cost-history.jsonl accumulates per-run records for trend analysis
  - PENDING_REVIEW.md (Phase 4) includes a 7-day rolling sum

Pricing is approximate (per million tokens, USD). Update CLAUDE_OPUS_PRICING
when Anthropic changes pricing or you switch model.
"""
from __future__ import annotations

import json
import os
import sys
from datetime import datetime, timezone
from typing import Any

# Per-million-token USD pricing. Adjust when pricing or model changes.
# Source: https://www.anthropic.com/pricing (Opus tier)
CLAUDE_OPUS_PRICING = {
    "input_per_mtok":               15.00,
    "output_per_mtok":              75.00,
    "cache_write_5m_per_mtok":      18.75,
    "cache_write_1h_per_mtok":      30.00,
    "cache_read_per_mtok":           1.50,
}


def parse_transcript(path: str) -> dict[str, int]:
    """Sum token usage across all messages in a stream-json transcript.

    Returns a dict with input_tokens, output_tokens, cache_read_input_tokens,
    cache_creation_input_tokens. Zero for any field absent. Returns all zeros
    if the file is missing/empty/unparseable.
    """
    totals = {
        "input_tokens":                  0,
        "output_tokens":                 0,
        "cache_read_input_tokens":       0,
        "cache_creation_input_tokens":   0,
    }
    if not os.path.exists(path):
        return totals
    with open(path) as f:
        for line in f:
            line = line.strip()
            if not line:
                continue
            try:
                event = json.loads(line)
            except json.JSONDecodeError:
                continue
            # Stream-json events nest usage under different keys depending on
            # event type. Look in the obvious places.
            usage = (
                event.get("usage")
                or event.get("message", {}).get("usage")
                or event.get("response", {}).get("usage")
                or {}
            )
            for k in totals:
                v = usage.get(k)
                if isinstance(v, int):
                    totals[k] += v
    return totals


def estimate_cost(usage: dict[str, int]) -> float:
    """Compute USD cost using CLAUDE_OPUS_PRICING. Cache-creation uses the
    5m tier (worst case). Returns float USD."""
    p = CLAUDE_OPUS_PRICING
    cost = (
        usage.get("input_tokens", 0)                / 1_000_000 * p["input_per_mtok"]
        + usage.get("output_tokens", 0)             / 1_000_000 * p["output_per_mtok"]
        + usage.get("cache_creation_input_tokens", 0) / 1_000_000 * p["cache_write_5m_per_mtok"]
        + usage.get("cache_read_input_tokens", 0)   / 1_000_000 * p["cache_read_per_mtok"]
    )
    return round(cost, 4)


def append_history(history_path: str, record: dict[str, Any]) -> None:
    """Append a per-run cost record to state/cost-history.jsonl."""
    record = {"ts": datetime.now(timezone.utc).isoformat(), **record}
    os.makedirs(os.path.dirname(os.path.abspath(history_path)) or ".", exist_ok=True)
    with open(history_path, "a") as f:
        f.write(json.dumps(record, sort_keys=True) + "\n")


def summary_line(usage: dict[str, int], cost_usd: float) -> str:
    """One-line cost summary suitable for the cron summary file."""
    return (
        f"tokens: in={usage['input_tokens']:,} "
        f"out={usage['output_tokens']:,} "
        f"cache_read={usage['cache_read_input_tokens']:,} "
        f"cache_write={usage['cache_creation_input_tokens']:,} "
        f"cost=${cost_usd:.4f}"
    )


def main():
    """CLI usage:  python3 -m orchestrator.cost_meter <transcript.jsonl> [<history.jsonl>]
    Prints a one-line summary; appends to history if a path is given."""
    if len(sys.argv) < 2:
        print("usage: cost_meter.py <transcript.jsonl> [<history.jsonl>]", file=sys.stderr)
        sys.exit(2)
    transcript = sys.argv[1]
    history = sys.argv[2] if len(sys.argv) > 2 else None
    usage = parse_transcript(transcript)
    cost = estimate_cost(usage)
    print(summary_line(usage, cost))
    if history:
        append_history(history, {"transcript": transcript, "usage": usage, "cost_usd": cost})


if __name__ == "__main__":
    # Self-test when no args given.
    if len(sys.argv) == 1:
        import tempfile
        tmpdir = tempfile.mkdtemp()
        # Synthesize a tiny transcript.
        t = os.path.join(tmpdir, "transcript.jsonl")
        with open(t, "w") as f:
            f.write(json.dumps({"type": "message_start", "message": {
                "usage": {"input_tokens": 10000, "output_tokens": 2000}
            }}) + "\n")
            f.write(json.dumps({"type": "message_delta", "usage": {
                "input_tokens": 0, "output_tokens": 500,
                "cache_read_input_tokens": 5000,
            }}) + "\n")
        usage = parse_transcript(t)
        assert usage["input_tokens"] == 10000
        assert usage["output_tokens"] == 2500
        assert usage["cache_read_input_tokens"] == 5000
        cost = estimate_cost(usage)
        # input: 10k * $15 / 1M = $0.15
        # output: 2.5k * $75 / 1M = $0.1875
        # cache_read: 5k * $1.5 / 1M = $0.0075
        # total ≈ 0.345
        assert 0.34 < cost < 0.35, f"unexpected cost: {cost}"
        print("OK", t, "cost=$", cost)
    else:
        main()

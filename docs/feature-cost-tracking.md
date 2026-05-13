# Feature: Cost tracking

Per-run dollar cost from token usage. Lives in `orchestrator/cost_meter.py`. Already in place; documented here so operators can find it.

## How it works

`bin/lsr-maintainer-run.sh` wraps each nightly invocation in `claude -p ... --output-format stream-json`. The full transcript writes to `<paths.log_dir>/<timestamp>.jsonl` (default `./var/log/`). At Phase 4 of `workflow-run.md`, the orchestrator calls `cost_meter.summary()` on that transcript and appends one line per run to `state/cost-history.jsonl`.

## What's tracked

Parsed from each `assistant`-role JSONL line's `message.usage`:

| Field | Source |
|---|---|
| `input_tokens` | non-cached input |
| `output_tokens` | model output |
| `cache_creation_input_tokens` | first-write to prompt cache (5-min tier) |
| `cache_read_input_tokens` | hits on prompt cache |

Pricing (Claude Opus, January 2026 list):

| Token kind | $/Mtok |
|---|---|
| input (uncached) | 15.00 |
| output | 75.00 |
| cache creation (5-min) | 18.75 |
| cache read | 1.50 |

Override pricing for a different model by editing the `PRICING` dict at the top of `cost_meter.py`.

## Output format

`state/cost-history.jsonl` (append-only, one line per run):

```json
{"ts":"2026-05-12T03:07:01+00:00","transcript":"var/log/20260512T030701.jsonl","input_tokens":12500,"output_tokens":3400,"cache_creation_input_tokens":8200,"cache_read_input_tokens":54000,"cost_usd":0.642}
```

## Where it surfaces

- One-line summary printed to stdout by `bin/lsr-maintainer-run.sh` after the agent exits.
- 7-day rolling sum included in `state/PENDING_REVIEW.md` (via `orchestrator/anomaly.py` reading the same history file).
- Anomalous spikes (cost > 3σ of trailing 14 days) trigger `notify(event="anomaly")` and optionally set `state/.halt` (kill switch). Configure via `config.anomaly`.

## Manual queries

```bash
# Last 7 runs
tail -n 7 state/cost-history.jsonl | jq -r '"\(.ts)  $\(.cost_usd|tostring|.[:5])  \(.transcript)"'

# 30-day total
python3 -c "
import json, datetime
cut = (datetime.datetime.now(datetime.timezone.utc).timestamp() - 30*86400)
total = 0
for line in open('state/cost-history.jsonl'):
    r = json.loads(line)
    if datetime.datetime.fromisoformat(r['ts']).timestamp() >= cut:
        total += r['cost_usd']
print(f'30d total: \${total:.2f}')
"
```

## Why not a third-party tool?

OpenLLMetry, langfuse, helicone, etc. all require an HTTP gateway between the agent and Anthropic — that's a credential-handling surface area we explicitly don't want. The `cost_meter.py` approach parses the transcript JSONL that Claude Code already writes, no extra moving parts.

## Tuning

- Change anomaly sensitivity: `config.anomaly.default_sigma` (default 3.0).
- Add per-metric override: `config.anomaly.thresholds.cost_usd = 5.0` (require 5σ for cost).
- Disable anomaly auto-halt: `config.anomaly.auto_halt_on_anomaly: false` (default).
- Pause cost tracking entirely: remove the `cost_meter.summary()` call from `bin/lsr-maintainer-run.sh` (the orchestrator code path stays — it's defensive against missing history).

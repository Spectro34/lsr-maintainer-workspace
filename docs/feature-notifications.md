# Feature: Out-of-band notifications

The agent calls you out-of-band when something needs attention — review board rejection, OBS build red, host-lock tripped, daily summary, anomaly. Lives in `orchestrator/notify.py`. Opt-in via `state/config.json::notify`.

## Backends

Pick one. All fail silently if misconfigured — never aborts a run.

### `ntfy` — easiest

Zero-config pubsub. Pick a long random topic; that's your private channel.

```json
"notify": {
  "backend": "ntfy",
  "events": ["reject", "anomaly", "halt", "host_lock_mismatch", "daily_summary"],
  "ntfy": {"url": "https://ntfy.sh/lsr-spectro-7f3a2c1b", "priority": "default"}
}
```

Install the [ntfy phone app](https://ntfy.sh), subscribe to the topic. Done.

### `email`

Uses the system mailer (msmtp / sendmail / mail). Configure msmtp once (`~/.msmtprc`), then:

```json
"notify": {
  "backend": "email",
  "events": ["reject", "halt", "host_lock_mismatch"],
  "email": {"to": "you@example.com"}
}
```

### `webhook`

Slack / Discord / Mattermost / custom HTTP endpoint. POST a JSON body.

```json
"notify": {
  "backend": "webhook",
  "events": ["reject", "halt", "host_lock_mismatch"],
  "webhook": {"url": "https://hooks.slack.com/services/.../..."}
}
```

The body shape:

```json
{"event": "halt", "text": "[halt] kill switch engaged: anomaly check tripped at 03:10", "priority": "high", "ts": "2026-05-12T01:10:23+00:00"}
```

## Event kinds

**Critical (always notify by default):**

| Event | Fires when | Priority |
|---|---|---|
| `reject` | Review board rejected a patch — needs human triage | default |
| `anomaly` | Run metric exceeded `mean + 3σ` (cost, duration, etc.) | high |
| `doctor_red` | Pre-flight failed (auth broken, tox venv gone, etc.) | high |
| `halt` | Kill switch engaged (`state/.halt` written) | high |
| `host_lock_mismatch` | `config.security.enforce_host_lock` tripped | high |

**Milestones (per-action progress, default on — gives live visibility for manual runs):**

| Event | Fires when | Priority | Typical count/run |
|---|---|---|---|
| `commit_pushed` | bug-fix-implementer pushed to a fork branch | default | 0–N |
| `fork_created` | fork-sync-checker created a new fork for a managed role | default | 0–5 |
| `enable_role_complete` | `new-role-enabler` returned a verdict (success or failure) | default / high | 0–1 |
| `human_action_needed` | `state/PENDING_REVIEW.md` gained a `manual_triage` item | high | 0–1 |

**Heartbeat (default on — useful for "is it still running?"):**

| Event | Fires when | Priority |
|---|---|---|
| `run_started` | After acquiring run lock (Phase 0 end) | low |
| `run_completed` | Full nightly path finished cleanly (Phase 5 end) | low |

**Summaries (1× per run):**

| Event | Fires when | Priority |
|---|---|---|
| `daily_summary` | Every clean run, one-line metrics | low |
| `fork_sync_summary` | End of Phase 2: batched fork-sync results | low / default |

**Typical night**: 5–10 pings (1 `run_started`, 1–5 fork events, 0–N `commit_pushed`, 1 `fork_sync_summary`, 1 `run_completed`, plus any critical events). Filter by editing `config.notify.events` — remove a kind to silence it. To minimize noise: keep only `reject`, `human_action_needed`, `halt`, `anomaly` and you'll only hear from the agent when something needs you.

## Why opt-in?

- ntfy is centralized (free public). Some operators don't want that.
- email requires a working mailer.
- webhooks may leak workflow details into Slack/Discord scrollback.

So nothing dials out unless you explicitly set `backend`.

## Backend health

```bash
# Smoke-test the backend without changing anything:
python3 -c "
import json, sys; sys.path.insert(0, '.')
from orchestrator.config import load_config
from orchestrator.notify import notify
cfg = load_config('state/config.json')
ok = notify(cfg, 'daily_summary', 'lsr-maintainer notify smoke-test', priority='low')
print('OK' if ok else 'no-op or failure (check config.notify)')
"
```

## Operationally

- `notify()` calls are best-effort. A 5xx from ntfy or a broken mailer does NOT abort the run.
- The transcript log still captures everything, so a missed notification doesn't lose information — just delays operator awareness.
- All notify calls go through `notify.py`; hooks never call it. Add new event kinds by editing `EVENT_KINDS` in `notify.py` AND adding the trigger in `workflow-run.md` Phase 4.

## Tradeoff

ntfy public topics are unauthenticated. If your topic name leaks (e.g. via a notification screenshot), anyone can publish to it. Self-host ntfy if that matters — `ntfy.url` accepts any ntfy-compatible server.

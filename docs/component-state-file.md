# Component: State file

Single JSON file at `state/.lsr-maintainer-state.json`. Source of truth across scheduled runs. Atomic writes (temp file + rename) by `orchestrator/state_schema.py`.

## Schema

```json
{
  "version": 1,
  "last_run_started_at":   "2026-05-12T03:07:00+02:00",
  "last_run_completed_at": "2026-05-12T04:33:12+02:00",
  "queue": [
    {
      "id": "pr-Spectro34-sudo-12",
      "priority": 0,
      "kind": "reviewer_change_requested",
      "pr": {"repo": "linux-system-roles/sudo", "number": 12, "head": "Spectro34:fix/suse-support", "url": "..."},
      "comments_text": "...",
      "discovered_at": "2026-05-11T22:14:00+02:00"
    }
  ],
  "roles": {
    "sudo": {
      "upstream_default_branch": "main",
      "last_seen_upstream_sha": "abc123",
      "fork_branch": "fix/suse-support",
      "patched_files": ["library/scan_sudoers.py", "meta/main.yml"],
      "last_local_test": {
        "sle-16":  {"sha": "7e47081", "result": "PASS", "at": "2026-04-02"},
        "leap-16.0": {"sha": "7e47081", "result": "PASS", "at": "2026-04-02"}
      },
      "pr_cursors": {
        "12": {"last_seen_comment_id": 9876543, "last_seen_review_id": 555, "last_seen_status_sha": "abc..."}
      }
    }
  },
  "obs": {
    "ansible-linux-system-roles": {
      "last_check":       "2026-05-11T03:09:00+02:00",
      "last_build_state": "succeeded"
    },
    "managed_roles": [
      {"name": "firewall", "version": "1.8.2", "sle16_only": false},
      {"name": "certificate", "version": "1.3.11", "sle16_only": true}
    ],
    "manifest_last_synced": "2026-05-11T03:09:00+02:00"
  },
  "host": {
    "fingerprint":       "sha256:abcd...",
    "bootstrapped_at":   "2026-05-08T09:00:00+02:00",
    "components_ready":  {
      "system_packages": true,
      "lsr_agent_symlink": true,
      "tox_venv": true,
      "qemu_images": {"sle-16": true, "leap-16.0": true},
      "gh_auth": true,
      "osc_auth": true,
      "cron_registered": true
    }
  },
  "pending_review_count": 3
}
```

## API

See `orchestrator/state_schema.py`:

```python
from orchestrator.state_schema import load_state, save_state, enqueue, pop_next, remove

state = load_state("state/.lsr-maintainer-state.json")
enqueue(state, {"id": "abc", "kind": "ci_failed", "pr": {...}})
top  = pop_next(state)
save_state("state/.lsr-maintainer-state.json", state)
```

## Concurrency

The orchestrator is single-threaded with respect to writes — only one `claude -p` instance is expected to be running at a time (cron entry fires nightly; ad-hoc `make run` is gated by the user). State writes are atomic so a SIGKILL mid-write doesn't corrupt the file (only the temp file is lost).

## Migration policy

When `STATE_VERSION` bumps in `state_schema.py`, `_migrate()` runs once and persists the upgraded format. Old versions are preserved as `<path>.bak` if the JSON failed to parse.

## What state never contains

- Credentials (tokens, passwords, key contents).
- Full file contents from tox logs (paths only — logs at `state/cache/tox-logs/`).
- Per-commit diffs (Git remembers those).
- User PII beyond the GitHub/OBS login already public.

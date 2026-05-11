# Component: State file

Single JSON file at `state/.lsr-maintainer-state.json`. Source of truth across scheduled runs. Atomic writes (temp file + rename) by `orchestrator/state_schema.py`.

## Schema

```json
{
  "version": 1,
  "last_run_started_at":   "2026-05-12T03:07:00+02:00",
  "last_run_completed_at": "2026-05-12T04:33:12+02:00",
  "last_run_aborted":      false,
  "queue": [
    {
      "id": "pr-${github_user}-sudo-12",
      "priority": 0,
      "kind": "reviewer_change_requested",
      "pr": {"repo": "linux-system-roles/sudo", "number": 12, "head": "${github_user}:fix/suse-support", "url": "..."},
      "comments_text": "...",
      "discovered_at": "2026-05-11T22:14:00+02:00"
    }
  ],
  "roles": {
    "sudo": {
      "role": "sudo",
      "version": "1.5.2",
      "sle16_only": false,
      "upstream_default_branch": "main",
      "last_seen_upstream_sha": "abc123",
      "fork_branch": "fix/suse-support",
      "fork_repo": "${github_user}/sudo",
      "upstream_repo": "linux-system-roles/sudo",
      "patched_files": ["library/scan_sudoers.py", "meta/main.yml"],
      "last_local_test": {
        "sle-16":   {"sha": "7e47081", "result": "PASS", "at": "2026-04-02", "image": "SLES-16.0-Minimal-VM...qcow2", "via": "native"},
        "leap-16.0":{"sha": "7e47081", "result": "PASS", "at": "2026-04-02", "image": "Leap-16.0-Minimal-VM...qcow2", "via": "native"}
      },
      "pr_cursors": {
        "12": {"last_seen_comment_id": 9876543, "last_seen_review_id": 555, "last_seen_status_sha": "abc..."}
      },
      "fix_attempts_by_pr": {"12": 1}
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
from orchestrator.state_schema import (
    load_state, save_state, enqueue, pop_next, remove, state_lock,
    default_role_entry, seed_roles_from_manifest,
)

# Always wrap mutations in a state_lock to serialize cron-vs-manual runs.
STATE_PATH = "state/.lsr-maintainer-state.json"
with state_lock(STATE_PATH, timeout_sec=30.0):
    state = load_state(STATE_PATH)
    enqueue(state, {"id": "abc", "kind": "ci_failed", "pr": {...}})
    top = pop_next(state)
    save_state(STATE_PATH, state)
# Lock auto-released on context exit.

# Seed per-role entries from OBS manifest + config.tracked_extra_roles
seed_roles_from_manifest(
    state,
    managed_roles=[{"name": "firewall", "version": "1.8.2", "sle16_only": False}, ...],
    github_user="alice",
    fork_branch="fix/suse-support",
    tracked_extra_roles=["sudo", "kernel_settings", ...],
)
```

## Concurrency

`state_lock` is an `fcntl.LOCK_EX` advisory lock on `<state-path>.lock`. It serializes the full read-modify-write block of a `/lsr-maintainer run` to prevent cron-vs-manual collisions from clobbering each other's queue mutations.

- **Timeout default**: 30 seconds. The orchestrator catches `TimeoutError` and exits cleanly (cron retries next slot).
- **Atomicity per write**: `save_state()` uses temp-file + `os.replace` regardless of locking, so a SIGKILL mid-write doesn't corrupt the file.
- **Pairs with the run-pidfile**: Phase 0 of `workflow-run.md` writes `state/.run.pid` and refuses to start if a fresh one exists. The pidfile catches most races; the flock is the second layer for the rare case where two processes pass the pidfile check simultaneously.

## Migration policy

When `STATE_VERSION` bumps in `state_schema.py`, `_migrate()` runs once and persists the upgraded format. Old versions are preserved as `<path>.bak` if the JSON failed to parse.

## What state never contains

- Credentials (tokens, passwords, key contents).
- Full file contents from tox logs (paths only — logs at `state/cache/tox-logs/`).
- Per-commit diffs (Git remembers those).
- User PII beyond the GitHub/OBS login already public.

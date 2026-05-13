# Architecture

## High-level dataflow

```
┌─ cron (03:07 nightly local) ──────────────────────────────────┐
│   bin/lsr-maintainer-run.sh                                   │
│   └─ claude -p "/lsr-maintainer run"                          │
└──────────────────────┬────────────────────────────────────────┘
                       ▼
              ┌─────────────────┐
              │ /lsr-maintainer │  orchestrator skill
              │   SKILL.md      │
              └────────┬────────┘
        ┌──────────────┼──────────────────┐
        ▼              ▼                  ▼
   state/             projects/           Skill()
   .lsr-maint-        lsr-agent/          obs-package-
   ainer-state        obs-package-skill/  skill (delegated)
   .json              osc-mcp/            
                       │
                       │  spawn sub-agents (parallel where safe)
   ┌───────────────────┼────────────────────────────────────────┐
   ▼              ▼               ▼              ▼              ▼
pr-status     upstream-       manifest-       bug-fix-       obs-package-
poller        drift-watcher   syncer          implementer    maintainer
   │              │               │              │              │
   └─events──>────┴───events──>───┘              ▼              │
                       │              ┌──── Review Board ───┐  │
                       │              │ (4 parallel agents) │  │
                       │              ├─ reviewer-correctness │
                       │              ├─ reviewer-cross-os    │
                       │              ├─ reviewer-upstream-st │
                       │              └─ reviewer-security    │
                       │                       │
                       │                       ▼
                       │              multi-os-regression-
                       │              guard (tox matrix)
                       │                       │
                       │                       ▼
                       │              git push origin fix/...
                       │                       │
                       ▼                       ▼
              state/PENDING_REVIEW.md    LSR_PROGRESS.md
                       │                       │
                       └───────────┬───────────┘
                                   ▼
                          user reads in morning,
                           opens PRs by hand
```

## Why submodules

Each managed project (`lsr-agent`, `obs-package-skill`, `osc-mcp`) is its own repo with its own commit history, remotes, and CI. The workspace pins each to a known-good ref via `.gitmodules`. Editing a sub-project still happens inside that submodule (push to its own remote); the workspace just records the new pin via `make sync-projects`.

This avoids two anti-patterns:

- **Monolith** that copies the skill code in and loses the bidirectional flow with the source repo.
- **Loose coordination** across scattered `~/github/<various>/` directories where there's no single command to operate the system. (The workspace's own runtime data — clones, ISOs, worktrees, venv — now lives self-contained in `./var/` for the same reason: one tree, one wipe-with-`rm -rf`.)

## Smart sub-agent routing

The orchestrator follows a deterministic policy (documented inline in `SKILL.md`) for when to spawn sub-agents vs handle inline:

| Decision | When | Why |
|---|---|---|
| Inline | small read, single decision, no write | spawning overhead exceeds the saving |
| Sub-agent | log >5K tokens, large source tree, specialist persona | context isolation, reuse of specialist framing |
| Parallel sub-agents | 2+ items with no data dependency | wall-clock win; example: review board |
| Sequential sub-agents | writes to the same worktree | avoid concurrent file mutation |

Cap: 6 concurrent sub-agents (prevents tox-QEMU resource starvation, stays under per-session limits).

## Review board

Every patch from `bug-fix-implementer` runs through 4 reviewers in parallel before the tox regression matrix:

1. **reviewer-correctness** — does the diff fix the stated problem?
2. **reviewer-cross-os-impact** — does it break SLE 15 / Leap 15 / RHEL?
3. **reviewer-upstream-style** — does it follow LSR conventions (set_vars pattern, vars/ layout, meta platforms)?
4. **reviewer-security** — does it introduce shell injection, world-writable files, broad firewall opens, credential templates?

Verdict merge:

- All `pass` → run regression matrix.
- Any `reject` → revert worktree, surface to PENDING_REVIEW.md.
- Any `concerns` → spawn `bug-fix-implementer` once more with the concerns; cap at 2 iterations.

Review fires **before** tox tests (cheap reviewers fail fast). Regression matrix runs only if review is clean.

## State

Single JSON file at `state/.lsr-maintainer-state.json`. Atomic writes (temp file + rename). Schema versioned.

Concurrency: every `/lsr-maintainer run` wraps its full read-modify-write in `state_lock` (an `fcntl.LOCK_EX` advisory lock on `<state>.lock`). Cron-vs-manual collisions are serialized; the second runner times out after 30s and exits cleanly. Paired with the run-pidfile in workflow-run.md Phase 0 for defense in depth.

Identity is NOT in state — it's in `state/config.json` (separate file, also gitignored). See [docs/component-config.md](docs/component-config.md) for the config schema and detection flow.

See [docs/component-state-file.md](docs/component-state-file.md).

## Security boundary

Three layers:

1. **`.claude/settings.json` permission deny** — pattern-based, fast.
2. **`.claude/hooks/block-upstream-actions.sh`** — re-parses commands with shell-quoting awareness, resolves git remotes to URLs, blocks at the tool-input level.
3. **`.claude/hooks/block-credential-leak.sh`** — blocks reads and echoes of credential paths and secret-y env vars.

Plus a SessionStart `scrub-env.sh` that unsets secret env vars before any sub-agent spawns.

See [SECURITY.md](SECURITY.md) and [docs/component-hooks.md](docs/component-hooks.md).

## Schedule and lifecycle

- **Trigger**: cron, nightly at `config.schedule.cron_time` (default `7 3 * * *`, 03:07 local). `install-cron.sh` emits a `CRON_TZ=` line derived from `timedatectl` so the entry fires at LOCAL time even when systemd-cron defaults to UTC. Override via `LSR_CRON_TIME` / `LSR_CRON_TZ` envs.
- **Doctor pre-flight**: every run starts with `bash bin/doctor.sh` (10 checks in pure bash, sub-second). Aborts cleanly if any red item is present. `bin/lsr-maintainer-run.sh` is the actual entry point.
- **Time budget**: default 90 min per run from `config.schedule.time_budget_minutes`; per-item soft caps from `config.schedule.per_item_budgets`.
- **Resumability**: state is the source of truth across runs. Each run reads `last_run_completed_at`, `last_run_aborted`, the priority queue, per-PR cursors, per-role tested-SHAs. A missed run picks up where the last successful one left off.
- **Identity**: read from `state/config.json` at the start of every run. Pre-init (empty `github.user`) makes all hooks treat every write as upstream — uninitialized = safest state.

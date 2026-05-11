# Workflow: `/lsr-maintainer run`

This is the full nightly autonomous workflow. The orchestrator (SKILL.md) loads this file when `/lsr-maintainer run` fires.

## Preconditions

- Workspace cwd is `lsr-maintainer-workspace/`
- `.claude/settings.json` loaded → security hooks active
- `state/` exists (created by `make install-deps`)

## Phase 0 — Acquire run lock (pidfile)

To prevent cron-vs-manual collisions, use a pidfile pattern that survives across the orchestrator's individual Bash tool calls (which run in separate shell processes — an `flock -n 9 ... 9>file` pattern would not survive).

Orchestrator does this as a Bash call:

```bash
PIDFILE=state/.run.pid
if [ -f "$PIDFILE" ]; then
  OLDPID=$(cat "$PIDFILE" 2>/dev/null)
  if [ -n "$OLDPID" ] && kill -0 "$OLDPID" 2>/dev/null; then
    echo "RUN_LOCK_HELD pid=$OLDPID"
    exit 0
  fi
  # Stale pidfile — previous run crashed. Continue but flag it.
  echo "STALE_PIDFILE pid=$OLDPID"
fi
echo $$ > "$PIDFILE"
echo "RUN_LOCK_ACQUIRED pid=$$"
```

Orchestrator parses the output:

- `RUN_LOCK_HELD` → exit cleanly (cron retries next slot).
- `STALE_PIDFILE` → set `state.last_run_aborted = true` (carry over from previous), surface "previous run crashed" PENDING entry, continue.
- `RUN_LOCK_ACQUIRED` → proceed.

**Cleanup**: Phase 5 explicitly removes `state/.run.pid`. If the orchestrator itself crashes between Phase 0 and Phase 5, the next run sees a stale pidfile and recovers.

Note: the agent's Bash calls each spawn a fresh shell. The pidfile (`$$` written at acquire time) is the PID of *that* shell, not the orchestrator's. That's fine — the next run's `kill -0` check will see that shell is gone (because the orchestrator's overall run finished or crashed, and any leftover shell exited).

For robustness against a coincident PID reuse, we also write a timestamp inside the pidfile and treat it as stale if older than 4 hours (longer than any realistic run including 90-min budget + 30-min image download).

```bash
echo "$$ $(date +%s)" > "$PIDFILE"
# On check:
NOW=$(date +%s)
if [ -f "$PIDFILE" ]; then
  read -r OLDPID OLDTS < "$PIDFILE"
  if [ -n "$OLDPID" ] && [ -n "$OLDTS" ] && \
     kill -0 "$OLDPID" 2>/dev/null && \
     [ $((NOW - OLDTS)) -lt 14400 ]; then
    echo "RUN_LOCK_HELD pid=$OLDPID age=$((NOW - OLDTS))s"
    exit 0
  fi
fi
```

## Phase 1 — Pre-flight (doctor)

Read-only checks. Abort early if anything critical is broken:

1. `state/.lsr-maintainer-state.json` loads (else default_state()).
2. `gh auth status` succeeds.
3. `osc whois` succeeds.
4. tox-lsr venv exists at `~/github/ansible/testing/tox-lsr-venv/`.
5. `git config --global user.email` and `user.name` are set.
6. `projects/lsr-agent/` symlink resolves.

For any 🔴: write a PENDING_REVIEW.md entry with the fix command, then skip the affected phases. (Auth broken → skip PR work; tox missing → skip tests.) Don't abort the whole run.

## Phase 2 — Queue refresh (3 sub-agents in PARALLEL)

Single `Agent()` batch with 3 calls:

```
Agent(prompt=read("agents/pr-status-poller.md"))
Agent(prompt=read("agents/upstream-drift-watcher.md"))
Agent(prompt=read("agents/manifest-syncer.md"))
```

Collect their JSON outputs. Each returns `{events: [...], ...cursor_updates}`.

After manifest-syncer returns its `managed_roles[]`:

```python
from orchestrator.state_schema import seed_roles_from_manifest
seed_roles_from_manifest(state, managed_roles)
```

This ensures every role in the OBS manifest has a per-role entry in `state.roles` with default fields populated (issue #6).

For each event, call `enqueue(state, item)` with a stable `id` derived from event kind + target (so duplicate events across runs don't re-queue).

## Phase 3 — Execute queue items within time budget

Default budget: 90 minutes wall-clock. Per-item soft budgets enforced.

Priority order (auto-sorted by `enqueue`):

| Priority | Kind | Per-item budget | Action |
|---|---|---|---|
| 0 | `reviewer_change_requested` | 15 min | PR-feedback fix path (§3a) |
| 1 | `ci_failed` | 15 min | PR-feedback fix path (§3a) |
| 2 | `obs_build_failure` | 30 min | OBS path (§3b) |
| 3 | `upstream_drift_conflicting` | 15 min | Rebase + regression (§3c) |
| 3 | `enable_role` | 60 min | new-role-enabler (§3d) |
| 4 | `round_robin_health` | 30 min | Single-target tox check (§3e) |

For each item popped:

1. Acquire `(component, target)` lock via `state.locks` JSON field (file-backed). If locked, requeue with later priority.
2. Run the path below.
3. Release lock.
4. If wall-clock budget exceeded, flush state + PENDING + exit.

### 3a — PR-feedback fix path

```
git worktree add state/worktrees/<role>-pr<N>/ <fork-branch>
   ↓
Spawn bug-fix-implementer with:
   role, worktree_path, task_kind="address_review",
   payload={review_comments, reviewer, pr_number}
   ↓
Returns commit_sha + diagnosis (or commit_sha=null=needs human triage)
   ↓
If commit_sha: spawn REVIEW BOARD in parallel (4 agents):
   Agent(reviewer-correctness)
   Agent(reviewer-cross-os-impact)
   Agent(reviewer-upstream-style)
   Agent(reviewer-security)
   ↓
Merge verdicts:
   any reject → revert worktree, PENDING with findings, exit item
   any concerns → re-invoke implementer once with concerns inlined
                  (cap: 2 iterations total; iteration 3+ = PENDING manual)
   all pass    → continue
   ↓
Spawn multi-os-regression-guard:
   role, worktree_path, patch_sha=commit_sha,
   baseline_pass_targets=<from state.roles[role].last_local_test, EXCLUDING via:*-fallback entries>
   ↓
verdict green → git push origin <fork-branch>
   then state.roles[role].pr_cursors[<num>].fix_attempts += 1
   verdict regression/infrastructure_gap → revert + PENDING
```

### 3b — OBS build-failure path

```
Spawn obs-package-maintainer with:
   package=ansible-linux-system-roles,
   obs_project={obs_branch_project},
   failure_context={…last build state…}
   ↓
Returns verdict succeeded/failed/needs_human
   ↓
Update state.obs.<package>.last_build_state
```

### 3c — Upstream-drift rebase

```
git worktree add state/worktrees/<role>-rebase/ <fork-branch>
git fetch upstream
git rebase upstream/<default-branch>
   ↓
If conflicts → PENDING "manual rebase needed for <role>", exit item
If clean → spawn review board on the rebase diff, then regression matrix
If green → git push origin <fork-branch>
```

### 3d — New-role enablement

Delegates to `agents/new-role-enabler.md` workflow. See `workflow-enable-role.md` for the playbook.

### 3e — Round-robin health check

Pick the role in `state.obs.managed_roles` with the oldest `last_local_test["sle-16"].at` (or `last_local_test["leap-16.0"].at` if SLE 16 unavailable). Run `tox-test-runner` against SLE 16 (or fallback). Update state. No commit, no push.

## Phase 4 — Surface

After all queue items processed (or budget exhausted):

```python
from orchestrator.pending_review_render import render
state["pending_review_count"] = sum(1 for q in state["queue"] if q["priority"] < 9)
text = render(state)
with open("state/PENDING_REVIEW.md", "w") as f:
    f.write(text)
```

Append a session block to `projects/lsr-agent/LSR_PROGRESS.md`:

```markdown
## Session 2026-05-12 03:07 (nightly auto)

Queue processed: 3 items
Pushed to forks: 1 ({github_user}/sudo @ fix/suse-support, commit abc123)
OBS rebuilt: 0
New roles enabled: 0
Health checks: 1 (sudo/sle-16 PASS, via fallback to Leap 16)
Pending human action: 2 (see PENDING_REVIEW.md)
```

## Phase 5 — Persist state + release lock

Wrap the entire run in `state_lock` (defined in `orchestrator/state_schema.py`). The lock pairs with the pidfile from Phase 0 — pidfile catches most cron-vs-manual collisions, the flock catches the rare race where two processes pass the pidfile check simultaneously.

```python
from orchestrator.state_schema import load_state, save_state, state_lock

STATE_PATH = "state/.lsr-maintainer-state.json"
try:
    with state_lock(STATE_PATH, timeout_sec=30.0):
        state = load_state(STATE_PATH)
        # ... all phases' mutations happen here within the lock ...
        state["last_run_completed_at"] = datetime.now(timezone.utc).isoformat()
        state["last_run_aborted"] = False
        save_state(STATE_PATH, state)
except TimeoutError:
    # Another /lsr-maintainer run held the lock too long. Exit cleanly;
    # cron retries next slot.
    print("state lock contended — exiting cleanly")
    sys.exit(0)
```

`state_lock` uses `fcntl.LOCK_EX` on `state/.lsr-maintainer-state.json.lock`. `save_state` itself remains atomic (temp file + rename); the lock prevents concurrent read-modify-write from clobbering each other.

Then remove the pidfile so the next run can acquire:

```bash
rm -f state/.run.pid
```

If any earlier Phase aborted with a fatal error, the orchestrator should still try to do these cleanups before exiting — otherwise the next run sees a stale pidfile and processes it. The pidfile timestamp guard (4-hour staleness in Phase 0) plus `state_lock` are the safety nets when cleanup fails entirely.

## Failure modes the orchestrator must handle gracefully

| Condition | Action |
|---|---|
| Sub-agent timeout | Abort sub-agent, mark item `needs_human`, continue queue |
| Sub-agent returns malformed JSON | Surface as PENDING parse-error entry, continue queue |
| `git push` rejected (force-push blocked, branch protected) | Revert worktree, PENDING |
| Disk full while writing logs | Flush state minimally, surface fatal PENDING, exit |
| Network down mid-poll | Skip PR work this run, continue OBS/drift (which use local checkouts) |
| Time budget exhausted | Flush state + PENDING with remaining queue; cron picks up next night |

Never crash. Always leave state coherent.

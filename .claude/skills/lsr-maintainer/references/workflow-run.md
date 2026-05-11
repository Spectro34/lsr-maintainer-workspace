# Workflow: `/lsr-maintainer run`

This is the full nightly autonomous workflow. The orchestrator (SKILL.md) loads this file when `/lsr-maintainer run` fires.

## Preconditions

- Workspace cwd is `lsr-maintainer-workspace/`
- `.claude/settings.json` loaded → security hooks active
- `state/` exists (created by `make install-deps`)

## Phase 0 — Acquire run lock

To prevent cron-vs-manual collisions (M-state, issue #7):

```bash
# Use a PID lockfile + fcntl-flock check
LOCKFILE=state/.run.lock
if ! flock -n 9; then
  echo "another /lsr-maintainer run is in progress (PID $(cat state/.run.pid 2>/dev/null)) — exiting cleanly"
  exit 0
fi 9>"$LOCKFILE"
echo $$ > state/.run.pid
trap 'rm -f state/.run.pid' EXIT
```

The orchestrator should attempt this via `Bash` and refuse to proceed if the lock can't be acquired. Cron retries the next slot.

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
   obs_project=home:Spectro34:branches:devel:sap:ansible,
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
Pushed to forks: 1 (Spectro34/sudo @ fix/suse-support, commit abc123)
OBS rebuilt: 0
New roles enabled: 0
Health checks: 1 (sudo/sle-16 PASS, via fallback to Leap 16)
Pending human action: 2 (see PENDING_REVIEW.md)
```

## Phase 5 — Persist state

```python
from orchestrator.state_schema import save_state
state["last_run_completed_at"] = datetime.now(timezone.utc).isoformat()
save_state("state/.lsr-maintainer-state.json", state)
```

Save is atomic (temp file + rename) per `state_schema.py`. The flock from Phase 0 is released by the trap.

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

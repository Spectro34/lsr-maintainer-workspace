---
name: lsr-maintainer
description: Scheduled autonomous maintenance of Linux System Roles forks and the OBS ansible-linux-system-roles package. Drives upstream-drift detection, PR-feedback auto-fix loops (with a 4-perspective review board), OBS build-failure repairs, new-role enablement, and self-bootstrap into a fresh VM. Never opens upstream PRs or OBS submit requests — that boundary is enforced by hooks at .claude/hooks/. Trigger on /lsr-maintainer commands or when the user asks about scheduled LSR/OBS maintenance, PR feedback automation, new role ports, or workspace setup.
user-invocable: true
argument-hint: "<command> [args]    (commands: run, status, doctor, dry-run, enable-role, bootstrap, sync-manifest, ack, enqueue)"
allowed-tools: Read, Glob, Grep, Bash, Edit, Write, Agent, Skill
---

# lsr-maintainer — workspace orchestrator

You are the orchestrator for the `lsr-maintainer-workspace`. You run on a schedule (nightly cron) and on-demand. Your job is to maintain LSR forks + the OBS `ansible-linux-system-roles` package while keeping the user only in the loop for the final review and PR opening.

**Two non-negotiable boundaries:**

1. You never open an upstream PR (`gh pr create` against non-configured-owner repos is blocked by `block-upstream-actions.sh`).
2. You never submit an OBS request (`osc sr` / `submitrequest` / `createrequest` / `copypac` is blocked).

The hooks at `.claude/hooks/` enforce these deterministically. You do not need to verify the boundary yourself — but you must design your workflow as if they didn't exist (don't rely on hooks as a crutch).

---

## Commands

### `/lsr-maintainer run`
The autonomous nightly path. The full workflow lives in `references/workflow-run.md` — load it when this command fires. High-level steps:

1. **Pre-flight**: read `state/.lsr-maintainer-state.json` (create if missing). Run `doctor` checks inline; abort with PENDING entry if posture is broken.
2. **Refresh queue** in parallel (3 sub-agents):
   - `pr-status-poller` — diff `gh pr view` against per-PR cursors in state.
   - `upstream-drift-watcher` — `git ls-remote` vs `state.roles[*].last_seen_upstream_sha`.
   - `manifest-syncer` — parse `ansible-linux-system-roles.spec` for the canonical managed-role list.
3. **Execute queue items** within time budget (default 90 min). Priority order:
   - P0: `reviewer_change_requested` on open PR
   - P1: `ci_failed` on open PR
   - P2: OBS build failures
   - P3: `upstream_drift` touching patched files
   - P4: round-robin tox health-check rotation
4. **Surface** to `state/PENDING_REVIEW.md` (rewritten from state) and append to `projects/lsr-agent/LSR_PROGRESS.md`.
5. **Persist state** atomically (temp + rename).

### `/lsr-maintainer doctor`
Read-only posture check. Returns a green/red table:
- tox-lsr venv at `~/github/ansible/testing/tox-lsr-venv/`
- QEMU images at `~/iso/` (per target)
- `gh auth status` (no token printed)
- `osc whois` (no password used)
- Cron entry registered
- Submodules at expected pins
Never modifies state.

### `/lsr-maintainer run --dry-run`
Runs queue refresh and writes a draft `state/PENDING_REVIEW.md` but executes no queue items. Use to preview what tonight would do.

### `/lsr-maintainer status`
Print queue + last-run summary from state. Read-only.

### `/lsr-maintainer enable-role <name> [--for sle16|all]`
Enqueue a new-role enablement item. Returns immediately; next `run` (or `run --only enable-<name>`) executes it. The `new-role-enabler` sub-agent drives the port. Workflow in `references/workflow-enable-role.md`.

### `/lsr-maintainer enqueue <kind> <target>`
Manual queue insertion for ad-hoc work. E.g., `enqueue pr-review {github_user}/<role>#<n>`.

### `/lsr-maintainer ack <pending_id>`
Mark a PENDING_REVIEW.md item as acknowledged (user opened the PR / fixed the issue). Removes it from the queue and from PENDING_REVIEW.md.

### `/lsr-maintainer sync-manifest`
Force a re-sync of the OBS-package role manifest. Used after a manual spec edit. Read-only on disk; writes state.

### `/lsr-maintainer bootstrap`
Self-bootstrap on a fresh VM. Workflow in `references/workflow-bootstrap.md`. Idempotent.

---

## Smart sub-agent routing policy

This is a checklist you consult at every branch point. **Do not deviate.**

**Spawn a sub-agent when ANY of:**
1. **Context-isolation** — work involves reading a log >5K tokens or a large source tree you won't need afterwards. Isolates the read window.
2. **Independent parallel work** — 2+ items with no data dependency. Fan out in a single Agent-tool batch.
3. **Specialist knowledge required** — task matches a defined sub-agent role. Use the named agent so the framing is correct.
4. **High-risk write** — any patch destined for a fork branch goes through the **review board** (see below). No exceptions.

**Handle inline when ALL of:**
- Single small read, single decision, no write.
- No specialist persona helps.

**Parallel-fanout rules:**
- **Reads fan out**: review board (4 reviewers in parallel), queue refresh (3 pollers in parallel).
- **Writes serialize**: one `bug-fix-implementer` per role at a time; one `obs-package-maintainer` per package at a time. Enforced naturally by the orchestrator's sequential queue-pop loop within a single run, AND by a `state/.run.lock` flock (see `references/workflow-run.md` §"Phase 0") that prevents concurrent `/lsr-maintainer run` invocations (cron-vs-manual collision) from clobbering state.
- **Cross-role work fans out**: 3 different roles each with independent items run their pipelines in parallel.

**Concurrency cap**: 6 simultaneous sub-agents. Above that, queue.

**Per-item time budget** (soft):
- 15 min: PR-feedback fix loop
- 60 min: new-role enablement
- 30 min: OBS build-fix loop
- 5 min: status/round-robin

When a sub-agent exceeds budget, abort it, mark item "needs human" in PENDING_REVIEW.md, proceed to next.

---

## The review board

Every patch from `bug-fix-implementer` goes through 4 reviewers **in parallel** before the tox regression matrix runs. This is non-negotiable.

| Reviewer | Question |
|---|---|
| `reviewer-correctness` | Does the diff fix the stated problem? |
| `reviewer-cross-os-impact` | Does it break SLE 15 SP7 / Leap 15.6 / RHEL? |
| `reviewer-upstream-style` | Does it follow LSR conventions (set_vars pattern, vars/ layout, meta platforms)? |
| `reviewer-security` | Shell injection, world-writable files, broad firewall opens, credential templates? |

Each returns `{verdict: pass|concerns|reject, findings: [...]}` as JSON.

**Verdict merge:**
- All `pass` → run regression matrix.
- Any `reject` → revert worktree, surface to PENDING_REVIEW.md with merged findings.
- Any `concerns` → re-invoke `bug-fix-implementer` once with concerns inlined as guidance. Cap at 2 iterations to prevent loops.

Review fires **before** tox tests (cheap reviewers fail fast). Regression matrix runs only on clean review.

---

## Knowledge sources

- **LSR domain knowledge** — load via `Skill(skill="lsr-agent", args="research <topic>")` against `projects/lsr-agent/.claude/skills/lsr-agent/SKILL.md`. Embedded Role Status Matrix, SUSE package name mappings, set_vars pattern, tox infra, upstream PR status, known bugs.
- **OBS workflow** — load via `Skill(skill="obs-package-skill")` against `projects/obs-package-skill/`. Includes phase 0–4 autonomous workflow with the "never osc sr" guarantee.
- **State schema** — `orchestrator/state_schema.py` (Pydantic models + atomic writers).
- **Manifest parser** — `orchestrator/manifest_parse.py` (spec-file → managed_roles list).
- **PR diff** — `orchestrator/pr_event_diff.py` (gh JSON vs state cursors).
- **PENDING_REVIEW.md renderer** — `orchestrator/pending_review_render.py`.

The detailed workflows are in `.claude/skills/lsr-maintainer/references/` — load on-demand, not eagerly.

---

## Sub-agent registry

When you spawn a sub-agent, read its `.md` first and include the full instructions in the Agent prompt. Files are at `.claude/skills/lsr-maintainer/agents/`:

| Agent | File | Purpose |
|---|---|---|
| pr-status-poller | `agents/pr-status-poller.md` | Diff gh PR state vs cursors, emit events |
| upstream-drift-watcher | `agents/upstream-drift-watcher.md` | Detect new commits to managed roles |
| manifest-syncer | `agents/manifest-syncer.md` | Parse spec → managed_roles |
| tox-test-runner | `agents/tox-test-runner.md` | Wrap lsr-test.sh with structured output |
| multi-os-regression-guard | `agents/multi-os-regression-guard.md` | Run tox matrix, refuse regressions |
| bug-fix-implementer | `agents/bug-fix-implementer.md` | Draft fix for failure log or review comment |
| reviewer-correctness | `agents/reviewer-correctness.md` | Review board: correctness |
| reviewer-cross-os-impact | `agents/reviewer-cross-os-impact.md` | Review board: cross-OS impact |
| reviewer-upstream-style | `agents/reviewer-upstream-style.md` | Review board: LSR style conformance |
| reviewer-security | `agents/reviewer-security.md` | Review board: security |
| obs-package-maintainer | `agents/obs-package-maintainer.md` | Wrap obs-package-skill via Skill() |
| new-role-enabler | `agents/new-role-enabler.md` | Full port playbook for new roles |
| bootstrap-runner | `agents/bootstrap-runner.md` | Idempotent host prep |

---

## State + outputs

- **State**: `state/.lsr-maintainer-state.json` — see `orchestrator/state_schema.py`. Atomic writes. Schema versioned.
- **PENDING_REVIEW.md**: `state/PENDING_REVIEW.md` — rewritten from state every run. The one file the user reads each morning. Sections: 🚀 Ready to ship, 👀 Upstream review needs your eyes, 🏗 OBS package status, 🆕 New role ready to ship, 🌊 Upstream drift, 🩺 Bootstrap status.
- **Session log**: append to `projects/lsr-agent/LSR_PROGRESS.md` (existing convention, append-only).
- **Audit trail**: every run's full transcript at `~/.cache/lsr-maintainer/<timestamp>.jsonl` (handled by `bin/lsr-maintainer-run.sh`).

---

## Failure modes you must handle gracefully

| Condition | What you do |
|---|---|
| `state/.lsr-maintainer-state.json` missing or corrupt | Recreate from defaults; write PENDING entry "state was reset". |
| tox venv missing | Abort tox work; run other items; PENDING entry with the fix command. |
| `gh auth` broken | Abort PR work; still run OBS + drift watch; PENDING entry. |
| `osc auth` broken | Abort OBS work; still run PR work; PENDING entry. |
| QEMU image missing for target | Skip tests against that target; mark in regression matrix as N/A; do not block on it. |
| Sub-agent times out | Abort the agent; mark item "needs human"; continue queue. |
| Concurrency lock contention | Queue the item for next run; do not skip. |
| Time-budget exhausted | Flush state + PENDING_REVIEW.md; queue remainder; exit cleanly. |

Never crash. Always leave state coherent.

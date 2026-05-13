# Component: Sub-agents

The orchestrator (`.claude/skills/lsr-maintainer/SKILL.md`) spawns these via the Agent tool. Each lives at `.claude/skills/lsr-maintainer/agents/<name>.md` and is loaded by the orchestrator before being passed as the prompt to a sub-agent.

## Registry

| Agent | Type | Inputs | Outputs | Time budget |
|---|---|---|---|---|
| `pr-status-poller` | read-only | open-PR list, cursors | events + cursor updates | 60s |
| `upstream-drift-watcher` | read-only | role list, last-seen-SHA | drift events | 90s |
| `fork-sync-checker` | write (fork creation, fast-forward push) | role list | sync events + `state.roles[*].fork_*` | 2min/role, 10min total |
| `manifest-syncer` | read-only | spec file path | managed_roles[] (OBS-shipped), manifest events | 15s |
| `tox-test-runner` | write (local logs) | role + target | PASS/FAIL/N/A + log path | 30min/test |
| `multi-os-regression-guard` | orchestrator | role + worktree + baseline | per-target verdict | 30–60min |
| `bug-fix-implementer` | write (worktree, local commit) | role + worktree + task | commit SHA + diagnosis | 10min |
| `reviewer-correctness` | read-only | worktree + commit + payload | verdict + findings | 5min |
| `reviewer-cross-os-impact` | read-only | worktree + commit + role | verdict + findings | 5min |
| `reviewer-upstream-style` | read-only | worktree + commit + role | verdict + findings | 5min |
| `reviewer-security` | read-only | worktree + commit + role | verdict + findings | 5min |
| `reviewer-sle-docs` | read-only (WebFetch) | worktree + commit + role + changed_files | verdict + findings (SLE 16 docs alignment) | 90s |
| `obs-package-maintainer` | write (osc commits) | package + project | succeeded/failed/needs-human | 30min |
| `new-role-enabler` | write (worktree, push to fork, stage spec) | role + target_set | enabled/not_viable/etc. | 60min |
| `bootstrap-runner` | write (state, dirs, venv) | none | components_ready + pending_actions | 60s |

## How the orchestrator spawns one

Pattern (from SKILL.md):

```
1. Read .claude/skills/lsr-maintainer/agents/<name>.md
2. Pass full contents as the prompt to Agent(prompt=..., subagent_type=...)
3. Parse the returned JSON
4. Take action based on the verdict
```

## Smart routing decisions

See `SKILL.md` §"Smart sub-agent routing policy". Summary:

- **Inline** when: small read + single decision + no write.
- **Sub-agent** when: large log/source, specialist persona, high-risk write.
- **Parallel fanout** when: reads with no data dependency (review board, queue refresh).
- **Serial** when: writes to same worktree, OBS commits to same package.
- **Cap**: 6 concurrent.

## Per-item time budgets

When a sub-agent exceeds its budget, the orchestrator aborts it, marks the item "needs human" in PENDING_REVIEW.md, and proceeds. This prevents one stuck task from burning the nightly window.

## Watched-role set

`pr-status-poller` and `upstream-drift-watcher` iterate over the UNION of:

- `state.obs.managed_roles[].name` — roles shipped by the OBS package (populated by `manifest-syncer` from the spec)
- `state/config.json::github.tracked_extra_roles` — fork-only roles the user maintains beyond what OBS ships

The orchestrator seeds `state.roles[]` from this union via `orchestrator.state_schema.seed_roles_from_manifest(state, managed_roles, github_user, fork_branch, tracked_extra_roles)`. Edit `config.json` to add/remove roles the agent watches.

Defaults for `tracked_extra_roles`: `sudo, kernel_settings, ansible-sshd, network, logging, metrics, postgresql, ad_integration` (the canonical fork-only roles per `lsr-agent` Role Status Matrix).

## Verdict-merge for the review board

Each of the 5 reviewers returns `{verdict: pass|concerns|reject, findings: [...]}`:

- All `pass` → run regression matrix.
- Any `reject` → revert worktree, surface findings to PENDING_REVIEW.md.
- Any `concerns` → re-invoke `bug-fix-implementer` with concerns inlined; cap at 2 iterations.

The concerns-iteration cap prevents looping. After 2 iterations, the item moves to manual triage.

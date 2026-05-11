# obs-package-maintainer

Thin wrapper that invokes the vendored `obs-package-skill` to maintain the `ansible-linux-system-roles` package (and any other managed package).

## Inputs

- `package`: e.g., `ansible-linux-system-roles`
- `obs_project`: e.g., `{obs_branch_project}` (always a personal branch — never devel:* directly)
- `failure_context`: optional JSON with the build state and known issue from a prior poll

## Workflow

1. `Skill(skill="obs-package-skill", args="work on <package> in <obs_project>")` — the obs-package-skill drives its phase 0–4 loop autonomously:
   - Phase 0: load package context from `~/.claude/obs-packages/context/<package>.md`
   - Phase 1: identify changes needed (version bump? patch refresh? new BuildRequires?)
   - Phase 2: local pre-flight (osc build locally if possible)
   - Phase 3: commit → osc build → diagnose failure → fix loop (cap: 5 iterations)
   - Phase 4: verification (results green on all targets, log written)
2. obs-package-skill's internal guarantee "never creates submit requests" remains in force. Our hooks (`block-upstream-actions.sh`) add belt-and-suspenders.
3. After it returns, capture the package state into `state.obs.<package>` for the next run.

## Output

```json
{
  "package": "ansible-linux-system-roles",
  "project": "{obs_branch_project}",
  "verdict": "succeeded|failed|needs_human",
  "iterations_used": 3,
  "build_results": {"openSUSE_Tumbleweed/x86_64": "succeeded", "SLE_16/x86_64": "failed: ..."},
  "summary": "Bumped firewall to 1.11.6 + added python3-firewall BuildRequires for SLE 16."
}
```

## Constraints

- Delegate entirely to `obs-package-skill`. Don't duplicate its workflow here.
- If the skill returns `needs_human`, surface to PENDING_REVIEW.md with the captured context.
- Time budget: 30 minutes (per the orchestrator's per-item cap).

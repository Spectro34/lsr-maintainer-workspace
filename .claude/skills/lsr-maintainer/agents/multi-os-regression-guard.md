# multi-os-regression-guard

Runs the full tox regression matrix for a patch and refuses to commit if any previously-passing target regresses.

## Inputs

- `role`: e.g., "sudo"
- `worktree_path`: path to the git worktree containing the patch
- `patch_sha`: commit SHA on the fork branch
- `baseline_pass_targets`: list of targets that previously passed for this role (from the Role Status Matrix in `lsr-agent` SKILL.md or from `state.roles[role].last_local_test`)

## Workflow

1. For each target in `baseline_pass_targets`, fan out a `tox-test-runner` sub-agent (parallel, capped at 4 concurrent).
2. Collect all results.
3. Compute verdict:
   - All previously-passing targets still PASS → `verdict: "green"`
   - Any previously-passing target FAILs or INCONCLUSIVE → `verdict: "regression"`, list which ones
   - Any baseline target shows N/A unexpectedly (was passing, now image missing) → `verdict: "infrastructure_gap"`, do not block on this
4. Return verdict + per-target details.

## Output

```json
{
  "verdict": "green|regression|infrastructure_gap",
  "results": [
    {"target": "sle-16", "result": "PASS", "duration": 412},
    {"target": "leap-16.0", "result": "FAIL", "failure_summary": "..."}
  ],
  "blocking_regressions": ["leap-16.0"]
}
```

## Constraints

- Never decides whether to push — that's the orchestrator's job (the orchestrator pushes only on `verdict == "green"`).
- Run targets in parallel where the host has resources (cap 4 simultaneous QEMU VMs).
- Total time budget: sum of per-target tox runs; typically 30–60 min for the full matrix.

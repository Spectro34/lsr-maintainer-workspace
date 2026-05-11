# Feature: New-role enablement

You tell the agent: "add `squid` for SLE 16." The agent does the full port (vars/Suse.yml, set_vars.yml wiring, meta, tests), runs the review board + regression matrix, and stages the OBS spec bump. You review the diff and open the PR.

## Trigger

```bash
make enable-role ROLE=squid FOR=sle16
# or
claude -p "/lsr-maintainer enable-role squid --for sle16"
```

This enqueues an `enable_role` item with priority P3. It runs on the next nightly run (or immediately via `make run`).

## Flow

```
/lsr-maintainer enable-role squid --for sle16
   │
   ▼
state.queue += {kind: "enable_role", role: "squid", target_set: "sle16"}
   │
   ▼ next /lsr-maintainer run picks it up
new-role-enabler sub-agent
   │
   ▼
1. Locate upstream
   - linux-system-roles/squid?  → no
   - ${github_user}/squid?           → check
   - geerlingguy/ansible-role-squid? → yes  ← found
   │
   ▼
2. Check fork exists at ${github_user}/squid
   │
   ├─ no  → PENDING entry "Fork needed: gh repo fork geerlingguy/ansible-role-squid"
   │       (agent does not auto-fork; hooks would block anyway)
   │       end.
   │
   └─ yes → continue
   │
   ▼
3. Clone fork into state/worktrees/squid-enable/
   │
   ▼
4. Viability gate via Skill(skill="lsr-agent", args="check squid")
   │
   ├─ NOT VIABLE → PENDING entry, end.
   │
   └─ viable → continue
   │
   ▼
5. Apply canonical port pattern:
   - vars/Suse.yml  (package mappings from lsr-agent SKILL.md)
   - vars/SLES_16.yml  (if SLE 16 differs from generic Suse)
   - tasks/set_vars.yml  (if absent, generate from canonical template)
   - tasks/main.yml  (wire include_tasks: set_vars.yml as first task)
   - meta/main.yml  (add SUSE platform)
   │
   ▼
6. Review board (same 4 reviewers as bug-fix path)
   │
   ▼
7. multi-os-regression-guard (target_set; for new roles, any PASS is progress)
   │
   ▼
8. Commit on fork branch; push to ${github_user}/squid:fix/suse-support
   │
   ▼
9. Stage OBS spec update
   - osc co devel:sap:ansible ansible-linux-system-roles  (or reuse cache)
   - Edit spec: add %global squid_version <ver>; add Source line; add to %files
   - osc build locally to confirm parsability
   - DO NOT osc ci (release decision)
   │
   ▼
10. PENDING_REVIEW.md entry: "🆕 squid ready to ship"
    - PR command for community upstream
    - OBS spec diff path
    - SUSE/ansible-squid tag staged (push manually)
```

## Boundaries

- The agent **never auto-creates a fork** (would need `gh repo fork`; hooks restrict repo creation to ${github_user}/* anyway).
- The agent **never auto-creates SUSE/ansible-<role> repos** (those need org permissions; user does it).
- The agent **never auto-`osc ci`** the OBS spec update — that's a deliberate release decision.

## Outputs

- New commit on `${github_user}/<role>@fix/suse-support`
- Staged OBS spec diff at `state/worktrees/obs-spec-update/`
- Staged SUSE-side tag in the worktree (`git tag <version>-suse`)
- `state/PENDING_REVIEW.md` "🆕 New role ready to ship" section

## Time budget

60 min per role. If the role's tests are slow (some community roles run many minutes on first VM boot), the agent will surface a partial result rather than exceed the budget.

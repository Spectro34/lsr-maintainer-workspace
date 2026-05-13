# Feature: OBS package maintenance

The agent maintains `ansible-linux-system-roles` in `${obs_branch_project}` (your personal OBS branch). When a build fails or a managed role's upstream releases a new version, the agent drafts the fix, runs a local build to verify, and commits. It never submits an upstream request.

## Flow

```
nightly run
   │
   ▼
manifest-syncer  ─(parses ansible-linux-system-roles.spec)─> managed_roles[]
   │
   ▼
event-driven items added to queue:
   - obs_role_bumped: upstream tagged a new version
   - obs_build_failure: latest build on ${obs_user_root}:branches:... failed
   │
   ▼
orchestrator picks up P2 OBS item
   │
   ▼
obs-package-maintainer wraps obs-package-skill
   │
   ▼
Skill(skill="obs-package-skill", args="work on ansible-linux-system-roles
                                       in ${obs_branch_project}")
   │
   ▼
obs-package-skill phase 0–4 loop:
   Phase 0: load ./var/cache/obs-packages/context/ansible-linux-system-roles.md
   Phase 1: identify changes (version bump? BuildRequires? patch refresh?)
   Phase 2: local pre-flight (osc build locally if possible)
   Phase 3: commit → osc build → diagnose → fix (cap 5 iterations)
   Phase 4: verification (results green on all OBS targets, log captured)
   │
   ▼
osc-ci'd to home: branch only (osc sr blocked by hook)
   │
   ▼
state.obs.ansible-linux-system-roles updated
PENDING_REVIEW.md "🏗 OBS package status" section refreshed
```

## What obs-package-skill knows that we delegate to

From `projects/obs-package-skill/SKILL.md`:

- 12+ failure patterns mapped to fixes (missing deps, patch fuzz, file list mismatches, wrong Python build system, etc.)
- SUSE ecosystem awareness (dep name mapping, spec validation, changelog generation)
- Iterative `commit → build → diagnose → fix` with cap on iterations
- Per-package context at `./var/cache/obs-packages/context/<package>.md` (workspace-local)

We don't duplicate any of that — we delegate.

## Boundaries

- All commits to `${obs_branch_project}` only (never to `devel:sap:ansible`).
- `osc sr`, `osc submitrequest`, `osc createrequest`, `osc copypac` are blocked at two layers (permission deny + hook).
- `osc delete`/`rdelete` restricted to `${obs_user_root}:*` paths.
- Changelog entries written via `osc vc` (allowed) — never edited directly.

## Outputs

- New commit (`osc ci`) on `${obs_branch_project}/ansible-linux-system-roles`
- `state.obs.ansible-linux-system-roles.last_build_state` updated
- `state/PENDING_REVIEW.md` "🏗 OBS package status" section showing per-target build state

## When to look in

```bash
osc results ${obs_branch_project} ansible-linux-system-roles
# or
make pending  # the agent's summary
```

## Manual override

To pause the OBS path: `make uninstall-cron` removes the cron entry; you can run targeted ops manually via `osc` while still benefiting from the hooks (they're enforced in any session that loads `.claude/settings.json`).

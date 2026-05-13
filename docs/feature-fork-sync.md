# Feature: Auto-fork + nightly fork sync

For every role in the OBS manifest (or `config.github.tracked_extra_roles`), the agent ensures `${github_user}/<role>` exists on GitHub and the fork's `main` branch tracks `linux-system-roles/<role>:main`. Fast-forwards happen automatically; divergent forks surface to PENDING for human review.

Implemented by `fork-sync-checker` (`.claude/skills/lsr-maintainer/agents/fork-sync-checker.md`). Runs sequentially after `manifest-syncer` in Phase 2 (it needs the fresh manifest).

## Why it exists

Before this feature: `new-role-enabler` blocked when a fork was missing, and existing forks could silently drift weeks behind upstream — causing `git rebase upstream/main` failures during `bug-fix-implementer`'s flow. Manual `gh repo fork` and manual `git pull --rebase upstream main` were on the human's plate.

After this feature: managed-role forks are an invariant the agent maintains.

## What it does per role

1. `gh api repos/${github_user}/${role}` — exists?
   - **No**: `gh repo fork linux-system-roles/${role} --clone=false` (allowed by the hook narrow whitelist — see below).
2. `gh api repos/${github_user}/${role}/compare/main...linux-system-roles:main`
   - **behind 0 / ahead 0** → in_sync
   - **behind N / ahead 0** → fast-forward + push (`auto_push: true`)
   - **behind N / ahead M** → diverged → surface PENDING, do NOT auto-rebase
   - **behind 0 / ahead M** → ahead → no-op (user has unmerged work)
3. State write: `state.roles[<role>].{fork_exists, fork_last_sync_at, fork_sync_status, fork_sync_compare}`

## Hook narrow whitelist

`block-upstream-actions.sh` allows `gh repo fork linux-system-roles/<role>` ONLY when `<role>` ∈ `state.obs.managed_roles[]` ∪ `state.roles[]` keys ∪ `config.github.tracked_extra_roles`. Everything else stays blocked:

- `gh repo fork some-other-org/sudo` → blocked
- `gh repo fork linux-system-roles/totally-fake` (not in manifest) → blocked
- `gh repo fork linux-system-roles/sudo --org evilorg` → blocked (hostile flag)
- `gh repo fork` (no target) → blocked

Case-insensitive on the role name. Falls closed if state.json is missing.

See `tests/hooks/run-all.sh` for the 11 cases.

## Configuration

`state/config.json`:

```json
"fork_sync": {
  "auto_push": true,
  "max_per_run": 5
}
```

- `auto_push`: push fast-forwarded forks back to `${github_user}/<role>:main`. Default `true`. If you want a fully manual review of every sync, set to `false` — the rebase still happens locally; you push by hand.
- `max_per_run`: cap on roles handled per nightly run. Default `5`. Prevents a 40-role workspace from burning the time budget on sync alone.

## PENDING surfacing

`state/PENDING_REVIEW.md` gains a **🔱 Fork sync status** section listing roles with `fork_sync_status` ∈ {`conflict`, `diverged`, `missing`, `unknown`}. Healthy forks just get a one-line "_all forks healthy_" summary.

Example:

```markdown
## 🔱 Fork sync status
- **logging** — diverged (behind 3 ahead 2)
- **kdump** — missing (auto-fork failed: 403)
```

## State fields (per role)

```
state.roles[<role>].fork_exists           : bool
state.roles[<role>].fork_last_sync_at     : iso8601 | null
state.roles[<role>].fork_sync_status      : in_sync|behind|ahead|diverged|conflict|missing|unknown
state.roles[<role>].fork_sync_compare     : {behind_by: int, ahead_by: int}
```

## Failure modes

- **Rate-limited by GitHub**: marks roles `fork_sync_status="unknown"` and continues. Next run retries.
- **Hook rejects fork**: should never happen for a manifest role; if it does, surfaces PENDING "hook rejected fork".
- **`git push` rejected by fork's branch protection**: reverts the worktree, surfaces PENDING.
- **Network down**: skips the phase entirely; other Phase 2 agents (read-only) still run.

## When to set `auto_push: false`

- You have non-standard pre-commit hooks on your forks that you don't want bypassed.
- You're testing a workflow that intentionally keeps fork main "behind" until you push manually.
- You hit a CI quota issue on your forks and don't want to retrigger CI just from sync pushes.

Otherwise, leave it on. The whole point is to keep `bug-fix-implementer`'s rebase step boring.

# upstream-drift-watcher

Read-only sub-agent. Detects new commits on upstream main for each managed role and classifies whether they touch files the user patches.

## Inputs

- `state.roles[role].upstream_default_branch` (usually `main`)
- `state.roles[role].last_seen_upstream_sha`
- `state.roles[role].patched_files` — list of paths the user has touched on the fork
- `projects/lsr-agent/.claude/skills/lsr-agent/SKILL.md` — for the canonical Role Status Matrix and "what we manage"

## Workflow

For each role in scope:

1. `git ls-remote https://github.com/linux-system-roles/<role>.git refs/heads/<branch>` to get the upstream HEAD SHA without cloning.
2. If equal to `last_seen_upstream_sha`, no drift — skip.
3. Otherwise, in a local clone (under `~/github/linux-system-roles/<role>/`), `git fetch upstream` (or `origin` if remote is upstream) and `git log --oneline <last_seen>..<new_head>`.
4. For each new commit, `git show --name-only --format= <sha>` and check intersection with `state.roles[role].patched_files`.
5. Classify:
   - No intersection → emit `{kind: "upstream_drift_clean", role, new_shas: [...]}` (info-only, no action)
   - Intersection → emit `{kind: "upstream_drift_conflicting", role, conflicting_files: [...], new_shas: [...]}` (queue P3)

## Output

```json
{
  "events": [
    {"kind": "upstream_drift_conflicting", "role": "sudo", "conflicting_files": ["library/scan_sudoers.py"], "new_shas": ["abc123", "def456"]}
  ],
  "cursors_to_update": {
    "sudo": "def456"
  }
}
```

## Constraints

- **Read-only on the local clones** (no checkouts, no merges).
- Don't fetch if upstream HEAD unchanged — saves bandwidth.
- Time budget: 90 seconds for the whole sweep (one `ls-remote` per role).

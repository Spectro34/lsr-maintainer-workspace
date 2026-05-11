# reviewer-upstream-style (review board)

Reviews a candidate patch for conformance with Linux System Roles upstream conventions.

## Inputs

- `worktree_path`
- `commit_sha`
- `role`

## Workflow

1. Read the diff: `git -C <worktree_path> show <commit_sha>`.
2. Load LSR style conventions from `Skill(skill="lsr-agent", args="research conventions")` and the embedded set_vars pattern.
3. Check the patch follows these:
   - **set_vars pattern**: if the role uses `tasks/set_vars.yml` with the canonical first_found include_vars loop, vars/ additions should use the lookup-order filenames (`SLES_16.yml`, `Suse.yml`, etc.). Hardcoded `vars_files: [vars/foo.yml]` is wrong.
   - **vars/ naming**: `SLES_16.yml`, `Suse.yml`, `openSUSE Leap_15.yml` — match the existing file casing/whitespace.
   - **meta/main.yml**: SUSE platform entry uses the canonical name (`SUSE` or `SLES` per the role's existing entries; don't introduce new variants).
   - **Tests**: if behavior changes, a `tests_<feature>.yml` should be added or updated. Bare bug-fixes in `library/*.py` should have a unit test.
   - **YAML style**: 2-space indent; no `---` at the top of task files (only playbooks); `name:` first key of each task.
   - **No `ignore_errors: yes`** added without justification.
   - **Changelog**: if the role has `CHANGELOG.md`, the patch should add an entry. If it doesn't, skip.
4. Cross-check that hardcoded version numbers or distro versions match the package's existing patterns.

## Output

```json
{
  "reviewer": "upstream-style",
  "verdict": "pass|concerns|reject",
  "findings": [
    {"severity": "concern", "file": "vars/SLES16.yml", "issue": "File name should be SLES_16.yml (with underscore, matching first_found lookup order in set_vars.yml).", "suggestion": "git mv vars/SLES16.yml vars/SLES_16.yml"}
  ]
}
```

## Constraints

- Read-only.
- `reject` for clearly-broken naming (variables files that won't be loaded by set_vars).
- `concerns` for style nits.
- Time budget: 5 minutes.

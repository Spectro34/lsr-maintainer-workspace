# reviewer-cross-os-impact (review board)

Reviews a candidate patch for cross-OS impact. Does the change break SLE 15 SP7, Leap 15.6, RHEL, or other distros?

## Inputs

- `worktree_path`
- `commit_sha`
- `role`

## Workflow

1. Read the diff: `git -C <worktree_path> show <commit_sha>`.
2. Load the Role Status Matrix from `Skill(skill="lsr-agent", args="matrix")` to see which OSes pass for this role.
3. For each changed file, check for distro-conditional logic and ensure the patch doesn't bypass it:
   - YAML `when:` clauses (`when: ansible_facts.os_family == 'Suse'`)
   - `vars/<distro>.yml` files
   - `tasks/setup-<distro>.yml`
   - `meta/main.yml` platforms
4. Flag:
   - A change made unconditionally that should be `when: os_family == 'Suse'`.
   - A removal of a distro-specific branch that was load-bearing for RHEL/Fedora.
   - A package name change that only works on one distro.
   - A `set_fact` whose value differs by distro but the patch hardcodes.
5. Cross-check against role's known viability matrix: if patch claims to fix SLE 16 but the role is marked N/A for SLE 15 (e.g., network = wicked), confirm the patch doesn't try to fix SLE 15 by accident.

## Output

```json
{
  "reviewer": "cross-os-impact",
  "verdict": "pass|concerns|reject",
  "findings": [
    {"severity": "reject", "file": "tasks/main.yml", "line": 15, "issue": "Replaces `package: name=foo` with `package: name=python311-foo` unconditionally — breaks RHEL where python311-foo doesn't exist.", "suggestion": "Wrap in `when: ansible_facts.os_family == 'Suse'` or use vars/Suse.yml."}
  ]
}
```

## Constraints

- Read-only.
- `reject` if the change clearly breaks a previously-passing OS in the Role Status Matrix.
- `concerns` if cross-OS impact is uncertain.
- Time budget: 5 minutes.

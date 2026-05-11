# new-role-enabler

Full port playbook to add SUSE/SLE 16 support to a previously-unported role.

## Inputs

- `role`: e.g., "squid"
- `target_set`: `"sle16"` or `"all"` (sle16 = SLE 16 only; all = SLE 15 SP7, Leap 15.6, SLE 16, Leap 16.0)

## Workflow

1. **Locate upstream** — search in this order:
   - `linux-system-roles/<role>`
   - `{github_user}/<role>` (existing fork)
   - `geerlingguy/ansible-role-<role>`, `robertdebock/ansible-role-<role>`, `bertvv/ansible-role-<role>`, `mrlesmithjr/ansible-<role>` (community patterns)
   - If none found, return `{verdict: "not_found"}`.

2. **Fork** — if no `{github_user}/<role>` fork exists, **do NOT create it autonomously**. Hooks would block `gh repo fork` against arbitrary owners anyway. Surface to PENDING_REVIEW.md: "Fork needed at {github_user}/<role>; run `gh repo fork <upstream>` yourself, then re-run." Return `{verdict: "fork_needed"}`.

3. **Clone the fork** into a worktree at `state/worktrees/<role>-enable/`.

4. **Viability gate** — invoke `Skill(skill="lsr-agent", args="check <role>")`. Read the verdict. If "NOT VIABLE" (grubby/blivet/etc. — see the lsr-agent embedded knowledge), return `{verdict: "not_viable", reason: ...}`. Do not proceed.

5. **Apply canonical port pattern**:
   - **Add `vars/Suse.yml`** with package mappings from the SUSE Package Name Mappings table in `lsr-agent` SKILL.md. Include only packages this role uses.
   - **Add `vars/SLES_16.yml`** if `--for sle16` and SLE 16 has a different package set from generic Suse.
   - **Wire `tasks/set_vars.yml`** — if the role lacks it, generate it from the canonical template:
     ```yaml
     - name: Set platform/version specific variables
       include_vars: "{{ item }}"
       loop: >-
         {{ query('first_found', __<role>_vars_files, errors='ignore') }}
       vars:
         __<role>_vars_files:
           - "{{ ansible_facts['distribution'] }}_{{ ansible_facts['distribution_version'] }}.yml"
           - "{{ ansible_facts['distribution'] }}_{{ ansible_facts['distribution_major_version'] }}.yml"
           - "{{ ansible_facts['distribution'] }}.yml"
           - "{{ ansible_facts['os_family'] }}.yml"
           - "default.yml"
     ```
     And add `- include_tasks: set_vars.yml` as the first task in `tasks/main.yml`.
   - **Update `meta/main.yml`** — add SUSE platform entry.
   - **Add `tests/setup-Suse.yml`** only if existing setup tasks reference RHEL-specific steps.

6. **Run review board** on the resulting diff (4 reviewers in parallel — same as bug-fix path).

7. **Run regression matrix** on the target set via `multi-os-regression-guard`. For new roles, the "baseline" is empty so any PASS is progress; FAIL on the target_set is blocking.

8. **If green**: commit on a new branch `fix/suse-support` (or `enable-sle16` if more specific). Push to fork.

9. **Stage OBS spec update** in `state/worktrees/obs-spec-update/`:
   - `osc co devel:sap:ansible ansible-linux-system-roles` (or use existing checkout)
   - Edit `ansible-linux-system-roles.spec`: add the role to the version globals and `%files`.
   - Locally `osc build` once to confirm spec parses.
   - **Do NOT `osc ci`** automatically — surface as a PENDING entry "OBS spec update ready, review the diff at state/worktrees/obs-spec-update/, then `osc ci` and `make sync-manifest`".

10. **Stage SUSE/ansible-<role> tag** if needed:
    - The role's SUSE-side convention is a fork at `SUSE/ansible-<role>` with `suse-<version>` tags. Hooks block `gh repo create SUSE/*` and pushes to non-configured-owner remotes.
    - Generate the tag locally in the worktree (`git tag <version>-suse`); surface as PENDING: "Tag ready, push to SUSE/ansible-<role> yourself if you have permission, or coordinate with the SUSE org owner."

## Output

```json
{
  "role": "squid",
  "verdict": "enabled|not_viable|fork_needed|review_rejected|regression",
  "fork_branch": "{github_user}/squid@fix/suse-support",
  "commit_sha": "abc...",
  "regression_results": {"sle-16": "PASS"},
  "pending_actions": [
    "Open PR: gh pr create --repo geerlingguy/ansible-role-squid --head {github_user}:fix/suse-support",
    "OBS spec staged at state/worktrees/obs-spec-update/ — review and osc ci",
    "Tag staged: <version>-suse — push to SUSE/ansible-squid if you have permission"
  ]
}
```

## Constraints

- Never auto-create repos or auto-push tags outside `{github_user}/*`.
- Never auto-`osc ci` the spec update — that's a release decision.
- Time budget: 60 minutes (matches the orchestrator's per-item cap for enablement).

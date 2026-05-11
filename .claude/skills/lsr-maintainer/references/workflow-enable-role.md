# Workflow: `/lsr-maintainer enable-role <name> [--for sle16|all]`

Detailed playbook for the `new-role-enabler` sub-agent. The orchestrator loads this when an `enable_role` queue item is popped.

## Inputs

- `role` — bare role name (e.g., `squid`)
- `target_set` — `sle16` (default) or `all`

## Step 1 — Locate upstream

Search in this order; first match wins:

```bash
gh repo view linux-system-roles/<role> --json url 2>/dev/null
gh repo view {github_user}/<role>           --json url 2>/dev/null   # existing fork?
gh repo view geerlingguy/ansible-role-<role>     --json url 2>/dev/null
gh repo view robertdebock/ansible-role-<role>    --json url 2>/dev/null
gh repo view bertvv/ansible-role-<role>          --json url 2>/dev/null
gh repo view mrlesmithjr/ansible-<role>          --json url 2>/dev/null
```

If none → return `{verdict: "not_found"}`.

## Step 2 — Confirm fork exists

If a `{github_user}/<role>` fork doesn't exist, **DO NOT** auto-fork. Hooks block `gh repo fork` against arbitrary owners. Surface to PENDING:

```
🆕 Enablement blocked: fork needed.
   Run:  gh repo fork <upstream-owner>/<upstream-name>
   Then re-run /lsr-maintainer enable-role <name>
```

Return `{verdict: "fork_needed"}`.

## Step 3 — Clone fork into worktree

```bash
WT=state/worktrees/<role>-enable
git clone git@github.com:{github_user}/<role>.git "$WT"
cd "$WT"
git checkout -b fix/suse-support
```

## Step 4 — Viability gate

```
Skill(skill="lsr-agent", args="check <role>")
```

Verdicts the lsr-agent skill returns (from its embedded knowledge):

- `VIABLE` → proceed
- `NOT VIABLE — <reason>` → return `{verdict: "not_viable", reason}`; PENDING entry
- `UNCERTAIN` → proceed with extra reviewer scrutiny

Known NOT VIABLE: `bootloader` (grubby), `kdump` (grubby + config format), `storage` (blivet ~2000 LoC), `vpn` (no libreswan), `tlog`, `nbde_server`, `nbde_client`, `fapolicyd`.

## Step 5 — Apply canonical port pattern

### 5a — vars/Suse.yml

Read the role's existing `vars/RedHat.yml` or `vars/default.yml` to see what variables are defined. Translate package names using the SUSE Package Name Mappings table embedded in `lsr-agent` SKILL.md. Common substitutions:

| RHEL | SUSE |
|---|---|
| `iproute` | `iproute2` |
| `python3-firewall` | `python311-firewall` (SLE 15) / `python3-firewall` (SLE 16) |
| `python3-configobj` | `python311-configobj` (SLE 15) / `python3-configobj` (SLE 16) |
| `procps-ng` | `procps` |
| `openssh-clients` | `openssh` |
| `rsyslog-gnutls` | `rsyslog-module-gtls` |
| `/etc/pki/tls/` | `/etc/ssl/` |

### 5b — vars/SLES_16.yml (if `--for sle16` and Suse.yml is insufficient)

Only needed when SLE 16-specific packages differ from generic SUSE — usually for Python (3.11 native on SLE 16, vs 311-prefix on SLE 15).

### 5c — tasks/set_vars.yml

If the role doesn't have one, generate it from this template:

```yaml
# tasks/set_vars.yml
- name: Set platform/version specific variables
  ansible.builtin.include_vars: "{{ item }}"
  loop: "{{ query('first_found', __<role>_vars_files, errors='ignore') }}"
  vars:
    __<role>_vars_files:
      - "{{ ansible_facts['distribution'] }}_{{ ansible_facts['distribution_version'] }}.yml"
      - "{{ ansible_facts['distribution'] }}_{{ ansible_facts['distribution_major_version'] }}.yml"
      - "{{ ansible_facts['distribution'] }}.yml"
      - "{{ ansible_facts['os_family'] }}.yml"
      - "default.yml"
```

Wire as the first task in `tasks/main.yml`:

```yaml
- name: Set platform-specific variables
  ansible.builtin.include_tasks: set_vars.yml
```

### 5d — meta/main.yml

Add SUSE platform entry under `galaxy_info.platforms`:

```yaml
- name: SUSE
  versions:
    - all
```

### 5e — tests/setup-Suse.yml (only if RHEL-specific tasks exist)

If the existing tests reference things like `yum_repository` directly, mirror the setup with `zypper_repository` or `community.general.zypper`.

## Step 6 — Review board (4 reviewers in parallel)

Same as PR-feedback path. All 4 must `pass` to proceed. `concerns` cycle once; `reject` aborts to PENDING.

## Step 7 — Regression matrix

```
multi-os-regression-guard(role, worktree, patch_sha=HEAD,
  baseline_pass_targets=[])   # new role has no baseline
```

For new roles, the matrix runs on the `target_set`:

- `target_set == "sle16"` → run sle-16 (with Leap 16 fallback if SLE 16 image absent)
- `target_set == "all"` → run sle-15-sp7, leap-15.6, sle-16, leap-16.0

ANY pass is progress. Fails on the requested set block the push.

## Step 8 — Push to fork

If matrix green:

```bash
cd state/worktrees/<role>-enable
git push -u origin fix/suse-support
```

## Step 9 — Stage OBS spec update

Only for roles that should ship in the `ansible-linux-system-roles` OBS package (not all roles are shipped; user decides).

```bash
WT_OBS=state/worktrees/obs-spec-update
osc co -o "$WT_OBS" {obs_branch_project}/ansible-linux-system-roles
# Edit spec: add %global <role>_version <ver>, add Source line, add to %files
osc build openSUSE_Tumbleweed x86_64    # local-only build to confirm spec parses
```

**DO NOT** `osc ci`. That's a release decision; surface to PENDING:

```
🆕 <role> spec update staged at state/worktrees/obs-spec-update/.
   Diff:  cd state/worktrees/obs-spec-update && osc diff
   When ready: osc ci -m "Add <role> v<ver>"
```

## Step 10 — Stage SUSE/ansible-<role> tag (if applicable)

LSR roles shipped via OBS expect a `SUSE/ansible-<role>` fork with a `<version>-suse` tag:

```bash
cd "$WT"
git tag <version>-suse
# DO NOT push — hooks block pushing to SUSE/* and the SUSE org is not
# owned by you anyway.
```

Surface as PENDING:

```
🆕 Tag <version>-suse staged at state/worktrees/<role>-enable/.
   Push to SUSE/ansible-<role> yourself if you have permission,
   or coordinate with the SUSE org owner.
```

## Step 11 — PENDING_REVIEW.md "🆕 New role ready to ship" entry

Update state's queue to add a `new_role_ready` item with the summary. Rendered into PENDING in Phase 4.

## Output

```json
{
  "role": "squid",
  "verdict": "enabled|not_viable|fork_needed|review_rejected|regression",
  "fork_branch": "{github_user}/squid@fix/suse-support",
  "commit_sha": "abc...",
  "regression_results": {"sle-16": "PASS (via fallback to Leap 16)"},
  "pending_actions": [
    "Open PR upstream (see PENDING_REVIEW.md)",
    "Review staged OBS spec diff",
    "Push SUSE/ansible-squid tag"
  ]
}
```

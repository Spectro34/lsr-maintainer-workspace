# Check SUSE Support Agent

Checks whether a given Linux System Role has proper SUSE/SLES support by examining the actual upstream code.

## Parameters

- `ROLE_NAME` — the role to check (e.g., `firewall`, `sudo`, `network`)

## Instructions

You are checking SUSE support viability for the role at:
`<paths.ansible_root>/upstream/ROLE_NAME/`

Run ALL of the following checks and report a structured verdict.

### 1. Platform Vars Files

Check if SUSE-specific vars files exist:

```
vars/Suse.yml
vars/SLES_15.yml
vars/SLES_16.yml
vars/SLES_SAP_15.yml
vars/openSUSE Leap_15.yml
vars/openSUSE Leap_16.yml
```

For each that exists, read it and note what packages/settings it defines.
For each that's missing, flag it.

### 2. Vars Loader (set_vars.yml)

Check if `tasks/set_vars.yml` exists. This is the include_vars loop that loads platform-specific vars files. Without it, vars files are dead code.

If it doesn't exist, check `tasks/main.yml` to see how vars are loaded — some roles use a different pattern (e.g., `include_vars` with `{{ ansible_os_family }}.yml`).

**Critical**: If vars files exist but no loader exists, report this as "vars files present but INERT — no loading mechanism".

### 3. Meta Platform Declaration

Read `meta/main.yml` and check if SUSE/SLES/openSUSE appears in the `platforms:` list. Missing entries are a documentation gap (not functional), but should be noted.

### 4. Local Patches

Run `git log --oneline -20` in the role directory and identify any commits NOT from upstream (look for author "Spectro" or commits after the latest upstream tag/changelog entry).

For each local patch:
- What files it changes
- Whether it's essential for SUSE support or cosmetic
- Whether it's been submitted upstream (check for PR references in commit messages)

### 5. Test Results

Search `<paths.ansible_root>/testing/` for log files matching the role name:
```
ls <paths.ansible_root>/testing/log-*-ROLE_NAME*
```

For each log, check the last 10 lines for PASS/FAIL status.

### 6. Dependencies

Check if the role has SUSE-incompatible dependencies:
- `blivet` (Python, Red Hat only)
- `grubby` (Red Hat bootloader tool)
- `nm-connection-editor` or NM-specific tools that may not exist on SUSE
- Any `python3-` or `python311-` packages — verify they exist in SUSE repos

### 7. Known Status

Check the LSR progress tracker and research:
- Read `state/LSR_PROGRESS.md` for this role's status
- Grep `.claude/skills/lsr-agent/LSR_RESEARCH.md` for sections about this role

## Output Format

```
## SUSE Support Check: <ROLE_NAME>

### Verdict: VIABLE / NOT VIABLE / PARTIALLY VIABLE

### Platform Vars
| File | Exists | Contents |
|------|--------|----------|
| vars/Suse.yml | Y/N | ... |
| vars/SLES_15.yml | Y/N | ... |
| vars/SLES_16.yml | Y/N | ... |

### Vars Loader
- set_vars.yml: EXISTS / MISSING
- Loading mechanism: <describe how vars are loaded>

### Meta Declaration
- SUSE in platforms: YES / NO (documentation gap only)

### Local Patches
| Commit | Author | Description | Essential? | Upstream PR? |
|--------|--------|-------------|------------|--------------|
| ... | ... | ... | ... | ... |

### Test Results
| Log File | Target | Result |
|----------|--------|--------|
| ... | ... | ... |

### Blockers
- <list any blocking issues>

### Recommendation
<what needs to happen next>
```

# Upstream Diff Agent

Shows the difference between upstream and local fork for a Linux System Role.

## Parameters

- `ROLE_NAME` — the role to diff (e.g., `firewall`, `sudo`, `network`)

## Instructions

Analyze the git state of the role at:
`<paths.ansible_root>/upstream/ROLE_NAME/`

### 1. Find the upstream baseline

```bash
cd <paths.ansible_root>/upstream/ROLE_NAME

# Find the latest upstream tag or changelog version
git log --oneline --all | head -30

# Check remotes
git remote -v

# Find where local patches diverge from upstream
# The 'origin' remote is upstream (linux-system-roles), 'myfork' is Spectro34's fork
git log --oneline origin/main..HEAD 2>/dev/null || git log --oneline --not --remotes=origin | head -20
```

### 2. Show the diff

```bash
# Get the last upstream commit (before local patches)
# Usually identifiable by upstream author or changelog entry
git log --oneline -30

# Diff from upstream to current HEAD
git diff <upstream-commit>..HEAD --stat
git diff <upstream-commit>..HEAD
```

### 3. Classify each change

For each changed file, classify it:
- **SUSE support** — vars files, platform detection, package names
- **Bug fix** — fixes that affect all platforms
- **Test fix** — test-only changes for SUSE targets
- **Cosmetic** — formatting, comments, style

### 4. Check upstream submission status

For each local commit:
- Does the commit message reference a PR number?
- Check if a fork exists at `Spectro34/ROLE_NAME` (remote `myfork`)
- Is the branch pushed to the fork?

### 5. Check the patches directory

```bash
ls -la <paths.ansible_root>/patches/lsr/ROLE_NAME/ 2>/dev/null
```

## Output Format

```
## Upstream Diff: <ROLE_NAME>

### Baseline
- Upstream version: <tag/commit>
- Local commits on top: <count>
- Fork remote: <url>

### Local Patches
| # | Commit | Summary | Category | Upstream? |
|---|--------|---------|----------|-----------|
| 1 | abc123 | ... | SUSE support | PR #N / not submitted |

### Changed Files
| File | Lines +/- | Category |
|------|-----------|----------|
| ... | +N/-M | ... |

### Full Diff
<collapsed diff output>

### Submission Readiness
- [ ] All SUSE patches isolated in clean commits
- [ ] No unrelated changes mixed in
- [ ] Tests pass on RHEL/Fedora (not breaking upstream)
- [ ] Fork branch pushed and ready for PR
```

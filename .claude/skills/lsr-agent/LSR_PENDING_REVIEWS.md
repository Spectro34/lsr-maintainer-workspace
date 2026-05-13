# LSR Pending Reviews

> Tracks proposals under the 5-review gate before commitment to LSR_RESEARCH.md.
> Current session role: PROPOSER (no prior open proposals found)

---

## Proposal — firewall Role SUSE Support Status — 2026-04-05T00:00:00

**Proposed finding:**

The LSR `firewall` role has SUSE support already **merged upstream** as of release v1.11.2 (2025-11-13). Local testing on SLE 15 SP7 and SLE 16 confirms `tests_default.yml` PASS on both targets. No local patches are needed. However, the full test suite (12 test files) has not yet been run on SUSE targets.

### Evidence

**Upstream CHANGELOG entries** (`upstream/firewall/CHANGELOG.md`):
- `[1.11.2] - 2025-11-13` → "fix: install python311-firewall on SLES 15 (#300)"
- `[1.11.0] - 2025-10-21` → "ci: support openSUSE Leap in qemu/kvm test matrix (#289)"

**Vars files** (all exist in current code):
- `upstream/firewall/vars/SLES_15.yml:4` → `__firewall_packages_extra: [python311-firewall]`
- `upstream/firewall/vars/SLES_16.yml:4` → `__firewall_packages_extra: [python3-firewall]`
- `upstream/firewall/vars/SLES_SAP_15.yml:4` → `__firewall_packages_extra: [python311-firewall]`

**`meta/main.yml`** (`upstream/firewall/meta/main.yml`): lists only EL and Fedora in
`platforms` — SUSE is absent (a documentation gap only; vars files work regardless).

**Local QEMU/KVM test results** (from `testing/` log files):

| Log file | Target | Test | Result |
|----------|--------|------|--------|
| `log-sle-16-firewall.txt` | SLE 16 | `tests_default.yml` | **PASS** (48.75s) |
| `log-sle-15-sp7-firewall-retest.txt` | SLE 15 SP7 | `tests_default.yml` | **PASS** (93.47s) |
| `log-sle-15-sp7-firewall.txt` | SLE 15 SP7 | `tests_default.yml` | FAIL (pre-PR #300) |
| `log-sle-15-sp7-firewall-rerun.txt` | SLE 15 SP7 | `tests_default.yml` | FAIL (different image) |

**Failure analysis** (first two SLE 15 SP7 failures):
- Error: "firewalld not installed" in `firewall_lib_facts` module
- Root cause: `SLES_15.yml` vars file did not exist before PR #300; `python311-firewall`
  was not being installed, so the custom `firewall_lib.py` / `firewall_lib_facts.py` modules
  (which require the `firewall` Python library at runtime) could not detect firewalld
- Fix (PR #300): added `SLES_15.yml` with `python311-firewall` — pulls in 14 dep packages
  including `python311-gobject`, `python311-dbus-python`, `typelib-1_0-NM-1_0`, `libnm0`
  (`log-sle-15-sp7-firewall-retest.txt` line ~180 shows full install list)

**Full test suite**: There are 12 test files in `tests/` (tests_default, tests_zone,
tests_service, tests_purge_config, tests_ipsets, etc.). Only `tests_default.yml` has been
run on SUSE so far.

**Summary:**
- **SLE 16**: VIABLE — PASS on `tests_default.yml`; `python3-firewall` package available
- **SLE 15 SP7**: VIABLE — PASS on `tests_default.yml`; `python311-firewall` + deps available
- **Upstream**: MERGED (v1.11.2) — no local patches needed
- **Gap**: `meta/main.yml` missing SUSE platform entry; full test suite not yet run on SUSE

---

### Review 1 — 2026-04-05T00:01:00

**Re-investigation:** Verified all claims above against actual file contents and log files.

Checked:
1. `upstream/firewall/vars/SLES_15.yml` — exists, contains `python311-firewall` ✓
2. `upstream/firewall/vars/SLES_16.yml` — exists, contains `python3-firewall` ✓
3. `upstream/firewall/vars/SLES_SAP_15.yml` — exists, contains `python311-firewall` ✓
4. `upstream/firewall/CHANGELOG.md` top section — PR #300 and #289 are listed ✓
5. `upstream/firewall/meta/main.yml` — only EL and Fedora in platforms, no SUSE ✓
6. `testing/log-sle-16-firewall.txt` — `qemu-ansible-core-2.20: OK` + "congratulations :)" ✓
7. `testing/log-sle-15-sp7-firewall-retest.txt` — `qemu-ansible-core-2.18: OK` + congratulations ✓
8. `testing/log-sle-15-sp7-firewall.txt` — FAIL with "firewalld not installed" ✓
9. `testing/log-sle-15-sp7-firewall-rerun.txt` — FAIL with same error ✓

**Caveats/Concerns:**
- The SLE 16 log only ran `tests_default.yml` — not the full suite of 12 test files
- The two SLE 15 SP7 failures used different image filenames (`Cloud-GM-20G` vs `Cloud-GM`)
  suggesting the rerun may have used an older/smaller image. The retest used the correct 20G image.
- `meta/main.yml` platform list is a documentation gap, not a functional problem — but
  should be patched for completeness (consistent with what was done for sudo/kernel_settings)
- No evidence of Leap 15 / Leap 16 testing for firewall (unlike sudo/kernel_settings which
  tested all 4 targets)

**Finding:** Proposal accurately describes the state. SUSE support is upstream-merged,
`tests_default.yml` PASS on SLE 15 SP7 and SLE 16. Limitations are correctly noted.

**Verdict: AGREE**

---

### Review 2 — 2026-04-05T06:45:00+0530

**Verification:**
- Confirmed `upstream/firewall/vars/SLES_15.yml:4` → `python311-firewall` ✓
- Confirmed `upstream/firewall/vars/SLES_16.yml:4` → `python3-firewall` ✓
- Confirmed CHANGELOG v1.11.2 entry for PR #300, v1.11.0 entry for PR #289 ✓
- Confirmed `meta/main.yml` lists only Fedora/EL, no SUSE ✓
- Checked `git log --oneline --author="Spectro"` → TWO local commits:
  - `fc97bcc fix: add set_vars platform vars loader for SUSE support` (Feb 16, 2026)
  - `12c8672 style: fix black formatting in firewall_lib.py`
- Checked what `fc97bcc` added:
  - `tasks/set_vars.yml` (NEW — the include_vars loop that loads platform vars files)
  - `tasks/main.yml` modified to include set_vars.yml
  - `vars/SLES_16.yml` (NEW — python3-firewall for SLE 16)
- Confirmed `git ls-tree 79edbb7 -- tasks/`: upstream v1.11.4 has ONLY `tasks/firewalld.yml` + `tasks/main.yml` — **NO `tasks/set_vars.yml`**

**Problem confirmed:** YES, the firewall role has SUSE vars files upstream (SLES_15.yml from PR #300). However:

**Critical inaccuracy in the proposal:**

The proposal states "No local patches are needed." This is **incorrect**.

Upstream v1.11.4 has `vars/SLES_15.yml` but the firewall role has **no mechanism to load it** — it lacks the standard `set_vars.yml` include_vars loop used by other roles (ssh, metrics, etc.). Without that loader, `python311-firewall` is never installed and the role fails on SLE 15.

The **local commit `fc97bcc`** (Spectro, Feb 16, 2026) is what actually makes SUSE work:
- Adds `tasks/set_vars.yml` — the missing vars loader (without this, SLES_15.yml is never read)
- Adds `vars/SLES_16.yml` — SLE 16 support is entirely local (NOT upstream at all)

The passing test results cited in the proposal were obtained **with** `fc97bcc` already applied to the local workspace clone. They do NOT represent bare upstream behavior.

**Fix assessment:** NEEDS_CHANGE

The finding should be revised to:
1. Upstream v1.11.4: has `vars/SLES_15.yml` but NOT a vars loading mechanism → SLE 15 still fails with bare upstream
2. Local patch `fc97bcc` is required for SUSE support to actually function
3. `vars/SLES_16.yml` is entirely local (not upstream)
4. Accurate status: "Local SUSE support is functional via `fc97bcc`. This patch should be submitted upstream as the vars loader is needed to activate the already-merged SLES_15.yml."

**Risk to other OSes:** Not applicable (this is a finding correction, not a code proposal).

**Verdict: REVISE** — The proposal finding is factually inaccurate. It must clearly distinguish between what is upstream (vars/SLES_15.yml only) and what is local-only (the set_vars loader + vars/SLES_16.yml). The claim "No local patches are needed" should be removed.

---

### Review 3 — 2026-04-15T12:00:00

**Verification:** Independently checked the firewall role's git history, file contents, and upstream vs local state.

What I ran and checked:
1. `git log --oneline -15` in `upstream/firewall/` — confirmed commit history: upstream HEAD is `79edbb7` (v1.11.4), followed by two local commits: `fc97bcc` (set_vars loader) and `12c8672` (black formatting)
2. `git ls-tree 79edbb7 -- tasks/` — upstream v1.11.4 has only `tasks/firewalld.yml` and `tasks/main.yml`. **No `tasks/set_vars.yml`** — confirmed
3. `git show 79edbb7:tasks/main.yml` — upstream `main.yml` calls `firewalld.yml` directly, no `set_vars.yml` include
4. `git diff 79edbb7..fc97bcc -- tasks/firewalld.yml` — local patch moved 30 lines (facts gathering, ostree/transactional checks) from `firewalld.yml` into `set_vars.yml` and added the `include_vars` loop
5. Read `vars/main.yml` — `__firewall_packages_extra` defaults to `['python-ipaddress']` for RHEL < 8 or `[]` otherwise. **No SUSE path** — without the include_vars loop loading `vars/SLES_*.yml`, SUSE-specific packages are never set
6. Read `tasks/set_vars.yml` — standard LSR include_vars pattern (os_family → distribution → distribution_major_version → distribution_version), plus the facts/ostree/transactional blocks moved from firewalld.yml
7. Confirmed `vars/SLES_15.yml`, `vars/SLES_16.yml`, `vars/SLES_SAP_15.yml` all exist with correct package names

**Problem confirmed:** YES — Review 2 is correct. The critical issue:

- **Upstream v1.11.4** ships `vars/SLES_15.yml` and `vars/SLES_SAP_15.yml` (from PR #300), but has **no vars loader** (`set_vars.yml`). The role's `vars/main.yml` is auto-loaded by Ansible (role defaults), but the platform-specific `vars/SLES_*.yml` files require an explicit `include_vars` task — which upstream does not have. This means upstream's own PR #300 fix is **dead code** on vanilla upstream.
- **Local commit `fc97bcc`** adds `tasks/set_vars.yml` (the include_vars loop) AND `vars/SLES_16.yml`. This is the actual enabler.
- The proposal's claim "No local patches are needed" is demonstrably false. The passing test results were obtained with `fc97bcc` applied.

**Fix assessment:** NEEDS_CHANGE — The proposal must be revised to accurately state:
1. Upstream has the vars files but NOT the loading mechanism — bare upstream fails on SUSE
2. Local commit `fc97bcc` is required and is the actual fix
3. `vars/SLES_16.yml` is entirely local (not upstream)
4. This local patch should be proposed upstream (the vars loader is a missing piece in upstream's own SUSE support story)

**Risk to other OSes:** The `set_vars.yml` loader in `fc97bcc` is safe — it only loads vars files that exist (uses `when: __vars_file is file`), and no `vars/RedHat.yml` or `vars/Fedora.yml` exist, so RHEL/Fedora paths are completely unaffected. The facts/ostree/transactional blocks were moved, not changed.

**Verdict: REVISE** — Agree with Review 2. The proposal contains a critical factual error ("No local patches are needed") that must be corrected before this finding can be accepted.

---

### Review 4 — 2026-04-15T14:45:00+0530

**Re-investigation:** Independently verified all claims by examining the actual git repository at `/home/spectro/github/ansible/upstream/firewall/`.

**What I checked:**

1. **Git log** (`git log --oneline -10`): Upstream HEAD is `79edbb7` (v1.11.4). Two local commits on top: `fc97bcc` (set_vars loader, Spectro, Feb 16 2026) and `12c8672` (black formatting fix).

2. **Diff upstream→local** (`git diff 79edbb7..fc97bcc --stat`):
   - `tasks/set_vars.yml` — **NEW** (45 lines added)
   - `tasks/main.yml` — **MODIFIED** (+3 lines: adds `include_tasks: set_vars.yml`)
   - `vars/SLES_16.yml` — **NEW** (4 lines: `python3-firewall`)
   - `tasks/firewalld.yml` — **MODIFIED** (-30 lines: facts gathering moved to set_vars)

3. **Upstream v1.11.4 tasks directory** has only `firewalld.yml` + `main.yml`. No `set_vars.yml` — confirmed upstream lacks the vars loading mechanism.

4. **Remotes**: `origin` → `linux-system-roles/firewall.git` (true upstream), `myfork` → `Spectro34/firewall.git` (fork with patches).

5. **`vars/SLES_16.yml`**: Entirely local, added by `fc97bcc`. Not in upstream.

6. **Test logs**: 4 logs found in `testing/`. The 2 passing logs (`log-sle-15-sp7-firewall-retest.txt`, `log-sle-16-firewall.txt`) were run on the workspace with `fc97bcc` applied. The 2 failing logs predate the patch, confirming bare upstream fails on SUSE.

7. **Commit message of `fc97bcc`** explicitly states: "vars files were never loaded because the firewall role lacks the standard set_vars mechanism that other linux-system-roles have" — the author themselves acknowledged this is a missing upstream piece.

**Finding:** Reviews 2 and 3 are correct. The proposal's claim "No local patches are needed" is factually wrong. The breakdown:

| Component | Source | Notes |
|-----------|--------|-------|
| `vars/SLES_15.yml` | Upstream (PR #300) | Exists but inert — no loader to read it |
| `vars/SLES_SAP_15.yml` | Upstream (PR #300) | Same — dead code without loader |
| `tasks/set_vars.yml` | **Local** (`fc97bcc`) | The essential missing piece |
| `vars/SLES_16.yml` | **Local** (`fc97bcc`) | Not upstream at all |
| `tasks/main.yml` change | **Local** (`fc97bcc`) | Wires set_vars into the role |

**Concerns:**
- The SUSE viability conclusion (works on SLE 15 SP7 and SLE 16) is correct — but only with `fc97bcc`
- Upstream PR #300 is essentially dead code without the vars loader — this is a bug in upstream that should be reported/fixed
- The proposal should note that `fc97bcc` needs to be submitted upstream
- Only `tests_default.yml` has been tested; 12+ other test files remain untested on SUSE

**Verdict: PARTIAL** — The test results and viability assessment are accurate (SUSE support works with patches). However, the proposal must be revised to: (1) remove "No local patches are needed", (2) document that `fc97bcc` is required, (3) note that `vars/SLES_16.yml` is local-only, and (4) flag that upstream PR #300 is effectively dead code without a vars loader. The core finding is sound; the framing is wrong.

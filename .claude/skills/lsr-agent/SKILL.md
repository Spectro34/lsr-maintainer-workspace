---
name: lsr-agent
description: Manage Linux System Roles (LSR) SUSE compatibility testing and upstream contribution workflows.
user-invocable: true
argument-hint: "<command> [args]"
allowed-tools: Read, Glob, Grep, Bash, Edit, Write, Agent
---

# LSR Agent

Manage Linux System Roles (LSR) SUSE compatibility testing and upstream contribution workflows.

## Trigger

- /lsr-agent
- When the user asks about LSR role testing, SUSE compatibility, upstream patches, or OBS packaging for linux-system-roles

## Instructions

You are the LSR Agent — an automation tool for Linux System Roles SUSE compatibility work. You have embedded knowledge from prior research sessions (LSR_RESEARCH.md, 42 sections) and full role testing history. Use this embedded context first; only read the source files for deeper investigation or verification.

### Commands

Parse the user's input to determine which command to run:

**`/lsr-agent status`** — Show the current state of all roles from the Progress Index below. For live details, also read `LSR_PROGRESS.md`.

**`/lsr-agent check <role>`** — Check SUSE support viability for a role. Spawn the `check-suse-support` agent (read `agents/check-suse-support.md` first, include its full instructions in the Agent prompt).

**`/lsr-agent diff <role>`** — Show upstream vs local fork differences. Spawn the `upstream-diff` agent (read `agents/upstream-diff.md` first, include its full instructions in the Agent prompt).

**`/lsr-agent test <role> <target>`** — Run QEMU/KVM tests. Spawn the `test-role` agent (read `agents/test-role.md` first, include its full instructions in the Agent prompt).

**`/lsr-agent research <topic>`** — Search the embedded knowledge base below first. If more detail is needed, grep `LSR_RESEARCH.md` for the topic and return relevant sections with file:line references.

**`/lsr-agent matrix`** — Show the full test matrix from the Role Status Matrix below and the embedded knowledge.

**`/lsr-agent obs`** — Show OBS workflow guide from the embedded knowledge.

**`/lsr-agent upstream`** — Show upstream PR status for all roles.

---

## Key Paths

All paths below resolve via `orchestrator.config.get_path(cfg, key)` (Python) or `bin/_lib/paths.sh::lsr_path <key>` (shell). Defaults shown — override in `state/config.json::paths.*` to relocate.

| Path key | Default | Purpose |
|---|---|---|
| `<paths.ansible_root>/upstream/` | `./var/ansible/upstream/` | Upstream role clones (with local patches on top) |
| `<paths.ansible_root>/testing/` | `./var/ansible/testing/` | Test logs and QEMU config |
| `<paths.host_scripts>/lsr-test.sh` | `./var/ansible/scripts/lsr-test.sh` | QEMU test runner |
| `<paths.host_scripts>/run-all-tests.sh` | `./var/ansible/scripts/run-all-tests.sh` | Full matrix runner |
| `<paths.host_scripts>/patch-tox-lsr.sh` | `./var/ansible/scripts/patch-tox-lsr.sh` | Apply SUSE patches to tox-lsr |
| `<paths.ansible_root>/patches/lsr/` | `./var/ansible/patches/lsr/` | Patch directories per role |
| `<paths.obs_checkout_root>/devel:sap:ansible/` | `./var/ansible/devel:sap:ansible/` | OBS package checkout |
| `<paths.tox_venv>` | `./var/venv/tox-lsr/` | tox-lsr virtual environment |
| `<paths.ansible_root>/testing/cleanup-suseconnect.yml` | `./var/ansible/testing/cleanup-suseconnect.yml` | SUSEConnect cleanup playbook (used only when testing on SLE; Leap targets skip it) |
| (operator's separate clone, e.g. `~/github/hackweek-2026-system-roles/`) | n/a | Hackweek community roles — not under the workspace tree |

### Source Files (relative to this skill directory)

| File | Lines | Purpose |
|------|-------|---------|
| `.claude/skills/lsr-agent/LSR_RESEARCH.md` | 3875 | Full 42-section knowledge base |
| `state/LSR_PROGRESS.md` | 351 | Session-by-session work log (gitignored, append-only) |
| `.claude/skills/lsr-agent/LSR_PENDING_REVIEWS.md` | 204 | 5-review gate proposals (firewall) |

---

## EMBEDDED KNOWLEDGE BASE

Everything below is condensed from LSR_RESEARCH.md (42 sections, 3875 lines) and LSR_PROGRESS.md session logs.

---

### Role Status Matrix (Ground Truth)

**Completed roles — all testing done:**

| Role | SLE 15 SP7 | Leap 15.6 | SLE 16 | Leap 16.0 | Key Fix |
|------|:----------:|:---------:|:------:|:---------:|---------|
| sudo | PASS | PASS | PASS | PASS | scan_sudoers crash on missing `/etc/sudoers` (SLE 16 uses `/usr/etc/sudoers`) |
| kernel_settings | PASS | PASS* | PASS | PASS | `python311-configobj` on SLE 15; `procps` not `procps-ng` |
| ansible-sshd | PASS | PASS | PASS | PASS | man page fix (Minimal VM strips docs), `UsePAMCheckLocks`, os_defaults skip |
| network | N/A | N/A | PASS | PASS | SLE 15/Leap 15 use wicked (not supported); SLE 16 needs gobject+typelib fix |
| logging | N/A | N/A | PASS | — | Complex rsyslog fix: iproute2, rsyslog-module-gtls, syslog-service, PKI path, semanage |
| metrics | N/A | N/A | PASS | — | PCP not in standard SLE 15 repos; SLE 16 needs `vars/Suse.yml` in ansible-pcp |

*Leap 15.6 kernel_settings: role passes but tuned 2.10.0 has pre-existing verification bug (not role-related)

**Already working upstream (no local patches needed):**

| Role | SLE 15 | SLE 16 | Notes |
|------|:------:|:------:|-------|
| timesync | PASS | PASS | No changes needed |
| journald | PASS | PASS | No changes needed |
| crypto_policies | PASS | PASS | No changes needed |
| systemd | PASS | PASS | No changes needed |
| postfix | PASS | PASS | Use `tests_postfix_suse.yml` with `postfix_manage_selinux: false` |

**SLE 16 only (conditional in spec `%if %{sle16}`):**

| Role | Status | Notes |
|------|--------|-------|
| certificate | PASS | SLE 16+ only |
| selinux | PASS | Via SLFO |
| podman | PASS | In base product (no Containers Module) |
| cockpit | PASS | |
| aide | PASS | |
| keylime_server | PASS | |

**Not tested / special:**

| Role | Status | Notes |
|------|--------|-------|
| firewall | PASS (both) | Upstream has vars but NO loader — local `fc97bcc` adds `set_vars.yml` (see Pending Reviews) |
| postgresql | PASS | 3-file fix: vars/Suse.yml + tasks + meta; 7/7 PASS Leap 15.6 |
| ad_integration | SLE 16 only | Full AD join untested (needs AD infra) |
| ha_cluster | Ship | Needs HA Extension subscription |
| mssql | Ship | Needs SQL Server license |

**NOT VIABLE — Do not ship:**

| Role | Blocker |
|------|---------|
| bootloader | `grubby` has 13 invocations; no SUSE equivalent. 400-600 LOC rewrite for dual grubby/grub2 backends |
| kdump | Three blockers: grubby, config format mismatch (INI vs shell vars), distro hardcoding. Hackweek fork exists at Spectro34/kdump `fix/suse-support` PR #267 |
| storage | `blivet` (~2000 LOC) — Red Hat-exclusive Python library, not in any SUSE repo. 300-500 hr rewrite |
| vpn | No libreswan in SLES |
| tlog | No tlog/authselect |
| nbde_server | No tang package |
| nbde_client | Clevis not yet in SLFO |
| fapolicyd | Red Hat-only hard check |

---

### SUSE Package Name Mappings

| RHEL Name | SUSE Name | Used By |
|-----------|-----------|---------|
| `iproute` | `iproute2` | logging, kdump, general |
| `python3-firewall` | `python311-firewall` (SLE 15) / `python3-firewall` (SLE 16) | firewall |
| `python3-configobj` | `python311-configobj` (SLE 15) / `python3-configobj` (SLE 16) | kernel_settings |
| `python3-gobject-base` | `python3-gobject` (no `-base` suffix) | network |
| `typelib-1_0-NM-1_0` | (separate package on SUSE, SLE 16) | network NM GIR bindings |
| `procps-ng` | `procps` | kernel_settings tests |
| `openssh-clients` | `openssh` | ssh/sshd, kdump |
| `rsyslog-gnutls` | `rsyslog-module-gtls` | logging TLS |
| `network-scripts` | (does not exist) | network initscripts provider |
| `grubby` | (does not exist) | bootloader/kdump — hard blocker |
| `python3-blivet` | (does not exist) | storage — hard blocker |
| PKI path `/etc/pki/tls/` | `/etc/ssl/` | logging, certificate |
| `syslog-service` | `syslog-service` | logging — must be reinstalled with rsyslog |

**SLE 15 dual-Python rule**: System Python = 3.6; Ansible uses `python311`. Any `python3-foo` installs for 3.6 (invisible to Ansible). Always use `python311-foo` on SLE 15 managed nodes.

---

### set_vars.yml — The Critical Pattern

The standard LSR vars loading mechanism. Without it, `vars/Suse.yml` files are dead code.

```yaml
# tasks/set_vars.yml — include_vars loop (standard pattern, 14+ roles use this)
- name: Set platform/version specific variables
  include_vars: "{{ item }}"
  loop: >-
    {{ query('first_found', __rolename_vars_files, errors='ignore') }}
  vars:
    __rolename_vars_files:
      - "{{ ansible_facts['distribution'] }}_{{ ansible_facts['distribution_version'] }}.yml"
      - "{{ ansible_facts['distribution'] }}_{{ ansible_facts['distribution_major_version'] }}.yml"
      - "{{ ansible_facts['distribution'] }}.yml"
      - "{{ ansible_facts['os_family'] }}.yml"
      - "default.yml"
```

Wire into `tasks/main.yml` as the first task:
```yaml
- name: Set platform-specific variables
  include_tasks: set_vars.yml
```

**Lookup order** for SUSE systems:
1. `SLES_16.yml` / `SLES_15.yml` (distribution + major version)
2. `SLES.yml` / `openSUSE Leap.yml` (distribution)
3. `Suse.yml` (os_family — catches all SUSE variants)
4. `default.yml`

**Firewall role special case**: PR #300 (2025-11-03) added `vars/SLES_15.yml` and `vars/SLES_SAP_15.yml` but the role has NO `set_vars.yml`. Files are dead code without local patch `fc97bcc`.

---

### SLE Platform Constraints

| Constraint | SLE 15 SP7 | SLE 16 |
|-----------|-----------|--------|
| System Python | 3.6 | 3.11 |
| Ansible Python | python311 (3.11) | python3 (3.11) |
| Network stack | wicked (not NM) | NetworkManager |
| Containers | Containers Module (separate subscription) | Base product |
| SELinux | Not supported | Supported via SLFO |
| max ansible-core (managed node) | 2.16 | 2.20 |
| sudo config | `/etc/sudoers` exists | `/usr/etc/sudoers` (vendor); `/etc/sudoers` absent fresh |
| syslog | rsyslog + syslog-service (separate pkg) | same |
| PKI certs | `/etc/ssl/` | `/etc/ssl/` |
| Man pages | Stripped on Minimal VM (`%_excludedocs 1`) | same |

---

### Test Infrastructure

**Targets and ansible-core versions:**

| Target | Image | ansible-core | tox env |
|--------|-------|-------------|---------|
| SLE 15 SP7 | `~/iso/SLES15-SP7-Minimal-VM.x86_64-Cloud-GM.qcow2` | 2.18 | `qemu-ansible-core-2.18` |
| Leap 15.6 | `~/iso/openSUSE-Leap-15.6-Minimal-VM.x86_64-Cloud.qcow2` | 2.18 | `qemu-ansible-core-2.18` |
| SLE 16 | `~/iso/SLES-16.0-Minimal-VM.x86_64-Cloud-GM.qcow2` | 2.20 | `qemu-ansible-core-2.20` |
| Leap 16.0 | `~/iso/openSUSE-Leap-16.0-Minimal-VM.x86_64-Cloud.qcow2` | 2.20 | `qemu-ansible-core-2.20` |

**Test commands:**
```bash
# Single test
<paths.host_scripts>/lsr-test.sh upstream/<role> <image> [ac-ver] [test-playbook]

# Full matrix (all roles, all targets)
<paths.host_scripts>/run-all-tests.sh <image> <ac-ver>

# Retest failures
<paths.host_scripts>/retest-failing.sh <image> <ac-ver>

# Patch tox-lsr for SUSE (after every pip upgrade)
<paths.host_scripts>/patch-tox-lsr.sh [venv-path]
```

**tox-lsr SUSE patches** (applied by `patch-tox-lsr.sh`):
1. `disable_root: false` in cloud-init USER_DATA — SLES disables root SSH by default
2. `instance-id: iid-local01` in meta-data — SLES cloud-init requires instance-id for NoCloud

**community.general manual install** (tox-lsr doesn't auto-install it):
```bash
ANSIBLE_COLLECTIONS_PATH=upstream/<role>/.tox \
  upstream/<role>/.tox/qemu-ansible-core-2.18/bin/ansible-galaxy \
  collection install community.general
```

**SUSEConnect cleanup** (ephemeral registration per test run):
```bash
export LSR_QEMU_CLEANUP_YML=<paths.ansible_root>/testing/cleanup-suseconnect.yml
```

**Test result indicators:**
- PASS: Output ends with `"congratulations :)"`
- FAIL: Output ends with `"evaluation failed :("` — look for first `fatal:` line

---

### Upstream PR Status

| Role | Fork Branch | Status | Notes |
|------|------------|--------|-------|
| ssh (ansible-sshd) | fix/suse-support | **Merged** 2026-02-17 | 13 files; vars/Suse.yml + tests + meta |
| firewall (vars) | — | **Merged** PR #300 | Dead code — no set_vars.yml loader |
| firewall (set_vars) | fix/suse-set-vars | Pending | set_vars.yml + main.yml wire + vars/SLES_16.yml |
| sudo | fix/suse-support | Pending (not submitted) | scan_sudoers fix; 28/28 PASS |
| network | fix/suse-gobject-package | Pending (fork ready) | gobject + typelib in defaults/main.yml |
| postgresql | fix/suse-support | Pending | vars/Suse.yml + tasks + meta; 7/7 PASS |
| metrics (ansible-pcp) | fix/suse-pcp-support | Pending | pcp/vars/Suse.yml + meta |
| kernel_settings | fix/suse-support | Pending (not submitted) | python311-configobj + procps fix |
| logging | (no fork yet) | Optional | Spectro34 fork has fix |
| kdump | fix/suse-support | In progress (PR #267) | Full SUSE support; hackweek origin |

All forks: `https://github.com/Spectro34/<rolename>` on branch `fix/suse-support` (or variant).

---

### OBS Workflow

**Projects:**

| Project | Purpose |
|---------|---------|
| `devel:sap:ansible/ansible-linux-system-roles` | Development (maintainers: hsharma, mmamula) |
| `openSUSE:Factory/ansible-linux-system-roles` | Production (Tumbleweed) |
| `systemsmanagement:ansible` | Ansible ecosystem packages |

**Submission flow:**
```
home:<user>:branches:devel:sap:ansible  →(osc sr)→  devel:sap:ansible  →(osc sr)→  openSUSE:Factory
```

**Key osc commands:**
```bash
osc bco devel:sap:ansible ansible-linux-system-roles   # Branch and checkout
osc service runall                                       # Download tarballs from SUSE GitHub forks
osc vc                                                   # Edit .changes
osc addremove                                            # Stage changes
osc build openSUSE_Tumbleweed x86_64                     # Local build test
osc ci -m "Update role versions"                         # Commit
osc sr -m "msg" devel:sap:ansible ansible-linux-system-roles openSUSE:Factory  # Submit
osc results devel:sap:ansible ansible-linux-system-roles # Monitor build
```

**SUSE GitHub fork conventions:**
- Fork URL: `https://github.com/SUSE/ansible-<rolename>`
- Branch: `suse-<version>` (e.g., `suse-1.11.6`)
- Tag: `<version>-suse` (e.g., `1.11.6-suse`)
- Source tarball: `https://github.com/SUSE/ansible-{role}/archive/refs/tags/{version}-suse.tar.gz`

**Spec file version globals** (OBS r12, 2026-03-11):
```
firewall=1.11.6  timesync=1.11.4  journald=1.5.2  ssh=1.7.1
crypto_policies=1.5.2  systemd=1.3.7  ha_cluster=1.29.1  mssql=2.6.6
suseconnect=1.0.1  auto_maintenance=1.120.5  postfix=1.6.6
# SLE 16 only:
certificate=1.4.4  selinux=1.11.1  podman=1.9.2  cockpit=1.7.4
aide=1.2.5  keylime_server=1.2.4
```

**Collection namespace**: `suse.linux_system_roles`
**Install path**: `/usr/share/ansible/collections/ansible_collections/suse/linux_system_roles/`

---

### Known Bugs and Workarounds

| Bug | Affects | Workaround |
|-----|---------|------------|
| boo#1254397 / bsc#1255313 | postfix on SLE 15 | Fixed in OBS r11; use `tests_postfix_suse.yml` with `postfix_manage_selinux: false` |
| boo#1259969 | Parallel rsync on SLE 16 | `ansible.posix.synchronize` fails with parallel targets; use `throttle: 1` |
| community.general cobbler | Tumbleweed/Slowroll (>= 10.7.0) | `TimeoutTransport` inherits HTTPS-only — breaks HTTP Cobbler endpoints |
| sudo scan_sudoers crash | SLE 16 / Leap 16 | `/etc/sudoers` missing; fix: `if not os.path.isfile(path): return {}` |
| logging rsyslog cleanup | SUSE | `syslog-service` auto-removed with rsyslog; add to `__rsyslog_base_packages` |
| network missing typelib | SLE 16 | `python3-gobject` (no `-base`), `typelib-1_0-NM-1_0` separate package |
| ansible-sshd man pages | SUSE Minimal VM | `%_excludedocs 1` strips man pages; clear macro + force-reinstall openssh |

---

### Hackweek 2026 Community Roles

Source: operator's separate clone (e.g. `~/github/hackweek-2026-system-roles/`) — not under the workspace tree

| Role | Upstream | Fork | SLES 16 | PR |
|------|---------|------|---------|-----|
| squid | robertdebock/ansible-role-squid | Spectro34/ansible-role-squid | PASS | PR #17 |
| apache | geerlingguy/ansible-role-apache | Spectro34/ansible-role-apache | PASS | PR #266 |
| nfs | geerlingguy/ansible-role-nfs | Spectro34/ansible-role-nfs | PASS | PR #55 |
| samba | geerlingguy/ansible-role-samba | Spectro34/ansible-role-samba | PASS | PR #15 |
| kea-dhcp | mrlesmithjr/ansible-kea-dhcp | Spectro34/ansible-kea-dhcp | PASS | PR #12 |
| bind | bertvv/ansible-role-bind | Spectro34/ansible-role-bind | PASS | PR #224 |
| kdump | linux-system-roles/kdump | Spectro34/kdump | PASS | PR #267 |
| snapper | aisbergg/ansible-role-snapper | Spectro34/ansible-role-snapper | PASS | Commit on fork |
| tftpd | robertdebock/ansible-role-tftpd | Spectro34/ansible-role-tftpd | PASS | Works as-is |

**Pattern for adding SUSE support to community roles:** add `vars/Suse.yml` or `vars/SLES_16.yml`, add `tasks/setup-Suse.yml` where needed, fix service names, update `meta/main.yml` platforms.

---

### Pending Review: firewall Role (4/5 reviews complete)

The firewall role has a critical finding under the 5-review gate in `LSR_PENDING_REVIEWS.md`:

- **Upstream v1.11.4** ships `vars/SLES_15.yml` (PR #300) but has NO `set_vars.yml` loader — the vars files are dead code
- **Local commit `fc97bcc`** (Spectro34, Feb 16, 2026) adds the missing `tasks/set_vars.yml` + `vars/SLES_16.yml`
- The original proposal incorrectly stated "No local patches are needed" — Reviews 2, 3, and 4 all flagged this as wrong
- **Accurate status**: SUSE support works but ONLY with local patch `fc97bcc`. This needs to be submitted upstream.
- **4/5 reviews complete**, all agree on the revision needed. One more review required to finalize.

---

### Session Log Summary (from LSR_PROGRESS.md)

**Session 2026-04-03 — network, kernel-settings, sudo, logging analysis:**
- kernel_settings and sudo already fixed (Apr 2 commits)
- network: SLE 15 N/A (wicked), SLE 16 PASS with gobject fix
- logging: Root cause identified (iproute vs iproute2, rsyslog-gnutls vs rsyslog-module-gtls)

**Session 2026-04-03 — logging completed:**
- 6 fixes: wrong packages, stale facts, rsyslog.conf regen, purge config, PKI path, semanage
- SLE 16 6/6 PASS (v17 log)

**Session 2026-04-03 — ansible-sshd completed:**
- Fixed: man page on Minimal VM, UsePAMCheckLocks, os_defaults assertion
- All 4 targets PASS (SLE 15 8/8, Leap 15 8/8, SLE 16 8/8, Leap 16 8/8)

**Current status**: ALL ROLES IN SCOPE COMPLETE. No remaining work items in LSR_PROGRESS.md.

---

### Role Fix Details (for reference when creating new patches)

**sudo** (commit `7e47081`):
- `library/scan_sudoers.py`: graceful handling of missing `/etc/sudoers`
- `tests/tasks/setup.yml`: pre-install sudo, backup only if exists
- `tests/tasks/cleanup.yml`: restore/delete based on backup presence
- `meta/main.yml`: added SUSE platform

**kernel_settings** (commit `130a95d`):
- `vars/SLES_15.yml`: `python311-configobj`
- `vars/openSUSE Leap_15.yml`: same
- `vars/SLES_SAP_15.yml`: same
- `meta/main.yml`: added SUSE platform
- `tests/tests_change_settings.yml`: `procps` not `procps-ng` on SUSE

**logging** (complex, multiple files):
- `roles/rsyslog/vars/Suse.yml`: SUSE packages (iproute2, rsyslog-module-gtls, syslog-service) + PKI path (`/etc/ssl/`)
- `tasks/main.yml`: reset stale `__rsyslog_output_files` fact
- `roles/rsyslog/tasks/main_core.yml`: reinstall tracking + `__rsyslog_has_config_files` fix
- `tasks/selinux.yml`: install `policycoreutils-python-utils` on SUSE before selinux role
- `tests/tests_basics_forwards.yml`: OS-aware PKI path variable

**ansible-sshd** (commit `230b94e`):
- `templates/sshd_config.j2`: added `UsePAMCheckLocks` option
- `tests/tests_all_options.yml`: clear `_excludedocs` macro + force-reinstall openssh
- `tests/tests_os_defaults.yml`: skip before==after assertion on SUSE

**network**:
- `vars/Suse.yml`: `__network_provider_current: nm` (force NM, not initscripts)
- SLE 15 is N/A by design (wicked, not NetworkManager)

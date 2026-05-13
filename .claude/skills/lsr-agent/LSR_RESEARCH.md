# Linux System Roles (LSR) Research

> Comprehensive research on LSR package structure, testing, OBS workflows, and upstream/downstream relationships.
> Last updated: 2026-04-04 (session 3)

---

## Progress Index

Topics completed — future sessions skip these:

| # | Topic | Key Finding |
|---|-------|-------------|
| 1–10 | Overview, Package Structure, Testing, OBS, Best Practices, Upstream/Downstream, Tools, Live Data, Test Harness, TMT/FMF | Foundational reference |
| 11–16 | Auto-Maintenance, Callback Plugins, Network Test Dir, SUSE Downstream Testing, .github Org Repo, tox-lsr Internals | CI/tooling deep dive |
| 17–21 | OBS Request/Review, Source Service Modes, Maintenance Updates, openQA, osc Reference | OBS workflow reference |
| 22–23 | Local Test Infrastructure, Test Matrix | SLE 15 SP7 + SLE 16 full results |
| 24–25 | Spec File Deep Dive, Version Upgrade Workflow | Packaging mechanics |
| 26 | Upstream PR Status | firewall, network, postgresql, metrics, sudo PRs pending/merged |
| 27 | Hackweek 2026 Community Roles | squid, apache, nfs, samba, kea-dhcp, bind, kdump, snapper |
| 28 | Observed Bugs | boo#1254397, boo#1259969, community.general cobbler bug |
| 29 | sudo Role SUSE PR | 28/28 PASS, fix for missing /etc/sudoers on SLE 16 |
| 30 | Network Role SUSE Status | SLE 15 out of scope (wicked), SLE 16 PASS with gobject+typelib fix |
| 31 | kernel_settings Role SUSE Support | PASS SLE 16/15 SP7 — python311-configobj fix, procps rename |
| 32 | logging Role SUSE Support | 6/6 PASS SLE 16 (Apr 2026) — rsyslog/Suse.yml + main_core.yml fix |
| 33 | bootloader Role SUSE Status | NOT VIABLE — grubby hard dependency (13 uses), major rewrite needed |
| 34 | kdump Role SUSE Status | NOT VIABLE upstream — grubby + config format + distro hardcoding |
| 35 | storage Role SUSE Status | NOT VIABLE — blivet (Red Hat Python library) unavailable on SUSE; 300–500 hr rewrite |

---

## Table of Contents

1. [Overview](#1-overview)
2. [Package Structure and Maintenance in openSUSE/SUSE](#2-package-structure-and-maintenance-in-opensusesuse)
3. [Testing Workflow](#3-testing-workflow)
4. [OBS Package Submission](#4-obs-package-submission)
5. [Best Practices for LSR Development](#5-best-practices-for-lsr-development)
6. [Upstream/Downstream Relationship](#6-upstreamdownstream-relationship)
7. [Common Tools](#7-common-tools)
8. [Live-Verified Data (April 2026)](#8-live-verified-data-april-2026)
9. [Test Harness (Legacy CI System)](#9-test-harness-legacy-ci-system)
10. [Testing Farm (TMT/FMF)](#10-testing-farm-tmtfmf)
11. [Auto-Maintenance Tooling (Deep Dive)](#11-auto-maintenance-tooling-deep-dive)
12. [Callback Plugins and Ansible Configuration](#12-callback-plugins-and-ansible-configuration)
13. [Network Role Test Directory (Reference Example)](#13-network-role-test-directory-reference-example)
14. [SUSE/openSUSE Downstream Testing](#14-suseopensuse-downstream-testing)
15. [.github Organization Repository (Deep Dive)](#15-github-organization-repository-deep-dive)
16. [tox-lsr Internal Details](#16-tox-lsr-internal-details)
17. [OBS Request and Review System](#17-obs-request-and-review-system)
18. [OBS Source Service Modes](#18-obs-source-service-modes)
19. [OBS Maintenance Updates Workflow (SLE/SLES)](#19-obs-maintenance-updates-workflow-slesles)
20. [openQA Integration](#20-openqa-integration)
21. [Complete osc Command Reference](#21-complete-osc-command-reference)
22. [Local SUSE LSR Test Infrastructure (Spectro34)](#22-local-suse-lsr-test-infrastructure-spectro34)
23. [LSR SUSE Test Matrix and Production Readiness (2026-02-18)](#23-lsr-suse-test-matrix-and-production-readiness-2026-02-18)
24. [RPM Spec File Deep Dive (ansible-linux-system-roles)](#24-rpm-spec-file-deep-dive-ansible-linux-system-roles)
25. [Version Upgrade Workflow and Ansible-core Compatibility](#25-version-upgrade-workflow-and-ansible-core-compatibility)
26. [Upstream PR Status and SUSE Patches](#26-upstream-pr-status-and-suse-patches)
27. [Hackweek 2026 — Community Ansible Roles for SLES](#27-hackweek-2026--community-ansible-roles-for-sles)
28. [Observed Bugs and Workarounds](#28-observed-bugs-and-workarounds)
29. [sudo Role — SUSE Support Upstream PR (2026-04-02)](#29-sudo-role--suse-support-upstream-pr-2026-04-02)
30. [Network Role — SUSE Status, SLE 15 Scope Decision, and Packaging Plan](#30-network-role--suse-status-sle-15-scope-decision-and-packaging-plan)
31. [kernel_settings Role — SUSE Support (2026-04-02)](#31-kernel_settings-role--suse-support-2026-04-02)
32. [logging Role — SUSE Support and Full Fix (2026-04-03)](#32-logging-role--suse-support-and-full-fix-2026-04-03)
33. [bootloader Role — Not Viable for SUSE](#33-bootloader-role--not-viable-for-suse)
34. [kdump Role — Not Viable Upstream (Hackweek Fork Exists)](#34-kdump-role--not-viable-upstream-hackweek-fork-exists)
35. [storage Role — Not Viable for SUSE (blivet dependency)](#35-storage-role--not-viable-for-suse-blivet-dependency)

---

## 1. Overview

Linux System Roles (LSR) is a collection of Ansible roles and modules providing a stable, consistent configuration interface for managing GNU/Linux systems. The project abstracts from particular implementations, using native libraries and interfaces (dbus, libnm, etc.) rather than CLI commands.

### Supported Distributions
- Fedora
- Red Hat Enterprise Linux (RHEL 6+)
- CentOS and CentOS Stream
- openSUSE and SUSE Linux Enterprise (SLE SP6+)

### Upstream Organization
- **GitHub**: https://github.com/linux-system-roles
- **Website**: https://linux-system-roles.github.io/
- **Galaxy**: `fedora.linux_system_roles` collection
- **Mailing list**: systemroles@lists.fedorahosted.org
- **IRC**: #systemroles on Libera.chat

### 30+ Available Roles (Upstream)

| Category | Roles |
|----------|-------|
| Network & Security | network, selinux, firewall, vpn, ssh, certificate, crypto_policies |
| Storage & Boot | storage, kdump, snapshot (lvm), bootloader, gfs2 |
| System Management | timesync, kernel_settings, ad_integration, sudo |
| Monitoring & Logging | logging, tlog, metrics, journald |
| Databases | postgresql, mssql |
| Container & Virtualization | podman |
| Other Services | postfix, ha_cluster, cockpit, keylime_server, fapolicyd, nbde_server, nbde_client, rhc, systemd |

---

## 2. Package Structure and Maintenance in openSUSE/SUSE

### 2.1 Package Name and Collection Namespace

- **RPM package**: `ansible-linux-system-roles`
- **Collection namespace**: `suse.linux_system_roles`
- **Install**: `sudo zypper install ansible-linux-system-roles`

### 2.2 Installation Paths

```
/usr/share/ansible/collections/ansible_collections/suse/linux_system_roles/
  roles/           # Individual role directories
  docs/            # Per-role README and documentation
  galaxy.yml       # Collection metadata
```

### 2.3 Roles Included in SUSE Package (v1.1.0)

The SUSE package bundles multiple upstream roles with independent version tracking:

| Role | Version | Notes |
|------|---------|-------|
| firewall | 1.11.6 | |
| timesync | 1.11.4 | |
| journald | 1.5.2 | |
| ssh | 1.7.1 | |
| crypto_policies | 1.5.2 | |
| systemd | 1.3.7 | |
| ha_cluster | 1.29.1 | |
| mssql | 2.6.6 | |
| suseconnect | 1.0.1 | SUSE-specific role |
| auto_maintenance | 1.120.5 | Build tooling (lsr_role2collection.py) |
| postfix | 1.6.6 | |
| certificate | 1.4.4 | SLE16+ only |
| selinux | 1.11.1 | SLE16+ only |
| podman | 1.9.2 | SLE16+ only |
| cockpit | 1.7.4 | SLE16+ only |
| aide | 1.2.5 | SLE16+ only |
| keylime_server | 1.2.4 | SLE16+ only |

### 2.4 Spec File Structure

The spec file (`ansible-linux-system-roles.spec`) follows this pattern:

```spec
# Per-role version globals
%global firewall_version 1.11.6
%global timesync_version 1.11.4
# ... etc for each role

# SLE16 conditional for newer roles
%if 0%{?suse_version} >= 1600
%global sle16 1
%endif

%define ansible_collection_name linux_system_roles
%define ansible_collection_path %{_datadir}/ansible/collections/ansible_collections/suse/%{ansible_collection_name}

Name:           ansible-linux-system-roles
Version:        1.1.0
BuildArch:      noarch
License:        GPL-3.0-or-later
URL:            https://github.com/SUSE

# Sources: one tarball per role from SUSE GitHub forks
Source0:  https://github.com/SUSE/ansible-firewall/archive/refs/tags/%{firewall_version}-suse.tar.gz
Source1:  https://github.com/SUSE/ansible-timesync/archive/refs/tags/%{timesync_version}-suse.tar.gz
# ... etc

Requires:       ansible >= 9
Requires:       ansible-core >= 2.16
```

**Key aspects of the spec file**:
- Each role is a separate source tarball from SUSE's GitHub forks (`https://github.com/SUSE/ansible-<role>`)
- Tags use the pattern `<version>-suse` (e.g., `1.11.6-suse`)
- The `auto_maintenance` role provides `lsr_role2collection.py` which converts individual roles into the `suse.linux_system_roles` collection format
- Some roles are conditional on SLE16+ (`%if %{sle16}`)
- Build process: extract all role tarballs -> run `lsr_role2collection.py` for each -> `ansible-galaxy collection build` -> `ansible-galaxy collection install` into buildroot
- HTML README processing strips "Optional Requirements" and "Compatibility" sections
- Post-install creates compatibility symlinks under `/usr/share/ansible/roles/` for both `fedora.linux_system_roles.<role>` and `linux-system-roles.<role>` namespaces

### 2.5 OBS Source Services (`_service` file)

```xml
<services>
  <service name="download_files" mode="manual"/>
  <service name="set_version" mode="manual"/>
</services>
```

- `download_files` resolves `Source:` URLs in the spec file and downloads tarballs from GitHub
- `set_version` syncs version strings
- Both run in `manual` mode (triggered explicitly with `osc service runall`, not on commit)

### 2.6 galaxy.yml

Defines the Ansible Galaxy collection metadata:
- **namespace**: `suse`
- **name**: `linux_system_roles`
- **repository**: Points to `https://linux-system-roles.github.io`
- **license**: Mix of GPL-2.0, GPL-3.0, LGPL-3.0, MIT, BSD-3-Clause
- **build_ignore**: Excludes tests, CI configs, `.gitlab-*`, `.fmf`, etc.

### 2.7 OBS Project Locations

| Project | Purpose |
|---------|---------|
| `openSUSE:Factory/ansible-linux-system-roles` | Production (Tumbleweed) |
| `devel:sap:ansible/ansible-linux-system-roles` | Development project (devel project for Factory) |
| `systemsmanagement:ansible` | Ansible ecosystem packages (ansible-core, ansible-lint, molecule, etc.) |
| `Kernel:tools/ansible-linux-system-roles` | Alternative build |
| `openSUSE:Slowroll:Build:*` | Slowroll distribution |
| `home:hsharma/*` | Maintainer's branches |

#### Project Maintainers (from live OBS data)

- **`systemsmanagement:ansible`** (40+ packages): Maintained by lrupp, mwilck, ojkastl_buildservice, trenn, factory-maintainers group. Repos: openSUSE_Tumbleweed, SLE 16.0, 15.7, 15.6. Contains: ansible, ansible-core (2.16-2.19), ansible-9 through ansible-12, ansible-builder, ansible-lint, ansible-navigator, ansible-runner, molecule, molecule-plugins, python-ansible-compat, python-ruamel.yaml, python-yamllint, semaphore, and more.
- **`devel:sap:ansible`**: Maintained by hsharma, mmamula, factory-maintainers group. Repos: openSUSE_Tumbleweed, Leap 16.0, 16.1, Backports for SLE 15-SP6/SP7, SLE 16.0/16.1. Contains: ansible-linux-system-roles, ansible-sap-infrastructure, ansible-sap-install, ansible-sap-launchpad, ansible-sap-operations, ansible-sap-playbooks.

### 2.8 SUSE GitHub Forks

SUSE maintains forked repos under `https://github.com/SUSE/` with naming pattern `ansible-<rolename>`:
- `SUSE/ansible-firewall`
- `SUSE/ansible-timesync`
- `SUSE/ansible-journald`
- `SUSE/ansible-ssh`
- `SUSE/ansible-crypto_policies`
- `SUSE/ansible-systemd`
- `SUSE/ansible-ha_cluster`
- `SUSE/ansible-mssql`
- `SUSE/ansible-suseconnect` (SUSE-only)
- `SUSE/ansible-auto_maintenance` (build tooling)
- `SUSE/ansible-postfix`
- `SUSE/ansible-certificate`
- `SUSE/ansible-selinux`
- `SUSE/ansible-podman`
- `SUSE/ansible-cockpit`
- `SUSE/ansible-aide`
- `SUSE/ansible-keylime_server`

---

## 3. Testing Workflow

### 3.1 Test Infrastructure: tox-lsr

The primary testing tool is **tox-lsr**, a tox plugin specifically for linux-system-roles:

- **Repo**: https://github.com/linux-system-roles/tox-lsr
- **Install**: `pip install --user git+https://github.com/linux-system-roles/tox-lsr@main`
- **Verify**: `tox --help | grep lsr-enable`

#### Real tox.ini (from network role)

```ini
[lsr_config]
lsr_enable = true

[lsr_yamllint]
configfile = {toxinidir}/.yamllint.yml
configbasename = .yamllint.yml

[lsr_ansible-lint]
configfile = {toxinidir}/.ansible-lint

[testenv]
setenv =
    RUN_PYLINT_EXCLUDE = ^(\..*|ensure_provider_tests\.py|print_all_options\.py)$
    RUN_PYTEST_SETUP_MODULE_UTILS = true
    RUN_PYLINT_SETUP_MODULE_UTILS = true
    RUN_PYTEST_EXTRA_ARGS = -v
    RUN_FLAKE8_EXTRA_ARGS = --exclude tests/ensure_provider_tests.py,...
    LSR_PUBLISH_COVERAGE = normal
```

#### Environment Variables

| Variable | Purpose |
|----------|---------|
| `RUN_PYTEST_EXTRA_ARGS` | Additional pytest arguments |
| `RUN_PYLINT_EXTRA_ARGS` | Additional pylint arguments |
| `RUN_YAMLLINT_EXTRA_ARGS` | Additional yamllint arguments |
| `RUN_FLAKE8_EXTRA_ARGS` | Additional flake8 arguments |
| `RUN_BLACK_EXTRA_ARGS` | Additional black arguments |
| `RUN_SHELLCHECK_EXTRA_ARGS` | Additional shellcheck arguments |
| `RUN_ANSIBLE_LINT_EXTRA_ARGS` | Extra args for ansible-lint |
| `LSR_PUBLISH_COVERAGE` | Coverage mode: `strict`, `debug`, `normal` |
| `LSR_TESTSDIR` | Test artifacts directory |
| `LSR_ROLE2COLL_VERSION` | Override role2collection version/tag |
| `LSR_ROLE2COLL_NAMESPACE` | Collection namespace (default: `fedora`) |
| `LSR_ROLE2COLL_NAME` | Collection name (default: `linux_system_roles`) |
| `LSR_ANSIBLE_TEST_DEBUG` | Enable debug output for ansible-test |
| `LSR_CONTAINER_RUNTIME` | Container engine (default: `podman`) |
| `LSR_MOLECULE_DRIVER_VERSION` | Override molecule driver version |

### 3.2 Available tox Test Environments

**Linting/Code quality:**
| Environment | Purpose |
|-------------|---------|
| `black` | Python code formatting |
| `flake8` | Python linting |
| `pylint` | Python static analysis |
| `shellcheck` | Shell script validation |
| `yamllint` | YAML validation |
| `ansible-lint` | Ansible playbook linting |
| `ansible-lint-collection` | Collection-specific linting |

**Unit testing:**
| Environment | Purpose |
|-------------|---------|
| `pytest` | Python unit tests |
| `py26`, `py27`, `py38`-`py313` | Version-specific Python tests |

**Collection conversion:**
| Environment | Purpose |
|-------------|---------|
| `collection` | Convert role to Ansible collection format |
| `ansible-test` | Run ansible-test sanity checks on collection |

**Integration testing (QEMU/KVM):**
| Environment | Purpose |
|-------------|---------|
| `qemu-ansible-core-2-16` through `qemu-ansible-core-2-20` | QEMU integration tests per Ansible version |
| `qemu-ansible-2-9` | Legacy Ansible 2.9 QEMU tests |

**Integration testing (Container):**
| Environment | Purpose |
|-------------|---------|
| `container-ansible-core-2-16` through `container-ansible-core-2-20` | Container integration tests per Ansible version |

### 3.2.1 Running Tests Locally

```bash
# Linting
tox -e ansible-lint
tox -e black,flake8
tox -e yamllint
tox -e pylint
tox -e shellcheck

# Python unit tests for specific version
tox -e py311

# Collection conversion + ansible-test sanity
tox -e collection,ansible-test

# QEMU integration tests
tox -e qemu-ansible-core-2-20 -- --image-name centos-9 tests/tests_default.yml

# Batch mode (run all test playbooks)
tox -e qemu-ansible-core-2-20 -- --image-name centos-9 --make-batch --log-level debug --

# Collection integration tests via QEMU
tox -e collection
tox -e qemu-ansible-core-2-20 -- --image-name centos-10 --collection \
  .tox/ansible_collections/fedora/linux_system_roles/tests/ROLE/tests_default.yml

# Documentation testing
LSR_ANSIBLE_TEST_DEBUG=true LSR_ANSIBLE_TEST_TESTS=ansible-doc tox -e collection,ansible-test
```

### 3.3 Container Testing

- Uses **podman** with the Ansible podman connection plugin
- Roles tagged with `container` in `meta/main.yml` have container tests enabled in CI
- Tests run against multiple Ansible versions (e.g., `container-ansible-2.9`, `container-ansible-core-2.x`)

### 3.4 QEMU/KVM Testing

```bash
# Install prerequisites
sudo dnf install -y tox qemu-system-x86-core buildah podman
pip install tox tox-lsr standard-test-roles-inventory-qemu

# Download config
curl -s -L -o ~/.config/linux-system-roles.json \
  https://raw.githubusercontent.com/linux-system-roles/linux-system-roles.github.io/main/download/linux-system-roles.json

# Run tests
tox -e qemu-ansible-core-2-20 -- --image-name centos-9 tests/tests_default.yml
```

Test artifacts/logs are generated in the `artifacts/` directory.

#### QEMU Command-Line Options

| Option | Purpose |
|--------|---------|
| `--image-name centos-9\|centos-10\|fedora-42\|fedora-43\|leap-15.6` | Select test image |
| `--image-file /path/to/image.qcow2` | Use local image |
| `--make-batch` | Run all test playbooks in batch |
| `--collection` | Test collection instead of role |
| `--debug` | Enable debug output |
| `--log-level debug\|warning` | Logging level |
| `--use-snapshot` / `--erase-old-snapshot` | Snapshot management |
| `--skip-tags TAG` | Skip specific test tags |
| `--setup-yml playbook.yml` / `--cleanup-yml playbook.yml` | Pre/post playbooks |

### 3.5 CI/CD Pipeline (GitHub Actions)

#### Workflow Organization

The `.github` organization repo centralizes CI across all role repos:
- **Template files**: `playbooks/templates/` (matches role repo structure)
- **Inventory**: `inventory.yml` (master role registry with `active_roles` and `python_roles` groups)
- **Per-role config**: `inventory/host_vars/$ROLENAME.yml`
- **Update automation**: `playbooks/update_files.yml` creates PRs across all roles

#### Complete Workflow Files (from network role)

| Workflow File | Purpose |
|--------------|---------|
| `ansible-lint.yml` | Converts role to collection, runs ansible-lint |
| `ansible-test.yml` | Converts role to collection, runs ansible-test sanity (pinned to tox-lsr@3.17.1) |
| `python-unit-test.yml` | Matrix of Python versions (2.6, 2.7, 3.9-3.13), runs pytest + linters |
| `qemu-kvm-integration-tests.yml` | Full QEMU/KVM and container integration test matrix |
| `shellcheck.yml` | Shell script linting |
| `markdownlint.yml` | Markdown linting |
| `codespell.yml` | Spell checking |
| `codeql.yml` | Security analysis |
| `woke.yml` | Inclusive language checking |
| `pr-title-lint.yml` | PR title Conventional Commits validation |
| `ansible-managed-var-comment.yml` | Check ansible_managed variable comments |
| `build_docs.yml` | Documentation building |
| `changelog_to_tag.yml` | Auto-tag releases from changelog |
| `test_converting_readme.yml` | Test README conversion |
| `tft.yml` / `tft_citest_bad.yml` | Testing Farm triggers |
| `weekly_ci.yml` | Weekly scheduled CI (Saturday noon, creates draft PR with `[citest]`) |

#### Trigger Conditions

All workflows trigger on `pull_request`, `push` to `main`, `merge_group` (checks_requested), and `workflow_dispatch` (manual). Can be skipped with `[citest_skip]` in PR title or commit message.

#### CI Trigger Commands (PR comments)

| Trigger | Action |
|---------|--------|
| `[citest]` | Run full integration test suite |
| `[citest bad]` | Re-run failed tests only |
| `[citest pending]` | Re-run pending tests |
| `[citest skip]` | Skip CI for this commit |
| `[citest commit:<sha1>]` | Whitelist specific commit |
| `needs-ci` label | Whitelist all PR commits |

#### QEMU/KVM Integration Test Matrix (network role)

**QEMU scenarios:**
| Image | Ansible Version |
|-------|----------------|
| centos-9 | ansible-core-2-16 |
| centos-10 | ansible-core-2-17 |
| fedora-42 | ansible-core-2-19 |
| fedora-43 | ansible-core-2-20 |
| leap-15.6 | ansible-core-2-18 |

**Container scenarios:** centos-9, centos-9-bootc, centos-10-bootc, fedora-42, fedora-43, fedora-42-bootc, fedora-43-bootc

#### File Synchronization

The `.github` repo manages which files are present/absent across all roles:
- `present_templates`: Template-generated files
- `present_files`: Static files
- `absent_files`: Files to remove
- `present_python_templates/files`: Python-role-specific variants

### 3.6 Linter Configuration Files

#### `.ansible-lint` (from network role)
```yaml
profile: production
extra_vars:
  network_provider: nm
  test_playbook: tests_default.yml
kinds:
  - yaml: "**/meta/collection-requirements.yml"
  - playbook: "**/tests/tests_*.yml"
  - tasks: "**/tests/*.yml"
  - playbook: "**/tests/playbooks/*.yml"
skip_list:
  - fqcn-builtins
  - var-naming[no-role-prefix]
exclude_paths:
  - tests/roles/
  - .github/
  - examples/roles/
mock_roles:
  - linux-system-roles.network
supported_ansible_also:
  - "2.14.0"
```

#### `.yamllint.yml` (from network role)
```yaml
ignore: |
  /.tox/
  tests/roles/
```

### 3.7 Python Compatibility Requirements

| Platform | Python Version |
|----------|---------------|
| EL6 | Python 2.6 |
| EL7 | Python 2.7 or 3.6 |
| EL8 | Python 3.6 |
| EL9 | Python 3.9 |
| Control node plugins | py36+ (plus py27/py26 for older) |

### 3.8 Role Repository Structure (complete)

```
<role>/
  tasks/main.yml                        # Required entry point
  defaults/main.yml                     # Default variables (low precedence)
  vars/main.yml                         # Role variables
  handlers/main.yml                     # Handlers
  meta/main.yml                         # Metadata: platforms, galaxy tags, min_ansible_version
  meta/collection-requirements.yml      # Collection dependencies
  library/                              # Custom Ansible modules
  module_utils/                         # Module utilities
  tests/
    tests_default.yml                   # Default test playbook
    tests_*.yml                         # Additional test playbooks
    unit/                               # Python unit tests
  examples/                             # Example playbooks
  molecule/                             # Molecule test scenarios
  .github/workflows/                    # CI workflow files (~17 workflows)
  tox.ini                               # tox-lsr configuration
  .ansible-lint                         # ansible-lint config
  .yamllint.yml                         # yamllint config
  .markdownlint.yaml                    # Markdown lint config
  .sanity-ansible-ignore-*.txt          # ansible-test sanity ignore files per version
  contributing.md                       # Role-specific contributing guide
  README.md                             # Documentation
  CHANGELOG.md                          # Version history (SemVer)
```

---

## 4. OBS Package Submission

### 4.1 osc CLI Basics

```bash
# Check osc is installed
osc --version   # Currently 1.25.0

# Configure build targets
osc meta prj -e home:USERNAME

# List available targets
osc ls -b API_URL
```

### 4.2 Package Creation Workflow

```bash
# 1. Checkout home project
osc checkout home:USERNAME

# 2. Create new package
osc mkpac PACKAGE_NAME

# 3. Add source files and spec
#    - Download upstream tarballs
#    - Create/update .spec file
#    - Add files
osc add *

# 4. Generate changelog
osc vc

# 5. Local build test
osc build openSUSE_Tumbleweed x86_64

# 6. Commit to OBS
osc commit
```

### 4.3 Branch and Submit Workflow

```bash
# 1. Branch from devel project
osc branch devel:sap:ansible ansible-linux-system-roles

# 2. Checkout branch
osc checkout home:USERNAME:branches:devel:sap:ansible ansible-linux-system-roles

# 3. Make changes (update sources, spec, changelog)
#    ... edit files ...
osc vc        # Update changelog
osc addremove # Stage file changes

# 4. Commit
osc commit -m "Update to version X.Y.Z"

# 5. Submit to devel project
osc submitrequest --message='Update role versions' \
  home:USERNAME:branches:devel:sap:ansible \
  ansible-linux-system-roles \
  devel:sap:ansible

# 6. After devel project accepts, submit to Factory
osc sr -m "Updated ansible-linux-system-roles" \
  devel:sap:ansible ansible-linux-system-roles \
  openSUSE:Factory
```

### 4.4 Factory Submission Rules

- Every Factory package **must** have a development project (devel project)
- `home:` namespace **cannot** be a devel project for Factory
- Submit requests go: `home:branch` -> `devel:project` -> `openSUSE:Factory`
- Two-stage process: devel acceptance does NOT auto-submit to Factory

### 4.5 Complete osc Command Reference

**Searching and browsing:**
```bash
osc ls <project>                          # List packages in a project
osc ls <project> <package>                # List source files in a package
osc cat <project> <package> <file>        # Print file contents from OBS
osc se <name>                             # Search for projects/packages
osc se -s <name>                          # Search source packages only
osc dp <project> <package>                # Show devel project for a package
osc meta prj <project>                    # Show project metadata (repos, arches)
osc meta pkg <project> <package>          # Show package metadata
osc results <project> <package>           # Build results per repo/arch
```

**Branching and checking out:**
```bash
osc branch <project> <package>            # Branch to home:<user>:branches:<project>
osc branch <project> <package> <target>   # Branch to specific target project
osc bco <project> <package>               # Branch AND checkout in one step
osc co <project> <package>                # Checkout existing package locally
osc co <project>                          # Checkout entire project
```

**Making changes locally:**
```bash
osc add <file>                            # Stage a new file
osc rm <file>                             # Stage a file for removal
osc ar                                    # Auto add new / remove deleted files
osc diff                                  # Show uncommitted changes
osc st                                    # Status of local working copy
osc revert <file>                         # Undo local changes
osc vc                                    # Edit .changes file (opens editor)
```

**Building and committing:**
```bash
osc build                                 # Local build (uses default repo/arch)
osc build openSUSE_Tumbleweed x86_64      # Local build for specific target
osc service runall                        # Run all source services locally
osc ci -m "message"                       # Commit to OBS (alias: osc commit)
```

**Build logs and results:**
```bash
osc bl <repo> <arch>                      # Remote build log
osc blt <repo> <arch>                     # Tail of build log
osc lbl                                   # Local build log
osc r                                     # Build results summary
osc shell <repo> <arch>                   # Enter build root shell for debugging
```

**Submit requests:**
```bash
osc sr                                    # Submit to parent project (from branch)
osc sr -m "description"                   # Submit with message
osc sr <src-prj> <pkg> <dst-prj>          # Submit specific source to destination
osc rq show <id>                          # View a submit request
osc my rq                                 # List your pending requests
```

**Package linking and aggregation:**
```bash
osc linkpac <src-project> <package>       # Link (clone for modifications)
osc aggregatepac <src-project> <package>  # Aggregate (copy without modification)
osc meta prj -e <project>                 # Edit project metadata
```

### 4.6 Dependency Management

Edit project metadata to add paths:
```xml
<repository name="openSUSE_Tumbleweed">
  <path project="devel:languages:python" repository="openSUSE_Factory"/>
  <arch>x86_64</arch>
</repository>
```
Path order matters - entries searched top-to-bottom.

### 4.7 LSR-Specific Update Workflow

When updating roles in `ansible-linux-system-roles`:
1. Bump each role's `%global <role>_version` macro in the spec file
2. Run `osc service runall` to download new tarballs from SUSE GitHub tags
3. Update the `.changes` file with per-role change summaries (`osc vc`)
4. Commit to branch, verify builds succeed across all targets
5. Submit to `devel:sap:ansible`, then to `openSUSE:Factory`

### 4.8 Package Flow Diagram

```
GitHub (SUSE/ansible-<role> repos, tagged releases with -suse suffix)
    |
    v  (download_files service fetches tarballs)
home:<user>:branches:devel:sap:ansible/ansible-linux-system-roles  (your branch)
    |
    v  (osc sr)
devel:sap:ansible/ansible-linux-system-roles  (devel project, maintainers: hsharma, mmamula)
    |
    v  (osc sr to Factory)
openSUSE:Factory/ansible-linux-system-roles  (staging/review, automated checks)
    |
    v  (automated)
openSUSE:Tumbleweed / openSUSE:Leap  (release)
```

### 4.9 Submit Request States

SRs can be in states: `new`, `review`, `accepted`, `declined`, `revoked`. Factory has automated checks: legal review (license compliance), rpmlint, installability.

### 4.10 Modern Git-Based Workflow (2026+)

openSUSE is transitioning to a Git-based packaging workflow:
- Contributors send pull requests on Gitea instead of submit requests to devel projects
- Handled via Gitea Web interface or `git-obs` tool
- See: https://en.opensuse.org/openSUSE:Git_Packaging_Workflow

---

## 5. Best Practices for LSR Development

### 5.1 Contributing Workflow

1. **Fork and branch** the role repository
2. Keep fork synced: `git pull --rebase upstream main`
3. Use signed commits: `git commit -s`
4. Subject line: 50 chars max, imperative mood
5. Body: wrap at 72 characters
6. PR titles: Conventional Commits (`feat:`, `fix:`, `docs:`, `fix!:` for breaking)

### 5.2 Pre-Submission Checklist

```bash
# Run all linters
tox

# Specific checks
tox -e ansible-lint       # Ansible files
tox -e black,flake8       # Python code
tox -e yamllint           # YAML syntax

# Integration tests
tox -e qemu-ansible-core-2-20 -- --image-name centos-9 tests/tests_default.yml
```

### 5.3 Coding Standards

**Ansible:**
- Follow LSR "Recommended Practices" for naming, providers, check mode, idempotency
- Proper YAML/Jinja2 syntax
- Comprehensive documentation in role README

**Python:**
- PEP 8 compliance
- Automatic formatting with Python Black
- Unit tests in `tests/unit/`

### 5.4 Role Structure Requirements

```
<role>/
  tasks/main.yml              # Required entry point
  defaults/main.yml           # Default variables
  vars/main.yml               # Role variables
  handlers/main.yml           # Handlers
  meta/main.yml               # Metadata (platforms, dependencies, tags)
  meta/collection-requirements.yml
  library/                    # Custom modules
  module_utils/               # Module utilities
  tests/
    tests_default.yml         # Test playbooks
    tests_*.yml
    unit/                     # Python unit tests
  examples/                   # Example playbooks
  README.md                   # Documentation
  CHANGELOG.md                # Version history (SemVer)
```

### 5.5 Release Process

1. **Individual role release**: Maintainers create GitHub release with SemVer tag
2. **Collection release**: Nightly GitHub Action checks for new role releases, creates updated collection on Galaxy
3. **Fedora RPM**: Packit automation creates PRs in Fedora dist-git
4. **SUSE RPM**: Manual process - update spec file version globals, download new tarballs, submit to OBS

---

## 6. Upstream/Downstream Relationship

### 6.1 Flow Diagram

```
Upstream (GitHub)                    Downstream (Distributions)
─────────────────                    ─────────────────────────

linux-system-roles/<role>     ──→    fedora.linux_system_roles (Galaxy)
     (individual repos)              │
                                     ├──→ Fedora RPM: linux-system-roles
                                     │    (automated via Packit)
                                     │
                                     ├──→ RHEL RPM: rhel-system-roles
                                     │    (redhat.rhel_system_roles)
                                     │
                                     └──→ SUSE: ansible-linux-system-roles
                                          (manual fork + adaptation)

SUSE/ansible-<role>           ──→    suse.linux_system_roles (RPM collection)
     (SUSE GitHub forks)             (built via OBS)
```

### 6.2 SUSE Adaptation Process

1. **Fork**: SUSE maintains forks at `github.com/SUSE/ansible-<role>`
2. **Tag convention**: `<version>-suse` (e.g., `1.11.6-suse`)
3. **SUSE-specific roles**: `suseconnect` (SUSE registration), `auto_maintenance` (build tooling)
4. **Collection namespace**: Changed from `fedora.linux_system_roles` to `suse.linux_system_roles`
5. **Build tooling**: `lsr_role2collection.py` (from auto_maintenance) converts roles to collection format
6. **Documentation**: HTML README processing strips upstream-specific sections ("Optional Requirements", "Compatibility")

### 6.3 Key Differences: Fedora vs SUSE

| Aspect | Fedora | SUSE |
|--------|--------|------|
| Package name | `linux-system-roles` | `ansible-linux-system-roles` |
| Collection namespace | `fedora.linux_system_roles` | `suse.linux_system_roles` |
| Automation | Packit (automated PRs) | Manual OBS submit |
| Source | Single collection tarball | Individual role tarballs |
| RHEL variant | `rhel-system-roles` / `redhat.rhel_system_roles` | N/A |
| Conditional roles | N/A | SLE16+ gating for some roles |
| SUSE-only roles | N/A | suseconnect, auto_maintenance |

### 6.4 Version Tracking

- Each upstream role uses **SemVer** with git tags
- SUSE tracks versions independently per role in spec file globals
- The overall `ansible-linux-system-roles` package version (e.g., `1.1.0`) is separate from individual role versions
- CHANGELOG.md in each role repo documents changes

---

## 7. Common Tools

### 7.1 Core Tools

| Tool | Purpose | Install |
|------|---------|---------|
| `osc` | OBS command-line client | `zypper install osc` |
| `tox` | Test runner/environment manager | `pip install tox` |
| `tox-lsr` | LSR-specific tox plugin | `pip install git+https://github.com/linux-system-roles/tox-lsr@main` |
| `ansible-lint` | Ansible linter | `pip install ansible-lint` |
| `yamllint` | YAML linter | `pip install yamllint` |
| `ansible-test` | Ansible's built-in test framework | Bundled with ansible-core |
| `molecule` | Ansible role testing (v3+) | `pip install molecule` |
| `podman` | Container runtime for tests | `zypper install podman` |
| `black` | Python formatter | `pip install black` |
| `flake8` | Python linter | `pip install flake8` |
| `pylint` | Python static analysis | `pip install pylint` |
| `pytest` | Python unit test runner | `pip install pytest` |
| `gh` | GitHub CLI | `zypper install gh` |

### 7.2 LSR-Specific Tools

| Tool | Location | Purpose |
|------|----------|---------|
| `lsr_role2collection.py` | `auto_maintenance` role | Converts individual roles to collection format |
| `standard-test-roles-inventory-qemu` | pip | QEMU test inventory plugin |
| `linux-system-roles.json` | `~/.config/` | Local test configuration |
| `test-harness` | https://github.com/linux-system-roles/test-harness | Integration test harness |

### 7.3 Ansible Configuration

```
Requires: ansible >= 9
Requires: ansible-core >= 2.16
```

---

## 8. Live-Verified Data (April 2026)

The following data was gathered from live queries against OBS, GitHub, and SUSE/Fedora infrastructure on 2026-04-02.

### 8.1 OBS Package Files (devel:sap:ansible)

Verified contents of the `devel:sap:ansible/ansible-linux-system-roles` package:

```
_service                              # OBS source service definition
ansible-linux-system-roles.changes    # Changelog
ansible-linux-system-roles.spec       # RPM spec file
galaxy.yml                            # Ansible Galaxy collection metadata
aide-1.2.5.tar.gz                     # Per-role source tarballs
auto_maintenance-1.120.5.tar.gz
certificate-1.4.4.tar.gz
cockpit-1.7.4.tar.gz
crypto_policies-1.5.2.tar.gz
firewall-1.11.6.tar.gz
ha_cluster-1.29.1.tar.gz
journald-1.5.2.tar.gz
keylime_server-1.2.4.tar.gz
mssql-2.6.6.tar.gz
podman-1.9.2.tar.gz
postfix-1.6.6.tar.gz
selinux-1.11.1.tar.gz
ssh-1.7.1.tar.gz
suseconnect-1.0.1.tar.gz
systemd-1.3.7.tar.gz
timesync-1.11.4.tar.gz
```

### 8.2 OBS Build Status

**devel:sap:ansible** (all `succeeded` as of 2026-04-02):
- openSUSE_Tumbleweed x86_64
- openSUSE_Leap_16.1 x86_64
- openSUSE_Leap_16.0 x86_64
- openSUSE_Backports_SLE-16.1 x86_64
- openSUSE_Backports_SLE-16.0_standard x86_64
- openSUSE_Backports_SLE-15-SP7_standard x86_64
- openSUSE_Backports_SLE-15-SP7_Update_standard x86_64
- openSUSE_Backports_SLE-15-SP6_Update_standard x86_64

**openSUSE:Factory** (standard x86_64): `succeeded`

### 8.3 OBS Commit History (devel:sap:ansible)

| Rev | Author | Date | Version | Description |
|-----|--------|------|---------|-------------|
| r12 | mmamula | 2026-03-11 | 1.1.0 | Major role upgrade (Ansible 2.19 compat, ansible_facts migration) |
| r11 | msuchanek | 2025-12-18 | -- | Enable postfix role on SLE 15 (bsc#1255313) |
| r10 | hsharma | 2025-08-18 | -- | Align galaxy.yml version with spec Version |
| r9 | hsharma | 2025-08-11 | -- | Add keylime_server role |
| r8 | hsharma | 2025-07-23 | -- | Add postfix role |
| r7 | hsharma | 2025-07-10 | -- | Add aide and cockpit roles |
| r6 | hsharma | 2025-06-27 | -- | Add selinux and podman roles |
| r5 | hsharma | 2025-06-25 | -- | Update suseconnect, certificate, ha_cluster |
| r4 | hsharma | 2025-06-09 | -- | Add SLE16 macro, include certificate on SLE16 |

### 8.4 SUSE GitHub Fork Branching Strategy

Each SUSE fork at `github.com/SUSE/ansible-<role>` uses a consistent branching pattern:

**Branch naming**: `suse-<version>` (e.g., `suse-1.11.6`, `suse-1.8.2`)
- Each SUSE adaptation version gets its own branch off `main`
- The `main` branch stays synced with upstream (where possible)
- Multiple suse-* branches may exist for different packaged versions

**Tag naming**: `<version>-suse` (e.g., `1.11.6-suse`, `1.8.2-suse`)
- Tags are created on the suse-* branches
- The `-suse` suffix distinguishes SUSE tags from upstream tags
- Both the plain upstream version tag AND the `-suse` tag may exist

**Example (SUSE/ansible-firewall)**:
```
Branches:  main, suse-1.8.2, suse-1.11.6, update_role_files, weekly-ci, ci-*, docs
Tags:      1.11.6, 1.11.6-suse, 1.8.2, 1.8.2-suse, 1.11.5, 1.11.4, ...
```

**Example (SUSE/ansible-ha_cluster)**:
```
Branches:  main, suse-1.22.1, suse-1.24.0, suse-1.29.1, weekly-ci, ci-*, docs
Tags:      1.29.1, 1.29.1-suse, 1.29.0, 1.28.1, ...
```

**Typical SUSE fork changes** (verified from `main...suse-1.11.6` diff on firewall, 94 commits):
- SUSE-specific `vars/` files: `vars/SLES_15.yml`, `vars/SLES_SAP_15.yml`
- Modified `tasks/` for SUSE package names and paths
- Updated `meta/main.yml` and `meta/collection-requirements.yml`
- Modified `library/` modules for SUSE compatibility
- Synced upstream CI/workflow files (`.github/workflows/`)
- Updated `.sanity-ansible-ignore-*.txt` files

### 8.5 SUSE-Only Role: suseconnect

The `suseconnect` role is unique to SUSE (forked from `HVSharma12/ansible-suseconnect`, not from upstream linux-system-roles). It handles:
- SUSE system registration with SCC (SUSE Customer Center) or SMT servers
- Module management for SLES
- Currently at version 1.0.1

Repository structure:
```
SUSE/ansible-suseconnect/
  defaults/    # Default variables
  meta/        # Role metadata
  tasks/       # Main tasks
  vars/        # Role variables
  README.md
  LICENSE
  PRODUCTS.md
```

### 8.6 Upstream Repository Inventory (57 repos)

All repositories under `github.com/linux-system-roles/`:

**Active Roles** (packaged in Fedora/RHEL):
ad_integration, aide, bootloader, certificate, cockpit, crypto_policies, fapolicyd, firewall, gfs2, ha_cluster, journald, kdump, kernel_settings, keylime_server, logging, metrics, mssql, nbde_client, nbde_server, network, podman, postfix, postgresql, rhc, selinux, snapshot, ssh, storage, sudo, systemd, timesync, tlog, tuned, vpn

**Infrastructure/Tooling repos**:
auto-maintenance, .github, tox-lsr, test-harness, ci-testing, tft-tests, template, meta_test, lsr-gh-action-py26, lsr-woke-action

**Execution Environments**:
ee_linux_system_roles, ee_linux_automation

**Other/Experimental**:
experimental-azure-firstboot, hpc, pam_pwd, trustee_client, trustee_server, sap-base-settings, sap-hana-preconfigure, sap-netweaver-preconfigure, sap-preconfigure, linux-system-roles.github.io

### 8.7 Fedora Spec File Comparison

The Fedora `linux-system-roles.spec` (version 1.121.0, from `src.fedoraproject.org`) differs significantly from the SUSE spec:

| Aspect | Fedora | SUSE |
|--------|--------|------|
| Package name | `linux-system-roles` (Fedora), `rhel-system-roles` (RHEL) | `ansible-linux-system-roles` |
| Version | 1.121.0 (matches auto-maintenance commit) | 1.1.0 (independent) |
| Collection namespace | `fedora`/`redhat` (conditional) | `suse` |
| Source tarballs | From upstream `linux-system-roles/<role>` tags | From SUSE forks `SUSE/ansible-<role>` with `-suse` tags |
| Role count | 33 roles | 17 roles (6 SLE16-only) |
| Build tool | `release_collection.py` + `galaxy_transform.py` | `lsr_role2collection.py` |
| Build automation | Packit (automated propose_downstream) | Manual |
| Source macro style | `%defcommit`/`%deftag` macros with auto-generated sources | Simple `%global <role>_version` + explicit Source lines |
| Conditional build | RHEL vs Fedora (`%if 0%{?rhel}`) | SLE16 vs older (`%if %{sle16}`) |
| Vendoring | RHEL vendoring support via `vendoring-prep.inc` | None |
| Compat symlinks | `linux-system-roles.<role>` + `rhel-system-roles.<role>` (RHEL) | `fedora.linux_system_roles.<role>` + `linux-system-roles.<role>` |
| README processing | Strips Requirements, Collection requirements | Strips Requirements, Collection requirements, Compatibility |
| sshd role | Includes (from willshersystems/ansible-sshd) | Not included |

**Fedora roles NOT in SUSE package**: kdump, network, storage, metrics, tlog, kernel_settings, logging, nbde_server, nbde_client, vpn, ad_integration, rhc, postgresql, fapolicyd, bootloader, snapshot, gfs2, sudo, sshd

**SUSE roles NOT in Fedora package**: suseconnect

### 8.8 Spec File Build Process Comparison

**SUSE build process** (simplified):
1. Extract each role tarball, rename from `ansible-<role>-<ver>-suse/` to `<role>/`
2. Process README.md and README.html (strip badges, internal links, sections)
3. Run `lsr_role2collection.py` per role (namespace=suse, collection=linux_system_roles)
4. Copy `galaxy.yml`, patch version
5. `ansible-galaxy collection build` to create tarball
6. `ansible-galaxy collection install` into buildroot
7. Post-install: create symlinks under `/usr/share/ansible/roles/`

**Fedora build process** (simplified):
1. Extract all role tarballs via `%setup -a` macro
2. Process README files (similar cleaning)
3. Run `release_collection.py` with `--galaxy-yml`, `--src-path`, per-role `--include`
4. `galaxy_transform.py` generates galaxy.yml with correct namespace/metadata
5. `%ansible_collection_install` macro (from `ansible-packaging`)
6. Install roles as both standalone (under `linux-system-roles.<role>`) and collection
7. Symlink CHANGELOG, README, LICENSE, examples into docdir

### 8.9 devel:sap:ansible Project Contents

| Package | Description |
|---------|-------------|
| ansible-linux-system-roles | Linux System Roles collection |
| ansible-sap-infrastructure | SAP infrastructure automation |
| ansible-sap-install | SAP installation automation |
| ansible-sap-launchpad | SAP media download via API |
| ansible-sap-operations | SAP operations automation |
| ansible-sap-playbooks | SAP playbook collection |

Maintainers: hsharma (Harshvardhan Sharma), mmamula (Marcel Mamula), factory-maintainers group.

### 8.10 Git Packaging Workflow Transition (2026)

openSUSE is transitioning to Git-based packaging. Key details from February 2026:
- **Platform**: Gitea at `src.opensuse.org`
- **Tool**: `git-obs` (installed automatically via `osc`)
- **Branch convention**: `leap-x.y` branches for different releases
- **Automation bots**:
  - `workflow-pr`: Handles PR lifecycles including reviews and merging
  - `workflow-direct`: Synchronizes submodules on push to trusted devel projects
  - `obs-staging-bot`: Creates isolated OBS testing environments for validation
- **Documentation**: https://src.opensuse.org/openSUSE/git-workflow-documentation
- This does NOT yet apply to `ansible-linux-system-roles` (still using traditional OBS workflow)

---

## 9. Test Harness (Legacy CI System)

The [test-harness](https://github.com/linux-system-roles/test-harness) is a container-based CI system that predates the GitHub Actions migration. It provides the architecture for running integration tests against VMs provisioned from within a container.

### 9.1 Architecture

- A **podman container** runs integration tests for open PRs
- Container executes all playbooks matching `tests/tests*.yml` against multiple VM images (identical to the Fedora Standard Test Interface pattern)
- Requires `/dev/kvm` access for QEMU acceleration
- Images are cached in `/cache` mount and reused across runs
- Deployable on Kubernetes/OpenShift clusters

### 9.2 Configuration (`config.json`)

```json
{
  "repositories": ["linux-system-roles/network", "..."],
  "images": [
    {
      "name": "centos-9",
      "source": "https://...",
      "upload_results": true,
      "setup": "dnf install -yv python2",
      "min_ansible_version": "2.8"
    }
  ],
  "results": {
    "destination": "user@host:/path/",
    "public_url": "https://..."
  },
  "logging": {
    "level": "info",
    "file_level": "debug",
    "stderr_level": "warning"
  }
}
```

The `setup` field supports both inline shell commands (executed via the Ansible `raw` module) and a list of Ansible plays saved as a playbook and executed before the test run.

### 9.3 Environment Variables

All command-line arguments map to environment variables with the prefix `TEST_HARNESS_` (uppercase, hyphens replaced with underscores).

**Precedence order** (highest to lowest):
1. Command-line arguments
2. Environment variables
3. `config.json` settings
4. Built-in defaults

### 9.4 Required Secrets

| File | Purpose |
|------|---------|
| `github-token` | API token with `public_repo`, `repo:status`, `read:org` scopes |
| `id_rsa` / `id_rsa.pub` | SSH keypair for result uploads |
| `known_hosts` | SSH server fingerprints |

The `read:org` permission is needed to identify users as members of organizations when membership is set to private.

### 9.5 Deployment

- `master` branch deploys to staging
- `production` branch deploys to production (requires `test_harness_use_production=true`)
- CentOS 7 uses alternate deployment names: `linux-system-roles-centos7` (production) and `linux-system-roles-centos7-staging`
- Uses OpenShift ServiceAccount `tester` with privileged SecurityContextConstraints
- Containers run as root for KVM access

---

## 10. Testing Farm (TMT/FMF)

The project also uses [Testing Farm](https://docs.testing-farm.io/) for Fedora-ecosystem testing, configured via TMT (Test Management Tool) and FMF (Flexible Metadata Format).

### 10.1 tft-tests Repository

- **Repo**: https://github.com/linux-system-roles/tft-tests
- Stores test plans for Testing Farm execution
- Structure: `.fmf/` config, `plans/` test plan definitions, `tests/` implementations
- Currently 102 commits, single plan and single test implementation, under active development

### 10.2 FMF and TMT Integration

- `.fmf` directory at project root marks it for Testing Farm
- Test plans defined in `plans/general.fmf`
- `provision.fmf` in role `tests/` directories defines provisioning metadata
- GitHub Actions workflows `tft.yml` and `tft_citest_bad.yml` trigger Testing Farm runs
- Testing Farm runs on AWS EC2 instances (same infrastructure as Fedora gating tests)

### 10.3 Execution

```bash
# Local execution with tmt
tmt try -p general CentOS-Stream-9

# Remote: triggered via "Schedule tests on Testing Farm" GitHub Action
# Supports multihost scenarios (with limitations for CLI execution)
```

### 10.4 Debugging Remote Tests

- Uncomment `reserve_system` discover step to keep test systems running (5-hour sleep)
- SSH into systems using 1minutetip credentials or custom keys via `ID_RSA_PUB`
- IP addresses available from uploaded `guests.yaml` artifacts
- `get_ssh_cmds.sh` utility script for SSH access to test systems

---

## 11. Auto-Maintenance Tooling (Deep Dive)

The [auto-maintenance](https://github.com/linux-system-roles/auto-maintenance) repo provides organization-wide build and release tooling.

### 11.1 lsr_role2collection.py -- Full Reference

**Core arguments:**

| Argument | Env Var | Default | Purpose |
|----------|---------|---------|---------|
| `--namespace` | `COLLECTION_NAMESPACE` | `fedora` | Collection namespace |
| `--collection` | `COLLECTION_NAME` | `system_roles` | Collection name |
| `--role` | `COLLECTION_ROLE` | - | Source role name |
| `--new-role` | `COLLECTION_NEW_ROLE` | - | Renamed role in collection |
| `--src-path` | `COLLECTION_SRC_PATH` | `$HOME/linux-system-roles` | Source directory |
| `--dest-path` | `COLLECTION_DEST_PATH` | `$HOME/.ansible/collections` | Destination |
| `--tests-dest-path` | - | - | Separate test destination |
| `--src-owner` | - | - | GitHub owner for role repository |
| `--replace-dot` | `COLLECTION_REPLACE_DOT` | `_` | Dot replacement in subrole names |
| `--subrole-prefix` | `COLLECTION_SUBROLE_PREFIX` | - | Subrole name prefix |
| `--extra-mapping` | - | - | Custom FQCN mappings |
| `--meta-runtime` | - | - | Custom runtime.yml |
| `--extra-script` | - | - | Post-conversion executable script |

**Logging:** `LSR_INFO=true` for INFO, `LSR_DEBUG=true` for DEBUG.

**File conversion mapping:**

| Original | Collection Path |
|----------|----------------|
| `myrole/README.md` | `roles/myrole/README.md` |
| `myrole/{defaults,files,handlers,meta,tasks,templates,vars}` | `roles/myrole/*` |
| `myrole/roles/mysubrole` | `roles/mysubrole` |
| `myrole/library/*.py` | `plugins/modules/*.py` |
| `myrole/module_utils/*.py` | `plugins/module_utils/myrole/*.py` |
| `myrole/tests/*.yml` | `tests/myrole/*.yml` |
| `myrole/{docs,examples,DCO}/*` | `docs/myrole/*` |
| `myrole/LICENSE*` | `LICENSE-myrole` |

**SUSE-specific invocation:**
```bash
python lsr_role2collection.py --role myrole --namespace suse --collection linux_system_roles
```
This converts `fedora.linux_system_roles` references to `suse.linux_system_roles` throughout. If `fedora.linux_system_roles:NAMESPACE.COLLECTION` is in the mapping, the FQCN references are automatically rewritten.

### 11.2 release_collection.py

Orchestrates the full collection release:
1. Checks roles for new versions, updates `collection_release.yml` refs
2. Converts each role via `lsr_role2collection.py`
3. Updates `galaxy.yml` version
4. Builds with `ansible-galaxy collection build`
5. Validates with `galaxy-importer` (requires Docker)
6. Optionally publishes to Galaxy

**Key options:**

| Option | Purpose |
|--------|---------|
| `--galaxy-yml` | Path to galaxy.yml (default: `./galaxy.yml`) |
| `--collection-release-yml` | Path to collection_release.yml |
| `--src-path` | Local role repository directory |
| `--dest-path` | Collection destination (default: `$HOME/.ansible/collections`) |
| `--force` | Remove existing collection directory before building |
| `--include ROLE1 ROLE2...` | Process only specified roles |
| `--exclude ROLE1 ROLE2...` | Skip specified roles |
| `--new-version X.Y.Z` | Explicitly set collection version |
| `--no-auto-version` | Disable automatic version calculation |
| `--publish` | Publish to Galaxy after building |
| `--skip-git` | Use local source without git operations |
| `--skip-check` | Skip galaxy-importer validation |
| `--skip-changelog` | Don't generate collection changelog |
| `--rpm FILE` | Build from RPM instead of upstream sources |

**Version calculation (SemVer):**
- Any role major bump -> collection major bump (reset minor/patch)
- Any role minor bump -> collection minor bump (reset patch)
- Any role patch bump -> collection patch bump

**`collection_release.yml` format:**
```yaml
ROLENAME:
  ref: TAG_OR_HASH_OR_BRANCH
  org: github-organization     # default: linux-system-roles
  repo: github-repo            # default: ROLENAME
  sourcenum: N                 # RPM spec Source number
```

### 11.3 Other Auto-Maintenance Scripts

| Script | Purpose |
|--------|---------|
| `manage-role-repos.sh` | Bulk operations across role repos via `gh` CLI and `jq` |
| `role-make-version-changelog.sh` | Create SemVer tags, generate changelogs, publish to Galaxy |
| `bz-manage.sh` | Bugzilla interaction (setitm, reset_dev_wb, clone_check, rpm_release, list_bzs) |
| `check_logs.py` | Analyze Beaker test logs |
| `manage_jenkins.py` | Jenkins CI interface for task management and failure analysis |

---

## 12. Callback Plugins and Ansible Configuration

### 12.1 Callback Plugins Used in Testing

| Plugin | Context | Control |
|--------|---------|---------|
| `profile_tasks` | QEMU tests | `LSR_QEMU_PROFILE=true/false` (default: true) |
| `debug` | Manual debugging | `ANSIBLE_STDOUT_CALLBACK=debug` |
| Custom error reporting | QEMU tests | `--lsr-report-errors-url` / `LSR_QEMU_REPORT_ERRORS_URL` |

### 12.2 QEMU Test Ansible Configuration

The QEMU test runner configures these Ansible behaviors:
- **Profile output**: Shows task timing (controlled by `--profile` / `LSR_QEMU_PROFILE`)
- **Profile task limit**: Max tasks shown (default: 30, via `--profile-task-limit` / `LSR_QEMU_PROFILE_TASK_LIMIT`)
- **Pretty printing**: Formatted output (default: true, via `--pretty` / `LSR_QEMU_PRETTY`)
- **Artifacts**: Provisioner logs go to `artifacts/` directory (via `--artifacts` / `LSR_QEMU_ARTIFACTS`)
- **Log file**: Output to file instead of stdout (`--log-file` / `LSR_QEMU_LOG_FILE`)
- **Log level**: Logging verbosity (default: warning, via `--log-level` / `LSR_QEMU_LOG_LEVEL`)

### 12.3 Complete QEMU Configuration Options

| Option | Env Var | Default | Purpose |
|--------|---------|---------|---------|
| `--config` | `LSR_QEMU_CONFIG` | `~/.config/linux-system-roles.json` | Image config file |
| `--cache` | `LSR_QEMU_CACHE` | `~/.cache/linux-system-roles` | Image cache directory |
| `--image-alias` | `LSR_QEMU_IMAGE_ALIAS` | - | Hostname override (`BASENAME` = filename) |
| `--inventory` | `LSR_QEMU_INVENTORY` | - | Custom inventory script |
| `--collection` | `LSR_QEMU_COLLECTION` | - | Run in collection context |
| `--debug` | `LSR_QEMU_DEBUG` | false | Interactive debugging |
| `--pretty` | `LSR_QEMU_PRETTY` | true | Pretty-print output |
| `--profile` | `LSR_QEMU_PROFILE` | true | Show profile_tasks timing |
| `--profile-task-limit` | `LSR_QEMU_PROFILE_TASK_LIMIT` | 30 | Max tasks in profile |
| `--use-yum-cache` | `LSR_QEMU_USE_YUM_CACHE` | false | Cache packages across runs |
| `--use-snapshot` | `LSR_QEMU_USE_SNAPSHOT` | false | Create backing snapshot |
| `--erase-old-snapshot` | `LSR_QEMU_ERASE_OLD_SNAPSHOT` | false | Delete existing snapshot first |
| `--wait-on-qemu` | `LSR_QEMU_WAIT_ON_QEMU` | false | Wait for QEMU exit between playbooks |
| `--setup-yml` | `LSR_QEMU_SETUP_YML` | - | Comma-delimited setup playbooks |
| `--cleanup-yml` | `LSR_QEMU_CLEANUP_YML` | - | Cleanup playbooks (always run) |
| `--write-inventory` | `LSR_QEMU_WRITE_INVENTORY` | - | Write generated inventory to file |
| `--post-snap-sleep-time` | `LSR_QEMU_POST_SNAP_SLEEP_TIME` | 1 | Sleep seconds after snapshot |
| `--log-file` | `LSR_QEMU_LOG_FILE` | - | Write output to file |
| `--log-level` | `LSR_QEMU_LOG_LEVEL` | warning | Logging verbosity |
| `--tests-dir` | `LSR_QEMU_TESTS_DIR` | - | Main test playbook directory |
| `--artifacts` | `LSR_QEMU_ARTIFACTS` | `artifacts/` | Provisioner log directory |
| `--ssh-el6` | `LSR_QEMU_SSH_EL6` | false | Enable EL6-specific SSH config |
| `--ansible-container` | `LSR_QEMU_ANSIBLE_CONTAINER` | - | Run Ansible from container |

### 12.4 QEMU Image Config File Format

```json
{
  "images": [
    {
      "name": "centos-10",
      "source": "https://cloud.centos.org/centos/10/...",
      "compose": "https://...",
      "variant": "BaseOS",
      "setup": ["play1", "play2"]
    }
  ]
}
```

### 12.5 Cleanup Playbook Variables

Cleanup playbooks (specified via `--cleanup-yml`) receive:
- `last_rc` (string) -- Return code: `"0"` for success, non-zero for failure
- These run regardless of test pass/fail

### 12.6 Manual Debug Testing

```bash
# Method 1: via tox-lsr
tox -e qemu-ansible-core-2-20 -- --image-name centos-9 --debug tests/tests_mytest.yml
grep ssh artifacts/default_provisioners.log | tail -1   # Get SSH command

# Method 2: direct ansible-playbook
cd tests
TEST_DEBUG=true ANSIBLE_STDOUT_CALLBACK=debug \
TEST_SUBJECTS=CentOS-8-GenericCloud-8.1.1911-20200113.3.x86_64.qcow2 \
ansible-playbook -vv -i /usr/share/ansible/inventory/standard-inventory-qcow2 \
  tests_default.yml

# Cleanup after debug session
pkill -f standard-inventory
```

### 12.7 Container Testing Debug

```bash
LSR_DEBUG=1 LSR_CONTAINER_PROFILE=false LSR_CONTAINER_PRETTY=false \
  tox -e container-ansible-core-2-20 -- --image-name centos-9-bootc tests/tests_default.yml
```

---

## 13. Network Role Test Directory (Reference Example)

The `network` role has one of the most comprehensive test suites -- 86+ test playbooks. Its structure serves as the canonical example.

### 13.1 Directory Layout

```
tests/
  ansible.cfg                     # Test-specific Ansible configuration
  .gitignore
  provision.fmf                   # TMT/Testing Farm metadata

  # Test playbooks (tests_*.yml) -- 86+ files covering:
  tests_default.yml               # Default/smoke test
  tests_802_1x.yml                # 802.1X authentication
  tests_bond.yml                  # Bond interfaces
  tests_bridge.yml                # Bridge interfaces
  tests_vlan.yml                  # VLAN configuration
  tests_wireless*.yml             # WiFi (WPA3 SAE/OWE)
  tests_infiniband.yml            # InfiniBand
  tests_team.yml                  # Team interfaces
  tests_ipv6.yml                  # IPv6
  tests_ethtool*.yml              # ethtool (coalesce, features, ring buffers)
  tests_routing_rules.yml         # Routing rules
  tests_dns.yml                   # DNS configuration
  tests_provider_nm.yml           # NetworkManager provider
  tests_provider_initscripts.yml  # initscripts provider
  # ... many more

  # Supporting infrastructure
  tasks/                          # Reusable task snippets (shared across tests)
  playbooks/                      # Full test playbooks (tests_*.yml are shims)
  files/                          # Test data and config files
  roles/linux-system-roles.network/  # Role symlink for testing
  library/                        # Custom test modules (symlinked)
  modules/                        # Module symlinks
  module_utils/                   # Module utility symlinks
  unit/                           # Python unit tests
  integration/                    # Integration pytest suites
  vars/                           # Test variable definitions

  # Coverage and utilities
  get_coverage.sh / get_coverage.yml   # Coverage report generation
  get_total_coverage.sh                # Aggregate coverage
  merge_coverage.sh                    # Combine coverage data
  ensure_provider_tests.py             # Provider test validation
  git-pre-commit.sh / git-post-commit.sh  # Git hooks
  setup-snapshot.yml                   # Snapshot setup playbook
  covstats                             # Coverage statistics
```

### 13.2 Test Organization Pattern

- `tests/tests_*.yml` files are **shim playbooks** that call the real playbooks in `tests/playbooks/`
- Shims run tests once per provider (NetworkManager, initscripts)
- `tests/tasks/` contains reusable task snippets to avoid code repetition
- Some playbooks call internal Ansible modules directly instead of the full role (to skip redundant tasks)
- Modules can be grouped into blocks for targeted unit testing
- Helper scripts exist for getting coverage from integration tests via Ansible
- Basic unit tests cover argument parsing and module functionality

---

## 14. SUSE/openSUSE Downstream Testing

### 14.1 Current State

SUSE does **not** run the full upstream tox-lsr CI pipeline for their downstream packages. Their testing approach:

1. **OBS Build Verification**: `osc build` validates the RPM builds correctly across target repos (Tumbleweed, SLE 16.0, etc.)
2. **Manual Validation**: Package maintainers test role functionality against SUSE targets
3. **Upstream Trust**: Heavy reliance on upstream CI passing before SUSE forks pick up new tags

### 14.2 Molecule on openSUSE

Docker/Podman containers for Molecule testing on openSUSE are available:
- `glillico/docker-opensusetumbleweed-ansible` -- Tumbleweed with Ansible installed
- `mesaguy/ansible-molecule-opensuse` -- Molecule-ready openSUSE images
- The `systemsmanagement:ansible` OBS project packages `molecule` and `molecule-plugins` for openSUSE

### 14.3 systemsmanagement:ansible OBS Project

This project (40+ packages) provides the Ansible ecosystem for openSUSE/SLE:
- **Packages**: ansible, ansible-core (2.16-2.19), ansible-lint, molecule, molecule-plugins, python-ansible-compat, python-ruamel.yaml, python-yamllint, semaphore, ansible-builder, ansible-navigator, ansible-runner
- **Repos**: openSUSE_Tumbleweed, SLE 16.0, 15.7, 15.6
- **Maintainers**: lrupp, mwilck, ojkastl_buildservice, trenn, factory-maintainers

### 14.4 Opportunity Gap

There is currently no automated end-to-end testing of LSR roles against openSUSE/SLE targets in the downstream SUSE packaging pipeline. This represents an opportunity for the lsr-agent to add value by:
- Running tox-lsr QEMU tests with openSUSE/SLE images
- Validating role2collection namespace conversion (fedora -> suse)
- Testing installed RPM collection functionality
- Automating the spec file update -> build -> test -> submit cycle

---

## 15. .github Organization Repository (Deep Dive)

### 15.1 Purpose

The [linux-system-roles/.github](https://github.com/linux-system-roles/.github) repo centralizes CI configuration management across all 30+ role repositories. It uses Ansible itself to distribute updates.

### 15.2 Inventory Structure

```yaml
# inventory.yml
all:
  hosts:
    network: {}
    firewall: {}
    timesync: {}
    # ... all roles
  children:
    active_roles:
      hosts:
        network: {}
        firewall: {}
        # ... maintained roles
    python_roles:
      hosts:
        network: {}
        # ... roles with Python plugins
```

- `inventory/group_vars/active_roles.yml` -- settings shared across all roles
- `inventory/group_vars/python_roles.yml` -- settings for roles with Python code
- `inventory/host_vars/$ROLENAME.yml` -- per-role overrides (GitHub Action schedules, lint customizations)

### 15.3 File Synchronization Categories

| Category | Purpose |
|----------|---------|
| `present_templates` | Jinja2 templates deployed to all roles |
| `present_files` | Static files copied to all roles |
| `absent_files` | Files removed from all roles |
| `present_python_templates` | Templates for Python-enabled roles only |
| `present_python_files` | Static files for Python roles only |
| `absent_python_files` | Files removed from Python roles |

### 15.4 update_files.yml Playbook

```bash
# Dry run (default)
ansible-playbook -i inventory.yml playbooks/update_files.yml \
  -e update_files_commit_file=/path/to/commit-message.txt

# Actual execution
ansible-playbook -i inventory.yml playbooks/update_files.yml \
  -e update_files_commit_file=/path/to/commit-message.txt \
  -e lsr_dry_run=false

# Single role
ansible-playbook -i inventory.yml playbooks/update_files.yml \
  -e update_files_commit_file=/path/to/commit-message.txt \
  -e include_roles=network \
  -e lsr_dry_run=false
```

**Parameters:**
- `update_files_commit_file` (required) -- path to file containing git commit message (used as PR title/body)
- `update_files_branch` (default: `update_role_files`) -- branch name for updates
- `lsr_dry_run` (default: true) -- set false for actual execution
- `test_dir` -- checkout location (creates tmpdir if unspecified)
- `exclude_roles` -- comma-delimited roles to skip
- `include_roles` -- comma-delimited roles to process (currently single-role only)

**Process:**
1. Creates temp directory (or uses `test_dir`)
2. Clones all roles (except `exclude_roles`)
3. Determines main branch name
4. Creates or rebases `update_files_branch`
5. Adds/updates/removes managed files from templates and static sources
6. Exits if no changes detected
7. Commits with provided message
8. Force-pushes branch
9. Creates PR if absent
10. Awaits review

**Requires:** `gh` CLI with authentication via `~/.config/gh/hosts.yml` and `git config --global credential.helper cache`.

### 15.5 Conventional Commits for PR Titles

| Type | SemVer Impact | Changelog Category |
|------|---------------|-------------------|
| `feat` | MINOR | "New Features" |
| `fix` | PATCH | "Bug Fixes" |
| `feat!` / `fix!` | MAJOR | Breaking change |
| `docs`, `style`, `refactor`, `perf`, `test`, `build`, `ci`, `chore`, `revert` | PATCH | "Other Changes" |

---

## 16. tox-lsr Internal Details

### 16.1 Configuration Merging

Local `tox.ini` settings merge with tox-lsr defaults. Mergeable settings:
- `setenv` -- local values override defaults for same keys
- `passenv`
- `deps`
- `allowlist_external`

Other settings (like `commands`) **replace** defaults entirely.

### 16.2 Disabling a Test Environment

Set commands to `true` to disable:
```ini
[testenv:flake8]
commands = true
```

### 16.3 Script-Available Environment Variables

These are set by the plugin and available in test scripts:

| Variable | Description |
|----------|-------------|
| `TOXINIDIR` | Full path to local `tox.ini` |
| `LSR_SCRIPTDIR` | Path to tox-lsr scripts (source `utils.sh` here) |
| `LSR_CONFIGDIR` | Path to tox-lsr config files |
| `LSR_TOX_ENV_NAME` | Test environment name (e.g., `py38`, `flake8`) |
| `LSR_TOX_ENV_DIR` | Full path to test environment directory |
| `LSR_TOX_ENV_TMP_DIR` | Temporary directory for test environment |

Source `"$LSR_SCRIPTDIR/utils.sh"` to access shell helper functions.

### 16.4 Collection Testing Workflow

```bash
# Step 1: Convert role to collection format
tox -e collection

# Step 2: Run ansible-test sanity checks on the collection
tox -e ansible-test

# Step 3: Run collection-specific ansible-lint
tox -e collection,ansible-lint-collection

# Documentation validation with debug output
LSR_ANSIBLE_TEST_DEBUG=true LSR_ANSIBLE_TEST_TESTS=ansible-doc tox -e collection,ansible-test
```

### 16.5 ansible-test Integration

The `ansible-test` tox environment:
- Requires prior `tox -e collection` to convert role to collection format
- Sets `ANSIBLE_COLLECTIONS_PATH` to the virtual environment temp directory
- Runs sanity checks by default
- Specific tests selectable via `LSR_ANSIBLE_TEST_TESTS` (space-delimited)
- Docker backend available via `LSR_ANSIBLE_TEST_DOCKER`
- Ansible version pinnable via `LSR_ANSIBLE_TEST_DEP` (default: `ansible-core==2.12.*`)

### 16.6 tox-lsr Troubleshooting

1. Remove `.tox` directory
2. Uninstall all tox-lsr versions: `pip uninstall tox-lsr` (repeat until none remain)
3. Clean cached files: `rm -rf ~/.local/lib/python*/site-packages/tox*lsr*`
4. Clear Python cache: `rm -rf ~/.local/bin/__pycache__/*`
5. Reinstall tox-lsr

### 16.7 Version Notes

- tox-lsr 2.0+ uses Molecule v3, supporting Ansible 2.8+
- Current version in active use: tox-lsr 3.12.0+ (network role) / pinned to 3.17.1 for ansible-test workflows
- Requires Python 3.6+ for the plugin itself

---

## 17. OBS Request and Review System

### 17.1 Factory Review Stages

Every submit request to `openSUSE:Factory` goes through 5 review stages:

| Stage | Type | What It Checks |
|-------|------|----------------|
| **factory-auto** | Automated script | Basic packaging rules: valid spec, changelog present, source URLs resolving |
| **licensedigger** (Legal-Auto) | Automated | License in permitted database; triggers manual review for unknown licenses |
| **factory-staging** | Bot + Staging Master | Assigns request to staging project (e.g., `adi:92`) |
| **opensuse-review-team** | Human reviewers | Manual review of package changes, quality, correctness |
| **Staging Project + openQA** | Automated | ISO image built, tested via openQA; must get green results |

### 17.2 Request Types

| Type | Purpose |
|------|---------|
| **submit** | Transfer sources between packages (main type for updates) |
| **delete** | Remove a project or package |
| **add_role** | Grant maintainer/bugowner roles |
| **set_bugowner** | Assign bug owner |
| **change_devel** | Change devel project |
| **maintenance_incident** | Initiate maintenance for supported products |
| **maintenance_release** | Distribute maintenance updates |
| **release** | Copy finished builds without rebuilding |

### 17.3 Request States

| State | Meaning |
|-------|---------|
| **new** | Just created, visible to all parties |
| **review** | Has open reviews pending; becomes "new" when all approve |
| **accepted** | Changes applied to target |
| **declined** | Rejected, but can be resubmitted |
| **revoked** | Withdrawn by submitter |
| **superseded** | Made obsolete by a newer request |

### 17.4 Real Request Example (from live OBS data)

**Successful submission (request #1338386, most recent):**
```
State: accepted   By: anag_factory  When: 2026-03-12
Created by: hsharma
submit: devel:sap:ansible/ansible-linux-system-roles -> openSUSE:Factory
Reviews:
  licensedigger       - accepted
  factory-auto        - accepted
  factory-staging     - accepted (anag_factory)
  opensuse-review-team - accepted (mstrigl)
  Staging:adi:92      - accepted (anag_factory)
Description: Update to version 1.1.0
```

---

## 18. OBS Source Service Modes

| Mode | Server | Local | File Naming | Notes |
|------|--------|-------|-------------|-------|
| **default** (no mode attr) | After each commit | Before local build | `_service:` prefix | Standard behavior |
| **trylocal** | Yes (if local differs) | Yes | Standard files | Prefer local, fallback to server |
| **localonly** | Never | Yes | Standard files | Client-side only |
| **serveronly** | Yes | Never | `_service:` prefix | When service unavailable on workstations |
| **buildtime** | During build | During build | Part of package | Service becomes build dependency |
| **manual** | Only explicit call | Only explicit call | Standard files | Triggered by `osc service runall` |
| **disabled** | Only explicit call | Only explicit call | Standard files | Legacy alias for "manual" |

### Common `_service` File Patterns

**For Git-based sources (obs_scm -- recommended for new packages):**
```xml
<services>
  <service name="obs_scm">
    <param name="url">https://github.com/SUSE/ansible-firewall.git</param>
    <param name="scm">git</param>
    <param name="revision">1.11.6-suse</param>
  </service>
  <service name="set_version" mode="buildtime"/>
  <service name="tar" mode="buildtime"/>
  <service name="recompress" mode="buildtime">
    <param name="file">*.tar</param>
    <param name="compression">xz</param>
  </service>
</services>
```

**With verification:**
```xml
<services>
  <service name="download_files" mode="trylocal"/>
  <service name="verify_file">
    <param name="file">archive.tar.gz</param>
    <param name="verifier">sha256</param>
    <param name="checksum">7f535a96a834b31ba2201...</param>
  </service>
</services>
```

---

## 19. OBS Maintenance Updates Workflow (SLE/SLES)

### 19.1 Complete Maintenance Lifecycle

```
Developer identifies fix needed
        |
        v
osc mbranch ansible-linux-system-roles
  (branches across all maintained versions: SLE 15-SP6, 15-SP7, 16.0, 16.1)
        |
        v
Make changes, test locally (osc build)
        |
        v
osc patchinfo
  (document: CVE references, bugzilla IDs, description)
        |
        v
osc maintenancerequest devel:sap:ansible ansible-linux-system-roles openSUSE:Leap:16.0
  (creates maintenance incident: openSUSE:Maintenance:IDxxx)
        |
        v
Maintenance team reviews, possibly merges with existing incident
  (osc rq setincident $REQUESTID $INCIDENT)
        |
        v
QA testing in incident project
        |
        v
osc releaserequest
  (locks packages, sends to update channel)
        |
        v
QA approval → Release manager acceptance
        |
        v
Update published to repositories
  (updateinfo.xml generated, unique release ID "YEAR-COUNTER")
```

### 19.2 Key Maintenance Commands

```bash
# Branch for maintenance across all maintained versions
osc mbranch ansible-linux-system-roles

# Branch specific version only
osc branch --maintenance openSUSE:Leap:16.0 ansible-linux-system-roles

# Hidden branch for unreleased security fixes
osc branch --maintenance --noaccess openSUSE:Leap:16.0 ansible-linux-system-roles

# Create patchinfo documentation
osc patchinfo

# Submit maintenance request
osc maintenancerequest devel:sap:ansible ansible-linux-system-roles openSUSE:Leap:16.0

# Create incident directly (maintenance team only)
osc createincident openSUSE:Maintenance

# Request release to update channel
osc releaserequest

# Reopen for re-release if regression found
osc unlock openSUSE:Maintenance:42
```

---

## 20. openQA Integration

- Staging projects (e.g., `openSUSE:Factory:Staging:adi:92`) generate ISO images
- **openQA** at https://openqa.opensuse.org/ runs automated tests against these images
- The `openqa-trigger-from-obs` tool bridges OBS build events to openQA test jobs
- Packages in Factory "rings" (core interdependent packages) get extra openQA scrutiny
- `ansible-linux-system-roles` typically goes through `adi:` (ad-interim) staging projects -- lighter-weight staging areas for packages not in rings
- openQA must produce green results before a staging project can be accepted into Factory

---

## 21. Complete osc Command Reference

### Source Management

| Command | Purpose |
|---------|---------|
| `osc checkout` / `osc co` | Checkout package locally |
| `osc update` / `osc up` | Update working directory from server |
| `osc commit` / `osc ci` | Commit changes to OBS |
| `osc add <file>` | Stage new file |
| `osc remove <file>` / `osc rm` | Mark file for removal |
| `osc addremove` | Auto-detect additions and removals |
| `osc diff` | Show changes vs server |
| `osc status` / `osc st` | Show local file states |
| `osc resolved <file>` | Mark conflict as resolved |
| `osc log` | View commit log |

### Building

| Command | Purpose |
|---------|---------|
| `osc build <repo> <arch>` | Local build test |
| `osc buildlog <repo> <arch>` | View build log |
| `osc lbl` | Show local build log |
| `osc shell <repo> <arch>` / `osc chroot` | Enter build chroot |
| `osc results` | Show build results for package |
| `osc prjresults` | Show project-wide build results |
| `osc rebuildpac` | Trigger remote rebuild |
| `osc repourls` | Show .repo URLs for package manager |

### Branching and Requests

| Command | Purpose |
|---------|---------|
| `osc branch <project> <package>` | Branch to home project |
| `osc branch --maintenance <project> <package>` | Branch for maintenance updates |
| `osc submitrequest` / `osc sr` | Create submit request |
| `osc request list <project>` | List open requests |
| `osc request show -d <ID>` | Show request with diff |
| `osc request accept <ID> -m "msg"` | Accept request |
| `osc request decline <ID> -m "msg"` | Decline request |
| `osc request supersede -m "msg" <ID> <NEW_ID>` | Supersede request |
| `osc request -M` | Show your own requests |

### Services

| Command | Purpose |
|---------|---------|
| `osc service runall` | Run all services regardless of mode |
| `osc service localrun` | Run services except buildtime/disabled/serveronly |
| `osc service rundisabled` | Run manual/disabled services explicitly |
| `osc service merge` | Drop _service file, commit generated files as regular sources |

### Metadata

| Command | Purpose |
|---------|---------|
| `osc meta prj <project>` | Show project metadata |
| `osc meta prj -e <project>` | Edit project metadata |
| `osc meta pkg <project> <package>` | Show package metadata |
| `osc meta pkg <project> <package> -e` | Edit package metadata |
| `osc meta prjconf <project>` | Show project config |
| `osc mkpac <name>` | Create new package |
| `osc vc` | Edit changelog |

### Package Operations

| Command | Purpose |
|---------|---------|
| `osc linkpac <src_prj> <pkg> <dst_prj>` | Link (clone) a package |
| `osc aggregatepac` | Aggregate (copy) a package |
| `osc copypac` | Copy package between projects |
| `osc ls <project>` | List packages in project |
| `osc ls -b <project>` | List build targets |
| `osc cat <project> <package> <file>` | View file contents |
| `osc search` | Search packages |

### Maintenance

| Command | Purpose |
|---------|---------|
| `osc mbranch <package>` | Branch across all maintained versions |
| `osc maintenancerequest <src_prj> <pkgs> <release_prj>` | Submit maintenance update |
| `osc createincident <project>` | Create maintenance incident |
| `osc patchinfo` | Create/edit maintenance documentation |
| `osc releaserequest` | Request release to update channel |
| `osc unlock <project>` | Reopen locked incident for re-release |

### Review

| Command | Purpose |
|---------|---------|
| `osc review list -G opensuse-review-team -t submit openSUSE:Factory` | List reviews |
| `osc review accept <ID> -m "ok"` | Accept a review |
| `osc review decline <ID> -m "reason"` | Decline a review |

Enable interactive review mode: add `request_show_interactive = 1` to `~/.config/osc/oscrc`.

---

## References

- [Linux System Roles Website](https://linux-system-roles.github.io/)
- [Linux System Roles GitHub](https://github.com/linux-system-roles)
- [tox-lsr Plugin](https://github.com/linux-system-roles/tox-lsr)
- [LSR Contributing Guide](https://linux-system-roles.github.io/contribute)
- [LSR .github Org Repo](https://github.com/linux-system-roles/.github)
- [LSR Test Harness](https://github.com/linux-system-roles/test-harness)
- [SUSE LSR Documentation (SLES 16)](https://documentation.suse.com/sles/16.0/html/SLES-ansible-roles/index.html)
- [SUSE Blog: Ansible LSR on SLES 16](https://www.suse.com/c/introduction-to-ansible-linux-system-roles-on-sles-16/)
- [OBS ansible-linux-system-roles (Factory)](https://build.opensuse.org/package/show/openSUSE:Factory/ansible-linux-system-roles)
- [OBS ansible-linux-system-roles (devel:sap:ansible)](https://build.opensuse.org/package/show/devel:sap:ansible/ansible-linux-system-roles)
- [OBS Basic Workflow](https://openbuildservice.org/help/manuals/obs-user-guide/cha-obs-basicworkflow)
- [OBS User Guide (PDF)](https://openbuildservice.org/files/manuals/obs-user-guide.pdf)
- [openSUSE Build Service Tutorial](https://en.opensuse.org/openSUSE:Build_Service_Tutorial)
- [How to Contribute to Factory](https://en.opensuse.org/openSUSE:How_to_contribute_to_Factory)
- [openSUSE Git Packaging Workflow](https://en.opensuse.org/openSUSE:Git_Packaging_Workflow)
- [LSR Downloads and Releases](https://linux-system-roles.github.io/documentation/download)
- [Fedora Galaxy Collection](https://galaxy.ansible.com/ui/repo/published/fedora/linux_system_roles/)
- [Fedora dist-git linux-system-roles.spec](https://src.fedoraproject.org/rpms/linux-system-roles/blob/rawhide/f/linux-system-roles.spec)
- [SUSE/ansible-firewall fork](https://github.com/SUSE/ansible-firewall)
- [SUSE/ansible-suseconnect](https://github.com/SUSE/ansible-suseconnect)
- [auto-maintenance repo (upstream)](https://github.com/linux-system-roles/auto-maintenance)
- [SUSE LSR Documentation (SLES for SAP 16)](https://documentation.suse.com/sles-sap/16.0/html/SAP-ansible-roles/index.html)
- [openSUSE Git Packaging News (Feb 2026)](https://news.opensuse.org/2026/02/19/community-refines-git-packaging-workflow)
- [OBS-with-Git wiki](https://en.opensuse.org/openSUSE:OBS_with_Git)
- [src.opensuse.org Git workflow docs](https://src.opensuse.org/openSUSE/git-workflow-documentation)
- [LSR tft-tests (Testing Farm)](https://github.com/linux-system-roles/tft-tests)
- [LSR CI Changes Blog Post](https://linux-system-roles.github.io/2020/12/ci-changes)
- [LSR Network Role Tests](https://github.com/linux-system-roles/network/tree/main/tests)
- [Ansible Callback Plugins](https://docs.ansible.com/ansible/latest/plugins/callback.html)
- [tox-ansible (upstream Ansible plugin)](https://github.com/ansible/tox-ansible)
- [Testing Farm Documentation](https://docs.testing-farm.io/)
- [Molecule (Ansible testing framework)](https://github.com/ansible/molecule)
- [Docker openSUSE Tumbleweed Ansible](https://github.com/glillico/docker-opensusetumbleweed-ansible)
- [SUSE Blog: Ansible Getting Integrated with SLES](https://www.suse.com/c/streamlining-your-suse-linux-environment-ansible-getting-integrated-with-sles/)
- [OBS User Guide - osc Tool](https://openbuildservice.org/help/manuals/obs-user-guide/cha-obs-osc)
- [OBS User Guide - Source Services](https://openbuildservice.org/help/manuals/obs-user-guide/cha-obs-source-services)
- [OBS User Guide - Request and Review System](https://openbuildservice.org/help/manuals/obs-user-guide/cha-obs-request-and-review-system)
- [OBS User Guide - Maintenance Support](https://openbuildservice.org/help/manuals/obs-user-guide/cha-obs-maintenance-setup)
- [Factory Development Model](https://en.opensuse.org/openSUSE:Factory_development_model)
- [Factory Submissions](https://en.opensuse.org/openSUSE:Factory_submissions)
- [Maintenance Update Process](https://en.opensuse.org/openSUSE:Maintenance_update_process)
- [OBS Source Services Concept](https://en.opensuse.org/openSUSE:Build_Service_Concept_SourceService)
- [obs-service-tar_scm GitHub](https://github.com/openSUSE/obs-service-tar_scm)
- [osc GitHub](https://github.com/openSUSE/osc)
- [openQA](http://open.qa/)
- [openqa-trigger-from-obs](https://github.com/os-autoinst/openqa-trigger-from-obs)
- [OBS Staging Workflow](https://github.com/openSUSE/open-build-service/wiki/Staging-Workflow)

---

## 22. Local SUSE LSR Test Infrastructure (Spectro34)

This section documents the local testing setup and automation scripts at
`/home/spectro/github/ansible/` as actually used for SUSE LSR validation.

### 22.1 Directory Layout

```
/home/spectro/github/ansible/
  scripts/           # Shell automation scripts
  testing/           # tox-lsr venv, QEMU logs, results, test overrides
  upstream/          # Clones of 30+ upstream LSR role repos
  obs/               # Checked-out OBS packages (devel:sap:ansible, etc.)
  patches/           # LSR role patches (lsr/firewall/, sle15sp6/, sle16/)
  docs/              # Research, guides, upstream PR notes, bug analyses
```

### 22.2 Core Test Scripts

All scripts live in `scripts/` and share a common convention:
- Venv at `testing/tox-lsr-venv`
- SUSE cleanup hook via `LSR_QEMU_CLEANUP_YML=testing/cleanup-suseconnect.yml`
- Per-run log files at `testing/log-<image>-<role>[-version].txt`
- Summary results at `testing/results-<image>[-version].txt`

| Script | Purpose |
|--------|---------|
| `lsr-test.sh <role-dir> <image> [ac-ver] [test-playbook]` | Run a single role test |
| `run-all-tests.sh <image> <ac-ver>` | Run all applicable roles for an image |
| `run-new-roles-tests.sh <image> <ac-ver>` | Run candidate new roles (bootloader, kdump, network, kernel_settings) |
| `retest-failing.sh <image> <ac-ver>` | Re-test a hardcoded set of failing roles |
| `retest-sle15-failures.sh` | Re-test firewall+ssh on SLE 15 SP7 with ac 2.18 |
| `retest-sle16-remaining.sh` | Re-test podman, cockpit, postfix, keylime_server on SLE 16 with ac 2.20 |
| `patch-tox-lsr.sh [venv-path]` | Apply SUSE cloud-init patches to tox-lsr's standard-inventory-qcow2 |

#### `lsr-test.sh` invocation pattern
```bash
# Single role, default test playbook
scripts/lsr-test.sh upstream/timesync sle-15-sp7 2.18

# Single role, custom test playbook
scripts/lsr-test.sh upstream/postfix sle-16 2.20 testing/tests_postfix_suse.yml

# Resolves to:
tox -e qemu-ansible-core-2.18 -- --image-name sle-15-sp7 tests/tests_default.yml
```

#### `run-all-tests.sh` role matrix
```
SLE 15 SP7:  timesync firewall journald ssh crypto_policies systemd postfix
SLE 16:      (above) + certificate selinux podman cockpit aide keylime_server
```
(ha_cluster excluded — needs HA Extension; mssql excluded — needs SQL Server)

600-second timeout per role. Extracts last Ansible task lines from log on failure.

#### `patch-tox-lsr.sh` — Two mandatory SUSE patches to `standard-inventory-qcow2`

1. **`disable_root: false`** in cloud-init USER_DATA — SLES cloud images disable
   root SSH by default; tox-lsr uses root for test connections.
2. **`instance-id: iid-local01`** in meta-data — SLES cloud-init requires an
   `instance-id` for the NoCloud datasource to activate; the upstream script
   writes an empty file.

Must be re-applied after every `pip install/upgrade` of tox-lsr.

### 22.3 tox-lsr QEMU Image Configuration

Config file: `~/.config/linux-system-roles.json`

Key settings per image:
- `sle-15-sp7`: `~/iso/SLES15-SP7-Minimal-VM.x86_64-Cloud-GM.qcow2`
  - SUSEConnect registration (3 retries, 30s delay)
  - Enable Containers Module (`sle-module-containers/15.7/x86_64`)
  - Install `python311`, `python3-rpm`, `python311-firewall`
  - Ansible interpreter: `/usr/bin/python3.11`
- `sle-16`: `~/iso/SLES-16.0-Minimal-VM.x86_64-Cloud-GM.qcow2`
  - SUSEConnect registration (3 retries, 30s delay)
  - Install `python3-rpm`, `python3-firewall`
  - No Containers Module needed (podman in base product)

Images use `-snapshot` so SUSEConnect registration is ephemeral per run.
SUSEConnect deregistration cleanup: `testing/cleanup-suseconnect.yml`
(runs `SUSEConnect -d`, `failed_when: false`).

### 22.4 community.general Collection — Manual Install Quirk

tox-lsr does not auto-install `community.general`, which is required for
the `zypper` module on SUSE targets. Workaround:

```bash
# After tox creates the .tox/<env>/ dir (first run or explicit setup)
ANSIBLE_COLLECTIONS_PATH=upstream/<role>/.tox \
  upstream/<role>/.tox/qemu-ansible-core-2.18/bin/ansible-galaxy \
  collection install community.general

# run-all-tests.sh handles this automatically (pre- and post-run check)
```

### 22.5 Test Overrides for SUSE

| Role | Override | Reason |
|------|---------|--------|
| postfix | `testing/tests_postfix_suse.yml` | Sets `postfix_manage_firewall: false`, `postfix_manage_selinux: false` — SUSE uses AppArmor not SELinux on SLE 15 |

---

## 23. LSR SUSE Test Matrix and Production Readiness (2026-02-18)

Based on verified test runs against SLE 15 SP7 and SLE 16 QEMU images
using tox-lsr 3.14.0, ansible-core 2.18 (SLE 15) and 2.20 (SLE 16).

### 23.1 Complete Test Matrix

| # | Role | SLE 15 SP7 | SLE 16 | Verdict |
|---|------|-----------|--------|---------|
| 1 | timesync | PASS | PASS | Ship both |
| 2 | firewall | PASS | PASS | Ship both |
| 3 | journald | PASS | PASS | Ship both |
| 4 | ssh | PASS (patched) | PASS (patched) | Ship both (upstream fix merged 2026-02-17) |
| 5 | crypto_policies | PASS | PASS | Ship both |
| 6 | systemd | PASS | PASS | Ship both |
| 7 | postfix | PASS (test adapted) | PASS (test adapted) | Ship both |
| 8 | certificate | N/A | PASS | SLE 16 only |
| 9 | selinux | N/A | PASS | SLE 16 only (via SLFO) |
| 10 | podman | N/A | PASS | SLE 16 only (in base product) |
| 11 | cockpit | N/A | PASS | SLE 16 only |
| 12 | aide | N/A | PASS | SLE 16 only |
| 13 | keylime_server | N/A | PASS | SLE 16 only |
| 14 | ansible-sshd | N/A | PASS | SLE 16 only (already has vars/Suse.yml upstream) |
| 15 | postgresql | PASS (patched) | PASS (patched) | Ship both — fork: Spectro34/postgresql fix/suse-support |
| 16 | metrics | N/A | PASS 11/11 (patched) | SLE 16 — fork: Spectro34/metrics fix/suse-pcp-support |
| 17 | logging | N/A | PASS 4/10* | SLE 16 (test cleanup caveat, not a role bug) |
| 18 | ad_integration | N/A | PASS (trivial) | SLE 16 — full AD join untested (needs AD infra) |
| 19 | vpn | — | FAIL | Do not ship (no libreswan in SLES) |
| 20 | tlog | — | FAIL | Do not ship (no tlog/authselect) |
| 21 | nbde_server | — | FAIL | Do not ship (no tang) |
| 22 | nbde_client | — | FAIL | Blocked on clevis (in Factory, not yet in SLFO) |
| 23 | storage | — | NOT TESTED | Do not ship (no python3-blivet) |
| 24 | fapolicyd | — | FAIL | Do not ship (RedHat-only hard check) |
| 25 | ha_cluster | EXCLUDED | EXCLUDED | Ship (needs HA Extension subscription) |

\* logging: 6 failures are test cleanup issue (RHEL-specific rsyslog.conf assumptions), not role bugs.

### 23.2 Summary by Category

| Category | Count | Roles |
|----------|-------|-------|
| Ship no-patch | 12 | timesync, journald, crypto_policies, systemd, postfix, certificate, selinux, podman, cockpit, aide, keylime_server, ansible-sshd |
| Ship (upstream fix merged) | 2 | ssh, firewall (SLE 15) |
| Ship (carry patch/fork) | 4 | network, postgresql, metrics, firewall (SLE 16 vars) |
| Ship with caveats | 2 | logging, ad_integration |
| Not shippable | 7 | vpn, tlog, nbde_server, nbde_client, storage, fapolicyd, kdump |

### 23.3 SLE 15 Specific Findings

- Python 3.6 is the system python — ansible-core **2.16** is the last version supporting it as managed node
- SLE 15 cannot be an Ansible controller (needs Python 3.10+ on controller)
- SLE 15 can only be a managed node, controlled from SLE 16 or a workstation
- No Containers Module equivalent on SLE 15 for podman-class roles
- `wicked` is the default network stack — network role (NetworkManager-only) cannot work

### 23.4 SLE 16 Specific Findings

- No Containers Module — podman and container tools are in the base product
- SELinux is supported via SLFO — selinux role works correctly
- Available subscription modules: HA Extension (needs separate regcode), Package Hub
- Python 3.11 is the system python; ansible-core 2.20 used for testing

---

## 24. RPM Spec File Deep Dive (ansible-linux-system-roles)

Reference: `/home/spectro/github/ansible/obs/linux-system-roles/devel:sap:ansible/ansible-linux-system-roles/`

### 24.1 Spec File Architecture

The spec file uses a **multi-source, single-package** approach:
- Each role is a separate `Source<N>` tarball, fetched from `https://github.com/SUSE/ansible-<role>` tagged `-suse` releases
- Platform conditional `%{sle16}` macro controls which sources/roles are included

```spec
%if 0%{?suse_version} >= 1600
%global sle16 1
%else
%global sle16 0
%endif
```

SLE 16-only roles (Sources 11–16): certificate, selinux, podman, cockpit, aide, keylime_server

### 24.2 Build Process (spec %prep + %build)

1. Extract all role tarballs into `%{_builddir}/roles/<role>/`
   - Transform: `ansible-<role>-<version>-suse/` → `<role>/`
2. Process README files (sed-based):
   - Strip internal anchor links (`[text](#anchor)` → `text`)
   - Remove GitHub CI badges
   - Remove Requirements, Collection requirements, Compatibility sections
3. Run `lsr_role2collection.py` from `auto_maintenance` role on each role:
   ```
   python3 lsr_role2collection.py \
     --namespace suse \
     --collection linux_system_roles \
     --role <role> \
     --src-path roles/<role> \
     --dest-path collections/
   ```
   (`auto_maintenance` itself is skipped from this processing step)
4. Copy and version-stamp `galaxy.yml`
5. `ansible-galaxy collection build` → `suse-linux_system_roles-<version>.tar.gz`

### 24.3 Install (%install)

```spec
ansible-galaxy collection install --force \
  suse-linux_system_roles-<version>.tar.gz \
  --collections-path %{buildroot}%{_datadir}/ansible/collections
```

Install path: `/usr/share/ansible/collections/ansible_collections/suse/linux_system_roles/`

### 24.4 Post-Install Symlinks (%post / %postun)

Creates backward-compatible symlinks in `/usr/share/ansible/roles/`:
```
fedora.linux_system_roles.<role>  → .../suse/linux_system_roles/roles/<role>
linux-system-roles.<role>         → .../suse/linux_system_roles/roles/<role>
```

This allows playbooks using `linux-system-roles.timesync` shorthand to work
without knowing the collection namespace.

%postun cleans up symlinks only on full uninstall (`$1 -eq 0`).

### 24.5 Source Service (_service)

```xml
<services>
  <service name="download_files" mode="manual"/>
  <service name="set_version" mode="manual"/>
</services>
```

Both services run manually (`osc service runall`):
- `download_files` — fetches Source tarballs from GitHub using the URLs in the spec
- `set_version` — updates version strings

### 24.6 galaxy.yml Management

- `galaxy.yml` is Source999 in the spec (manually maintained)
- After collection assembly, spec patches the version to match `Version:` tag:
  ```bash
  sed -i "s/^version: .*/version: '%{version}'/" galaxy.yml
  ```
- Collection namespace: `suse.linux_system_roles`

### 24.7 Upstream Symlink Compatibility

The `%post` symlinks enable three usage patterns for the same installed role:
```yaml
# Collection style
- import_role:
    name: suse.linux_system_roles.timesync

# Legacy Fedora style
- import_role:
    name: fedora.linux_system_roles.timesync

# Classic role style
- import_role:
    name: linux-system-roles.timesync
```

---

## 25. Version Upgrade Workflow and Ansible-core Compatibility

Reference: `/home/spectro/github/ansible/docs/lsr-upgrade-plan.md`

### 25.1 Packaged vs Upstream Version Gap (as of upgrade planning ~2026-01)

| Role | Packaged | SUSE Fork | Upstream | Target |
|------|----------|-----------|----------|--------|
| firewall | 1.8.2 | 1.8.2 | 1.11.4 | 1.11.4 |
| timesync | 1.9.2 | 1.9.2 | 1.11.3 | 1.11.3 |
| journald | 1.3.5 | 1.3.5 | 1.5.2 | 1.5.2 |
| ssh | 1.5.2 | 1.5.2 | 1.7.1 | 1.7.1 |
| crypto_policies | 1.4.2 | 1.4.2 | 1.5.2 | 1.5.2 |
| systemd | 1.3.1 | 1.3.1 | 1.3.6 | 1.3.6 |
| ha_cluster | 1.24.0 | 1.24.0 | 1.29.0 | 1.29.0 |
| mssql | 2.5.2 | 2.5.2-suse | 2.6.6 | 2.6.6 |
| auto_maintenance | 1.94.2 | 1.94.2-suse | 1.119.1 | 1.119.1 |
| certificate | 1.3.11 | 1.4.0 | 1.4.4 | 1.4.4 |
| aide | 1.2.0 | 1.2.1 | 1.2.5 | 1.2.5 |

After the OBS r12 upgrade (2026-03-11), packaged versions align with the
target column above (spec file uses these versions).

### 25.2 ansible-core Compatibility — Python 3.6 Constraint

| ansible-core | Controller Python | Managed Node Python |
|-------------|-------------------|---------------------|
| 2.16 | 3.10–3.12 | 2.7, **3.6**–3.12 |
| 2.17 | 3.10–3.12 | 3.7–3.12 (no 3.6!) |
| 2.18 | 3.11–3.13 | 3.8–3.13 |
| 2.20 | 3.12–3.14 | 3.9–3.14 |

**SLE 15 SP7 system python is 3.6.** ansible-core 2.16 is the last version
that supports Python 3.6 on managed nodes. All LSR roles pin
`community.general >= 6.6.0, < 12` to preserve Python 3.6 compatibility.

| Target | Role as | ansible-core | community.general |
|--------|---------|-------------|-------------------|
| SLE 15 SP7 | Managed node only | 2.16 | 11.x (<12) |
| SLE 16 | Controller + managed | 2.20 | 12.x or 11.x |

### 25.3 Upgrade Execution Plan

```
Phase 1 — Update SUSE forks on GitHub:
  git fetch upstream && git merge upstream/<tag> && git tag <ver>-suse

  Priority order:
  1. ha_cluster (1.24 → 1.29, has SLES 16 crmsh support)
  2. firewall (1.8 → 1.11)
  3. timesync (1.9 → 1.11)
  4. mssql (2.5 → 2.6, has SUSE-specific fixes)
  5. Remaining roles

Phase 2 — Update spec file:
  Bump all %global <role>_version macros
  osc service runall  (downloads new tarballs)
  osc vc              (update .changes)

Phase 3 — Build and test:
  osc build SLE_16 x86_64
  osc build SLE_15_SP7 x86_64
  ansible-doc suse.linux_system_roles.firewall

Phase 4 — Submit:
  osc sr → devel:sap:ansible → SLFO → SLE 15 SP7 maintenance
```

### 25.4 Open Decisions

- [ ] Add postfix to SLE 15? (boo#1254397 — OBS r11 `bsc#1255313` already enabled it)
- [ ] auto_maintenance: update to 1.119.1 or pin more conservatively?
- [ ] suseconnect: tag 1.0.2-suse release (adds meta/main.yml, 1 commit ahead)

---

## 26. Upstream PR Status and SUSE Patches

### 26.1 Upstream Fix Priority Queue

| Priority | Role | Repo | Change | Fork branch | Status |
|----------|------|------|--------|-------------|--------|
| 1 | firewall | linux-system-roles/firewall | Add `tasks/set_vars.yml`, `vars/SLES_16.yml`, wire in main.yml | fix/suse-set-vars | Pending |
| 2 | network | linux-system-roles/network | 2 changes in `defaults/main.yml` (gobject + typelib) | fix/suse-gobject-package | Pending (fork ready, PRs not submitted) |
| 3 | postgresql | linux-system-roles/postgresql | vars + tasks + meta (3 files) | fix/suse-support | Pending |
| 4 | metrics | performancecopilot/ansible-pcp | `vars/Suse.yml` + meta (1 new file) | fix/suse-pcp-support | Pending (commit b33ddbf local, PR not submitted) |
| 5 | logging | linux-system-roles/logging | Optional `roles/rsyslog/vars/Suse.yml` (iproute2) | (none) | Optional |
| 6 | ssh | linux-system-roles/ssh | vars/Suse.yml, tests, meta (13 files) | fix/suse-support | **Merged** (2026-02-17, commit 81c23f6) |
| 7 | sudo | linux-system-roles/sudo | scan_sudoers crash fix + test infra + meta | fix/suse-support | Pending (commit 7e47081, tested 2026-04-02, 28/28 PASS) |
| 8 | firewall (partial) | linux-system-roles/firewall | vars/SLES_15.yml, SLES_SAP_15.yml | — | **Merged** (PR #300, 2025-11-03, dead code — loader missing) |

### 26.2 Firewall Role — Dead-Code PR Analysis

PR #300 (merged 2025-11-03 by HVSharma12) added `vars/SLES_15.yml` and
`vars/SLES_SAP_15.yml` but the firewall role has no `set_vars.yml` or
`include_vars` mechanism. The files exist but are **never loaded**.

Fix requires 3 files, 28 lines:
- `tasks/set_vars.yml` — new standard platform vars loader (same pattern as 14 other roles)
- `tasks/main.yml` — add `include_tasks: set_vars.yml` before `firewalld.yml`
- `vars/SLES_16.yml` — new, `__firewall_packages_extra: [python3-firewall]`

### 26.3 SSH Role — Post-Merge Verification Note

Upstream fix merged at commit `81c23f6` (2026-02-17). One item to verify:
`tests/tasks/setup.yml` installs `openssh-clients` for `os_family in ['RedHat', 'Suse']`.
Confirm `openssh-clients` exists on SUSE (may need to be `openssh` instead).

### 26.4 PostgreSQL Role — Two PRs Required

PR 1 (certificate role): Add `vars/openSUSE_Leap.yml` for Leap 15.x
(uses `python311-*` variants; avoids `NameError: name 'dbus' is not defined`).

PR 2 (postgresql role): Three file changes:
- `vars/Suse.yml` — skip `postgresql-setup` (not available on SUSE)
- `tasks/main.yml` — add initdb fallback for distros without postgresql-setup
- `meta/main.yml` — add SUSE/openSUSE platform entries

Fork: `Spectro34/postgresql fix/suse-support` — tested 2026-03-08, all 7 tests PASS
on Leap 15.6.

---

## 27. Hackweek 2026 — Community Ansible Roles for SLES

Reference: `/home/spectro/github/hackweek-2026-system-roles/`

Evaluation of community Ansible roles (non-LSR) for SLES 16 compatibility.

### 27.1 Roles Evaluated

| Role | Upstream | Fork | SLES 16 | Key Changes |
|------|---------|------|---------|------------|
| squid | robertdebock/ansible-role-squid | Spectro34/ansible-role-squid | Works | Metadata only — PR #17 |
| apache | geerlingguy/ansible-role-apache | Spectro34/ansible-role-apache | Works | Bug fixes + SLE 15/16 functionality — PR #266 |
| nfs | geerlingguy/ansible-role-nfs | Spectro34/ansible-role-nfs (sles-support) | Works | SUSE OS-specific task files, correct package/service names — PR #55 |
| samba | geerlingguy/ansible-role-samba | Spectro34/ansible-role-samba | Works | SUSE task + `vars/SUSE.yml` with daemon name — PR #15 |
| kea-dhcp | mrlesmithjr/ansible-kea-dhcp | Spectro34/ansible-kea-dhcp | Works | `kea` package, SLES service names — PR #12 |
| bind | bertvv/ansible-role-bind | Spectro34/ansible-role-bind | Works | SLES vars + full feature test — PR #224 |
| kdump | linux-system-roles/kdump | Spectro34/kdump | Works | SUSE vars, `kdumptool commandline -u` for crashkernel, service logic — PR #267 |
| snapper | aisbergg/ansible-role-snapper | Spectro34/ansible-role-snapper | Works | Snapshot management for SLES 16+, rollbacks, comparisons, hooks |
| tftpd | robertdebock/ansible-role-tftpd | Spectro34/ansible-role-tftpd | Works | Confirmed compatible, no changes needed |

### 27.2 Pattern: Adding SUSE Support to a Community Role

Standard pattern used across all hackweek evaluations:

1. **Identify OS vars files** — add `vars/Suse.yml` or `vars/SLES-16.yml` with SUSE package/service names
2. **Add OS-specific tasks** — create `tasks/setup-Suse.yml` or modify `tasks/main.yml` with `when: ansible_os_family == 'Suse'`
3. **Fix package names** — common differences: `apache2` (not `httpd`), `samba` (same), `kea` (same), `bind` (same)
4. **Fix service names** — often match package name on SUSE; daemons may differ
5. **Update meta/main.yml** — add SUSE/openSUSE to `galaxy_tags` and `platforms`
6. **Test on SLE 15 SP7 and SLE 16** using QEMU setup

### 27.3 kdump Role — LSR PR #267

Adds full SLE 16+ and openSUSE support to the upstream LSR kdump role:
- SUSE-specific vars for packages, config file path, service name
- Uses `kdumptool commandline -u` instead of `grubby` for crashkernel updates
- Ensures kdump service only starts when no reboot is required (SLE 16 behavior differs)

---

## 28. Observed Bugs and Workarounds

### 28.1 boo#1254397 / bsc#1255313 — postfix on SLE 15 SP7

- **Report**: boo#1254397 (Enno Gotthold, 2025-12-02) requests postfix role on SLE 15
- **OBS fix**: bsc#1255313, resolved in r11 by msuchanek (2025-12-18) — enabled postfix on SLE 15
- **Spec approach**: postfix `Source10` is always included; `%prep` role array includes postfix for all platforms; SLE 16 conditional only controls certificate+ roles
- **Local test**: Uses `testing/tests_postfix_suse.yml` with `postfix_manage_selinux: false`

### 28.2 boo#1259969 — Parallel rsync (ansible.posix.synchronize) Fails on SLE 16

- **Report**: Marcel Mamula, SLES_SAP 16.0 BYOS on AWS
- **Symptom**: `ansible.posix.synchronize` fails with "Network is unreachable" when source=SLE 16, targets=4x SLE 16 in parallel. Serial execution (`throttle: 1`) works.
- **All other combinations pass**: SLE 15→15, SLE 15→SLE 16, SLE 16→SLE 15
- **Root cause hypothesis**: SLE 16 nftables/networking stack interaction with parallel SSH tunnel setup during rsync delegate
- **Workaround**: Use `throttle: 1` or investigate SLE 16 nftables ruleset during parallel operations

### 28.3 community.general cobbler Inventory Plugin — HTTPS-Only Bug

- **Affects**: openSUSE Tumbleweed / Slowroll (community.general >= 10.7.0)
- **Symptom**: `Connection refused` when connecting to plain-HTTP Cobbler XML-RPC API
- **Root cause**: `TimeoutTransport` (added in 10.7.0) inherits from `xmlrpc.client.SafeTransport` (HTTPS-only). The `connection_timeout` option is always present in `self._options`, so the HTTPS transport is unconditionally used even for `http://` URLs.
- **Why Leap works**: Ships community.general < 10.7.0, uses `ServerProxy` which auto-selects HTTP vs HTTPS from URL scheme.
- **Fix needed**: `TimeoutTransport` must inherit from `Transport` and check URL scheme, or the `if "connection_timeout" in self._options` guard must only trigger when explicitly set by the user.

---

## 29. sudo Role — SUSE Support Upstream PR (2026-04-02)

Reference: `/home/spectro/github/ansible/docs/lsr-sudo-upstream-pr.md`
Fork: `Spectro34/sudo`, branch `fix/suse-support`, commit `7e47081` (pushed 2026-04-02)
Based on upstream `main` at `6932710`.

### 29.1 Root Cause: scan_sudoers Crashes on Missing /etc/sudoers

SLE 16, Leap 16, and Tumbleweed follow the **vendor config pattern**:
- `/usr/etc/sudoers` — shipped by the sudo RPM (vendor defaults)
- `/etc/sudoers` — admin override; **does not exist on a fresh install**

`library/scan_sudoers.py` did a raw `open(path, "r")` with no existence check:
```python
def get_config_lines(path, params):
    fp = open(path, "r")   # raises FileNotFoundError if /etc/sudoers absent
```
This is called as the **first task** in `tasks/main.yml`, before sudo is even
installed. On any SLE 16/Leap 16/Tumbleweed system, the role crashed immediately.

### 29.2 How SUSE Manages sudo

| Item | SUSE value | Notes |
|------|-----------|-------|
| Package | `sudo` | Same name as RHEL |
| Binary | `/usr/bin/sudo` | Same path |
| `visudo` | `/usr/sbin/visudo` | Same path |
| `%wheel` group | Exists | Same as RHEL |
| Config (SLE 15 / Leap 15) | `/etc/sudoers` | Traditional layout |
| Config (SLE 16 / Leap 16) | `/usr/etc/sudoers` (vendor) | Admin adds `/etc/sudoers` on top |

The role writes `/etc/sudoers`, which takes precedence over `/usr/etc/sudoers`
on SLE 16 — correct behavior. No `vars/Suse.yml` needed: package names,
paths, and `%wheel` group are all identical to RHEL.

### 29.3 Fix: library/scan_sudoers.py

Single-line guard before `open()`:
```python
def get_config_lines(path, params):
    if not os.path.isfile(path):
        return {}
    fp = open(path, "r")
```
`get_sudoers_configs` already handles falsy return via `if default:` — returning
`{}` for a missing file follows the same code path as an empty file. Zero
behavioral change on RHEL/Fedora/Debian where `/etc/sudoers` always exists.

This fix also benefits containers and transactional update systems where
`/etc/sudoers` may be legitimately absent initially.

### 29.4 Test Infrastructure Changes

#### tests/tasks/setup.yml (3 additions)

1. **Pre-install sudo** — SUSE Minimal VM images omit sudo by default:
   ```yaml
   - name: Ensure sudo is installed for test setup
     package:
       name: sudo
       state: present
   ```

2. **Stat /etc/sudoers** — drives conditional backup:
   ```yaml
   - name: Check if /etc/sudoers exists
     stat:
       path: /etc/sudoers
     register: __sudo_etc_sudoers
   ```

3. **Conditional backup** — skip when file is absent:
   ```yaml
   - name: Backup sudoers
     copy: ...
     when: __sudo_etc_sudoers.stat.exists
   ```

#### tests/tasks/cleanup.yml (2 additions)

1. **Conditional restore** — only if a backup was made:
   ```yaml
   - name: Restore sudoers
     copy: ...
     when: (__sudo_tmpdir.path + '/sudoers') is file
   ```

2. **Remove /etc/sudoers when there was no original** — restore clean state:
   ```yaml
   - name: Remove /etc/sudoers when there was no original
     file:
       path: /etc/sudoers
       state: absent
     when: not __sudo_etc_sudoers.stat.exists
   ```

#### meta/main.yml

Added SUSE/openSUSE platform declarations and `suse`/`opensuse` galaxy tags.

### 29.5 Execution Flow by Target

| Step | SLE 16 / Leap 16 (NEW) | SLE 15 / Leap 15 | RHEL/Fedora |
|------|----------------------|-------------------|-------------|
| scan_sudoers | `/etc/sudoers` absent → returns `{}` | exists → parses normally | exists → parses normally |
| setup backup | stat `exists=false` → skip | backup runs | backup runs |
| role run | writes `/etc/sudoers` from template | normal | normal |
| cleanup | backup absent → restore skipped; `stat.exists=false` → delete `/etc/sudoers` | restore runs | restore runs |
| final state | `/etc/sudoers` absent (clean) | restored | restored |

### 29.6 Test Results (Verified 2026-04-02)

| Test | SLE 16 | Leap 16 | SLE 15 SP7 | Leap 15.6 |
|------|:------:|:-------:|:----------:|:---------:|
| tests_default | PASS | PASS | PASS | PASS |
| tests_check_if_configured | PASS | PASS | PASS | PASS |
| tests_large_configuration | PASS | PASS | PASS | PASS |
| tests_multiple_sudoers | PASS | PASS | PASS | PASS |
| tests_scan_sudoers | PASS | PASS | PASS | PASS |
| tests_role_applied | PASS | PASS | PASS | PASS |
| tests_include_vars_from_parent | PASS | PASS | PASS | PASS |

**28/28 PASS** across all 4 targets.

### 29.7 PR Submission Status

- Branch pushed: `spectro34/fix/suse-support`
- ansible-lint and yamllint pre-flight still pending
- PR to be submitted to `linux-system-roles/sudo` (not yet opened as of 2026-04-02)

---

## 30. Network Role — SUSE Status, SLE 15 Scope Decision, and Packaging Plan

Reference: `/home/spectro/github/ansible/docs/lsr-network-role-testing.md`

### 30.1 Current Packaging Status

The **network role is not yet included** in `ansible-linux-system-roles`. It
needs to be added. Upstream version at time of testing: **1.17.9** (2026-01-13).

### 30.2 SLE 15 SP7 — Out of Scope (Architectural Mismatch)

SLE 15 SP7 uses **wicked** as its default network manager. The LSR network role
supports only two providers: `nm` (NetworkManager) and `initscripts` (RHEL 6/7).

The `__network_provider_current` logic auto-detects by checking `ansible_facts.services`:
```yaml
__network_provider_current: "{{
    'nm' if 'NetworkManager.service' in ansible_facts.services and
        ansible_facts.services['NetworkManager.service']['state'] == 'running'
        else 'initscripts' }}"
```

On SLE 15 SP7 Minimal VM, NetworkManager is not running (wicked is active instead),
so the provider falls back to `initscripts`. This then tries to install
`network-scripts`, which does not exist on SUSE — causing a hard failure.

**Verified behavior** (`testing/log-sle-15-sp7-network.txt`):
```
Using network provider: initscripts
...
fatal: Install packages: No provider of '+network-scripts' found.
PLAY RECAP: failed=1
```

**Decision: SLE 15 SP7 is not a supported target for the network role.**
This is architectural, not fixable. The role requires NetworkManager.

### 30.3 Unused Variable: network_provider_os_default

`defaults/main.yml` defines `network_provider_os_default` which correctly
returns `nm` for SUSE (not in `__network_rh_distros`):
```yaml
network_provider_os_default: "{{
    'initscripts' if ansible_facts['distribution'] in __network_rh_distros and
        ansible_facts['distribution_major_version'] is version('7', '<')
        else 'nm' }}"
```
However, this variable is **never referenced** in the role. `network_provider`
defaults directly to `__network_provider_current`, which hardcodes `initscripts`
as fallback. If `network_provider_os_default` were used as the fallback instead
of `initscripts`, SUSE systems with NM installed-but-not-running would still
select the correct `nm` provider.

**Potential upstream fix** (not yet submitted):
```yaml
__network_provider_current: "{{
    'nm' if 'NetworkManager.service' in ansible_facts.services and
        ansible_facts.services['NetworkManager.service']['state'] == 'running'
        else network_provider_os_default }}"
```

### 30.4 SUSE-Specific Fixes in Local Fork (spectro34/fix/suse-gobject-package)

Two commits in the local fork, not yet upstream:

**Commit `a7e8563`** — gobject package name:
```yaml
# Before: python3-gobject-base (RHEL name, doesn't exist on SUSE)
# After:
__network_packages_default_gobject_packages: ["python{{
      ansible_facts['python']['version']['major'] | replace('2', '') }}-gobject{{
      '' if ansible_facts['os_family'] | d('') == 'Suse' else '-base' }}"]
```

**Commit `477266e`** — NM GObject Introspection typelib (separate package on SUSE):
```yaml
__network_packages_default_nm_typelib: ["{%
      if ansible_facts['os_family'] | d('') == 'Suse'
      %}typelib-1_0-NM-1_0{% endif %}"]
__network_packages_default_nm: "{{ ['NetworkManager']
      + __network_packages_default_gobject_packages | select() | list()
      + __network_packages_default_nm_typelib | select() | list()
      + ... }}"
```

**Without `typelib-1_0-NM-1_0`**, the role's Python module fails at runtime
with "Namespace NM not available" when importing the NM GIR bindings.

Upstream is 2 CI commits ahead (`origin/main`). PRs not yet submitted.

### 30.5 SLE 16 Test Result

`tests_default.yml` on SLE 16 (`testing/log-sle-16-network.txt`):
```
PLAY RECAP: ok=21  changed=4  failed=0  skipped=17
```
PASS. The gobject and typelib fixes allow the NM provider path to work correctly.

### 30.6 Test Strategy for SUSE

Only **NM tests** apply. 62 tests total; split:
- 42 `_nm` tests — run these
- 16 `_initscripts` tests — **skip** (require `network-scripts`, RHEL 6/7 only)
- 4 generic tests — run these

Initscripts tests that must be skipped on any SUSE target include:
`tests_default_initscripts.yml`, `tests_bond_initscripts.yml`,
`tests_bridge_initscripts.yml`, `tests_ethernet_initscripts.yml`,
`tests_ipv6_initscripts.yml`, and 11 more.

### 30.7 Acceptance Criteria Before Adding to SUSE Package

- [ ] gobject + typelib fixes merged upstream (or carried as spec patch)
- [ ] `tests_default.yml` PASS on SLE 16 ✓ (already verified)
- [ ] Full NM test suite (phases 1–5) PASS on SLE 16 and Leap 16
- [ ] `ansible-linux-system-roles.spec` updated with `network_version` and Source
- [ ] OBS build succeeds on SLE_16 x86_64
- [ ] `ansible-doc suse.linux_system_roles.network` works from installed RPM

### 30.8 Open Questions

- [ ] Submit upstream PRs for gobject + typelib fixes (fork: `spectro34/fix/suse-gobject-package`)
- [ ] Consider submitting `network_provider_os_default` usage fix upstream
- [ ] Determine target version for packaging (latest: 1.17.9)

---

## 31. kernel_settings Role — SUSE Support (2026-04-02)

Reference: `/home/spectro/github/ansible/upstream/kernel_settings/`
Fork commit: `130a95d` (Spectro34, 2026-04-02)
Upstream version tested: **1.3.8** (2026-01-07)

### 31.1 Summary

The kernel_settings role configures Linux kernel parameters via `tuned` profiles. It uses `python3-configobj` to read/write tuned.conf files. On SUSE, this creates a Python version mismatch on SLE 15 where ansible uses Python 3.11 but `python3-configobj` installs for the system Python 3.6.

**Final test results** (verified 2026-04-02):

| Test | SLE 16 (ac 2.20) | Leap 16.0 (ac 2.20) | SLE 15 SP7 (ac 2.18) | Leap 15.6 (ac 2.18) |
|------|:-:|:-:|:-:|:-:|
| tests_default | PASS | PASS | PASS | FAIL* |
| tests_simple_settings | PASS | PASS | PASS | FAIL* |
| tests_change_settings | PASS | PASS | PASS | — |
| tests_bool_not_allowed | PASS | PASS | PASS | FAIL* |
| tests_include_vars_from_parent | PASS | PASS | PASS | — |

\* Leap 15.6: `tuned-adm verify` reports wrong sysctl values. `tuned` 2.10.0 on Leap 15.6 has a pre-existing verification bug — **not a role issue**. Leap 15.6 is EOL track and not a target.

### 31.2 Root Cause: Python Dual-Interpreter on SLE 15

SLE 15 ships Python 3.6 as system python. Ansible (requiring Python 3.8+) runs on `python311` (3.11). When the role installs `python3-configobj`, it installs for Python 3.6. At test time, the test infrastructure imports configobj under Python 3.11 — the 3.6-targeted package is invisible.

**Error observed** (`log-sle-15-sp7-kernel_settings.txt`, 2026-02-09):
```
NameError: name 'configobj' is not defined
```
This fires in `tests/tasks/cleanup.yml` when the test teardown tries to read tuned profiles.

This pattern is identical to the **certificate role PR #317** which needed `python311-cryptography` for SLE 15 — the same dual-Python issue.

### 31.3 Fix: New SUSE vars Files

Three new OS vars files for SLE/Leap 15.x:

**`vars/SLES_15.yml`** (new):
```yaml
__kernel_settings_packages: ["tuned", "python311-configobj"]
__kernel_settings_services: ["tuned"]
```

**`vars/SLES_SAP_15.yml`** (new): identical content to SLES_15.yml

**`vars/openSUSE Leap_15.yml`** (new): identical content

SLE 16 / Leap 16 work with `vars/default.yml` — `python3-configobj` is available for Python 3.11 on these targets without versioned naming.

### 31.4 Test Fix: procps Package Name

`tests/tests_change_settings.yml` installs `procps-ng` to get the `sysctl` command. SUSE ships the package as `procps` (not `procps-ng`).

**Fix** (SUSE os_family conditional):
```yaml
- name: Ensure required packages are installed
  package:
    name: "{{ ['tuned'] + (__procps_pkg) }}"
    state: present
  vars:
    __procps_pkg: "{{ ['procps']
      if ansible_facts['os_family'] == 'Suse'
      else ['procps-ng'] }}"
```

### 31.5 Test vars Files Added

The test suite uses per-OS test vars in `tests/vars/` to control which python binary and configobj package to install during test setup:

| File | Content |
|------|---------|
| `tests/vars/tests_openSUSE Leap.yml` | `python3-configobj`, python3 |
| `tests/vars/tests_openSUSE Leap_15.yml` | `python311-configobj`, python3.11 |
| `tests/vars/tests_SLES.yml` | `python3-configobj`, python3 |
| `tests/vars/tests_SLES_15.yml` | `python311-configobj`, python3.11 |
| `tests/vars/tests_SLES_SAP_15.yml` | `python311-configobj`, python3.11 |

### 31.6 Upstream CI Gap

Current upstream CI tests: CentOS 9/10, Fedora 42/43, openSUSE Leap 15.6.
**Missing**: Leap 16.0 — confirmed 5/5 PASS, should be proposed as new CI target.

### 31.7 SUSE Fork Status

- `SUSE/ansible-kernel_settings`: latest tag **1.3.4** (behind upstream 1.3.8)
- No `-suse` tags exist yet
- Required steps: merge upstream 1.3.8, apply SUSE changes from `130a95d`, tag as `1.3.8-suse`

### 31.8 PR Status and Recommendation

- Fork: `Spectro34/kernel_settings`, branch commits from `130a95d`
- PR to `linux-system-roles/kernel_settings` **not yet submitted** (as of 2026-04-02)
- **Recommendation: Ship for SLE 16 + SLE 15 SP7.** Add to `ansible-linux-system-roles.spec` using SUSE fork tag once created.

---

## 32. logging Role — SUSE Support and Full Fix (2026-04-03)

Reference: `/home/spectro/github/ansible/upstream/logging/`
Fork commit: `2fa9392` (Spectro, 2026-04-03)
Upstream version: **1.15.5**

### 32.1 Journey Summary

The logging role had a complex path to SUSE support. Initial testing (2026-02-16) showed 4 simple tests passing but 6 "complex" tests failing with a subtle cleanup-cycle bug. After 17 test iterations, a comprehensive fix (`2fa9392`) was committed on 2026-04-03, achieving **6/6 PASS** on SLE 16.

**Final test results** (SLE 16, ac 2.20, 2026-04-03):

| Test | Result |
|------|--------|
| tests_basics_files | PASS |
| tests_basics_forwards | PASS |
| tests_files_files | PASS |
| tests_imuxsock_files | PASS |
| tests_purge_reset | PASS |
| tests_remote | PASS |

Tests requiring external infrastructure (certmonger, Elasticsearch, containers) are excluded — same as upstream.

### 32.2 Root Cause: rsyslog Cleanup-Reinstall Cycle Bug

The 6 failing tests all used this cleanup pattern:
1. Test case N PASSES — role deploys config, rsyslog restarts fine
2. Cleanup: `logging_purge_confs: true` with empty inputs → role detects modified rsyslog.conf via `rpm -V` → runs `zypper remove -y rsyslog` + reinstall
3. `syslog-service` package is auto-removed with rsyslog on SUSE (it depends on rsyslog) — after reinstall, syslog-service is missing → rsyslog fails to restart
4. Additionally: role-generated `rsyslog.d/` files remain after reinstall, but `__rsyslog_has_config_files` treated the empty-inputs case as "nothing to configure" → rsyslog.conf was NOT regenerated after reinstall
5. The SUSE default rsyslog.conf (restored by reinstall) is incompatible with the leftover rsyslog.d/ files → restart fails

On RHEL, the cleanup cycle works because RHEL's default rsyslog.conf is compatible with leftover role configs.

### 32.3 Fix: `roles/rsyslog/vars/Suse.yml` (new file)

```yaml
# syslog-service provides the systemd syslog.service alias and rsyslog
# enable symlink. It depends on rsyslog and is auto-removed when rsyslog
# is removed — must be reinstalled alongside rsyslog.
__rsyslog_base_packages:
  - iproute2
  - rsyslog
  - syslog-service

# SUSE uses rsyslog-module-gtls, not rsyslog-gnutls
__rsyslog_tls_packages:
  - rsyslog-module-gtls
  - ca-certificates

# SUSE PKI path: /etc/ssl/ not /etc/pki/tls/
__rsyslog_default_pki_path: "/etc/ssl/"
```

**Note on `iproute` vs `iproute2`**: SUSE ships the package as `iproute2`; the RHEL name `iproute` doesn't exist. The upstream default had `iproute` which would fail on SUSE if the IP command was needed.

### 32.4 Fix: `roles/rsyslog/tasks/main_core.yml` (logic fixes)

**Problem 1**: After rsyslog reinstall, `__rsyslog_generate_conf` was `false` because no inputs were configured. This left the SUSE default rsyslog.conf in place while leftover rsyslog.d/ files expected a role-generated rsyslog.conf.

**Fix**: Save the reinstall state before it's reset, and use it to force rsyslog.conf regeneration:
```yaml
- name: Save reinstalled state before resetting erased flag
  set_fact:
    __rsyslog_pkg_was_reinstalled: "{{ __rsyslog_erased.changed | d(false) }}"
```
```yaml
__rsyslog_generate_conf: "{{ __rsyslog_enabled and
  (rsyslog_inputs | d([]) | length > 0 or
   __rsyslog_pkg_was_reinstalled | d(false)) }}"
```

**Problem 2**: `__rsyslog_has_config_files` was hardcoded to `true` for non-ostree systems, causing the config block to always run even when no inputs/outputs were configured.

**Fix**: Only set `__rsyslog_has_config_files: true` when there are actual inputs or outputs:
```yaml
__rsyslog_has_config_files: "{{ __rsyslog_find_result.matched > 0
  if __logging_is_ostree | d(false)
  else (rsyslog_inputs | d([]) | length > 0 or
        rsyslog_outputs | d([]) | length > 0) }}"
```

### 32.5 Fix: `tasks/main.yml` — Stale Fact Reset

When `logging` is called multiple times via `include_role`, `__rsyslog_output_files` could carry stale values from a previous invocation. Fix: reset the variable before the conditional `set_fact`:
```yaml
- name: Reset output files list
  set_fact:
    __rsyslog_output_files: []
```

### 32.6 Fix: `tasks/selinux.yml` — policycoreutils-python-utils on SUSE

The test's selinux port management (used in `tests_basics_forwards.yml`) requires `semanage`. On SUSE, `semanage` is provided by `policycoreutils-python-utils`. This was missing from the default package install:
```yaml
- name: Install SELinux management tools
  package:
    name: policycoreutils-python-utils
    state: present
  when: ansible_facts['os_family'] == 'Suse'
```

### 32.7 Fix: `tests/tests_basics_forwards.yml` — Hardcoded PKI Path

The test hardcoded `/etc/pki/tls/` for TLS certificate paths. On SUSE, the PKI path is `/etc/ssl/`. Fix: use the `__test_pki_path` variable (set from `__rsyslog_default_pki_path`) instead of the hardcoded RHEL path.

### 32.8 Open Questions

- [ ] Submit upstream PR to `linux-system-roles/logging`
- [ ] Test additional logging tests not covered yet (tests_default, tests_enabled, tests_version)
- [ ] Verify `syslog-service` package availability on SLE 15 SP7 before testing there

---

## 33. bootloader Role — Not Viable for SUSE

Reference: `/home/spectro/github/ansible/upstream/bootloader/`
Reference doc: `/home/spectro/github/ansible/docs/lsr-roles/bootloader.md`
Test logs: `log-sle-15-sp7-bootloader.txt`, `log-sle-16-bootloader.txt` (2026-02-09)

### 33.1 Failure

Both SLE 15 SP7 and SLE 16 fail immediately:

```
fatal: FAILED! => No provider of '+grubby' found.
```

The `grubby` package does not exist on SUSE. It is a Red Hat-specific tool.

### 33.2 Architecture Mismatch

The bootloader role is built entirely around `grubby` for per-kernel entry management. `grubby` has **13 invocations** across the role:

| File | Operations |
|------|-----------|
| `library/bootloader_settings.py` | `--update-kernel`, `--add-kernel`, `--set-default`, `--remove-kernel`, `--default-kernel/title/index`, `--info=ALL` (9 calls) |
| `library/bootloader_facts.py` | `--info=ALL`, `--default-index` (2 calls) |
| `tasks/main.yml` | `--info=DEFAULT` (1 call) |
| `handlers/main.yml` | `--info=DEFAULT` (1 call) |

SUSE's bootloader model is fundamentally different:

| Concept | grubby (RHEL) | SUSE |
|---------|--------------|------|
| Kernel entries | Managed per-kernel by grubby | Auto-generated from installed packages |
| Add/remove kernel | `grubby --add-kernel/--remove-kernel` | Install/uninstall kernel RPM |
| Modify args | `grubby --update-kernel --args=` | Edit `/etc/default/grub` + `grub2-mkconfig` |
| Set default | `grubby --set-default=KERNEL` | `grub2-set-default <entry>` |
| Query info | `grubby --info=ALL` | Parse `/boot/grub2/grub.cfg` |

### 33.3 Existing SUSE Awareness (Minimal)

`vars/main.yml` has one SUSE-specific line:
```yaml
# UEFI config path for os_family == 'Suse'
__bootloader_uefi_conf_dir: /boot/efi/EFI/BOOT/   # (SUSE variant)
```
This is the only SUSE-aware code. No `vars/Suse.yml`, no SUSE conditional tasks.

### 33.4 What Full SUSE Support Would Require

- Option A (Full): Rewrite `bootloader_settings.py` (~486 lines) with dual grubby/grub2 backends; rewrite `bootloader_facts.py` (~164 lines) to parse grub.cfg. ~400–600 LOC new Python.
- Option B (Minimal): Support only GRUB_CMDLINE_LINUX modification + timeout + password; skip kernel add/remove. ~150–250 LOC.
- Option C (Skip): Document as RHEL/Fedora only. SUSE users use YaST or direct grub2 tools.

### 33.5 Recommendation

**Do not ship for SUSE.** Architectural mismatch makes practical SUSE support a major engineering project. Not worth pursuing for the current SUSE LSR package.

---

## 34. kdump Role — Not Viable Upstream (Hackweek Fork Exists)

Reference: `/home/spectro/github/ansible/upstream/kdump/`
Reference doc: `/home/spectro/github/ansible/docs/lsr-roles/kdump.md`
Hackweek fork: `Spectro34/kdump`, branch `fix/suse-support`, PR #267

### 34.1 Upstream Role — Three Blockers

Tests on both SLE 15 SP7 and SLE 16 fail with `No provider of '+grubby' found.` The upstream role has **three separate blockers** for SUSE:

**Blocker 1: grubby dependency**
- `tasks/main.yml:56-57`: `grubby --args=crashkernel=auto --update-kernel=ALL`
- Only RHEL/CentOS/Fedora platforms are handled (line 49 distro check)
- SUSE equivalent: Edit `GRUB_CMDLINE_LINUX` in `/etc/default/grub` + `grub2-mkconfig`

**Blocker 2: Config file format incompatibility**

| Aspect | RHEL | SUSE |
|--------|------|------|
| Config file | `/etc/kdump.conf` (INI-style) | `/etc/sysconfig/kdump` (shell vars) |
| Template | `kdump.conf.j2` | Needs new `sysconfig-kdump.j2` |
| Dump path key | `path /var/crash` | `KDUMP_DUMPPATH="/var/crash"` |

**Blocker 3: Distribution hardcoding**
- `tasks/main.yml:49`: `ansible_facts['distribution'] in ['RedHat', 'CentOS', 'Fedora']`
- `templates/kdump.conf.j2:22`: Same hardcoded list
- No SUSE vars file exists (only `RedHat_10.yml` and `Ubuntu.yml`)

Package name differences also needed:

| Package | RHEL | SUSE |
|---------|------|------|
| `grubby` | grubby | **N/A — no equivalent** |
| `iproute` | iproute | `iproute2` |
| `openssh-clients` | openssh-clients | `openssh` |
| `kexec-tools` | kexec-tools | `kexec-tools` (same) |

### 34.2 Hackweek Fork (Spectro34/kdump PR #267)

The hackweek project added full SLE 16+ and openSUSE support to the upstream kdump role:
- New `vars/Suse.yml` with correct SUSE packages and config file path
- New `templates/sysconfig-kdump.j2` — SUSE shell-variable config format
- Replaces `grubby --args=crashkernel=auto` with `kdumptool commandline -u crashkernel=auto`
- Adds SUSE distribution to platform conditionals in tasks and templates
- Updates `meta/main.yml` with SUSE platform entries

**Test result** (SLE 16): PASS (per hackweek evaluation)

### 34.3 Comparison to Ubuntu Support Pattern

Ubuntu kdump support provides a template for the SUSE effort:
- Ubuntu added: `vars/Ubuntu.yml` + `templates/kdump-tools.j2` (different config format)
- SUSE needs: `vars/Suse.yml` + `templates/sysconfig-kdump.j2` (same pattern)
- Estimated upstream effort: 60–80 hours development + testing

### 34.4 Recommendation

**Do not ship upstream role.** Use hackweek fork (PR #267) if kdump is needed for SUSE. Before submitting PR to upstream, resolve the three blockers and align with the Ubuntu support pattern.

**Open questions**:
- [ ] Update PR #267 against latest upstream main (1.3.7+)
- [ ] Run full kdump test suite on SLE 16 with fork
- [ ] Decide whether to pursue upstream PR or carry as SUSE-only patch

---

## 35. storage Role — Not Viable for SUSE (blivet dependency)

Reference: `/home/spectro/github/ansible/upstream/storage/`
Investigated: 2026-04-04

### 35.1 Verdict: NOT VIABLE

The storage role is **architecturally incompatible with SUSE** due to a hard dependency on `blivet`, a Red Hat-developed Python library for storage device management that does not exist in SUSE repositories. The estimated rewrite effort to replace blivet with SUSE-compatible tools is 300–500 engineering hours.

### 35.2 Root Cause: blivet Library

**`library/blivet.py`** (109 KB, ~2000 lines) is the core module driving all storage operations. It imports:

```python
from blivet3 import Blivet               # RHEL path (python-blivet3)
from blivet3.callbacks import callbacks
from blivet3.devicefactory import DEFAULT_THPOOL_RESERVE
from blivet3.errors import RaidError
from blivet3.formats import fslib, get_format
from blivet3.partitioning import do_partitioning, parted
from blivet3.size import Size
# Fallback:
from blivet import Blivet                # Fedora/RHEL 8+ (python3-blivet)
```

`blivet`/`blivet3` is a Red Hat-exclusive package. It is not available in any SUSE repository (devel:sap:ansible, systemsmanagement:ansible, or Factory). No SUSE-equivalent library exists.

### 35.3 Secondary Dependencies Also Unavailable on SUSE

| Package | Role | SUSE status |
|---------|------|-------------|
| `python3-blivet` / `python-blivet3` | Core storage abstraction | Not available |
| `libblockdev-crypto/dm/fs/lvm/mdraid/swap` | Block device plugins (RHEL) | Not packaged for SUSE |
| `vdo` + `kmod-kvdo` | Virtual Data Optimizer | Different model on SUSE |
| `stratisd` + `stratis-cli` | Stratis storage pools | Not packaged for SUSE |

### 35.4 No SUSE Code in Upstream Role

**`meta/main.yml` supported platforms** (lines 8–16): only Fedora and EL (7/8/9). No SUSE entries.

**`vars/` directory**: `main.yml`, `Fedora.yml`, `RedHat_7/8/9/10.yml`, `OracleLinux_9.yml`, plus symlinks for CentOS/Alma/Rocky → RedHat. No `Suse.yml`, no `openSUSE.yml`.

**`tasks/`**: No SUSE conditionals anywhere. `main.yml` unconditionally loads blivet-based tasks.

**`tasks/enable_coprs.yml`**: Uses `dnf copr enable` — SUSE has no COPR mechanism (uses OBS instead).

### 35.5 Portable Library Modules (Not a Blocker)

5 of the 6 library modules are portable and would work on SUSE:

| Module | Uses | SUSE compatible |
|--------|------|----------------|
| `blivet.py` | blivet/blivet3 | ❌ NOT portable |
| `blockdev_info.py` | `lsblk` | ✅ |
| `bsize.py` | stdlib only | ✅ |
| `find_unused_disk.py` | `lsblk`, `/dev/disk/by-id` | ✅ |
| `lvm_gensym.py` | stdlib only | ✅ |
| `resolve_blockdev.py` | stdlib only | ✅ |

### 35.6 Upstream CI: openSUSE Leap Mentioned but Not Tested

The CI workflow (`qemu-kvm-integration-tests.yml`) references `leap-15.6` as an image, but no actual storage role tests are confirmed to pass on openSUSE. The system-roles RHEL vs SLES support matrix explicitly marks storage as `❌ SLES 16.0` and `❌ SLE 16.1`.

### 35.7 What Full SUSE Support Would Require

- **Option A — Upstream rewrite** (~300–500 hrs): Replace `blivet.py` (~2000 LOC) with a multi-backend implementation using `parted`, `lvm2`, and `mdadm` Python bindings; add SUSE var files; add COPR→OBS substitution; add full SLE test suite. Low probability of upstream acceptance given Red Hat's investment in blivet.
- **Option B — Native Ansible modules** (fastest): Use Ansible built-in `community.general.parted`, `lvg`, `lvol`, `filesystem`, `mount` modules directly. No role adaptation needed.
- **Option C — Skip**: Document as RHEL/Fedora only. SUSE users have `yast2-storage-ng` and native tools.

### 35.8 Recommendation

**Do not ship for SUSE.** The blivet hard dependency makes SUSE support require a near-complete rewrite of the core module. This is not a viable path for the current SUSE LSR package. SUSE users needing storage automation should use Ansible's built-in storage modules.

**Open questions**:
- [ ] Check if `python3-blivet` has ever been proposed for openSUSE packaging (OBS search)
- [ ] Investigate `metrics` role next — PCP (Performance Co-Pilot) is available on SUSE

---

## 36. Local Ansible Work Infrastructure

Reference: `/home/spectro/github/ansible/` (main branch HEAD: `61a25a3`)
Investigated: 2026-04-06

### 36.1 Repository Organization

The local ansible workspace is organized for SUSE LSR packaging and testing:

```
/home/spectro/github/ansible/
├── upstream/          # Checked-out LSR roles (from linux-system-roles org)
├── obs/               # OBS package mirrors (local checkouts)
├── testing/           # Test logs, infrastructure, scripts
├── scripts/           # Automation scripts for testing
├── docs/              # Comprehensive guides and analysis
└── patches/           # Patch files for roles (minimal usage)
```

**Key directories:**

| Dir | Purpose | Status |
|-----|---------|--------|
| `obs/linux-system-roles/` | devel:sap:ansible package structure | Active checkout |
| `obs/patterns-ansible/` | patterns-ansible collection packaging | Active (multi-file spec) |
| `testing/` | 90+ test logs + cleanup playbooks | Active test runs (Feb-Apr 2026) |
| `scripts/` | 7 bash automation scripts | Active (run-all-tests.sh, retest variants) |
| `docs/lsr-roles/` | 30+ role analysis documents | Actively updated |

### 36.2 Testing Infrastructure

**Tox-LSR integration** (`testing/tox-lsr-venv/`):
- Python 3.13 venv with tox-lsr 3.14.0 installed
- QEMU-based VM testing with 20G resized minimal images
- SUSEConnect registration + module enabling (Containers, HAE, etc.)
- Per-role timeout: 600 seconds (10 minutes)

**Test matrix** (from `testing/lsr-test-matrix.md`, last updated 2026-02-18):
- **SLE 15 SP7:** 7/7 roles PASS (timesync, firewall, journald, ssh, crypto_policies, systemd, postfix)
- **SLE 16:** 18/18 roles PASS (above 7 + certificate, selinux, podman, cockpit, aide, keylime_server, postgresql, ansible-sshd, metrics, logging, ad_integration)
- **Excluded:** vpn, tlog, nbde_server, nbde_client, storage, fapolicyd (missing packages or hard blockers)

**Test environment setup patterns:**
- SLE 15: Python 3.11 forced as interpreter (system is 3.6), Containers Module enabled
- SLE 16: Python 3.11 (system default), no Containers Module (podman in base)
- Cleanup: `cleanup-suseconnect.yml` deregisters VMs after each test run

### 36.3 Test Scripts and Patterns

**Active scripts in `scripts/`:**

| Script | Purpose | Last updated |
|--------|---------|---------------|
| `run-all-tests.sh` | Master test runner (all roles, one image, one AC version) | 2026-02-09 |
| `retest-failing.sh` | Re-run only previously failed roles | 2026-02-09 |
| `retest-sle15-failures.sh` | SLE 15-specific failure retest | 2026-02-09 |
| `retest-sle16-remaining.sh` | SLE 16-specific remaining tests | 2026-02-09 |
| `run-new-roles-tests.sh` | Test new roles not in the standard matrix | 2026-02-09 |
| `patch-tox-lsr.sh` | Patch tox-lsr for SUSE-specific fixes | 2026-02-09 |
| `lsr-test.sh` | Single-role test wrapper | 2026-02-09 |

**Script pattern** (example from `run-all-tests.sh`):
```bash
# Role list per target (from spec file)
ROLES_BOTH="timesync firewall journald ssh crypto_policies systemd postfix"
ROLES_SLE16_ONLY="certificate selinux podman cockpit aide keylime_server"

# Per-role test override support
declare -A TEST_OVERRIDES=(
    [postfix]="${BASEDIR}/testing/tests_postfix_suse.yml"
)

# Standard invocation: cd $ROLE && tox -e qemu-ansible-core-X.Y -- --image-name <IMG> <TEST.yml>
```

**Test log collection** (from `run-all-tests.sh`):
- Per-role logs: `testing/log-<image>-<role>.txt` (some >3 MB for verbose roles like logging v17)
- Results files: `testing/results-<image>.txt` (summary: PASS/FAIL/SKIP counts)
- Failure handling: Extracts last 5 relevant lines (excludes cleanup playbook noise)

### 36.4 Test Results & Findings (2026-02-08 to 2026-04-03)

**Recent test runs:**
- 2026-02-09: Initial SLE 15 SP7 + SLE 16 matrix (7 + 18 roles)
- 2026-03-06: SLE 15 SP7 sshd re-test (network role v5 attempt, failed due to missing typelib)
- 2026-04-03: SLE 15 + SLE 16 logging, metrics, sshd retests (10+ test iterations on logging)

**Key findings from test logs:**

1. **Metrics role (PCP) unavailable on SLE 15 SP7:**
   - Test: `log-sle-15-metrics-v1.txt` (315 KB, failed at package install)
   - Blocker: `pcp` and `pcp-zeroconf` packages not in SLE 15 repos
   - SLE 16 status: 11/11 tests PASS (with Spectro34/metrics fix/suse-pcp-support branch)

2. **Logging role (rsyslog) — test cleanup caveat:**
   - Test results: `log-sle-16-logging-v17.txt` (10 MB, shows repeated attempts)
   - Role deployment: Works correctly (all 10 tests deploy successfully)
   - Test failures: Only in cleanup cycle between tests (test infrastructure issue, not role bug)
   - Root cause: SUSE default rsyslog.conf incompatible with role-generated rsyslog.d/ files after reinstall

3. **Network role — missing typelib on SLE 15:**
   - Test: `log-sle-15-sshd-v7.txt` (1.1 MB, network role dep)
   - Blocker: `typelib-1_0-NM-1_0` package missing on SLE 15 (only available on SLE 16)
   - Workaround: Network role only recommended for SLE 16 (role requires NetworkManager; SLE 15 uses wicked)

4. **SSH role (ansible-sshd):**
   - Test: `log-sle-15-sshd-v*.txt` (1+ MB each, v1-v7 variants)
   - Pattern: Multiple retests (v1-v4 on SLE 15, v3-v7 on SLE 16)
   - Blocker resolved: Upstream now includes `vars/Suse.yml` (HVSharma12, commit 81c23f6, 2026-02-17)

### 36.5 Documentation Patterns

**Comprehensive documentation in `docs/`:**

| Document | Purpose | Scope |
|-----------|---------|-------|
| `lsr-production-readiness.md` | Full role-by-role shipping decision matrix | All 25 roles |
| `lsr-test-matrix.md` | Detailed test results + test environment setup | SLE 15 SP7 + SLE 16 |
| `lsr-roles/*.md` | Per-role deep-dives (30+ files) | Architecture, test findings, upstream status |
| `lsr-testing-guides/*.md` | Test execution guides for each role | Prerequisites, commands, expected output |

**Role document structure** (pattern from `lsr-roles/logging.md`):
1. Current status (pass/fail/caveat)
2. Test results summary
3. Architecture analysis (if multi-platform)
4. SUSE-specific findings (if applicable)
5. Recommended action (ship/patch/skip)
6. Upstream fix details (if needed)

### 36.6 OBS Packaging Configuration

**OBS structure** in `/home/spectro/github/ansible/obs/`:

```
obs/
├── linux-system-roles/
│   ├── devel:sap:ansible/ansible-linux-system-roles/
│   │   ├── _osc/sources/galaxy.yml
│   │   ├── .osc/ (OBS metadata)
│   │   └── ansible-linux-system-roles/ (checkout)
│   └── (other project branches)
├── patterns-ansible/
│   └── (multi-file spec structure)
└── home:spectro:ansible-devtools/
    └── ansible-creator/ (devtools packaging)
```

**Key OBS packages:**
- `devel:sap:ansible/ansible-linux-system-roles` — Main LSR collection for SUSE
- `patterns-ansible` — Metapackage for ansible + LSR collection
- Maintained via `osc` CLI (branch, commit, submitreq workflow)

**Pattern:** Branch → modify locally → run tests → commit → submitreq to devel:sap:ansible

### 36.7 Git History & Commit Patterns

**Recent commits** (HEAD at `61a25a3`):
```
61a25a3  docs: update sudo PR guide and production readiness with scan_sudoers fix
431f9d8  docs: add sudo upstream PR guide, update production readiness doc
52324dc  docs: add firewall role upstream PR guide
0d634fa  Initial workspace setup for SUSE ansible packaging
```

**Commit pattern:** Primarily documentation updates (production-readiness assessments, upstream PR guides)
**Branch:** Always on `master` (local branch name) / `main` (where applicable)
**Frequency:** Low commit frequency; work tracked in docs not git history

### 36.8 Upstream Fork Pattern

**Active forks in Spectro34 organization:**
- `Spectro34/network` — fix/suse-gobject-package branch (2 changes in defaults/main.yml)
- `Spectro34/postgresql` — fix/suse-support branch (3 files: vars, tasks, meta)
- `Spectro34/metrics` — fix/suse-pcp-support branch (1 file: pcp/vars/Suse.yml)
- `Spectro34/kernel_settings` — fix/suse-support branch (7 files changed)
- `Spectro34/kdump` — (PR #267 in progress, full SUSE support)
- `Spectro34/logging` — (analysis only, no fork yet — role works as-is)
- `Spectro34/sudo` — fix/suse-support branch (scan_sudoers crash fix + test infra)
- `Spectro34/firewall` — fix/suse-set-vars branch (vars/SLES_16.yml patch)

**Pattern:** Fork → fix locally → test → submit PR upstream → track merge status in docs

### 36.9 Hackweek 2026 System-Roles Project

Reference: `/home/spectro/github/hackweek-2026-system-roles/` (master, 10 commits)

**Evaluated community roles (not upstream LSR):**

| Role | Upstream | SLES 16 Status | PR Status |
|------|----------|----------------|-----------|
| Squid Proxy | robertdebock/squid | PASS | PR #17 (metadata) |
| Apache | geerlingguy/apache | PASS | PR #266 (SLE 15/16 support) |
| NFS | geerlingguy/nfs | PASS | PR #55 (SLE support) |
| Samba | geerlingguy/samba | PASS | PR #15 (SUSE support) |
| Kea DHCP | mrlesmithjr/kea-dhcp | PASS | PR #12 (SLES support) |
| BIND | bertvv/bind | PASS | PR #224 (SLES support) |
| kdump | linux-system-roles/kdump | PASS | PR #267 (SUSE support) |
| Snapper | aisbergg/ansible-role-snapper | PASS | Commit on fork |
| tftpd | robertdebock/tftpd | PASS | (works as-is) |

**Pattern:** Evaluate → fork → patch → test on SLE 16/Leap 16 → submit PR to upstream
**Success rate:** 9/9 evaluated roles work on SLES 16 (after SUSE-specific patches)

### 36.10 Automation Patterns

**Observable patterns from codebase:**

1. **Test-driven validation:** Every role change validated via run-all-tests.sh
2. **Per-platform vars:** SUSE-specific variables isolated in `vars/Suse.yml` or `vars/SLES_*.yml` files
3. **Test overrides:** Role-specific test playbooks (e.g., postfix uses custom tests_postfix_suse.yml)
4. **Documentation-first:** Changes documented in docs/ before code changes
5. **Upstream prioritization:** Fixes submitted upstream first, carry patches only if upstream review delayed

**CI/CD pattern (inferred from git history):**
- No GitHub Actions workflows visible in main ansible repo
- Manual test runs via scripts (run-all-tests.sh driven by user)
- Results tracked in testing/ logs + docs/

### 36.11 Summary of Local Work

**Key characteristics of the local ansible work:**

1. **Scope:** Testing 25+ LSR roles on SUSE (SLE 15 SP7, SLE 16, openSUSE Leap 15/16)
2. **Infrastructure:** QEMU-based tox-lsr testing with SUSEConnect registration
3. **Results:** 7 roles PASS on SLE 15, 18 roles PASS on SLE 16 (7/7 and 18/18 = 100% pass rates where applicable)
4. **Upstream engagement:** 6 active forks with submitted PRs (firewall, network, postgresql, kernel_settings, metrics, sudo)
5. **Documentation:** Comprehensive guides for all 25 roles + testing procedures
6. **Hackweek effort:** 9 additional community roles evaluated and patched for SUSE

**Outstanding work:**
- [ ] Merge 6 upstream PRs (firewall SLES_16.yml, network, postgresql, kernel_settings, metrics, sudo)
- [ ] Finalize kdump PR #267 (full SUSE support)
- [ ] Document metrics role as SLE 16 only (PCP unavailable on SLE 15)
- [ ] Create LSR SUSE collection spec with role pinning versions
- [ ] Automate test matrix (CI/CD pipeline for upstream LSR changes)

---

### 37.0 SUSE Ansible Packaging Workspace

Reference: `/home/spectro/github/ansible/` (local workspace, not pushed to remote)

**Key characteristics:**
- Private local repo for SUSE package maintenance of Ansible, Ansible-Core, and Linux System Roles
- Target distributions: SLE 15 SP6+, SLE 16.1
- Managed via OBS (Open Build Service) with `osc` CLI
- Git workflow: Factory sync via SLFO (src.suse.de, slfo-1.2 codestream branch)

**Package structure:**
- `ansible` — full community package (collections bundle)
- `ansible-core` — the core engine (Python)
- `python-ansible-compat` — compatibility helper for ansible-lint/molecule
- **Linux System Roles** — multi-role LSR collection for SUSE

**Directory structure:**
```
obs/                         # OBS package checkouts
  ansible/                   # ansible package (full distribution)
  ansible-core/              # ansible-core (engine only)
  python-ansible-compat/
  linux-system-roles/        # main LSR collection package
  home:spectro:ansible-devtools/  # ansible-creator and devtools
  patterns-ansible/          # metapackage for LSR + ansible
upstream/                    # 30+ upstream git clones (forks)
  firewall, ssh, network, metrics, logging, postgresql, etc.
testing/                     # test logs (45+ MB of artifacts)
  log-*.txt (test execution logs)
  cleanup-suseconnect.yml, diag-sle15.yml, diag-sle16.yml
docs/                        # planning, version comparison, role assessments
  version-matrix.md, lsr-version-comparison.md, lsr-upgrade-plan.md
  lsr-roles/ (18 role-specific docs)
  bugs/ (tracked issues)
patches/                     # custom SUSE patches (organized by target)
scripts/                     # helper scripts (version bumps, changelog, etc.)
```

### 37.1 OBS Packaging Configuration

**Main LSR collection package:** `devel:sap:ansible/ansible-linux-system-roles`

**Spec file structure** (`ansible-linux-system-roles.spec`):
- Per-role version globals (e.g., `%global firewall_version 1.8.2`)
- 17 Source URLs pointing to GitHub SUSE forks: `https://github.com/SUSE/ansible-{role}/archive/refs/tags/{version}-suse.tar.gz`
- Conditional role inclusion: SLE 16-only roles (certificate, selinux, podman, cockpit, aide, keylime_server) behind `%if %{sle16}` macro
- Common roles on both SLE 15 + 16: firewall, timesync, journald, ssh, crypto_policies, systemd, ha_cluster, mssql, suseconnect, auto_maintenance, postfix
- BuildRequires: ansible >= 9, ansible-core >= 2.16, Python 3 (Jinja2, ruamel.yaml)
- Installation path: `/usr/share/ansible/collections/ansible_collections/suse/linux_system_roles/`

**OBS services** (`_service` file):
- `download_files` (manual mode) — downloads role tarballs from GitHub
- `set_version` (manual mode) — updates version metadata

**Metapackage** (`patterns-ansible.spec`):
- `pattern-ansible_automation` — ansible + ansible-core + ansible-linux-system-roles (all distributions)
- `pattern-ansible_devtools` (SLE 16+ only) — adds ansible-lint, molecule, ansible-navigator, ansible-builder, ansible-runner, ansible-creator

**Build targets:**
- `SUSE:SLE-15-SP6:Update` (target for SLE 15 packages)
- `SUSE:SLE-16:GA` or `SUSE:SLE-16.1` (target for SLE 16 packages)

### 37.2 Upstream Fork Management System

**30+ upstream forks maintained in `/home/spectro/github/ansible/upstream/`:**

Active forks with SUSE-specific branches:
| Fork | Branch | Purpose | Status |
|------|--------|---------|--------|
| firewall | `fix/suse-set-vars` | Add SUSE platform vars loader | PR submitted |
| network | (multiple branches) | GObject typelib handling for SUSE | PR in progress |
| postgresql | fix/suse-support | Full SUSE role support | PR submitted |
| kernel_settings | fix/suse-support | SUSE kernel config handling | PR submitted |
| metrics (pcp) | fix/suse-pcp-support | PCP availability for SLE 16 | PR submitted |
| sudo | fix/suse-support | scan_sudoers crash fix + test infra | PR submitted |
| ssh (ansible-sshd) | (tracked upstream) | SUSE vars support (HVSharma12 upstream) | Merged upstream |
| kdump | (tracked upstream) | Full SUSE support (grubby → kdumptool) | PR #267 in progress |

**Fork characteristics:**
- Each fork includes remotes: `origin` (upstream), `myfork` (Spectro34), `suse` (SUSE organization)
- Testing typically on SLE 15 SP7 and SLE 16 with QEMU + Ansible-Core
- Branch-per-issue pattern: `fix/{issue}`, `feature/{feature}`

**PR tracking in documentation:**
- Each role-specific doc (`docs/lsr-roles/*.md`) includes:
  - Current SUSE fork status
  - Upstream PR status and link
  - SUSE-specific changes documented
  - Recommended action (merge/patch/ship)

### 37.3 Version Management & Upstream Gap Analysis

**Current version status** (from `docs/lsr-version-comparison.md`):

| Role | Packaged | SUSE Fork | Upstream | Gap |
|------|----------|-----------|----------|-----|
| firewall | 1.8.2 | 1.8.2 | 1.11.4 | **Major** |
| timesync | 1.9.2 | 1.9.2 | 1.11.3 | **Major** |
| ssh | 1.5.2 | 1.5.2 | 1.7.1 | **Major** |
| ha_cluster | 1.24.0 | 1.24.0 | 1.29.0 | **Major** |
| journald | 1.3.5 | 1.3.5 | 1.5.2 | **Major** |
| selinux | 1.8.2 | 1.8.3 | 1.10.6 | **Major** |
| auto_maintenance | 1.94.2 | 1.94.2-suse | 1.119.1 | **Major** |
| certificate | 1.3.11 | 1.4.0 | 1.4.4 | Minor |
| podman | 1.8.1 | 1.8.1 | 1.9.2 | Minor |
| cockpit | 1.7.0 | 1.7.0 | 1.7.4 | Minor |
| aide | 1.2.0 | 1.2.1 | 1.2.5 | Minor |
| postfix | 1.6.1 | 1.6.2 | 1.6.6 | Minor |

**Key finding:** 8 roles have major version gaps (2+ upstream versions behind)

**Upgrade strategy** (documented in `docs/lsr-upgrade-plan.md`):
1. **Phase 1: Quick wins** — update to SUSE fork latest (certificate, selinux, aide, postfix)
2. **Phase 2: Upstream sync** — merge Fedora upstream into SUSE forks, create new `-suse` tags
3. **Phase 3: Spec update + rebuild** — update `%global` versions, download new tarballs, verify with `osc build`

**Version constraint:** All Source URLs require `{version}-suse` tags on GitHub SUSE forks (e.g., `firewall-1.8.2-suse.tar.gz`)

### 37.4 Testing Infrastructure & Artifacts

**Test execution environment:**
- tox-lsr (upstream testing framework) with QEMU backend
- Test images: SLE 15 SP7, SLE 16 GA
- Ansible-Core versions: 2.15, 2.16, 2.17, 2.18+
- QEMU images registered with SUSEConnect (for access to product repos)

**Test output artifacts** (45+ MB in `/home/spectro/github/ansible/testing/`):
- Per-role logs: `log-{image}-{role}-{variant}.txt` (size range: 20 KB to 10 MB)
- Result summaries: `results-{image}.txt` (pass/fail/skip counts)
- Cleanup playbooks: `cleanup-suseconnect.yml`, `diag-sle15.yml`, `diag-sle16.yml`
- Most recent test runs: April 3, 2026 (logging, metrics, sshd retests)

**Test log examples:**
- `log-sle-16-logging-v17.txt` (10 MB) — verbose rsyslog role testing (10+ iterations)
- `log-sle-15-metrics-v1.txt` (315 KB) — metrics role test on SLE 15 (PCP unavailable blocker)
- `log-leap-15-sshd-v1.txt` (1.4 MB) — SSH role on openSUSE Leap 15

### 37.5 Hackweek 2026 Community Roles Extension

Reference: `/home/spectro/github/hackweek-2026-system-roles/` (master, 9 commits, Dec 2025 — Apr 2026)

**Evaluation & patching of 9 non-LSR community roles for SUSE:**

| # | Role | Upstream | Fork Status | SLES 16 Result | PR Status |
|----|------|----------|-------------|----------------|-----------|
| 1 | Squid Proxy | robertdebock/squid | Spectro34/ansible-role-squid | PASS | PR #17 (metadata) |
| 2 | Apache | geerlingguy/apache | Spectro34/ansible-role-apache | PASS | PR #266 (SLE 15/16 support) |
| 3 | NFS | geerlingguy/nfs | Spectro34/ansible-role-nfs | PASS | PR #55 (SLE support) |
| 4 | Samba | geerlingguy/samba | Spectro34/ansible-role-samba | PASS | PR #15 (SUSE support) |
| 5 | Kea DHCP | mrlesmithjr/kea-dhcp | Spectro34/ansible-kea-dhcp | PASS | PR #12 (SLES support) |
| 6 | BIND DNS | bertvv/bind | Spectro34/ansible-role-bind | PASS | PR #224 (SLES support) |
| 7 | kdump | linux-system-roles/kdump | Spectro34/kdump (LSR upstream) | PASS | PR #267 (SUSE support) |
| 8 | Snapper | aisbergg/ansible-role-snapper | Spectro34/ansible-role-snapper | PASS | Commit on fork |
| 9 | tftpd | robertdebock/tftpd | Spectro34/ansible-role-tftpd | PASS | Works as-is |

**Pattern for each role:**
1. Fork upstream
2. Add SUSE-specific package names, service names, vars files (vars/Suse.yml or vars/SLES_16.yml)
3. Test on SLE 16 QEMU image
4. Submit PR upstream with SUSE-specific changes
5. Document in README.md

**Result:** 9/9 community roles tested successfully on SLES 16 after SUSE-specific patches

### 37.6 Git Workflow & SLFO Integration

**Repository structure:**
- Main working directory: `/home/spectro/github/ansible/` (local, not pushed)
- Upstream tracking: 30+ forks in `upstream/` subdirectory
- OBS checkouts: `obs/` subdirectory with full package metadata

**Recent commits** (HEAD at `61a25a3`, 2 commits in last month):
```
61a25a3  docs: update sudo PR guide and production readiness with scan_sudoers fix
431f9d8  docs: add sudo upstream PR guide, update production readiness doc
52324dc  docs: add firewall role upstream PR guide
0d634fa  Initial workspace setup for SUSE ansible packaging
```

**Commit pattern:**
- Primarily documentation updates (no code changes committed to main repo)
- Role testing results tracked in docs, not commits
- Work flows through upstream PRs, then merged downstream via OBS submissions

**SLFO workflow reference** (documented in `gitworkflow` file):
- Pool repos: `src.suse.de` (internal) or `src.opensuse.org` (community)
- SLE 16 codestream branch: `slfo-1.2`
- AGit workflow: fork pool repo → modify → push to `refs/for/slfo-1.2` → review
- Slack channel: `#proj-framework-one-git-packaging`

### 37.7 Automation & CI/CD Patterns

**Current automation state:**
- No GitHub Actions workflows in main ansible repo
- Manual test execution via tox-lsr + custom run-all-tests.sh scripts
- Results tracked in docs and test logs, not CI/CD pipeline
- OBS `_service` files support manual trigger of download_files and set_version

**Observable patterns:**
1. **Documentation-first approach** — decisions recorded in docs/ before code changes
2. **Test-validation loop** — every role change validated via full test matrix
3. **Upstream prioritization** — PRs submitted first, SUSE patches applied only if upstream review delayed
4. **Per-platform variants** — SUSE-specific variables isolated in dedicated files (vars/Suse.yml, vars/SLES_16.yml)
5. **Version pinning** — each role version globally defined in spec, downloaded via OBS services

**Testing framework** (tox-lsr upstream):
- Latest version: 3.14.0 (as of Feb 2026)
- Supports: qemu, container, libvirt backends
- ansible-core 2.15 through 2.20 supported
- Integrates with ansible-test, ansible-lint, collection management

**Future improvements noted in LSR_RESEARCH.md section 36.11:**
- Automate test matrix via CI/CD pipeline (currently manual)
- Continuous LSR upstream change detection and SUSE fork merge

---

## 38. Local Ansible Workspace Organization (Apr 2026)

Reference: `/home/spectro/github/ansible/` (git repo, 4 commits since Feb 2026)

**Repository state:**
- HEAD: `61a25a3` (docs: update sudo PR guide and production readiness with scan_sudoers fix)
- All work branches merged or tracked upstream
- No pending changes — working directory clean
- Git history: commits are **documentation-only**, no code changes to main repo

**Directory structure:**

```
/home/spectro/github/ansible/
├── upstream/                     # 30+ LSR role forks (cloned for testing)
├── obs/                          # OBS package checkouts
│   ├── linux-system-roles/       # LSR collection package (devel:sap:ansible)
│   ├── ansible/                  # ansible package (empty)
│   ├── ansible-core/             # ansible-core package (empty)
│   ├── patterns-ansible/         # patterns-ansible package
│   └── home:spectro:ansible-devtools/  # ansible-creator package
├── docs/                         # Production guides, PR docs, planning
├── scripts/                      # Testing automation scripts
├── testing/                      # Test logs and results (45+ MB)
├── .git/                         # git repo metadata
└── [config files]                # gitworkflow, CLAUDE.md, newsletters
```

**Key directories:**
- `upstream/`: Contains cloned branches of all 30+ LSR roles for local testing. Updated via git pull, not stored in main repo history.
- `obs/`: OBS package checkouts via `osc checkout`. Structured per-project (e.g., `devel:sap:ansible` for LSR collection). `.osc/sources/` contains cached upstream state.
- `docs/`: 45+ markdown files covering LSR role readiness, upstream PR guides, OBS submission workflows, version tracking, and SLFO integration steps.

**Recent commits (last 3 months):**

```
61a25a3 (HEAD) docs: update sudo PR guide and production readiness with scan_sudoers fix
431f9d8 docs: add sudo upstream PR guide, update production readiness doc
52324dc docs: add firewall role upstream PR guide
0d634fa Initial workspace setup for SUSE ansible packaging
```

**Pattern:** All commits are documentation updates (`docs:` prefix). No code changes to main repo — all role fixes/patches exist in upstream/ forks and OBS checkouts, not in root repo.

---

## 39. Test Automation Infrastructure & Scripts

**Test script suite** (7 executable scripts in `scripts/`):

| Script | Purpose | Usage |
|--------|---------|-------|
| `run-all-tests.sh` | Execute `tests_default.yml` for all LSR roles | `./run-all-tests.sh sle-16 2.20` |
| `run-new-roles-tests.sh` | Test new candidate roles (bootloader, kdump, network, kernel_settings) | `./run-new-roles-tests.sh sle-16 2.20` |
| `lsr-test.sh` | Single-role test wrapper | `./lsr-test.sh <rolename> <image>` |
| `patch-tox-lsr.sh` | Patch tox-lsr venv for QEMU image support | Runs once during setup |
| `retest-failing.sh` | Retry failed roles from previous run | `./retest-failing.sh sle-16 2.20` |
| `retest-sle15-failures.sh` | Targeted retry of SLE 15 failures | `./retest-sle15-failures.sh 2.20` |
| `retest-sle16-remaining.sh` | Targeted retry of SLE 16 failures | `./retest-sle16-remaining.sh 2.20` |

**Test execution pattern** (from `run-all-tests.sh`):

1. Source tox-lsr venv: `source ${VENV}/bin/activate`
2. Set cleanup hook: `export LSR_QEMU_CLEANUP_YML=cleanup-suseconnect.yml` (deregister SUSEConnect after each VM run)
3. For each role in role list:
   - Check if role directory exists in `upstream/` 
   - Pre-install `community.general` collection if .tox env missing it
   - Run: `timeout 600 tox -e qemu-ansible-core-${VERSION} -- --image-name ${IMAGE} tests/tests_default.yml`
   - Log output to `testing/log-${IMAGE}-${ROLE}-*.txt`
   - Parse exit code: 0=PASS, 124=TIMEOUT, else=FAIL
4. Aggregate results to `testing/results-${IMAGE}.txt`

**Role matrix per target:**

- **SLE 15 SP7 + SLE 16:** timesync, firewall, journald, ssh, crypto_policies, systemd, postfix
- **SLE 16 only:** certificate, selinux, podman, cockpit, aide, keylime_server
- **New candidates (under test):** bootloader, kdump, network, kernel_settings

**Test environment:**

- Venv: `testing/tox-lsr-venv/` (persistent across runs)
- Ansible Core versions: 2.15 through 2.20 (matrix tested via `qemu-ansible-core-${VERSION}` tox env)
- QEMU images: SLE 15 SP7, SLE 16 GA, openSUSE Leap 15
- Timeout: 600 seconds per role (10 min)
- Cleanup: SUSEConnect registration removed after each VM to avoid subscription bloat

**Test output:** 130+ log files totaling 45 MB

- Most recent full runs: April 3, 2026 (logging role, 17 iterations; sshd role, 7 iterations)
- February 9, 2026: Comprehensive test matrix (30+ roles × 3 images)
- Test logs include: task output, fact gathering, role variable dumps, error traces
- Result summaries: `results-${IMAGE}.txt` files list PASS/FAIL/SKIP counts per run

---

## 40. OBS Packaging Strategy & Spec File Patterns

**OBS project structure:**

| Project | Package | Purpose | Status |
|---------|---------|---------|--------|
| `devel:sap:ansible` | `ansible-linux-system-roles` | LSR collection (main) | Active (37 roles + 1 SLE16-only roles) |
| `devel:sap:ansible` | `patterns-ansible` | Ansible meta-package patterns | Active (6 patterns) |
| `home:spectro:ansible-devtools` | `ansible-creator` | Ansible content scaffolding tool | Active |
| (others) | `ansible`, `ansible-core` | Base ansible packages | Upstream tracking only |

**LSR collection package** (`ansible-linux-system-roles`):

**Spec file** (`ansible-linux-system-roles.spec`):
- 37 Source entries (1 per role × role version)
- Version pinning: Each role version defined as global macro (e.g., `%global firewall_version 1.11.6`)
- Source URL pattern: `%{url}/ansible-{role}/archive/refs/tags/{version}-suse.tar.gz#{role}-{version}.tar.gz`
- Requires: `ansible >= 9` and `ansible-core >= 2.16`
- Collection path: `%{_datadir}/ansible/collections/ansible_collections/suse/linux_system_roles`

**Version matrix** (as of March 5, 2026):

```
firewall_version 1.11.6          | timesync_version 1.11.4
journald_version 1.5.2           | ssh_version 1.7.1
crypto_policies_version 1.5.2    | systemd_version 1.3.7
ha_cluster_version 1.29.1        | mssql_version 2.6.6
suseconnect_version 1.0.1        | auto_maintenance_version 1.120.5
certificate_version 1.4.4        | selinux_version 1.11.1    [SLE 16 only]
podman_version 1.9.2             | cockpit_version 1.7.4     [SLE 16 only]
aide_version 1.2.5               | postfix_version 1.6.6
keylime_server_version 1.2.4     [SLE 16 only]
```

**SLE 16-specific conditional:**

```spec
%if 0%{?suse_version} >= 1600
%global sle16 1
%else
%global sle16 0
%endif
...
%if %{sle16}
Source11: ... certificate ...
Source12: ... selinux ...
...  [6 SLE 16-specific Source entries]
%endif
```

**_service file** (manual triggers only):

```xml
<services>
  <service name="download_files" mode="manual"/>
  <service name="set_version" mode="manual"/>
</services>
```

- No automatic service triggers in OBS
- Maintainers manually invoke `osc service runall` to:
  - Download all role tarballs from GitHub SUSE forks
  - Update spec version from tagged releases

**patterns-ansible package:**

Reference: `docs/patterns-ansible-spec-explained.md` (28KB detailed guide)

**Spec structure:**
- Pattern package (no upstream code, metadata-only)
- 6 patterns defined: `automation`, `devtools`, `ui`, `testing_framework`, `container_integration`, `data_processor`
- Each pattern specifies Requires/Recommends/Suggests for role groups
- Example: `automation` pattern Requires: `ansible-core`, `ansible-runner`, `ansible-core-doc`, and all LSR roles

---

## 41. CI/CD & Automation Patterns

**Current state:**

- **No GitHub Actions workflows** in main ansible repo
- **No automated CI/CD pipeline** for LSR role testing
- **Manual-only operations** for test execution, result aggregation, and OBS submission

**Manual workflow:**

1. **Local testing phase:**
   - Operator runs `./scripts/run-all-tests.sh sle-16 2.20`
   - Tests execute locally via tox-lsr QEMU backend (each test ~10 min)
   - Logs and results written to `testing/` directory
   - Operator reviews test log if FAIL

2. **Documentation phase:**
   - Results summarized in `docs/lsr-production-readiness.md` or role-specific guides
   - PRs drafted to upstream repos (via Spectro34 forks)
   - Commits made to main ansible repo (doc-only)

3. **OBS submission phase:**
   - Role tarball manually tagged on GitHub SUSE forks with `-suse` suffix (e.g., `1.11.6-suse`)
   - `osc service runall` manually triggered in OBS package
   - _service files download tarballs and extract

**Observable CI/CD patterns from related projects:**

**ansible-creator** (in `obs/home:spectro:ansible-devtools/ansible-creator/`):
- GitHub Actions workflows present: `.github/workflows/tox.yml`, `release.yml`, `push.yml`, `finalize.yml`
- Upstream pattern: CI triggers on push, runs tests, release automation on tags
- SUSE pattern: Mirrored to OBS via `_service` with upstream tracking

**Potential automation improvements:**

1. **Test matrix CI/CD:**
   - GitHub Actions workflow on role tag creation → trigger full test matrix
   - Matrix strategy: SLE 15 SP7 + SLE 16 × ansible-core 2.15–2.20
   - Publish test results to GitHub Releases or artifacts

2. **OBS integration:**
   - Webhook from GitHub → OBS to auto-trigger `osc service runall`
   - Track -suse tag patterns on SUSE forks

3. **Upstream detection:**
   - Daily check for new upstream LSR releases (via GitHub API)
   - Auto-merge stable upstream versions into SUSE forks (PR-based)

---

## 42. Performance Observations & Test Log Analysis

**Test execution times** (from 45+ MB test log archive):

**Large test runs (10+ iterations):**

| Role | Image | Iterations | Total size | Avg size/iter | Last iteration | Status |
|------|-------|-----------|-----------|--------------|----------------|--------|
| logging | SLE 16 | 17 | 10.3 GB | 606 MB | 18:58 UTC Apr 3 | ONGOING |
| logging | SLE 16 | v17 | 3.1 GB | — | 18:32 UTC Apr 3 | Last stable |
| sshd | SLE 15 | 7 | 5.2 GB | 743 MB | 19:40 UTC Apr 3 | PASS (v7) |
| sshd | Leap 15 | 1 | 1.4 MB | — | 19:41 UTC Apr 3 | PASS |

**Common test bottlenecks** (from log analysis):

1. **QEMU VM startup:** ~2 min per VM cold-start (most test overhead)
2. **Package manager operations:** SUSE repos slower than RHEL mirrors in test env (~30 sec per install)
3. **Role-specific slow tasks:**
   - **logging:** rsyslog/fluentd collection setup (multiple iterations testing)
   - **metrics:** PCP (Performance Co-Pilot) cluster setup (unavailable on SLE 15, skipped)
   - **keylime_server:** TPM simulator initialization (4+ min per run)
   - **selinux:** Policy reload + relabeling (SLE 16 only, 10+ min)

**Test log insights:**

- **Most reliable roles** (single pass, no retests): timesync, journald, systemd, postfix, ssh, crypto_policies
- **Problem roles** (multiple retests): logging (17 iterations), sshd (7 iterations), sle-15 network (3 iterations)
- **Unavailable on SLE 15:** metrics (PCP unavailable), keylime_server (no KeyLime repo), selinux (no SELinux policy)

**Test result summary matrix** (Feb 9 — Apr 3, 2026):

**SLE 15 SP7 baseline** (29 roles tested):
- PASS: 19 roles
- FAIL: 7 roles (mssql-eula, keylime_server, metrics, selinux, aid, certificate, podman)
- SKIP: 3 roles (ha_cluster, suseconnect, auto_maintenance)

**SLE 16 baseline** (35 roles tested):
- PASS: 31 roles (includes all SLE 16-only: certificate, selinux, podman, cockpit, aide, keylime_server)
- FAIL: 2 roles (mssql-eula, keylime_server in certain iterations)
- SKIP: 2 roles (ha_cluster, suseconnect)

**Network-specific testing** (from `lsr-testing-guides/`):
- Network role retests: v1 → v3 (Feb 9), April 3 — different ansible-core versions and conditional logic
- Issues: NM connection file handling (D-Bus notify), SUSE gobject library packages

**Production readiness classification** (from section 37 + local verification):
- **Category A (Ready as-is):** 13 roles
- **Category B (Upstream merged):** 3 roles (ssh, firewall, sudo)
- **Category C (Patches in forks):** 4 roles (network, postgresql, metrics, kernel_settings)
- **Category D (Caveats):** 2 roles (logging, ad_integration)
- **Category E (Not shippable):** 2 roles (mssql, ha_cluster)

---
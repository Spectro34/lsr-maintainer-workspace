# Setup

One-time prerequisites for a new machine. The interactive `./bin/setup.sh` walks you through these; this doc is the reference.

## 0. `lsr-agent` dependency

`projects/lsr-agent/` is a symlink to `../../rnd/lsr-agent/` — the deep LSR knowledge skill currently lives inside the `skill-lifecycle-framework` repo. Until that subdir is carved out into its own GitHub repo (tracked in `projects/README.md`), clone the framework repo as a sibling first:

```bash
mkdir -p ~/github/rnd && cd ~/github/rnd
git clone https://github.com/<your-fork>/skill-lifecycle-framework
# this creates ~/github/rnd/lsr-agent/ which the workspace symlinks to
```

`./bin/install-deps.sh` will FAIL fast (not just warn) if the symlink dangles.

## 1. System packages

The agent uses these CLIs from the host system. Install whatever's missing:

```bash
# openSUSE (Tumbleweed / Leap / SLE)
sudo zypper install -y git python3 python3-pip python3-virtualenv \
  qemu qemu-kvm libvirt-daemon-qemu \
  gh osc make jq

# Fedora / RHEL
sudo dnf install -y git python3 python3-pip python3-virtualenv \
  qemu-kvm libvirt-daemon-driver-qemu \
  gh osc make jq

# Debian / Ubuntu (note: osc may need OBS repos enabled)
sudo apt install -y git python3 python3-pip python3-venv \
  qemu-system-x86 qemu-kvm libvirt-daemon-system \
  gh make jq
# Then follow https://en.opensuse.org/openSUSE:OSC for osc
```

You'll also need to be in the `libvirt` (or `kvm`) group:

```bash
sudo usermod -aG libvirt $USER
# log out and back in
```

## 2. GitHub setup

Required:

- A GitHub account (`${github_user}` (from setup.sh detection)).
- An SSH key registered with GitHub. Test: `ssh -T git@github.com`.
- A fork on **each role you want the agent to maintain**. The agent's first run will list any missing forks in `state/PENDING_REVIEW.md` so you can create them on demand.

Authenticate the `gh` CLI:

```bash
gh auth login --git-protocol ssh --hostname github.com
```

Choose token or browser flow — either way, you type/paste the credential, not the agent.

Verify:

```bash
gh auth status
gh api user --jq '.login'
```

Token scopes needed: `repo`, `read:org`. The agent will warn if `delete_repo` is present (overscoped).

## 3. OBS setup

Required:

- An account on https://build.opensuse.org (`${obs_user}` (from setup.sh detection)).
- Membership in `${obs_user_root}` (you have this automatically).
- Read access to `devel:sap:ansible` (request membership if you want to maintain that project's packages directly; the agent works from `${obs_branch_project}` either way).

Authenticate `osc`:

```bash
osc -A https://api.opensuse.org whois
# First run prompts for password and saves to ~/.config/osc/oscrc
```

Verify:

```bash
osc whois
osc ls home:$(osc whois | awk '{print $1}')
```

## 4. QEMU images

The agent runs tox-LSR tests against SUSE/openSUSE images at `./var/iso/` inside this workspace (the `paths.iso_dir` key in `state/config.json`; override with an absolute path like `/mnt/big/iso` if you keep images elsewhere). The agent detects images by **glob pattern**, so variants are fine (e.g., `-20G`, `-GM`, `Full-VM` vs `Minimal-VM`).

**Per-target glob patterns:**

| Target | Glob | Source |
|---|---|---|
| `sle-16` | `SLES-16.0-*Minimal-VM*.x86_64*.qcow2` | SUSE Customer Center (license required) |
| `leap-16.0` | `Leap-16.0-Minimal-VM*.x86_64*Cloud*.qcow2` | `download.opensuse.org` (free) |
| `sle-15-sp7` | `SLES15-SP7-Minimal-VM*.x86_64*.qcow2` | SUSE Customer Center |
| `leap-15.6` | `openSUSE-Leap-15.6*.x86_64*.qcow2` or `Leap-15.6-Minimal-VM*.x86_64*.qcow2` | `download.opensuse.org` |

**SLE 16 → Leap 16 fallback**: if you don't have the SLE 16 image (it's license-restricted, not freely redistributable), the agent transparently runs `sle-16`-target tests against Leap 16. ansible-core version is the same (2.20); `os_family` is `Suse` for both. For LSR compatibility testing this is close enough — package vendor strings differ but the load-bearing pieces (Python version, NetworkManager, sudo path, syslog setup) are identical.

**Downloading Leap 16:** `make install-deps` auto-fetches it into `./var/iso/` if missing (~330 MB; 7-day re-download guard prevents nightly cron from re-pulling it). `./bin/setup.sh` offers to do this interactively too. `bootstrap-runner` does the same autonomously during a scheduled run if the workspace is configured with `state/.bootstrap-state.json::config.auto_download_leap == true` (the default).

To grab it by hand:

```bash
. bin/_lib/paths.sh                            # exposes lsr_path
curl -fL --progress-bar \
  -o "$(lsr_path iso_dir)/Leap-16.0-Minimal-VM.x86_64-Cloud.qcow2" \
  https://download.opensuse.org/distribution/leap/16.0/appliances/Leap-16.0-Minimal-VM.x86_64-Cloud.qcow2
```

**To opt out of auto-download** (e.g., metered connection): edit `state/.bootstrap-state.json` and set `"config": {"auto_download_leap": false}` before the first scheduled run.

**License-restricted images (SLE 15 SP7, SLE 16, SLE 16 Full)**: the agent will never download these. If you have credentials for SUSE Customer Center, download manually and place at `./var/iso/` (or wherever `paths.iso_dir` resolves). The agent's `doctor` command reports which are present and tells you which targets will run.

## 5. Run setup.sh

```bash
cd lsr-maintainer-workspace
./bin/setup.sh
```

This re-runs the verifications above non-interactively, walks you through anything missing, and writes `state/.setup-complete.json` (public info only — login names + timestamps, no credentials).

## 6. Install

```bash
make install
```

Idempotent. Builds the tox-lsr venv, creates required directories, installs the nightly cron entry.

## 7. Verify

```bash
claude -p "/lsr-maintainer doctor"
```

Should return a green/red table covering: tox venv, QEMU images per target, `gh auth`, `osc auth`, cron registered, submodules at expected pins.

## Disk and RAM expectations

- Disk: ~20 GB for QEMU images + ~5 GB for tox venvs and worktrees, **all under `./var/`** inside this workspace. Move the workspace, move the data with it. `rm -rf var/` is a full reset.
- RAM: 4 GB free during tox tests (each QEMU VM uses ~2 GB; tests run one VM at a time per role).
- Network: agent assumes GitHub + OBS reachable; tox tests need DNS for SUSEConnect / package mirrors.

## Where things live

After `make install`:

```
lsr-maintainer-workspace/var/
  iso/             QEMU images (Leap auto-downloaded; SLE manual)
  clones/<role>/   Per-role fork clones (one per managed role)
  worktrees/       Rebase + fix-implementer worktrees
  ansible/         OBS checkout + tox + patches + scripts
  venv/tox-lsr/    Tox-lsr virtualenv
  log/             security.log + nightly run transcripts (jsonl/txt)
  cache/           obs-packages context, misc caches
```

Every one of these paths is a key in `state/config.json::paths`. Override any value (e.g., to point `iso_dir` at `/mnt/big/iso`) and the agent picks it up at next run — see [docs/component-config.md](docs/component-config.md).

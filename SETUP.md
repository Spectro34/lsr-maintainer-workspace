# Setup

One-time prerequisites for a new machine. The interactive `./bin/setup.sh` walks you through these; this doc is the reference.

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

- A GitHub account (`Spectro34` for the canonical setup).
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

- An account on https://build.opensuse.org (`spectro34` for the canonical setup).
- Membership in `home:Spectro34` (you have this automatically).
- Read access to `devel:sap:ansible` (request membership if you want to maintain that project's packages directly; the agent works from `home:Spectro34:branches:devel:sap:ansible` either way).

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

The agent runs tox-LSR tests against SUSE images at `~/iso/`. Download these manually (the agent will not download GB-scale ISOs autonomously):

| Image | Where to get it |
|---|---|
| `SLES-16.0-Minimal-VM.x86_64-Cloud-GM.qcow2` | SUSE Customer Center |
| `SLES15-SP7-Minimal-VM.x86_64-Cloud-GM.qcow2` | SUSE Customer Center |
| `openSUSE-Leap-16.0-Minimal-VM.x86_64-Cloud.qcow2` | https://get.opensuse.org/ |
| `openSUSE-Leap-15.6-Minimal-VM.x86_64-Cloud.qcow2` | https://get.opensuse.org/ |

Place them at `~/iso/`. The agent's `doctor` command will report which are present.

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

- Disk: ~20 GB for QEMU images + ~5 GB for tox venvs and worktrees.
- RAM: 4 GB free during tox tests (each QEMU VM uses ~2 GB; tests run one VM at a time per role).
- Network: agent assumes GitHub + OBS reachable; tox tests need DNS for SUSEConnect / package mirrors.

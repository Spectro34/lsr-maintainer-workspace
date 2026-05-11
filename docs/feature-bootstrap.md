# Feature: Self-bootstrap into a fresh VM

The agent can stand itself up on a previously-untouched machine (or a VM/container provisioned specifically for it). Everything except the system-package install and the user-typed credentials is automated.

## Flow

```
fresh VM, no agent installed yet
   │
   ▼
1. User: git clone --recurse-submodules <workspace> && cd lsr-maintainer-workspace
   │
   ▼
2. User: ./bin/setup.sh    (interactive — user types credentials into gh/osc)
   │
   ▼
3. User: make install
   │
   ├─ install-deps.sh
   │    ├─ creates required dirs
   │    ├─ checks lsr-agent symlink target (or surfaces clone command)
   │    └─ checks tox-lsr venv (or surfaces creation steps)
   │
   └─ install-cron.sh
        └─ adds nightly entry (idempotent)
   │
   ▼
4. User: claude -p "/lsr-maintainer doctor"
   │
   ▼
5. Doctor reports green/red:
   - system_packages       (red → user runs sudo zypper/apt/...)
   - directories           (auto-fixed by install-deps)
   - lsr_agent_symlink     (red → user clones skill-lifecycle-framework)
   - tox_venv              (red → bootstrap-runner creates it on next run)
   - qemu_images           (red → user downloads images per SETUP.md)
   - gh_auth               (red → user re-runs setup.sh)
   - osc_auth              (red → user re-runs setup.sh)
   - cron_registered       (red → user runs make install-cron)
   │
   ▼
6. Each scheduled run starts with a doctor pre-flight; if posture has drifted
   (token revoked, oscrc gone), the run aborts with a PENDING entry pointing
   back to ./bin/setup.sh. State is not touched.
```

## Host fingerprint

The agent records `sha256(hostname, primary-mac, /etc/os-release ID+VERSION_ID)` in `state/.bootstrap-state.json`. When fingerprint mismatch is detected (you cloned the workspace to a new machine), bootstrap-runner re-runs all checks from scratch.

State (`state/.lsr-maintainer-state.json`) is portable across hosts because it's keyed on logical things (PR cursors, role names, spec versions). Bootstrap state is host-specific.

## What bootstrap-runner does NOT do

- Run `sudo` — blocked. It surfaces the install command for you.
- Download QEMU images (multi-GB, license-restricted). Surfaces URLs.
- Modify auth state. Only reads `gh auth status` / `osc whois` as a check.
- Create GitHub repos or OBS projects.

## Testing the bootstrap path

```bash
# Spin up a clean container:
podman run --rm -it -v $(pwd):/repo:Z opensuse/tumbleweed bash
cd /repo
zypper install -y git python3 gh osc make jq
./bin/setup.sh   # interactive
make install
claude -p "/lsr-maintainer doctor"
```

The doctor output is the contract: it tells you exactly what's missing and the command to fix each item.

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
   └─ install-deps.sh   (host prep only — NO cron by default)
        ├─ creates required dirs
        ├─ verifies inlined `.claude/skills/lsr-agent/SKILL.md` is present
        └─ checks tox-lsr venv (or surfaces creation steps)
   │
   ▼
4. User: bash bin/doctor.sh   (static check, <1s, no claude -p)
   │
   ▼
5. Doctor reports green/red:
   - state/config.json     (red → user re-runs setup.sh)
   - gh_auth               (red → user re-runs setup.sh)
   - osc_auth              (red → user re-runs setup.sh)
   - tox_venv              (yellow → bootstrap-runner creates it on next run)
   - lsr-agent skill       (red → workspace clone is incomplete; re-clone with --recurse-submodules)
   - qemu_images           (yellow → user downloads images per SETUP.md)
   - cron_registered       (yellow if absent — that's expected when running manual-only)
   - hook test harness     (red → fix hooks; never run the agent with broken hooks)
   │
   ▼
6. User runs the agent on demand:
       make run            # live narration in terminal
       make pending        # read state/PENDING_REVIEW.md afterwards

7. (Optional) User opts in to scheduled runs later:
       make install-cron   # nightly at 03:07 local
       make uninstall-cron # turn it off
       touch state/.halt   # pause without removing cron (e.g., vacation)

Each run (manual OR scheduled) starts with a doctor pre-flight inside
bin/lsr-maintainer-run.sh; if posture has drifted (token revoked, oscrc
gone), the run aborts with a PENDING entry pointing back to ./bin/setup.sh.
State is not touched.
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
./bin/setup.sh         # interactive
make install           # host prep only — no cron
bash bin/doctor.sh     # green/yellow/red posture check
```

The doctor output is the contract: it tells you exactly what's missing and the command to fix each item. Cron is intentionally absent from the install — opt in via `make install-cron` when you're ready for scheduled runs.

# bootstrap-runner

Idempotent host preparation. Safe to run repeatedly. Designed for `/lsr-maintainer bootstrap` and as a pre-flight inside `/lsr-maintainer run`.

## Inputs

- None. Reads `state/.bootstrap-state.json` (creates if missing) and `/etc/os-release`.

## Workflow

1. **Detect host** — read `/etc/os-release` for `ID` and `VERSION_ID`. Compute `host_fingerprint` via `python3 -m orchestrator.host_lock --compute` (sha256 of `(hostname, primary-mac, ID, VERSION_ID)`). The Python module is the single source of truth so `config.security.enforce_host_lock` (checked in workflow-run.md Phase 0a) sees the same formula.
2. **System packages** — check for presence of `git`, `python3`, `gh`, `osc`, `make`, `jq`, `qemu-system-x86`. If any missing, emit a PENDING entry with the exact install command for the detected OS. Do NOT run sudo/zypper/apt/dnf — those are blocked.
3. **Directories** — `bin/install-deps.sh` already handles this on first install; replay the logic here for idempotency (mkdir -p ...).
4. **lsr-agent skill present** — verify `.claude/skills/lsr-agent/SKILL.md` exists. The skill is inlined in this workspace; on a fresh clone it's already there. If missing, surface PENDING "workspace clone is incomplete — run `git submodule update --init --recursive` and re-bootstrap".
5. **tox-lsr venv** — resolve `paths.tox_venv` via `orchestrator.config.get_path(cfg, "tox_venv")` (default `<workspace>/var/venv/tox-lsr`). Check `<tox_venv>/bin/activate` exists. If not:
   - Create venv: `python3 -m venv <tox_venv>`
   - Install: `<tox_venv>/bin/pip install tox-lsr` (pin to the version in `references/tox-lsr-pin.txt` if present).
   - Run `<paths.host_scripts>/patch-tox-lsr.sh` (clone the host-scripts first into `<paths.host_scripts>` if missing).
6. **QEMU images** — detect by glob pattern (target → glob, see `tox-test-runner.md`):
   - `sle-16`     → `SLES-16.0-*Minimal-VM*.x86_64*.qcow2`
   - `leap-16.0`  → `Leap-16.0-Minimal-VM*.x86_64*Cloud*.qcow2`
   - `sle-15-sp7` → `SLES15-SP7-Minimal-VM*.x86_64*.qcow2`
   - `leap-15.6`  → `openSUSE-Leap-15.6*.x86_64*.qcow2` or `Leap-15.6-Minimal-VM*.x86_64*.qcow2`

   **Download policy** (per image source):
   - SLES-* images: license-restricted (SUSE Customer Center). **Never download.** Surface PENDING with the SCC URL.
   - Leap-* images: openSUSE, freely redistributable from `download.opensuse.org`. **OK to download** if missing AND the user has not opted out (check `state/.bootstrap-state.json::config.auto_download_leap == false` to opt out; default is true).

   Canonical Leap 16 URL:
   `https://download.opensuse.org/distribution/leap/16.0/appliances/Leap-16.0-Minimal-VM.x86_64-Cloud.qcow2`
   (~330 MB; uses `curl -fL --progress-bar` so the cron log shows progress.)

   **SLE 16 → Leap 16 fallback**: if `sle-16` glob has no match but `leap-16.0` does, mark `components_ready.qemu_images.sle-16` as `"fallback_to_leap-16.0"` (truthy). The `tox-test-runner` honors this fallback per `tox-test-runner.md` §2.
7. **Auth** — run `gh auth status` and `osc whois` non-interactively. Token/password not printed. If either fails, emit PENDING "Run ./bin/setup.sh to re-auth."
8. **Cron** — check if the cron entry is registered (`crontab -l | grep -q "# lsr-maintainer-workspace"`). If not, emit PENDING "Run `make install-cron` to schedule nightly runs."
9. **Write bootstrap state** — `state/.bootstrap-state.json` with `components_ready` map.

## Output

```json
{
  "host_fingerprint": "sha256:abcd...",
  "components_ready": {
    "system_packages": true,
    "directories": true,
    "lsr_agent_symlink": true,
    "tox_venv": true,
    "qemu_images": {"sle-16": true, "leap-16.0": true, "sle-15-sp7": false, "leap-15.6": true},
    "gh_auth": true,
    "osc_auth": true,
    "cron_registered": true
  },
  "pending_actions": [
    "Download SLES15-SP7-Minimal-VM image to <paths.iso_dir> (see SETUP.md §4 for source)"
  ]
}
```

## Constraints

- **Never run sudo or package managers** (blocked by hooks anyway).
- **Never download license-restricted images** (SLES-*). Always allowed: openSUSE Leap-* from `download.opensuse.org` (free + redistributable).
- **Never modify auth state** — only check it.
- Idempotent: running multiple times produces the same components_ready and pending_actions. A Leap download attempt that fails (network down) does not change state — just emits PENDING.
- Time budget: 60 seconds for the checks; if a Leap image download is needed, that's a separate phase with its own 5-minute budget (Leap 16 Cloud variant is ~330 MB, ~30s on a fast connection).

# bootstrap-runner

Idempotent host preparation. Safe to run repeatedly. Designed for `/lsr-maintainer bootstrap` and as a pre-flight inside `/lsr-maintainer run`.

## Inputs

- None. Reads `state/.bootstrap-state.json` (creates if missing) and `/etc/os-release`.

## Workflow

1. **Detect host** — read `/etc/os-release` for `ID` and `VERSION_ID`. Compute `host_fingerprint` = sha256 of `(hostname, primary-mac, ID, VERSION_ID)`.
2. **System packages** — check for presence of `git`, `python3`, `gh`, `osc`, `make`, `jq`, `qemu-system-x86`. If any missing, emit a PENDING entry with the exact install command for the detected OS. Do NOT run sudo/zypper/apt/dnf — those are blocked.
3. **Directories** — `bin/install-deps.sh` already handles this on first install; replay the logic here for idempotency (mkdir -p ...).
4. **Symlink target check** — `projects/lsr-agent` should resolve. If broken (running on a host without `~/github/rnd/lsr-agent/`), emit PENDING "Clone Spectro34/skill-lifecycle-framework to ~/github/rnd/ for the lsr-agent symlink to resolve."
5. **tox-lsr venv** — check `~/github/ansible/testing/tox-lsr-venv/bin/activate` exists. If not:
   - Create venv: `python3 -m venv ~/github/ansible/testing/tox-lsr-venv`
   - Install: `~/github/ansible/testing/tox-lsr-venv/bin/pip install tox-lsr` (pin to the version in `references/tox-lsr-pin.txt` if present).
   - Run `~/github/ansible/scripts/patch-tox-lsr.sh` (clone the host-scripts first if missing — `git clone <eventual-repo-url> ~/github/ansible/scripts`).
6. **QEMU images** — for each target the agent will test against, check `~/iso/<image>` presence. Never download (multi-GB). Surface missing as PENDING with the source URL.
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
    "Download SLES15-SP7-Minimal-VM image to ~/iso/ (see SETUP.md §4 for source)"
  ]
}
```

## Constraints

- **Never run sudo or package managers** (blocked by hooks anyway).
- **Never download QEMU images** (too large, license-restricted on SLE).
- **Never modify auth state** — only check it.
- Idempotent: running multiple times produces the same components_ready and pending_actions.
- Time budget: 60 seconds.

# Workflow: `/lsr-maintainer bootstrap`

Idempotent host preparation. Safe to run repeatedly. Designed for two contexts:

1. **One-shot setup** — user runs `make install` on a fresh machine, which invokes `bin/install-deps.sh` (which does most of the work) and then this workflow tops it off.
2. **Pre-flight inside `/lsr-maintainer run`** — every scheduled run calls this first as a posture check. Must complete in <60 seconds.

## Outputs

`state/.bootstrap-state.json`:

```json
{
  "version": 1,
  "host_fingerprint": "sha256:abcd...",
  "bootstrapped_at": "2026-05-08T09:00:00+02:00",
  "last_check_at":   "2026-05-12T03:07:05+02:00",
  "config": {
    "auto_download_leap": true
  },
  "components_ready": {
    "system_packages": true,
    "directories": true,
    "lsr_agent_symlink": true,
    "tox_venv": true,
    "qemu_images": {
      "sle-16": true,
      "leap-16.0": true,
      "sle-15-sp7": false,
      "leap-15.6": true
    },
    "gh_auth": true,
    "osc_auth": true,
    "git_user_config": true,
    "cron_registered": true,
    "mcp_config": true
  },
  "pending_actions": [
    "Download SLES15-SP7 image to ~/iso/ (see SETUP.md §4)"
  ]
}
```

## Steps

### 1. Host fingerprint

```python
import hashlib, subprocess
hostname = subprocess.run(["hostname"], capture_output=True, text=True).stdout.strip()
# Primary MAC: first non-loopback iface
mac = subprocess.run(["sh","-c","ip link show | awk '/link\\/ether/ {print $2; exit}'"], capture_output=True, text=True).stdout.strip()
# OS release ID + VERSION_ID
osrel = open("/etc/os-release").read()
def _v(k): return next((line.split("=",1)[1].strip().strip('"') for line in osrel.splitlines() if line.startswith(k+"=")), "")
fingerprint = "sha256:" + hashlib.sha256(f"{hostname}|{mac}|{_v('ID')}|{_v('VERSION_ID')}".encode()).hexdigest()[:16]
```

If fingerprint differs from `state/.bootstrap-state.json::host_fingerprint`, force a fresh bootstrap (treat as new host).

### 2. System packages

Required: `git python3 gh osc make jq curl qemu-system-x86`. For each missing:

```python
distro = _v("ID")
install_cmd = {
  "opensuse-tumbleweed": "sudo zypper install -y",
  "opensuse-leap":       "sudo zypper install -y",
  "sles":                "sudo zypper install -y",
  "fedora":              "sudo dnf install -y",
  "rhel":                "sudo dnf install -y",
  "ubuntu":              "sudo apt install -y",
  "debian":              "sudo apt install -y",
}.get(distro, "<install via your package manager>")
```

Emit PENDING with the exact command for the user to run. **Never run sudo** (blocked by hooks anyway).

### 3. Directories

```python
for d in [
  "~/.cache/lsr-maintainer",
  "~/github/ansible/upstream",
  "~/github/ansible/testing",
  "~/github/ansible/scripts",
  "~/github/ansible/patches/lsr",
  "~/github/linux-system-roles",
  "~/github/.lsr-maintainer-worktrees",
  "<workspace>/state/cache",
  "<workspace>/state/worktrees",
  "~/.claude/obs-packages/context",   # for obs-package-skill (issue #9)
]:
  os.makedirs(os.path.expanduser(d), exist_ok=True)
```

### 4. lsr-agent symlink

```bash
if [ -L projects/lsr-agent ]; then
  if [ -d projects/lsr-agent/.claude ]; then
    components_ready.lsr_agent_symlink = true
  else
    pending_actions.append("Clone the upstream skill-lifecycle-framework repo (whichever fork you use) to ~/github/rnd/ so projects/lsr-agent symlink resolves.")
  fi
fi
```

### 5. tox-lsr venv

```python
tox_venv = os.path.expanduser("~/github/ansible/testing/tox-lsr-venv")
if not os.path.exists(f"{tox_venv}/bin/activate"):
  # Create
  subprocess.run(["python3", "-m", "venv", tox_venv], check=True)
  # Install pinned tox-lsr (read pin from references/tox-lsr-pin.txt)
  pin = open(".claude/skills/lsr-maintainer/references/tox-lsr-pin.txt").read().strip()
  subprocess.run([f"{tox_venv}/bin/pip", "install", pin], check=True)
  # Apply SUSE patches
  subprocess.run(["bash", os.path.expanduser("~/github/ansible/scripts/patch-tox-lsr.sh"), tox_venv])
```

If `~/github/ansible/scripts/patch-tox-lsr.sh` is missing, surface PENDING (the host-scripts repo carve-out from `projects/ansible-host-scripts/` hasn't happened yet).

### 6. QEMU images

For each target, check the glob in `~/iso/` (patterns from `tox-test-runner.md`).

Special case Leap 16 — auto-download if missing:

```bash
LEAP_URL="https://download.opensuse.org/distribution/leap/16.0/appliances/Leap-16.0-Minimal-VM.x86_64-Cloud.qcow2"
OUT="$HOME/iso/Leap-16.0-Minimal-VM.x86_64-Cloud.qcow2"

# Skip if downloaded recently (< 7 days) — prevents re-download nightly
if [ -f "$OUT" ] && [ "$(find "$OUT" -mtime -7)" ]; then
  skip
elif config.auto_download_leap == true; then
  curl -fL --no-progress-meter --silent --show-error -o "$OUT" "$LEAP_URL"
fi
```

License-restricted images (SLES-*) are never downloaded. Surface PENDING with SCC URL.

SLE 16 → Leap 16 fallback: if `sle-16` glob has no match but `leap-16.0` does, set `components_ready.qemu_images.sle-16 = "fallback_to_leap-16.0"`. `tox-test-runner` honors this per its workflow doc.

### 7. Auth checks

```bash
gh auth status >/dev/null 2>&1 && components_ready.gh_auth = true \
  || pending_actions.append("Run ./bin/setup.sh to re-auth gh")
osc whois >/dev/null 2>&1 && components_ready.osc_auth = true \
  || pending_actions.append("Run ./bin/setup.sh to re-auth osc")
```

Don't print tokens; don't read auth files.

### 8. Git user config

```bash
test -n "$(git config --global user.email)" \
  && test -n "$(git config --global user.name)" \
  && components_ready.git_user_config = true \
  || pending_actions.append("Set git author: git config --global user.email '…'; user.name '…'")
```

Bug-fix commits need this (issue #11).

### 9. Cron registered

```bash
crontab -l 2>/dev/null | grep -q '# lsr-maintainer-workspace' \
  && components_ready.cron_registered = true \
  || pending_actions.append("Run make install-cron")
```

### 10. MCP config

Workspace's `.mcp.json` should exist and point at `projects/osc-mcp` so the osc MCP server runs from the pinned commit (issue #9).

```bash
test -f .mcp.json \
  && components_ready.mcp_config = true \
  || pending_actions.append("Generate .mcp.json pointing at projects/osc-mcp")
```

### 11. Write state

Atomic write to `state/.bootstrap-state.json` via the same pattern as `state_schema.save_state`.

## Constraints

- **Never run sudo or package managers** (blocked by hooks; surface install commands instead).
- **Never download license-restricted images** (SLES-*). Free + redistributable images (Leap-*) OK from `download.opensuse.org`.
- **Never modify auth state** — only check it.
- Time budget: 60 seconds for checks. Image download is a separate phase with its own 5-minute budget.
- Idempotent. Running multiple times produces the same `components_ready` and `pending_actions`.

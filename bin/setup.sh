#!/usr/bin/env bash
# bin/setup.sh — one-time interactive auth setup.
#
# The user runs this. The agent does NOT run this. No credential ever passes
# through the agent's context — the user types them directly into gh/osc.

set -u

WORKSPACE="$(cd "$(dirname "$0")/.." && pwd)"
cd "$WORKSPACE" || exit 1

bold() { printf '\033[1m%s\033[0m\n' "$*"; }
warn() { printf '\033[33mWARN\033[0m %s\n' "$*"; }
err()  { printf '\033[31mERR \033[0m %s\n' "$*"; }
ok()   { printf '\033[32mOK  \033[0m %s\n' "$*"; }

bold "=== lsr-maintainer setup ==="
echo ""
echo "This script walks you through one-time host setup. It will NOT see any"
echo "credentials directly. You type them into gh/osc when those tools prompt."
echo ""

# ---------------------------------------------------------------- prereqs
bold "[1/5] Checking required system commands..."
MISSING=()
for cmd in git python3 gh osc make jq; do
  if ! command -v "$cmd" >/dev/null 2>&1; then MISSING+=("$cmd"); fi
done
if (( ${#MISSING[@]} > 0 )); then
  err "Missing: ${MISSING[*]}"
  echo "Install with (openSUSE):"
  echo "  sudo zypper install -y ${MISSING[*]}"
  echo "or see SETUP.md for other distros. Re-run this script after."
  exit 1
fi
ok "All required commands present."

# ---------------------------------------------------------------- gh
bold "[2/5] GitHub auth"
if gh auth status >/dev/null 2>&1; then
  GH_USER="$(gh api user --jq .login 2>/dev/null || echo unknown)"
  ok "gh already authenticated as $GH_USER"
else
  echo "Not authenticated. Running 'gh auth login' — follow the prompts."
  echo "(Use SSH protocol when asked.)"
  read -rp "Press Enter to continue..."
  gh auth login --git-protocol ssh --hostname github.com || { err "gh auth failed"; exit 1; }
  GH_USER="$(gh api user --jq .login 2>/dev/null || echo unknown)"
  ok "gh authenticated as $GH_USER"
fi

# Check SSH to github.
if ssh -o BatchMode=yes -o ConnectTimeout=5 -T git@github.com 2>&1 | grep -q "successfully authenticated"; then
  ok "SSH to git@github.com works"
else
  warn "SSH to git@github.com not working. Add your SSH key to GitHub before scheduling runs."
  warn "  Test with: ssh -T git@github.com"
fi

# Check token scopes (read-only).
echo ""
echo "Token scopes:"
gh auth status 2>&1 | grep -i "scope" | sed 's/^/  /' || true
echo ""

# ---------------------------------------------------------------- osc
bold "[3/5] OBS (osc) auth"
if osc whois >/dev/null 2>&1; then
  OBS_USER="$(osc whois 2>/dev/null | awk '{print $1}')"
  ok "osc already authenticated as $OBS_USER"
else
  echo "Not authenticated. Running 'osc -A https://api.opensuse.org whois' — enter password when prompted."
  read -rp "Press Enter to continue..."
  if osc -A https://api.opensuse.org whois 2>&1; then
    OBS_USER="$(osc whois 2>/dev/null | awk '{print $1}')"
    ok "osc authenticated as $OBS_USER"
  else
    err "osc auth failed — re-run setup after fixing."
    exit 1
  fi
fi

# ---------------------------------------------------------------- QEMU
bold "[4/5] QEMU images (info-only — agent never downloads these)"
ISO_DIR="${HOME}/iso"
mkdir -p "$ISO_DIR"
declare -a EXPECTED=(
  "SLES-16.0-Minimal-VM.x86_64-Cloud-GM.qcow2"
  "SLES15-SP7-Minimal-VM.x86_64-Cloud-GM.qcow2"
  "openSUSE-Leap-16.0-Minimal-VM.x86_64-Cloud.qcow2"
  "openSUSE-Leap-15.6-Minimal-VM.x86_64-Cloud.qcow2"
)
MISSING_IMG=()
for img in "${EXPECTED[@]}"; do
  if [[ -f "$ISO_DIR/$img" ]]; then ok "  found: $img"
  else MISSING_IMG+=("$img"); warn "  missing: $img"; fi
done
if (( ${#MISSING_IMG[@]} > 0 )); then
  warn "Some QEMU images are missing. doctor will report which tests cannot run."
  warn "See SETUP.md §4 for download sources."
fi

# ---------------------------------------------------------------- record state
bold "[5/5] Recording setup state (public info only — no secrets)"
mkdir -p "$WORKSPACE/state"
python3 - <<PY
import json, os, datetime
state = {
    "version": 1,
    "completed_at": datetime.datetime.now(datetime.UTC).isoformat(),
    "github_user": "${GH_USER}",
    "obs_user": "${OBS_USER}",
    "missing_qemu_images": ${#MISSING_IMG[@]},
    "host": os.uname().nodename,
}
with open("$WORKSPACE/state/.setup-complete.json", "w") as f:
    json.dump(state, f, indent=2)
PY
ok "Wrote state/.setup-complete.json"

echo ""
bold "Setup complete. Next steps:"
echo "  make install            # bootstrap host + install cron"
echo "  make doctor             # verify posture"
echo "  make dry-run            # preview what tonight would do"

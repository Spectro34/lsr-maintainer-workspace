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
bold "[4/5] QEMU images"
ISO_DIR="${HOME}/iso"
mkdir -p "$ISO_DIR"

# Image detection: match by glob pattern, not exact filename. SUSE/openSUSE
# ship variants (Cloud, Cloud-20G, kvm-and-xen, Full-VM, etc.) — we accept
# any qcow2 matching the target's canonical pattern.
#
# Target → glob pattern (first match wins; agent uses whichever is present)
declare -A TARGET_GLOBS=(
  [sle-16]="SLES-16.0-*Minimal-VM*.x86_64*.qcow2"
  [leap-16.0]="Leap-16.0-Minimal-VM*.x86_64*Cloud*.qcow2"
  [sle-15-sp7]="SLES15-SP7-Minimal-VM*.x86_64*.qcow2"
  [leap-15.6]="openSUSE-Leap-15.6*.x86_64*.qcow2 Leap-15.6-Minimal-VM*.x86_64*.qcow2"
)
declare -A TARGET_FOUND
MISSING_IMG=()
for target in "${!TARGET_GLOBS[@]}"; do
  match=""
  for pattern in ${TARGET_GLOBS[$target]}; do
    for f in $ISO_DIR/$pattern; do
      [[ -f "$f" ]] && { match="$(basename "$f")"; break 2; }
    done
  done
  if [[ -n "$match" ]]; then
    TARGET_FOUND[$target]="$match"
    ok "  $target → $match"
  else
    MISSING_IMG+=("$target")
    warn "  $target → (missing)"
  fi
done

# SLE 16 → Leap 16 fallback policy.
# SLE 16 image is license-restricted (SUSE Customer Center); agent cannot
# download. Leap 16 is openSUSE and freely downloadable. If SLE 16 is
# missing AND Leap 16 is present, tests claiming "sle16" target will run
# against Leap 16 (same ansible-core 2.20, same default package set, close
# enough for compatibility testing of LSR roles).
if [[ -z "${TARGET_FOUND[sle-16]:-}" ]] && [[ -n "${TARGET_FOUND[leap-16.0]:-}" ]]; then
  warn "  SLE 16 image missing — sle16-target tests will fall back to Leap 16.0 (${TARGET_FOUND[leap-16.0]})"
fi

# Offer to download Leap 16 (openSUSE, freely redistributable) if missing.
if [[ -z "${TARGET_FOUND[leap-16.0]:-}" ]]; then
  echo ""
  warn "Leap 16.0 image is missing. This is the canonical fallback for sle16 testing."
  read -rp "Download from download.opensuse.org now? (~330 MB) [y/N] " resp
  if [[ "$resp" =~ ^[Yy] ]]; then
    URL="https://download.opensuse.org/distribution/leap/16.0/appliances/Leap-16.0-Minimal-VM.x86_64-Cloud.qcow2"
    OUT="$ISO_DIR/Leap-16.0-Minimal-VM.x86_64-Cloud.qcow2"
    echo "Downloading: $URL"
    if command -v curl >/dev/null; then
      curl -fL --progress-bar -o "$OUT" "$URL" && ok "downloaded: $OUT" && TARGET_FOUND[leap-16.0]="$(basename "$OUT")"
    elif command -v wget >/dev/null; then
      wget -O "$OUT" "$URL" && ok "downloaded: $OUT" && TARGET_FOUND[leap-16.0]="$(basename "$OUT")"
    else
      err "Neither curl nor wget available."
    fi
  else
    warn "Skipping. Download later: curl -fL -o $ISO_DIR/Leap-16.0-Minimal-VM.x86_64-Cloud.qcow2 \\"
    warn "  https://download.opensuse.org/distribution/leap/16.0/appliances/Leap-16.0-Minimal-VM.x86_64-Cloud.qcow2"
  fi
fi

if (( ${#MISSING_IMG[@]} > 0 )); then
  echo ""
  warn "Targets missing images: ${MISSING_IMG[*]}"
  warn "  - SLE 15 SP7, SLE 16: SUSE Customer Center (license required)"
  warn "  - Leap 15.6, Leap 16.0: https://get.opensuse.org/ (free)"
fi

# ---------------------------------------------------------------- record state
bold "[5/5] Writing workspace config from detected identity"
mkdir -p "$WORKSPACE/state"

# Generate state/config.json — the single source of truth the hooks and
# sub-agents read. This makes the workspace reusable across GH/OBS accounts:
# every host that runs ./bin/setup.sh gets its own config and operates under
# its own identity.
GH_USER_JSON="$GH_USER"
OBS_USER_JSON="$OBS_USER"
GIT_EMAIL="$(git config --global user.email 2>/dev/null || echo '')"
GIT_NAME="$(git config --global user.name 2>/dev/null || echo '')"

cd "$WORKSPACE"
python3 - <<PY
import json, os, sys
sys.path.insert(0, "$WORKSPACE")
from orchestrator.config import default_config, load_config, init_from_identity, save_config

# Preserve any existing user overrides (e.g. source_project changed manually).
existing = load_config("$WORKSPACE/state/config.json")
detected = {
    "github_user": "$GH_USER_JSON",
    "obs_user":    "$OBS_USER_JSON",
    "git_email":   "$GIT_EMAIL",
    "git_name":    "$GIT_NAME",
}
cfg = init_from_identity(detected, existing)
save_config("$WORKSPACE/state/config.json", cfg)
print(f"github.user = {cfg['github']['user']}")
print(f"obs.user = {cfg['obs']['user']}")
print(f"obs.personal_project_root = {cfg['obs']['personal_project_root']}")
PY

# Legacy setup-complete marker — kept for backwards compat with anything
# that reads it.
python3 - <<PY
import json, os, datetime
state = {
    "version": 1,
    "completed_at": datetime.datetime.now(datetime.UTC).isoformat(),
    "github_user": "$GH_USER_JSON",
    "obs_user": "$OBS_USER_JSON",
    "missing_qemu_images": ${#MISSING_IMG[@]},
    "host": os.uname().nodename,
}
with open("$WORKSPACE/state/.setup-complete.json", "w") as f:
    json.dump(state, f, indent=2)
PY
ok "Wrote state/config.json and state/.setup-complete.json"

# Verify git author is set; bug-fix-implementer needs it.
if [[ -z "$GIT_EMAIL" ]] || [[ -z "$GIT_NAME" ]]; then
  warn "git user.email / user.name not set globally."
  warn "Run: git config --global user.email 'you@example.com'"
  warn "     git config --global user.name 'Your Name'"
  warn "Without these, bug-fix-implementer commits will be rejected by GitHub."
fi

echo ""
bold "Setup complete. Next steps:"
echo "  make install            # bootstrap host + install cron"
echo "  make doctor             # verify posture"
echo "  make dry-run            # preview what tonight would do"

#!/usr/bin/env bash
# bin/setup.sh — one-time interactive auth setup.
#
# The user runs this. The agent does NOT run this. No credential ever passes
# through the agent's context — the user types them directly into gh/osc.

set -u

WORKSPACE="$(cd "$(dirname "$0")/.." && pwd)"
cd "$WORKSPACE" || exit 1

# shellcheck source=_lib/paths.sh
source "$WORKSPACE/bin/_lib/paths.sh"

bold() { printf '\033[1m%s\033[0m\n' "$*"; }
warn() { printf '\033[33mWARN\033[0m %s\n' "$*"; }
err()  { printf '\033[31mERR \033[0m %s\n' "$*"; }
ok()   { printf '\033[32mOK  \033[0m %s\n' "$*"; }

# Migration advisory: detect pre-self-containment installs and tell the
# operator how to reuse existing clones/ISOs without re-downloading.
if [[ -d "$HOME/github/linux-system-roles" || -d "$HOME/iso" || -d "$HOME/github/ansible" ]] \
   && [[ ! -e "$WORKSPACE/var" ]]; then
  warn "Detected pre-self-containment layout at \$HOME/github/{ansible,linux-system-roles} or \$HOME/iso."
  warn "The new layout uses \$WORKSPACE/var/{ansible,clones,iso}. To reuse existing data without re-downloading:"
  warn "  mkdir -p '$WORKSPACE/var'"
  [[ -d "$HOME/iso" ]] && \
    warn "  ln -s '$HOME/iso' '$WORKSPACE/var/iso'"
  [[ -d "$HOME/github/linux-system-roles" ]] && \
    warn "  ln -s '$HOME/github/linux-system-roles' '$WORKSPACE/var/clones'"
  [[ -d "$HOME/github/ansible" ]] && \
    warn "  ln -s '$HOME/github/ansible' '$WORKSPACE/var/ansible'"
  warn "Or skip and let 'make install' create fresh dirs under \$WORKSPACE/var/."
  echo ""
fi

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
  GH_USER="$(gh api user --jq .login 2>/dev/null)"
if [[ -z "$GH_USER" ]]; then err "gh api user returned empty — auth not working"; exit 1; fi
  ok "gh already authenticated as $GH_USER"
else
  echo "Not authenticated. Running 'gh auth login' — follow the prompts."
  echo "(Use SSH protocol when asked.)"
  read -rp "Press Enter to continue..."
  gh auth login --git-protocol ssh --hostname github.com || { err "gh auth failed"; exit 1; }
  GH_USER="$(gh api user --jq .login 2>/dev/null)"
if [[ -z "$GH_USER" ]]; then err "gh api user returned empty — auth not working"; exit 1; fi
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
ISO_DIR="$(lsr_path iso_dir)"
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
# Heredoc QUOTED ('PY') — no shell interpolation. Values passed via env vars
# so usernames with any character (dot, dash, all-numeric) are safe.
export LSR_GH_USER="$GH_USER_JSON"
export LSR_OBS_USER="$OBS_USER_JSON"
export LSR_GIT_EMAIL="$GIT_EMAIL"
export LSR_GIT_NAME="$GIT_NAME"
export LSR_WORKSPACE="$WORKSPACE"
export LSR_MISSING_IMG_COUNT="${#MISSING_IMG[@]}"

# Identity-change guard (issue #14 / P-M3): if existing config has a
# different gh/obs user than what we just detected, refuse to silently
# overwrite. Operator must confirm interactively. Under cron (no TTY)
# we fail hard.
existing_gh="$(python3 -c '
import os, sys, json
ws = os.environ["LSR_WORKSPACE"]
sys.path.insert(0, ws)
from orchestrator.config import load_config
print(load_config(os.path.join(ws, "state/config.json"))["github"]["user"])
')"
existing_obs="$(python3 -c '
import os, sys, json
ws = os.environ["LSR_WORKSPACE"]
sys.path.insert(0, ws)
from orchestrator.config import load_config
print(load_config(os.path.join(ws, "state/config.json"))["obs"]["user"])
')"

if [[ -n "$existing_gh" && "$existing_gh" != "$GH_USER_JSON" ]]; then
  warn "Identity migration detected:"
  warn "  state/config.json has github.user='$existing_gh'"
  warn "  but gh api user returned '$GH_USER_JSON'"
  if [[ -t 0 ]]; then
    read -rp "Rewrite identity? [y/N] " resp
    [[ "$resp" =~ ^[Yy] ]] || { err "aborted by user"; exit 1; }
    # Clear existing.github.user via python so init_from_identity fills new.
    python3 - <<'CLEAR'
import os, sys, json
ws = os.environ["LSR_WORKSPACE"]
sys.path.insert(0, ws)
from orchestrator.config import load_config, save_config
cfg = load_config(os.path.join(ws, "state/config.json"))
cfg["github"]["user"] = ""
save_config(os.path.join(ws, "state/config.json"), cfg)
CLEAR
  else
    err "Identity change requires interactive confirmation; running under cron/no-TTY. Aborting."
    exit 1
  fi
fi

if [[ -n "$existing_obs" && "$existing_obs" != "$OBS_USER_JSON" ]]; then
  warn "OBS identity migration: state has '$existing_obs', osc whois returned '$OBS_USER_JSON'"
  if [[ -t 0 ]]; then
    read -rp "Rewrite OBS identity? [y/N] " resp
    [[ "$resp" =~ ^[Yy] ]] || { err "aborted by user"; exit 1; }
    python3 - <<'CLEAR'
import os, sys, json
ws = os.environ["LSR_WORKSPACE"]
sys.path.insert(0, ws)
from orchestrator.config import load_config, save_config
cfg = load_config(os.path.join(ws, "state/config.json"))
cfg["obs"]["user"] = ""
cfg["obs"]["personal_project_root"] = ""
save_config(os.path.join(ws, "state/config.json"), cfg)
CLEAR
  else
    err "OBS identity change requires interactive confirmation. Aborting."
    exit 1
  fi
fi

python3 - <<'PY'
import json, os, sys
ws = os.environ["LSR_WORKSPACE"]
sys.path.insert(0, ws)
from orchestrator.config import load_config, init_from_identity, save_config

# init_from_identity preserves existing user overrides (e.g. a manually-set
# source_project). See orchestrator/config.py for the merge policy.
existing = load_config(os.path.join(ws, "state/config.json"))
detected = {
    "github_user": os.environ.get("LSR_GH_USER", ""),
    "obs_user":    os.environ.get("LSR_OBS_USER", ""),
    "git_email":   os.environ.get("LSR_GIT_EMAIL", ""),
    "git_name":    os.environ.get("LSR_GIT_NAME", ""),
}
cfg = init_from_identity(detected, existing)
save_config(os.path.join(ws, "state/config.json"), cfg)
print(f"github.user = {cfg['github']['user']}")
print(f"obs.user = {cfg['obs']['user']}")
print(f"obs.personal_project_root = {cfg['obs']['personal_project_root']}")
PY

# Legacy setup-complete marker — kept for back-compat.
python3 - <<'PY'
import json, os, datetime
ws = os.environ["LSR_WORKSPACE"]
state = {
    "version": 1,
    "completed_at": datetime.datetime.now(datetime.UTC).isoformat(),
    "github_user": os.environ.get("LSR_GH_USER", ""),
    "obs_user":    os.environ.get("LSR_OBS_USER", ""),
    "missing_qemu_images": int(os.environ.get("LSR_MISSING_IMG_COUNT", "0")),
    "host": os.uname().nodename,
}
with open(os.path.join(ws, "state/.setup-complete.json"), "w") as f:
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

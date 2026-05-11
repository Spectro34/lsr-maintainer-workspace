#!/usr/bin/env bash
# bin/install-deps.sh — idempotent host preparation.
#
# Creates required directories, sets up tox-lsr venv, initializes submodules.
# Does NOT install system packages (those need sudo and are surfaced to the
# user via PENDING_REVIEW.md).

set -u

WORKSPACE="$(cd "$(dirname "$0")/.." && pwd)"
cd "$WORKSPACE" || exit 1

ok()   { printf '\033[32mOK  \033[0m %s\n' "$*"; }
warn() { printf '\033[33mWARN\033[0m %s\n' "$*"; }
err()  { printf '\033[31mERR \033[0m %s\n' "$*"; }

# --- 1. dirs ---
DIRS=(
  "$HOME/.cache/lsr-maintainer"
  "$HOME/github/ansible/upstream"
  "$HOME/github/ansible/testing"
  "$HOME/github/ansible/scripts"
  "$HOME/github/ansible/patches/lsr"
  "$HOME/github/linux-system-roles"
  "$HOME/github/.lsr-maintainer-worktrees"
  "$WORKSPACE/state/cache"
  "$WORKSPACE/state/worktrees"
)
for d in "${DIRS[@]}"; do
  if [[ ! -d "$d" ]]; then mkdir -p "$d" && ok "created: $d"
  else ok "exists:  $d"; fi
done

# --- 2. submodules ---
if [[ -f .gitmodules ]] && [[ -d .git ]]; then
  if git submodule status 2>/dev/null | grep -q '^-'; then
    echo "Initializing submodules..."
    git submodule update --init --recursive && ok "submodules initialized"
  else
    ok "submodules already initialized"
  fi
fi

# --- 3. lsr-agent symlink target check ---
if [[ -L projects/lsr-agent ]]; then
  if [[ -d projects/lsr-agent/.claude/skills/lsr-agent ]]; then
    ok "lsr-agent symlink resolves"
  else
    warn "projects/lsr-agent symlink points at missing target — see projects/README.md"
  fi
fi

# --- 4. tox-lsr venv (best-effort) ---
TOX_VENV="$HOME/github/ansible/testing/tox-lsr-venv"
if [[ -d "$TOX_VENV/bin" ]]; then
  ok "tox-lsr venv exists at $TOX_VENV"
else
  warn "tox-lsr venv missing — bootstrap-runner agent will set it up on next run."
fi

# --- 4b. Leap 16 image (auto-download from download.opensuse.org if missing) ---
ISO_DIR="$HOME/iso"
mkdir -p "$ISO_DIR"

has_image_for() {
  local pattern="$1"
  for f in $ISO_DIR/$pattern; do
    [[ -f "$f" ]] && return 0
  done
  return 1
}

if has_image_for "Leap-16.0-Minimal-VM*.x86_64*Cloud*.qcow2"; then
  ok "Leap 16.0 image present"
else
  URL="https://download.opensuse.org/distribution/leap/16.0/appliances/Leap-16.0-Minimal-VM.x86_64-Cloud.qcow2"
  OUT="$ISO_DIR/Leap-16.0-Minimal-VM.x86_64-Cloud.qcow2"
  if [[ "${LSR_NO_AUTO_DOWNLOAD:-0}" == "1" ]]; then
    warn "Leap 16.0 image missing; LSR_NO_AUTO_DOWNLOAD=1 set — skipping."
  elif command -v curl >/dev/null 2>&1; then
    warn "Leap 16.0 image missing — downloading from openSUSE (~330 MB)..."
    if curl -fL --progress-bar -o "$OUT" "$URL"; then
      ok "downloaded: $(basename "$OUT")"
    else
      warn "Download failed — agent will retry next run."
      rm -f "$OUT" 2>/dev/null
    fi
  else
    warn "curl unavailable; install curl to enable auto-download of Leap 16."
  fi
fi

# Report SLE 16 fallback policy
if ! has_image_for "SLES-16.0-*Minimal-VM*.x86_64*.qcow2"; then
  if has_image_for "Leap-16.0-Minimal-VM*.x86_64*Cloud*.qcow2"; then
    ok "SLE 16 image absent — sle16-target tests will use Leap 16 fallback"
  else
    warn "SLE 16 image absent AND Leap 16 fallback unavailable — sle16-target tests cannot run"
  fi
fi

# --- 5. .gitignore for workspace's own ignored-state ---
if ! grep -q '^state/' .gitignore 2>/dev/null; then
  warn ".gitignore should ignore state/* — please verify."
fi

echo ""
ok "install-deps complete. Run 'make install-cron' to schedule nightly runs."

#!/usr/bin/env bash
# bin/install-deps.sh — idempotent host preparation.
#
# Creates required directories, sets up tox-lsr venv, initializes submodules.
# Does NOT install system packages (those need sudo and are surfaced to the
# user via PENDING_REVIEW.md).

set -u

WORKSPACE="$(cd "$(dirname "$0")/.." && pwd)"
cd "$WORKSPACE" || exit 1

# shellcheck source=_lib/paths.sh
source "$WORKSPACE/bin/_lib/paths.sh"

ok()   { printf '\033[32mOK  \033[0m %s\n' "$*"; }
warn() { printf '\033[33mWARN\033[0m %s\n' "$*"; }
err()  { printf '\033[31mERR \033[0m %s\n' "$*"; }

# --- 1. dirs (all in-workspace via paths.* in state/config.json) ---
ANSIBLE_ROOT="$(lsr_path ansible_root)"
DIRS=(
  "$(lsr_path log_dir)"
  "$(lsr_path cache_dir)/obs-packages/context"
  "$ANSIBLE_ROOT/upstream"
  "$ANSIBLE_ROOT/testing"
  "$(lsr_path host_scripts)"
  "$ANSIBLE_ROOT/patches/lsr"
  "$(lsr_path lsr_clones_root)"
  "$(lsr_path worktrees_root)"
  "$(dirname "$(lsr_path tox_venv)")"
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

# --- 3. lsr-agent skill (now inlined at .claude/skills/lsr-agent/) ---
if [[ -d .claude/skills/lsr-agent ]] && [[ -f .claude/skills/lsr-agent/SKILL.md ]]; then
  ok "lsr-agent skill present (inlined)"
else
  err ".claude/skills/lsr-agent/SKILL.md missing — workspace clone incomplete?"
  err "Expected the skill at .claude/skills/lsr-agent/ after 'git clone'."
  exit 1
fi

# --- 4. tox-lsr venv (created here, deterministically) ---
# Don't defer to bootstrap-runner — without the venv, the regression matrix
# can't run, which means the agent will skip pushing fixes. Better to fail
# loudly here than silently degrade the agent to "advisory only" mode.
TOX_VENV="$(lsr_path tox_venv)"
PIN_FILE="$WORKSPACE/.claude/skills/lsr-maintainer/references/tox-lsr-pin.txt"
PIN_SPEC="$(grep -Ev '^[[:space:]]*(#|$)' "$PIN_FILE" 2>/dev/null | head -1)"
[[ -z "$PIN_SPEC" ]] && PIN_SPEC="tox-lsr"
# Stricter readiness check: the venv counts as ready ONLY if tox-lsr is
# actually importable (a half-built venv with python3 -m venv succeeded but
# pip install failed otherwise looks fine and silently degrades the agent).
venv_has_tox_lsr() {
  [[ -x "$TOX_VENV/bin/python" ]] && "$TOX_VENV/bin/python" -c 'import tox_lsr' 2>/dev/null
}
if venv_has_tox_lsr; then
  ok "tox-lsr venv ready at $TOX_VENV ($("$TOX_VENV/bin/pip" show tox-lsr 2>/dev/null | awk '/^Version:/ {print $2}'))"
else
  if [[ -d "$TOX_VENV/bin" ]]; then
    warn "tox-lsr venv exists at $TOX_VENV but tox-lsr is not installed — installing..."
  else
    warn "tox-lsr venv missing — creating now..."
    mkdir -p "$(dirname "$TOX_VENV")"
    python3 -m venv "$TOX_VENV" 2>/dev/null || true
  fi
  if [[ -x "$TOX_VENV/bin/pip" ]] \
     && "$TOX_VENV/bin/pip" install --quiet --upgrade pip \
     && "$TOX_VENV/bin/pip" install --quiet "$PIN_SPEC"; then
    ok "tox-lsr installed in $TOX_VENV (spec: $PIN_SPEC)"
  else
    warn "tox-lsr install failed — bootstrap-runner will retry on next 'make run'."
    warn "Manual: $TOX_VENV/bin/pip install $PIN_SPEC"
  fi
fi

# --- 4b. Leap 16 image (auto-download from download.opensuse.org if missing) ---
ISO_DIR="$(lsr_path iso_dir)"
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
  # 7-day guard: if a stub file exists touched within 7 days, don't redownload.
  # Prevents nightly cron from re-pulling 330 MB if the file was transiently
  # removed by an admin.
  STUB_MARKER="$ISO_DIR/.leap-16.0-download-attempted"
  if [[ -f "$STUB_MARKER" ]] && [[ -n "$(find "$STUB_MARKER" -mtime -7 2>/dev/null)" ]]; then
    warn "Leap 16.0 image missing but last download attempt was <7 days ago; skipping."
    warn "Force retry: rm $STUB_MARKER"
  elif [[ "${LSR_NO_AUTO_DOWNLOAD:-0}" == "1" ]]; then
    warn "Leap 16.0 image missing; LSR_NO_AUTO_DOWNLOAD=1 set — skipping."
  elif command -v curl >/dev/null 2>&1; then
    warn "Leap 16.0 image missing — downloading from openSUSE (~330 MB)..."
    touch "$STUB_MARKER"
    # --no-progress-meter and --show-error keep the cron log clean
    # (no carriage-return-rich control sequences from --progress-bar).
    if curl -fL --no-progress-meter --show-error -o "$OUT" "$URL"; then
      ok "downloaded: $(basename "$OUT")"
      rm -f "$STUB_MARKER"  # success — clear guard so next legit missing triggers retry
    else
      warn "Download failed — agent will retry after 7 days (or remove $STUB_MARKER)."
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

# --- 4c. SCC register/cleanup playbooks (drop into var/ansible/testing/) ---
# Source-of-truth lives in assets/playbooks/ (tracked). Copy with -n (no-clobber)
# so local edits in var/ansible/testing/ survive re-runs. See
# assets/playbooks/README.md for the vault setup flow.
TESTING_DIR="$ANSIBLE_ROOT/testing"
mkdir -p "$TESTING_DIR"
for pb in register-suseconnect.yml cleanup-suseconnect.yml vault-suseconnect.yml.example; do
  src="$WORKSPACE/assets/playbooks/$pb"
  dst="$TESTING_DIR/$pb"
  if [[ -f "$src" ]]; then
    if [[ -f "$dst" ]]; then
      ok "playbook present (preserving local edits): $dst"
    else
      cp "$src" "$dst" && ok "installed playbook: $dst"
    fi
  fi
done
if [[ -f "$TESTING_DIR/vault-suseconnect.yml" ]]; then
  if head -1 "$TESTING_DIR/vault-suseconnect.yml" 2>/dev/null | grep -q '^\$ANSIBLE_VAULT'; then
    ok "vault-suseconnect.yml present and encrypted"
  else
    warn "vault-suseconnect.yml present but NOT encrypted — run: ansible-vault encrypt $TESTING_DIR/vault-suseconnect.yml"
  fi
else
  warn "vault-suseconnect.yml absent — SCC registration will fail on SLE targets."
  warn "  See assets/playbooks/README.md for vault setup, or run: make scc-vault-init"
fi

# --- 5. .gitignore for workspace's own ignored-state ---
if ! grep -q '^state/' .gitignore 2>/dev/null; then
  warn ".gitignore should ignore state/* — please verify."
fi

echo ""
ok "install-deps complete. Run 'make install-cron' to schedule nightly runs."

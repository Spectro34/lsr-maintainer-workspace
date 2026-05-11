#!/usr/bin/env bash
# bin/doctor.sh — fast static posture check.
#
# Mirrors the 8 checks the orchestrator's `/lsr-maintainer doctor` command
# performs, but as pure bash so you can run it before scheduling the cron
# (or as the cron's own pre-flight) without paying for a `claude -p` call.
#
# Exit 0 = all green (or only neutral items missing).
# Exit 1 = critical red (cron not safe to fire).

set -u

WORKSPACE="$(cd "$(dirname "$0")/.." && pwd)"
cd "$WORKSPACE" || exit 1

GREEN='\033[32m'; YELLOW='\033[33m'; RED='\033[31m'; CYAN='\033[36m'; NC='\033[0m'

PASS=0; WARN=0; FAIL=0
emit_pass() { printf "${GREEN}🟢${NC} %-32s %s\n" "$1" "$2"; PASS=$((PASS+1)); }
emit_warn() { printf "${YELLOW}🟡${NC} %-32s %s\n" "$1" "$2"; WARN=$((WARN+1)); }
emit_fail() { printf "${RED}🔴${NC} %-32s %s\n" "$1" "$2"; FAIL=$((FAIL+1)); }

printf "${CYAN}== doctor (static, no claude -p) ==${NC}\n"

# 1. state/config.json
if [[ -f state/config.json ]]; then
  gh_user="$(jq -r '.github.user // ""' state/config.json 2>/dev/null)"
  obs_user="$(jq -r '.obs.user // ""' state/config.json 2>/dev/null)"
  if [[ -n "$gh_user" ]]; then
    emit_pass "state/config.json"   "github=$gh_user obs=${obs_user:-(unset)}"
  else
    emit_fail "state/config.json"   "empty github.user — run ./bin/setup.sh"
  fi
else
  emit_fail "state/config.json"     "absent — run ./bin/setup.sh"
fi

# 2. gh auth
if gh auth status >/dev/null 2>&1; then
  who="$(gh api user --jq .login 2>/dev/null || echo '?')"
  emit_pass "gh auth"               "$who"
else
  emit_fail "gh auth"               "broken — run gh auth login"
fi

# 3. osc auth
if command -v osc >/dev/null 2>&1 && osc whois >/dev/null 2>&1; then
  who="$(osc whois 2>/dev/null | awk '{print $1}')"
  emit_pass "osc auth"              "$who"
else
  emit_fail "osc auth"              "broken — run osc -A https://api.opensuse.org whois"
fi

# 4. tox-lsr venv
if [[ -d "$HOME/github/ansible/testing/tox-lsr-venv/bin" ]]; then
  emit_pass "tox-lsr venv"          "$HOME/github/ansible/testing/tox-lsr-venv"
else
  emit_warn "tox-lsr venv"          "missing — bootstrap-runner will create on next run"
fi

# 5. git user.email / user.name (bug-fix-implementer needs these)
ge="$(git config --global user.email 2>/dev/null || true)"
gn="$(git config --global user.name 2>/dev/null || true)"
if [[ -n "$ge" && -n "$gn" ]]; then
  emit_pass "git author"            "$gn <$ge>"
else
  emit_fail "git author"            "set with: git config --global user.email/name"
fi

# 6. projects/lsr-agent symlink
if [[ -L projects/lsr-agent ]]; then
  if [[ -d projects/lsr-agent/.claude/skills/lsr-agent ]]; then
    emit_pass "lsr-agent symlink"   "$(readlink projects/lsr-agent)"
  else
    emit_fail "lsr-agent symlink"   "dangles — see SETUP.md §0"
  fi
fi

# 7. QEMU images per target (uses config globs if available)
iso_dir="$HOME/iso"
glob_match() {
  for f in $iso_dir/$1; do
    [[ -f "$f" ]] && { echo "$(basename "$f")"; return 0; }
  done
  return 1
}
declare -A IMG_GLOBS=(
  [sle-16]="SLES-16.0-*Minimal-VM*.x86_64*.qcow2"
  [leap-16.0]="Leap-16.0-Minimal-VM*.x86_64*Cloud*.qcow2"
  [sle-15-sp7]="SLES15-SP7-Minimal-VM*.x86_64*.qcow2"
  [leap-15.6]="openSUSE-Leap-15.6*.x86_64*.qcow2 Leap-15.6-Minimal-VM*.x86_64*.qcow2"
)
img_summary=""
for target in sle-16 leap-16.0 sle-15-sp7 leap-15.6; do
  match=""
  for pattern in ${IMG_GLOBS[$target]}; do
    match="$(glob_match "$pattern" 2>/dev/null)" && break
  done
  if [[ -n "$match" ]]; then img_summary+="✓ "; else img_summary+="✗ "; fi
done
if [[ "$img_summary" == "✓ ✓ ✓ ✓ " ]]; then
  emit_pass "QEMU images"           "all 4 targets present"
elif [[ "$img_summary" == *"✗"* ]]; then
  # sle-16 ✗ but leap-16.0 ✓ → fallback OK, still pass
  if [[ "${img_summary:0:2}" == "✗ " && "${img_summary:2:2}" == "✓ " ]]; then
    emit_warn "QEMU images"         "sle-16 missing, Leap 16 fallback OK"
  else
    emit_warn "QEMU images"         "sle-16=${img_summary:0:1} leap-16.0=${img_summary:2:1} sle-15-sp7=${img_summary:4:1} leap-15.6=${img_summary:6:1}"
  fi
fi

# 8. Cron entry registered
if crontab -l 2>/dev/null | grep -q '# lsr-maintainer-workspace'; then
  cron_line="$(crontab -l 2>/dev/null | grep '# lsr-maintainer-workspace' | head -1)"
  emit_pass "cron registered"       "${cron_line:0:60}..."
else
  emit_warn "cron registered"       "absent — run: make install-cron"
fi

# 9. Submodules
if [[ -f .gitmodules ]] && command -v git >/dev/null; then
  dirty="$(git submodule status 2>/dev/null | grep -cE '^[+-]' || true)"
  if [[ "$dirty" == "0" ]]; then
    submodule_count="$(wc -l < .gitmodules)"  # rough
    emit_pass "submodules"          "$(git submodule status 2>/dev/null | wc -l) clean"
  else
    emit_warn "submodules"          "$dirty dirty (run: git submodule update --init)"
  fi
fi

# 10. Hook test harness
if bash tests/hooks/run-all.sh >/dev/null 2>&1; then
  emit_pass "hook test harness"     "all tests pass"
else
  emit_fail "hook test harness"     "FAILING — run: bash tests/hooks/run-all.sh"
fi

echo ""
printf "${CYAN}== summary: %s green, %s yellow, %s red ==${NC}\n" "$PASS" "$WARN" "$FAIL"

if (( FAIL > 0 )); then
  echo "Fix red items before installing cron."
  exit 1
fi
exit 0

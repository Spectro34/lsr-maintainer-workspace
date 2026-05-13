#!/usr/bin/env bash
# block-self-modify.sh — PreToolUse hook for Write|Edit.
#
# Closes C-PROD-1: the agent has Edit/Write in its allowed-tools and could
# otherwise rewrite its own hooks (.claude/hooks/*), settings.json (which
# registers the hooks), identity config (state/config.json), pinned
# submodule SHAs (.gitmodules), MCP server config (.mcp.json), or its own
# test harness — neutralizing the security layer for the NEXT scheduled
# run.
#
# Allowed targets: state/ runtime artefacts (PENDING_REVIEW.md,
# .lsr-maintainer-state.json, .run.pid, .bootstrap-state.json, cache/,
# worktrees/), and anything outside the workspace tree (e.g. files in
# git worktrees of fork repos that bug-fix-implementer needs to patch).
#
# Exit 0 → allow.
# Exit 2 → block.

set -u

# Locate workspace root via the hook script's own path.
HOOK_DIR="$(cd "$(dirname "$(readlink -f "$0" 2>/dev/null || echo "$0")")" && pwd)"
WORKSPACE_ROOT="$(dirname "$(dirname "$HOOK_DIR")")"

SECURITY_LOG="${WORKSPACE_ROOT}/var/log/security.log"
mkdir -p "$(dirname "$SECURITY_LOG")" 2>/dev/null || true

emit_block() {
  local reason="$1"
  local path="${2:-<unknown>}"
  printf '{"decision":"deny","reason":%s}\n' \
    "$(printf '%s' "$reason" | python3 -c 'import sys,json; print(json.dumps(sys.stdin.read()))')"
  local ts log_line
  ts="$(date -Iseconds)"
  log_line="[$ts] SELFMOD-BLOCK: $reason :: $path"
  echo "$log_line" >> "$SECURITY_LOG"
  if command -v systemd-cat >/dev/null 2>&1; then
    echo "$log_line" | systemd-cat -t lsr-maintainer-security -p warning 2>/dev/null || true
  fi
  exit 2
}

# Parse tool input. Use a printable delimiter (bash strips null bytes from
# command substitution).
DELIM=$'\x1f'  # ASCII 0x1F unit separator — preserved in $() and very
               # unlikely to appear in tool names or filesystem paths.
input_json="$(cat)"
parsed="$(printf '%s' "$input_json" | DELIM="$DELIM" python3 -c '
import os, sys, json
d = "?"
try:
  d = json.loads(sys.stdin.read())
  tool = d.get("tool_name", "")
  ti = d.get("tool_input", {}) or {}
  path = ti.get("file_path") or ti.get("notebook_path") or ""
  sep = os.environ.get("DELIM", "|")
  print(f"{tool}{sep}{path}", end="")
except Exception:
  pass
')"

tool="${parsed%%${DELIM}*}"
path="${parsed#*${DELIM}}"

# Only intercept Write/Edit/NotebookEdit.
case "$tool" in
  Write|Edit|NotebookEdit|MultiEdit) : ;;
  *) exit 0 ;;
esac
[[ -z "$path" ]] && exit 0

# Resolve to an absolute path if it's not one. The tool input may be relative
# to the cwd of the agent's shell — we conservatively reject anything we
# can't resolve.
abs="$path"
case "$abs" in /*) : ;; *) abs="$(pwd)/$path" ;; esac
# Realpath normalises ../ and symlinks. Falls back to the raw absolute.
real="$(readlink -f "$abs" 2>/dev/null || echo "$abs")"

# Forbidden patterns under the workspace tree.
forbidden_under_workspace() {
  local p="$1"
  case "$p" in
    "$WORKSPACE_ROOT"/.claude/*)             return 0 ;;
    "$WORKSPACE_ROOT"/.mcp.json)             return 0 ;;
    "$WORKSPACE_ROOT"/.gitmodules)           return 0 ;;
    "$WORKSPACE_ROOT"/.gitignore)            return 0 ;;
    "$WORKSPACE_ROOT"/bin/*)                 return 0 ;;
    "$WORKSPACE_ROOT"/tests/hooks/*)         return 0 ;;
    "$WORKSPACE_ROOT"/Makefile)              return 0 ;;
    "$WORKSPACE_ROOT"/state/config.json)     return 0 ;;
    "$WORKSPACE_ROOT"/state/config.json.lock) return 0 ;;
    "$WORKSPACE_ROOT"/orchestrator/*)        return 0 ;;
  esac
  return 1
}

if forbidden_under_workspace "$real"; then
  emit_block "$tool against $real is forbidden — agent must not modify its own hooks/config/scripts/tests. State runtime artefacts in state/ (excluding config.json) are allowed." "$real"
fi

# Forbidden absolute paths regardless of workspace location.
case "$real" in
  /etc/cron*|/var/spool/cron*|/etc/sudoers*|/etc/passwd|/etc/shadow|/etc/group|/etc/hosts)
    emit_block "$tool against system config $real is forbidden." "$real" ;;
  "$HOME"/.bashrc|"$HOME"/.bash_profile|"$HOME"/.profile|"$HOME"/.zshrc|"$HOME"/.config/fish/*)
    emit_block "$tool against shell init files is forbidden." "$real" ;;
  "$HOME"/.ssh/*|"$HOME"/.gnupg/*|"$HOME"/.config/osc/*|"$HOME"/.config/gh/*|"$HOME"/.netrc|"$HOME"/.aws/*|"$HOME"/.azure/*|"$HOME"/.kube/*)
    emit_block "$tool against credential path $real is forbidden." "$real" ;;
  "$HOME"/.claude/hooks/*|"$HOME"/.claude/settings*.json)
    emit_block "$tool against user-global Claude hook/settings is forbidden." "$real" ;;
  # Audit log + transcripts (issue #16): the agent must not be able to
  # truncate or rewrite the very logs that record what it did. Hooks append
  # in append-mode; this PreToolUse block prevents Write/Edit from racing.
  "$WORKSPACE_ROOT"/var/log/*)
    emit_block "$tool against audit/transcript path $real is forbidden (preserves forensic trail)." "$real" ;;
esac

exit 0

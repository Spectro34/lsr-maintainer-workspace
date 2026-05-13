#!/usr/bin/env bash
# block-credential-leak.sh — PreToolUse hook for Bash and Read.
#
# Bash side: blocks env/printenv, echo $SECRET_VAR, cat/head/tail/less/grep
# against credential files, ssh-keyscan against known hosts.
#
# Read side: blocks Read() against credential paths.
#
# Exit 0 → allow.
# Exit 2 → block.

set -u

# Locate workspace root via this hook's own path.
HOOK_DIR="$(cd "$(dirname "$(readlink -f "$0" 2>/dev/null || echo "$0")")" && pwd)"
WORKSPACE_ROOT="$(dirname "$(dirname "$HOOK_DIR")")"

SECURITY_LOG="${WORKSPACE_ROOT}/var/log/security.log"
mkdir -p "$(dirname "$SECURITY_LOG")" 2>/dev/null || true

# Credential path patterns (glob-ish, used in shell case matching).
CRED_PATHS=(
  "*/.config/osc/oscrc"
  "*/.netrc"
  "*/.config/gh/hosts.yml"
  "*/.config/gh/config.yml"
  "*/.ssh/id_*"
  "*/.ssh/identity*"
  "*/.gnupg/*"
  "*/.aws/credentials"
  "*/.aws/config"
  "*/.azure/*"
  "*/.kube/config"
)

emit_block() {
  local reason="$1"
  local cmd="${2:-<read>}"
  printf '{"decision":"deny","reason":%s}\n' "$(printf '%s' "$reason" | python3 -c 'import sys,json; print(json.dumps(sys.stdin.read()))')"
  local ts log_line
  ts="$(date -Iseconds)"
  log_line="[$ts] CRED-BLOCK: $reason :: $cmd"
  echo "$log_line" >> "$SECURITY_LOG"
  if command -v systemd-cat >/dev/null 2>&1; then
    echo "$log_line" | systemd-cat -t lsr-maintainer-security -p warning 2>/dev/null || true
  fi
  exit 2
}

input_json="$(cat)"

# Detect tool and route.
tool="$(printf '%s' "$input_json" | python3 -c '
import sys, json
try:
  d = json.loads(sys.stdin.read())
  print(d.get("tool_name", ""), end="")
except Exception:
  pass
')"

case "$tool" in
  Bash)
    cmd="$(printf '%s' "$input_json" | python3 -c '
import sys, json
try:
  d = json.loads(sys.stdin.read())
  print(d.get("tool_input", {}).get("command", ""), end="")
except Exception:
  pass
')"
    [[ -z "$cmd" ]] && exit 0

    # 1. Block wrapper programs that could hide credential reads behind a
    #    different program name. (Sister hook block-upstream-actions.sh blocks
    #    these too, but defense-in-depth.)
    #
    # Same narrow exception as upstream-actions: allow `bash <script>.sh`
    # without -c/heredoc, so Makefile-invoked scripts still work.
    first_word="${cmd%% *}"
    case "$first_word" in
      bash|sh)
        # Allow `bash <path>` only when the next word doesn't start with `-`
        # and no heredoc/redirect is present, and there IS a next word.
        if [[ "$cmd" == "$first_word" ]]; then
          # Bare `bash` / `sh` — interactive shell, forbidden.
          emit_block "Bare $first_word forbidden (interactive shell)." "$cmd"
        fi
        rest="${cmd#$first_word }"
        nextword="${rest%% *}"
        if [[ -n "$nextword" ]] && [[ "$nextword" != -* ]] && \
           [[ "$cmd" != *'<<'* ]] && [[ "$cmd" != *'< '* ]]; then
          : # legitimate script runner — allow
        else
          emit_block "Wrapper program ($first_word) forbidden — could hide a credential read." "$cmd"
        fi
        ;;
      dash|zsh|ksh|fish|ash|csh|tcsh|\
      eval|exec|source|.|\
      xargs|parallel|env|nohup|timeout|setsid|nice|ionice|\
      python|python2|python3|perl|ruby|node|nodejs|lua|tcl|php|\
      sudo|doas|pkexec|runuser|su|\
      watch|unbuffer|script|\
      awk|gawk|mawk|\
      ssh|scp|rsync|sftp|\
      tmux|screen|at|batch|crontab|Xvfb|\
      time|flock|chronic|ifne|taskset|chrt|\
      firejail|bwrap|strace|ltrace|valgrind|gdb|\
      socat|setpriv|cset|expect|\
      pssh|parallel-ssh|\
      docker|podman|nsenter|lxc|lxc-attach|kubectl|oc)
        emit_block "Wrapper program ($first_word) forbidden — could hide a credential read." "$cmd"
        ;;
      make)
        # Narrow allow: `make <target>` with no -f/-C/-I and no shell metachars.
        if [[ "$cmd" =~ (^|[[:space:]])- ]] || [[ "$cmd" == *'$('* ]] || [[ "$cmd" == *'`'* ]] || \
           [[ "$cmd" == *'>'* ]] || [[ "$cmd" == *'|'* ]] || [[ "$cmd" == *';'* ]]; then
          emit_block "make with flags or shell metachars forbidden." "$cmd"
        fi
        ;;
    esac

    # 1b. coproc as a bash keyword bypass
    if [[ "$cmd" =~ ^[[:space:]]*coproc[[:space:]] ]]; then
      emit_block "coproc keyword forbidden — could hide a credential read." "$cmd"
    fi

    # 2. Block command substitution and backticks at the string level.
    if [[ "$cmd" == *'$('* ]] || [[ "$cmd" == *'`'* ]]; then
      emit_block "Command substitution forbidden — could hide a credential read." "$cmd"
    fi

    # 3. Block env-dump primitives.
    if [[ "$cmd" =~ (^|[\;\|\&[:space:]])env([[:space:]]|$) ]]; then
      emit_block "Bare 'env' dumps secret env vars — forbidden." "$cmd"
    fi
    if [[ "$cmd" =~ (^|[\;\|\&[:space:]])printenv([[:space:]]|$) ]]; then
      emit_block "'printenv' dumps secret env vars — forbidden." "$cmd"
    fi
    if [[ "$cmd" =~ (^|[\;\|\&])[[:space:]]*set[[:space:]]*$ ]]; then
      emit_block "Bare 'set' dumps shell state including secrets — forbidden." "$cmd"
    fi
    # Block declare/typeset/compgen/export env dumps.
    for envdump in 'declare -p' 'typeset -x' 'compgen -v' 'compgen -e'; do
      if [[ "$cmd" == *"$envdump"* ]]; then
        emit_block "'$envdump' dumps env including secrets — forbidden." "$cmd"
      fi
    done
    # Block /proc/self/environ reads (dumps process env).
    if [[ "$cmd" == */proc/self/environ* ]] || [[ "$cmd" == */proc/*/environ* ]]; then
      emit_block "Reading /proc/*/environ dumps process env — forbidden." "$cmd"
    fi

    # 4. Block echo $SECRET_VAR patterns.
    if [[ "$cmd" =~ echo[[:space:]]+\"?\$[A-Za-z_][A-Za-z0-9_]*(TOKEN|PASSWORD|SECRET|API_KEY|ACCESS_KEY|PRIVATE_KEY|AUTH)[A-Za-z0-9_]* ]] || \
       [[ "$cmd" =~ echo[[:space:]]+\"?\$\{[A-Za-z_][A-Za-z0-9_]*(TOKEN|PASSWORD|SECRET|API_KEY|ACCESS_KEY|PRIVATE_KEY|AUTH)[A-Za-z0-9_]* ]]; then
      emit_block "echo of secret-looking env var is forbidden." "$cmd"
    fi

    # 5. CRITICAL: Block ANY mention of a credential path in the command,
    #    regardless of which binary is invoked. Catches cp, mv, tar, xxd, od,
    #    vim, dd, source, ., and anything else we didn't think to enumerate.
    for pat in "${CRED_PATHS[@]}"; do
      # shellcheck disable=SC2053
      if [[ "$cmd" == *${pat}* ]]; then
        emit_block "Credential path mentioned in command ($pat) — forbidden regardless of tool." "$cmd"
      fi
    done
    ;;

  Read)
    path="$(printf '%s' "$input_json" | python3 -c '
import sys, json
try:
  d = json.loads(sys.stdin.read())
  print(d.get("tool_input", {}).get("file_path", ""), end="")
except Exception:
  pass
')"
    [[ -z "$path" ]] && exit 0
    for pat in "${CRED_PATHS[@]}"; do
      # shellcheck disable=SC2053
      if [[ "$path" == $pat ]]; then
        emit_block "Read() against credential path is forbidden: $path" "Read $path"
      fi
    done
    ;;
esac

exit 0

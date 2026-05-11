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

SECURITY_LOG="${HOME}/.cache/lsr-maintainer/security.log"
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
  echo "[$(date -Iseconds)] CRED-BLOCK: $reason :: $cmd" >> "$SECURITY_LOG"
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

    # Block bare env / printenv (printing the whole environment).
    if [[ "$cmd" =~ (^|[\;\|\&[:space:]])env([[:space:]]|$) ]]; then
      emit_block "Bare 'env' dumps secret env vars — forbidden." "$cmd"
    fi
    if [[ "$cmd" =~ (^|[\;\|\&[:space:]])printenv([[:space:]]|$) ]]; then
      emit_block "'printenv' dumps secret env vars — forbidden." "$cmd"
    fi
    # Block `set` with no args (dumps env in many shells).
    if [[ "$cmd" =~ (^|[\;\|\&])[[:space:]]*set[[:space:]]*$ ]]; then
      emit_block "Bare 'set' dumps shell state including secrets — forbidden." "$cmd"
    fi
    # Block `echo $SOMETHING_SECRET` patterns.
    if [[ "$cmd" =~ echo[[:space:]]+\"?\$[A-Za-z_][A-Za-z0-9_]*(TOKEN|PASSWORD|SECRET|API_KEY|ACCESS_KEY|PRIVATE_KEY|AUTH)[A-Za-z0-9_]* ]] || \
       [[ "$cmd" =~ echo[[:space:]]+\"?\$\{[A-Za-z_][A-Za-z0-9_]*(TOKEN|PASSWORD|SECRET|API_KEY|ACCESS_KEY|PRIVATE_KEY|AUTH)[A-Za-z0-9_]* ]]; then
      emit_block "echo of secret-looking env var is forbidden." "$cmd"
    fi
    # Block cat/head/tail/less/more/grep against credential paths.
    for prog in cat head tail less more grep awk sed strings; do
      if [[ "$cmd" =~ (^|[\;\|\&[:space:]])${prog}[[:space:]] ]]; then
        for pat in "${CRED_PATHS[@]}"; do
          # shellcheck disable=SC2053
          if [[ "$cmd" == *${pat}* ]]; then
            emit_block "$prog against credential path is forbidden ($pat)." "$cmd"
          fi
        done
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

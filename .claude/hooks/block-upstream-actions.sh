#!/usr/bin/env bash
# block-upstream-actions.sh — PreToolUse Bash hook.
#
# Re-parses the proposed Bash command (with shell-quoting awareness, chained
# commands, env-var prefixes, --repo flags, and remote-name → URL resolution)
# and blocks any path that would push, PR, or SR to anything outside the
# allowed personal forks / home: OBS projects.
#
# Exit 0 → allow.
# Exit 2 → block (Claude Code will surface the JSON reason to the model).
#
# Stdin: { tool_name: "Bash", tool_input: { command: "..." } }
# Stdout (on block): { "decision": "deny", "reason": "..." }

set -u

# Personal namespaces — anything else is "upstream" and blocked from writes.
ALLOW_GH_OWNER="Spectro34"
ALLOW_OSC_PREFIX="home:Spectro34"
SECURITY_LOG="${HOME}/.cache/lsr-maintainer/security.log"
mkdir -p "$(dirname "$SECURITY_LOG")" 2>/dev/null || true

# ------------------------------------------------------------------- helpers
emit_block() {
  local reason="$1"
  local input="${2:-<unknown>}"
  printf '{"decision":"deny","reason":%s}\n' "$(printf '%s' "$reason" | python3 -c 'import sys,json; print(json.dumps(sys.stdin.read()))')"
  echo "[$(date -Iseconds)] BLOCK: $reason :: cmd=$input" >> "$SECURITY_LOG"
  exit 2
}

# Resolve a git remote name to its URL within the current worktree.
remote_url() {
  local name="$1"
  git remote get-url "$name" 2>/dev/null
}

# True if a GitHub URL points outside our allowed owner.
gh_url_is_upstream() {
  local url="$1"
  case "$url" in
    *github.com:${ALLOW_GH_OWNER}/*|*github.com/${ALLOW_GH_OWNER}/*) return 1 ;;
    *github.com:*|*github.com/*) return 0 ;;
    *) return 0 ;;  # unknown URL → treat as upstream
  esac
}

# True if an OBS project name is outside our home: namespace.
osc_proj_is_upstream() {
  local proj="$1"
  case "$proj" in
    ${ALLOW_OSC_PREFIX}*) return 1 ;;
    *) return 0 ;;
  esac
}

# Split a chained command on ; && || and re-check each part. Doesn't try to
# be a full shell parser — enough to catch easy obfuscation like
# `false; gh pr create --repo ...`.
split_chained() {
  printf '%s\n' "$1" | tr ';|&' '\n' | sed 's/^[[:space:]]*//;s/[[:space:]]*$//'
}

# Strip leading "VAR=val VAR=val " env-var prefixes so the command itself is
# what we check.
strip_env_prefix() {
  local s="$1"
  while [[ "$s" =~ ^[A-Za-z_][A-Za-z0-9_]*= ]]; do
    s="${s#* }"
  done
  printf '%s' "$s"
}

# --------------------------------------------------------------- parse input
input_json="$(cat)"
cmd="$(printf '%s' "$input_json" | python3 -c '
import sys, json
try:
  d = json.loads(sys.stdin.read())
  if d.get("tool_name") != "Bash":
    sys.exit(0)
  print(d.get("tool_input", {}).get("command", ""), end="")
except Exception:
  sys.exit(0)
')"

# Not a Bash call → allow.
[[ -z "$cmd" ]] && exit 0

# Iterate over chained subcommands.
while IFS= read -r sub; do
  [[ -z "$sub" ]] && continue
  sub="$(strip_env_prefix "$sub")"

  # Get the program (first word, ignoring any leading expansion).
  prog="${sub%% *}"

  case "$prog" in
    # ----------------------------------------------------------- gh
    gh)
      args=" ${sub#gh } "  # leading + trailing space simplifies word matching
      case "$args" in
        # Blocked actions — already in deny rules, but belt-and-suspenders.
        *" pr create "*|*" pr create"*)
          emit_block "gh pr create is forbidden — the agent must never open PRs upstream." "$sub" ;;
        *" pr merge "*|*" pr merge"*)
          emit_block "gh pr merge is forbidden — merging is a human decision." "$sub" ;;
        *" repo create "*|*" repo create"*)
          # Allow only Spectro34/* repo creation if it ever needs to.
          if [[ "$args" =~ " repo create "(Spectro34/[A-Za-z0-9._-]+) ]]; then
            :  # allowed — proceed
          else
            emit_block "gh repo create is restricted to ${ALLOW_GH_OWNER}/* (got: $sub). Surface to PENDING_REVIEW.md instead." "$sub"
          fi ;;
        *" repo delete"*)
          emit_block "gh repo delete is forbidden." "$sub" ;;
        *" pr edit"*"--base"*)
          emit_block "Re-basing a PR via gh pr edit is forbidden — that's an upstream-touching operation." "$sub" ;;
      esac
      # Explicit --repo flag → check owner.
      if [[ "$args" =~ --repo[[:space:]=]+([A-Za-z0-9._/-]+) ]]; then
        target="${BASH_REMATCH[1]}"
        owner="${target%%/*}"
        if [[ "$owner" != "$ALLOW_GH_OWNER" ]] && [[ "$args" =~ " pr "|" repo " ]]; then
          # Read-only gh commands like `gh pr view --repo X` are fine.
          case "$args" in
            *" pr view"*|*" pr list"*|*" pr diff"*|*" pr checks"*|*" pr status"*) : ;;
            *" repo view"*) : ;;
            *) emit_block "gh write op against --repo $target is upstream; only ${ALLOW_GH_OWNER}/* allowed." "$sub" ;;
          esac
        fi
      fi
      ;;

    # ----------------------------------------------------------- osc
    osc)
      args=" ${sub#osc } "
      case "$args" in
        *" sr "*|*" sr"*|*" submitrequest"*|*" submitreq "*|*" submitreq"*|*" createrequest"*)
          emit_block "osc submit-request is forbidden — packages may be staged in home: only." "$sub" ;;
        *" copypac"*)
          emit_block "osc copypac is forbidden — could overwrite upstream packages." "$sub" ;;
        *" rdelete"*|*" delete "*|*" delete"*|*" undelete"*)
          # Allow deletes only inside home:Spectro34:*
          if [[ "$args" =~ (home:Spectro34[^[:space:]]*) ]]; then
            : # allowed personal namespace
          else
            emit_block "osc delete/rdelete is restricted to ${ALLOW_OSC_PREFIX}*." "$sub"
          fi ;;
        *" lock"*|*" unlock"*)
          emit_block "osc lock/unlock is forbidden (affects shared state)." "$sub" ;;
        *" ci "*|*" ci"*|*" commit "*|*" commit"*)
          # Commits are fine inside home:* but block elsewhere. Project name
          # is usually the cwd's parent dir under an osc checkout.
          if [[ "$args" =~ -p[[:space:]]+([^[:space:]]+) ]]; then
            proj="${BASH_REMATCH[1]}"
            if osc_proj_is_upstream "$proj"; then
              emit_block "osc commit to $proj is forbidden — only ${ALLOW_OSC_PREFIX}* allowed." "$sub"
            fi
          fi
          # If no -p, fall through; relies on cwd. Acceptable risk: hook
          # cannot read cwd without forking osc itself.
          ;;
      esac
      ;;

    # ----------------------------------------------------------- git
    git)
      args=" ${sub#git } "
      case "$args" in
        *" push "*)
          # Block force-push outright (already in deny rules).
          if [[ "$args" =~ --force|" -f " ]]; then
            emit_block "git push --force is forbidden — could rewrite history on a fork." "$sub"
          fi
          # Identify the remote arg.
          # Forms: git push <remote> ..., git push --set-upstream <remote> ...
          remote=""
          # shellcheck disable=SC2207
          tokens=($(echo "$args"))
          for (( i=0; i<${#tokens[@]}; i++ )); do
            t="${tokens[$i]}"
            if [[ "$t" == "push" ]]; then
              # next non-flag token is the remote
              for (( j=i+1; j<${#tokens[@]}; j++ )); do
                tt="${tokens[$j]}"
                if [[ "$tt" != -* ]] && [[ "$tt" != "" ]]; then remote="$tt"; break; fi
                if [[ "$tt" == "-u" || "$tt" == "--set-upstream" ]]; then continue; fi
              done
              break
            fi
          done
          if [[ -n "$remote" ]]; then
            # If remote looks like a URL, check it directly.
            if [[ "$remote" =~ ^(https?:|git@|ssh:) ]]; then
              if gh_url_is_upstream "$remote"; then
                emit_block "git push to non-fork URL ($remote) is forbidden." "$sub"
              fi
            else
              # Resolve remote name → URL.
              url="$(remote_url "$remote")"
              if [[ -n "$url" ]] && gh_url_is_upstream "$url"; then
                emit_block "git push to remote '$remote' ($url) is upstream; only ${ALLOW_GH_OWNER}/* allowed." "$sub"
              fi
              # If we can't resolve (no cwd context), refuse pushes whose
              # remote name suggests upstream.
              case "$remote" in
                upstream|UPSTREAM|original) emit_block "git push to remote named '$remote' is forbidden by policy." "$sub" ;;
              esac
            fi
          fi
          ;;
      esac
      ;;

    # ----------------------------------------------------------- destructive
    rm)
      args=" ${sub#rm } "
      # Match literal "$HOME" — single-quote it so bash doesn't expand at parse time.
      case "$args" in
        *' -rf /'*|*' -rf ~'*|*' -rf $HOME'*|*' -rf /home'*|*' -rf ${HOME}'*)
          emit_block "Destructive rm against system paths is forbidden." "$sub" ;;
      esac
      ;;

    # ----------------------------------------------------------- sudo / pkg mgr
    sudo|zypper|apt|apt-get|dnf|yum)
      emit_block "$prog is forbidden — the agent must surface install commands to PENDING_REVIEW.md, not run them." "$sub" ;;
  esac
done < <(split_chained "$cmd")

exit 0

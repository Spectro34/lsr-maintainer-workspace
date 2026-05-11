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

# Locate workspace root via the hook script's own path. Robust to agent cwd.
HOOK_DIR="$(cd "$(dirname "$(readlink -f "$0" 2>/dev/null || echo "$0")")" && pwd)"
WORKSPACE_ROOT="$(dirname "$(dirname "$HOOK_DIR")")"
# Env-var override for tests; default to the workspace's state/config.json.
CONFIG_JSON="${LSR_CONFIG_OVERRIDE:-${WORKSPACE_ROOT}/state/config.json}"

# Personal namespaces — read from config.json at runtime. If the config
# doesn't exist yet (pre-init), both vars are empty strings which makes
# the `gh_url_is_upstream` / `osc_proj_is_upstream` checks treat EVERYTHING
# as upstream (safer than allowing writes against a guessed identity).
# Run ./bin/setup.sh once to populate.
ALLOW_GH_OWNER=""
ALLOW_OSC_PREFIX=""
if [ -f "$CONFIG_JSON" ] && command -v jq >/dev/null 2>&1; then
  ALLOW_GH_OWNER="$(jq -r '.github.user // ""' "$CONFIG_JSON" 2>/dev/null)"
  ALLOW_OSC_PREFIX="$(jq -r '.obs.personal_project_root // ""' "$CONFIG_JSON" 2>/dev/null)"
fi

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
# Pre-init (ALLOW_GH_OWNER empty) treats EVERYTHING as upstream.
gh_url_is_upstream() {
  local url="$1"
  if [[ -z "$ALLOW_GH_OWNER" ]]; then return 0; fi
  case "$url" in
    *github.com:${ALLOW_GH_OWNER}/*|*github.com/${ALLOW_GH_OWNER}/*) return 1 ;;
    *github.com:*|*github.com/*) return 0 ;;
    *) return 0 ;;  # unknown URL → treat as upstream
  esac
}

# True if an OBS project name is outside our home: namespace.
# Pre-init (ALLOW_OSC_PREFIX empty) treats EVERYTHING as upstream.
osc_proj_is_upstream() {
  local proj="$1"
  if [[ -z "$ALLOW_OSC_PREFIX" ]]; then return 0; fi
  case "$proj" in
    ${ALLOW_OSC_PREFIX}*) return 1 ;;
    *) return 0 ;;
  esac
}

# Split a chained command on ; && || \n and re-check each part. Doesn't try
# to be a full shell parser — enough to catch easy obfuscation like
# `false; gh pr create --repo ...` or multi-line commands.
split_chained() {
  printf '%s\n' "$1" | tr ';|&\n' '\n\n\n\n' | sed 's/^[[:space:]]*//;s/[[:space:]]*$//'
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

# Wrapper programs that can launch arbitrary commands. We block these outright
# because (a) the agent has no legitimate need for shell-of-shell trickery in
# normal operation, and (b) allowing them creates a hook bypass — e.g.,
# `bash -c "gh pr create --repo X"` only shows `bash` as the program name.
#
# `bash`/`sh` have a narrow legitimate-use exception: running an explicit
# `.sh` script file. See is_legit_script_runner().
#
# Also blocks command substitution `$(...)` and backticks at the string level.
WRAPPERS_DENY="bash sh dash zsh ksh fish ash csh tcsh \
               eval exec source . \
               xargs parallel env nohup timeout setsid nice ionice \
               python python2 python3 perl ruby node nodejs lua tcl php \
               sudo doas pkexec runuser su \
               watch unbuffer script \
               awk gawk mawk \
               make ssh scp rsync sftp \
               tmux screen at batch crontab Xvfb \
               time flock chronic ifne taskset chrt \
               firejail bwrap strace ltrace valgrind gdb \
               socat setpriv cset expect \
               pssh parallel-ssh \
               docker podman nsenter lxc lxc-attach kubectl oc"

# True if the given command is a legitimate script invocation pattern:
#   bash <relative-path-ending-.sh> [args...]
#   sh <relative-path-ending-.sh> [args...]
# AND the next token is a script path (ends in `.sh` OR starts with bin/tests/scripts/).
# AND the next token doesn't start with `-` (no flags like -c/-i/-x/--rcfile).
# AND there's no heredoc or redirect (`<`).
# AND the path doesn't contain `..` (no traversal up out of the workspace).
is_legit_script_runner() {
  local s="$1"
  local first="${s%% *}"
  case "$first" in bash|sh) ;; *) return 1 ;; esac
  # If there's nothing after `bash`/`sh`, it's a bare invocation (interactive shell).
  if [[ "$s" == "$first" ]]; then return 1; fi
  # Rest of the command after "bash " / "sh ".
  local rest="${s#$first }"
  # First word of rest must be a path that doesn't start with `-`.
  local nextword="${rest%% *}"
  case "$nextword" in
    -*|'') return 1 ;;
  esac
  # No heredoc/redirect anywhere.
  case "$s" in *'<<'*|*'< '*) return 1 ;; esac
  # Reject path traversal.
  case "$nextword" in *..*) return 1 ;; esac
  # Require .sh suffix OR a workspace-relative path prefix (bin/, tests/, scripts/, etc.).
  case "$nextword" in
    *.sh) return 0 ;;
    bin/*|tests/*|scripts/*|projects/*) return 0 ;;
    *) return 1 ;;
  esac
}

# True if the given command is a legitimate `make <target>` invocation:
#   make           (default target)
#   make help      (named target, no shell metachars)
#   make ROLE=x enable-role  (var-prefix + target)
# Rejects: make -f /tmp/evil.mk (custom makefile), make -C /tmp/evil (dir switch),
#          make ; rm -rf /, make --include-dir=/tmp, etc.
is_legit_make_runner() {
  local s="$1"
  local first="${s%% *}"
  [[ "$first" != "make" ]] && return 1
  # Reject any `-` flag (no -f/-C/-I/-W/-e/--include-dir/--directory/etc).
  if [[ "$s" =~ (^|[[:space:]])- ]]; then return 1; fi
  # Reject shell metachars / substitution / redirect that might escape.
  case "$s" in
    *'$('*|*'`'*|*'<<'*|*'< '*|*'>'*|*'|'*|*';'*|*'&'*) return 1 ;;
  esac
  # Each remaining token must be either a bare target name or VAR=value.
  local rest="${s#make}"
  local tok
  for tok in $rest; do
    case "$tok" in
      [A-Za-z_][A-Za-z0-9_-]*) : ;;                            # bare target
      [A-Za-z_][A-Za-z0-9_]*=[A-Za-z0-9._/-]*) : ;;            # VAR=value (safe chars only)
      *) return 1 ;;
    esac
  done
  return 0
}

# True if the given command string contains a shell-wrapper invocation, command
# substitution, backtick, or variable-expanded command. Echoes a reason on
# match. Empty stdout = no wrapper detected.
detect_wrapper() {
  local s="$1"
  # Command substitution $(...)
  if [[ "$s" == *'$('* ]]; then echo "command substitution \$(...)"; return; fi
  # Backticks
  if [[ "$s" == *'`'* ]]; then echo "backtick command substitution"; return; fi
  # Heredoc that pipes into a wrapper (catches `bash <<EOF ... EOF`)
  if [[ "$s" =~ \<\<-?[[:space:]]*[\"\']?[A-Za-z_] ]]; then echo "heredoc input"; return; fi
  # bash keyword: `coproc <cmd>` at the start (not in WRAPPERS_DENY because
  # `${s%% *}` returns "coproc" as a word, but case-statement match in main
  # loop won't catch it without explicit listing; treat coproc as a wrapper).
  if [[ "$s" =~ ^[[:space:]]*coproc[[:space:]] ]]; then echo "coproc keyword"; return; fi
  # First word a known wrapper — but allow narrow legit forms:
  #   `bash <script.sh>` for shell-script runners
  #   `make <target>` for Makefile targets
  local first="${s%% *}"
  for w in $WRAPPERS_DENY; do
    if [[ "$first" == "$w" ]]; then
      if is_legit_script_runner "$s"; then return; fi
      if is_legit_make_runner "$s"; then return; fi
      echo "wrapper program: $w"; return;
    fi
  done
  # Variable expansion as a command: `$cmd`, `${cmd}`, `"$cmd"` at start
  if [[ "$first" =~ ^[\"\']?\$\{? ]]; then echo "variable-expanded command"; return; fi
  # Quick check: aliases via 'alias x=...' setup followed by use of x
  if [[ "$s" =~ ^[[:space:]]*alias[[:space:]] ]]; then echo "alias definition"; return; fi
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

# Check for wrappers at the FULL command level first (before chain split, so
# we catch heredocs and command substitution that may span chain operators).
wrapper_reason="$(detect_wrapper "$cmd")"
if [[ -n "$wrapper_reason" ]]; then
  emit_block "Wrapper invocations forbidden ($wrapper_reason). The agent must call CLIs directly." "$cmd"
fi

# Iterate over chained subcommands.
while IFS= read -r sub; do
  [[ -z "$sub" ]] && continue
  sub="$(strip_env_prefix "$sub")"

  # Re-check each chained subcommand for wrappers (in case the user chains
  # `something_innocent && bash -c "..."`).
  wrapper_reason="$(detect_wrapper "$sub")"
  if [[ -n "$wrapper_reason" ]]; then
    emit_block "Wrapper invocations forbidden in chained command ($wrapper_reason)." "$sub"
  fi

  # Get the program (first word, ignoring any leading expansion).
  prog="${sub%% *}"

  # Block `find ... -exec X ...` which is its own bypass class.
  if [[ "$prog" == "find" ]] && [[ "$sub" =~ -exec[[:space:]] ]]; then
    emit_block "find -exec is forbidden (bypass class)." "$sub"
  fi

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
          # Allow only configured-user/* repo creation. Pre-init blocks all.
          if [[ -z "$ALLOW_GH_OWNER" ]]; then
            emit_block "gh repo create is forbidden — workspace not initialized (run ./bin/setup.sh)." "$sub"
          elif [[ "$args" =~ " repo create "(${ALLOW_GH_OWNER}/[A-Za-z0-9._-]+) ]]; then
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
        if [[ -z "$ALLOW_GH_OWNER" ]] || [[ "$owner" != "$ALLOW_GH_OWNER" ]]; then
          # Read-only gh subcommands are fine even against upstream.
          case "$args" in
            *" pr view"*|*" pr list"*|*" pr diff"*|*" pr checks"*|*" pr status"*) : ;;
            *" repo view"*|*" repo list"*) : ;;
            *" issue view"*|*" issue list"*|*" issue status"*) : ;;
            *" release view"*|*" release list"*) : ;;
            *" workflow view"*|*" workflow list"*) : ;;
            *" run view"*|*" run list"*|*" run watch"*) : ;;
            *" api "*)
              # gh api is read-mostly, but -X POST/PUT/PATCH/DELETE / --method <write>
              # is a write op. Only allow read methods (GET, HEAD, default).
              if [[ "$args" =~ (-X|--method)[[:space:]]+([A-Z]+) ]]; then
                method="${BASH_REMATCH[2]}"
                case "$method" in
                  GET|HEAD) : ;;
                  *) emit_block "gh api --method/-X $method against $target is a write op; blocked." "$sub" ;;
                esac
              fi
              ;;
            *" auth status"*) : ;;
            *)
              # Any write-style gh subcommand against non-configured-owner → block.
              # Catches: pr create/merge/close/edit/review,
              #          repo create/delete/edit/fork --remote=,
              #          issue create/edit/close/comment/develop/transfer,
              #          release create/delete/edit/upload,
              #          workflow run/enable/disable,
              #          gist create/delete/edit,
              #          secret/variable/ruleset/cache/label set/delete.
              emit_block "gh write op against --repo $target is upstream; only ${ALLOW_GH_OWNER}/* allowed." "$sub" ;;
          esac
        fi
      else
        # No --repo flag, but commands without --repo may infer from cwd.
        # For high-risk write ops with no explicit --repo, surface a warning-block.
        case "$args" in
          *" issue create"*|*" issue close"*|*" issue comment"*|*" issue edit"*)
            emit_block "gh issue write op without --repo is risky (could target wrong repo); use explicit --repo ${ALLOW_GH_OWNER:-<configured-owner>}/<name>." "$sub" ;;
          *" release create"*|*" release delete"*|*" release upload"*|*" release edit"*)
            emit_block "gh release write op without --repo is risky." "$sub" ;;
          *" gist create"*|*" gist delete"*|*" gist edit"*)
            emit_block "gh gist write op forbidden (gists are public unless --secret; agent should not post)." "$sub" ;;
        esac
        # gh api -X POST/PUT/PATCH/DELETE against ANY endpoint (no --repo flag).
        if [[ "$args" =~ " api " ]] && [[ "$args" =~ (-X|--method)[[:space:]]+([A-Z]+) ]]; then
          method="${BASH_REMATCH[2]}"
          case "$method" in
            GET|HEAD) : ;;
            *) emit_block "gh api --method/-X $method is a write op (any endpoint); blocked. Surface via PENDING instead." "$sub" ;;
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
          # Allow deletes only inside the configured personal namespace.
          if [[ -z "$ALLOW_OSC_PREFIX" ]]; then
            emit_block "osc delete/rdelete is forbidden — workspace not initialized." "$sub"
          elif [[ "$args" == *"$ALLOW_OSC_PREFIX"* ]]; then
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
      # git sub-commands that can run arbitrary commands as a side-effect.
      case "$args" in
        *" submodule foreach "*)
          emit_block "git submodule foreach is forbidden — can launch arbitrary commands." "$sub" ;;
        *" rebase --exec"*|*" rebase -x "*)
          emit_block "git rebase --exec is forbidden — can launch arbitrary commands per commit." "$sub" ;;
        *" bisect run "*|*" bisect-run "*)
          emit_block "git bisect run is forbidden — can launch arbitrary commands." "$sub" ;;
        *" filter-branch"*|*" filter-repo"*)
          emit_block "git filter-branch/filter-repo is forbidden — rewrites history." "$sub" ;;
        *" worktree add"*" --command"*)
          emit_block "git worktree add --command is forbidden." "$sub" ;;
        *" clone "*" --upload-pack"*|*" fetch "*" --upload-pack"*|*" pull "*" --upload-pack"*)
          emit_block "git --upload-pack= is forbidden — can launch arbitrary commands." "$sub" ;;
        *" clone "*" --config core.sshCommand"*|*" -c core.sshCommand"*)
          emit_block "git core.sshCommand override is forbidden." "$sub" ;;
        *" -c core.editor"*|*" -c sequence.editor"*|*" -c diff.external"*|*" -c merge.tool"*|*" -c pager.*"*|*" -c help.format"*)
          emit_block "git -c <config-override-that-runs-a-command> is forbidden." "$sub" ;;
        *" config "*core.editor*)
          emit_block "git config core.editor write is forbidden (would launch arbitrary cmd at next commit)." "$sub" ;;
        *" config "*sequence.editor*)
          emit_block "git config sequence.editor write is forbidden." "$sub" ;;
      esac
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
                emit_block "git push to remote '$remote' ($url) is upstream; only ${ALLOW_GH_OWNER:-<unconfigured>}/* allowed." "$sub"
              fi
              # If we can't resolve to a URL (no cwd context, or remote not
              # configured in the cwd's repo), apply policy:
              # 1. Pre-init (ALLOW_GH_OWNER empty) → DENY everything.
              # 2. Block by known-bad remote names (upstream/UPSTREAM/original).
              # 3. Only `origin`, `fork`, and `${ALLOW_GH_OWNER}` are accepted
              #    as plausibly-personal remote names.
              if [[ -z "$url" ]]; then
                if [[ -z "$ALLOW_GH_OWNER" ]]; then
                  emit_block "git push pre-init (no config) to remote '$remote': cannot verify target." "$sub"
                fi
                case "$remote" in
                  upstream|UPSTREAM|original)
                    emit_block "git push to remote named '$remote' is forbidden by policy." "$sub" ;;
                  origin|fork|"$ALLOW_GH_OWNER") : ;;  # plausible personal remote name
                  *)
                    emit_block "git push to unknown remote '$remote' (cannot resolve URL): refuse to push without verifying target." "$sub" ;;
                esac
              fi
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

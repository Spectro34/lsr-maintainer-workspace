#!/usr/bin/env bash
# tests/hooks/run-all.sh — fire synthetic tool-input JSON at each hook and
# assert exit codes. This must pass before anything else in the workspace runs.

set -u

WORKSPACE="$(cd "$(dirname "$0")/../.." && pwd)"
UPSTREAM="$WORKSPACE/.claude/hooks/block-upstream-actions.sh"
CRED="$WORKSPACE/.claude/hooks/block-credential-leak.sh"
ENV_SCRUB="$WORKSPACE/.claude/hooks/scrub-env.sh"
SELFMOD="$WORKSPACE/.claude/hooks/block-self-modify.sh"

# Synthesize a test config so the existing tests (which assume a known
# identity) work regardless of what state/config.json says on the host.
# Hook reads LSR_CONFIG_OVERRIDE if set.
TEST_CONFIG="$(mktemp -t lsr-test-config.XXXXXX.json)"
trap 'rm -f "$TEST_CONFIG"' EXIT
cat > "$TEST_CONFIG" <<'EOF'
{
  "version": 1,
  "github": {"user": "Spectro34", "fork_pattern": "{user}/{role}"},
  "obs":    {"user": "spectro34", "personal_project_root": "home:Spectro34"}
}
EOF
export LSR_CONFIG_OVERRIDE="$TEST_CONFIG"

PASS=0
FAIL=0
FAIL_LINES=()

check() {
  local desc="$1" expected="$2" actual="$3" details="${4:-}"
  if [[ "$expected" == "$actual" ]]; then
    PASS=$((PASS+1))
    printf '  ok   %s\n' "$desc"
  else
    FAIL=$((FAIL+1))
    FAIL_LINES+=("  FAIL  $desc  expected=$expected actual=$actual  $details")
    printf '  FAIL %s  expected=%s actual=%s\n' "$desc" "$expected" "$actual"
  fi
}

# Run a hook against a JSON input; return exit code.
run_hook() {
  local hook="$1" json="$2"
  bash "$hook" <<<"$json" >/dev/null 2>&1
  echo $?
}

# ---------------------------------------------------------------- upstream
echo "== block-upstream-actions.sh =="

# Allow-list: read-only ops and pushes to fork remotes (no remote → cannot verify).
ALLOW_CASES=(
  '{"tool_name":"Bash","tool_input":{"command":"gh pr list --state open"}}|gh pr list'
  '{"tool_name":"Bash","tool_input":{"command":"gh pr view 42 --repo linux-system-roles/sudo --json comments"}}|read-only gh pr view against upstream OK'
  '{"tool_name":"Bash","tool_input":{"command":"git fetch origin"}}|git fetch'
  '{"tool_name":"Bash","tool_input":{"command":"osc results devel:sap:ansible ansible-linux-system-roles"}}|osc results read-only'
  '{"tool_name":"Bash","tool_input":{"command":"osc co home:Spectro34:branches:devel:sap:ansible"}}|osc co into home: is fine'
  '{"tool_name":"Bash","tool_input":{"command":"osc ci -m \"update\" -p home:Spectro34:branches:devel:sap:ansible"}}|osc ci in home: namespace'
  '{"tool_name":"Edit","tool_input":{"file_path":"/tmp/foo.txt"}}|non-Bash non-Read tool ignored'
)
for entry in "${ALLOW_CASES[@]}"; do
  desc="${entry##*|}"; json="${entry%|*}"
  code=$(run_hook "$UPSTREAM" "$json")
  check "ALLOW $desc" "0" "$code"
done

# ---- C1/C2 reviewer-found bypasses for upstream-actions hook ----
# All must now DENY. (Pre-fix: all bypassed via wrapper not being a known
# program name. Post-fix: wrappers blocked outright + newline-aware splits.)
BYPASS_CASES=(
  '{"tool_name":"Bash","tool_input":{"command":"bash -c \"gh pr create --repo Foo/bar\""}}|wrapper bash -c'
  '{"tool_name":"Bash","tool_input":{"command":"sh -c gh pr create"}}|wrapper sh -c'
  '{"tool_name":"Bash","tool_input":{"command":"eval gh pr create --repo Foo/bar"}}|wrapper eval'
  '{"tool_name":"Bash","tool_input":{"command":"exec gh pr create --repo Foo/bar"}}|wrapper exec'
  '{"tool_name":"Bash","tool_input":{"command":"xargs -I{} gh pr create --repo {}"}}|wrapper xargs'
  '{"tool_name":"Bash","tool_input":{"command":"timeout 5 gh pr create --repo Foo/bar"}}|wrapper timeout'
  '{"tool_name":"Bash","tool_input":{"command":"nohup gh pr create --repo Foo/bar"}}|wrapper nohup'
  '{"tool_name":"Bash","tool_input":{"command":"setsid gh pr create"}}|wrapper setsid'
  '{"tool_name":"Bash","tool_input":{"command":"python3 -c \"import subprocess; subprocess.run([\\\"gh\\\",\\\"pr\\\",\\\"create\\\"])\""}}|wrapper python3 -c'
  '{"tool_name":"Bash","tool_input":{"command":"perl -e print"}}|wrapper perl -e'
  '{"tool_name":"Bash","tool_input":{"command":"node -e console.log"}}|wrapper node -e'
  '{"tool_name":"Bash","tool_input":{"command":"sudo gh pr create"}}|wrapper sudo'
  '{"tool_name":"Bash","tool_input":{"command":"find . -name X -exec gh pr create {} ;"}}|find -exec bypass class'
  '{"tool_name":"Bash","tool_input":{"command":"echo $(gh pr create --repo Foo/bar)"}}|command substitution dollar-paren'
  '{"tool_name":"Bash","tool_input":{"command":"echo `gh pr create --repo Foo/bar`"}}|backtick substitution'
  '{"tool_name":"Bash","tool_input":{"command":"echo ok\ngh pr create --repo Foo/bar"}}|newline-chained command'
  '{"tool_name":"Bash","tool_input":{"command":"watch gh pr create"}}|wrapper watch'
  '{"tool_name":"Bash","tool_input":{"command":"unbuffer gh pr create"}}|wrapper unbuffer'
)
for entry in "${BYPASS_CASES[@]}"; do
  desc="${entry##*|}"; json="${entry%|*}"
  code=$(run_hook "$UPSTREAM" "$json")
  check "DENY  bypass-fix $desc" "2" "$code"
done

# ---- N1-N10 re-review bypass vectors (must DENY) ----
N_BYPASS=(
  '{"tool_name":"Bash","tool_input":{"command":"coproc gh pr create"}}|N1 coproc keyword'
  '{"tool_name":"Bash","tool_input":{"command":"awk BEGIN{system(\"gh pr create\")}"}}|N2 awk system()'
  '{"tool_name":"Bash","tool_input":{"command":"make -f /tmp/evil.mk all"}}|N3 hostile make (custom Makefile)'
  '{"tool_name":"Bash","tool_input":{"command":"git submodule foreach gh pr create"}}|N4 git submodule foreach'
  '{"tool_name":"Bash","tool_input":{"command":"git rebase --exec \"gh pr create\" main"}}|N5 git rebase --exec'
  '{"tool_name":"Bash","tool_input":{"command":"git bisect run gh pr create"}}|N6 git bisect run'
  '{"tool_name":"Bash","tool_input":{"command":"ssh host gh pr create"}}|N7 ssh remote'
  '{"tool_name":"Bash","tool_input":{"command":"tmux new-window gh pr create"}}|N8a tmux'
  '{"tool_name":"Bash","tool_input":{"command":"screen -dm gh pr create"}}|N8b screen'
  '{"tool_name":"Bash","tool_input":{"command":"Xvfb :99 -- gh pr create"}}|N9 Xvfb'
  '{"tool_name":"Bash","tool_input":{"command":"crontab -l"}}|N10a crontab'
  '{"tool_name":"Bash","tool_input":{"command":"at now"}}|N10b at'
  '{"tool_name":"Bash","tool_input":{"command":"batch"}}|N10c batch'
  '{"tool_name":"Bash","tool_input":{"command":"git filter-branch --tree-filter ls"}}|N-filter-branch'
  '{"tool_name":"Bash","tool_input":{"command":"git -c core.sshCommand=ls fetch"}}|N-ssh-command override'
  '{"tool_name":"Bash","tool_input":{"command":"rsync -e gh pr create file host:"}}|N-rsync wrapper'
)
for entry in "${N_BYPASS[@]}"; do
  desc="${entry##*|}"; json="${entry%|*}"
  code=$(run_hook "$UPSTREAM" "$json")
  check "DENY  N-bypass $desc" "2" "$code"
done

# ---- MJ-2 fix: legitimate `bash <script.sh>` invocations must ALLOW ----
LEGIT_BASH=(
  '{"tool_name":"Bash","tool_input":{"command":"bash tests/hooks/run-all.sh"}}|MJ-2 bash tests/hooks/run-all.sh'
  '{"tool_name":"Bash","tool_input":{"command":"bash bin/install-deps.sh"}}|MJ-2 bash bin/install-deps.sh'
  '{"tool_name":"Bash","tool_input":{"command":"bash bin/setup.sh"}}|MJ-2 bash bin/setup.sh'
  '{"tool_name":"Bash","tool_input":{"command":"bash bin/install-cron.sh --remove"}}|MJ-2 bash bin/install-cron.sh with arg'
  '{"tool_name":"Bash","tool_input":{"command":"sh some/path/build.sh arg1 arg2"}}|MJ-2 sh script.sh args'
)
for entry in "${LEGIT_BASH[@]}"; do
  desc="${entry##*|}"; json="${entry%|*}"
  code=$(run_hook "$UPSTREAM" "$json")
  check "ALLOW $desc" "0" "$code"
done

# ---- Round-3: bash <non-script-path> tightening (must DENY) ----
BASH_PATH_BYPASS=(
  '{"tool_name":"Bash","tool_input":{"command":"bash /etc/passwd"}}|R3 bash /etc/passwd (not .sh)'
  '{"tool_name":"Bash","tool_input":{"command":"bash /tmp/x"}}|R3 bash /tmp/x (not .sh)'
  '{"tool_name":"Bash","tool_input":{"command":"bash ../escape.sh"}}|R3 bash path traversal'
  '{"tool_name":"Bash","tool_input":{"command":"sh /tmp/anyfile"}}|R3 sh non-workspace path'
)
for entry in "${BASH_PATH_BYPASS[@]}"; do
  desc="${entry##*|}"; json="${entry%|*}"
  code=$(run_hook "$UPSTREAM" "$json")
  check "DENY  $desc" "2" "$code"
done

# ---- Round-3: make <legit-target> must ALLOW (regression fix) ----
LEGIT_MAKE=(
  '{"tool_name":"Bash","tool_input":{"command":"make"}}|R3 bare make'
  '{"tool_name":"Bash","tool_input":{"command":"make help"}}|R3 make help'
  '{"tool_name":"Bash","tool_input":{"command":"make doctor"}}|R3 make doctor'
  '{"tool_name":"Bash","tool_input":{"command":"make test-hooks"}}|R3 make test-hooks'
  '{"tool_name":"Bash","tool_input":{"command":"make install"}}|R3 make install'
  '{"tool_name":"Bash","tool_input":{"command":"make ROLE=squid enable-role"}}|R3 make VAR=val target'
)
for entry in "${LEGIT_MAKE[@]}"; do
  desc="${entry##*|}"; json="${entry%|*}"
  code=$(run_hook "$UPSTREAM" "$json")
  check "ALLOW $desc" "0" "$code"
done

# ---- Round-3: hostile make invocations must DENY ----
MAKE_BYPASS=(
  '{"tool_name":"Bash","tool_input":{"command":"make -f /tmp/evil.mk"}}|R3 make -f custom Makefile'
  '{"tool_name":"Bash","tool_input":{"command":"make -C /tmp/evil all"}}|R3 make -C dir switch'
  '{"tool_name":"Bash","tool_input":{"command":"make --include-dir=/tmp"}}|R3 make --include-dir'
  '{"tool_name":"Bash","tool_input":{"command":"make ; rm -rf /"}}|R3 make chain bypass'
)
for entry in "${MAKE_BYPASS[@]}"; do
  desc="${entry##*|}"; json="${entry%|*}"
  code=$(run_hook "$UPSTREAM" "$json")
  check "DENY  $desc" "2" "$code"
done

# ---- Round-3: more wrappers (must DENY) ----
R3_WRAPPERS=(
  '{"tool_name":"Bash","tool_input":{"command":"time gh pr create"}}|R3 time wrapper'
  '{"tool_name":"Bash","tool_input":{"command":"flock /tmp/x gh pr create"}}|R3 flock wrapper'
  '{"tool_name":"Bash","tool_input":{"command":"taskset 0x1 gh pr create"}}|R3 taskset wrapper'
  '{"tool_name":"Bash","tool_input":{"command":"strace gh pr create"}}|R3 strace wrapper'
  '{"tool_name":"Bash","tool_input":{"command":"firejail gh pr create"}}|R3 firejail wrapper'
  '{"tool_name":"Bash","tool_input":{"command":"docker run --rm img gh pr create"}}|R3 docker wrapper'
  '{"tool_name":"Bash","tool_input":{"command":"podman run img cmd"}}|R3 podman wrapper'
  '{"tool_name":"Bash","tool_input":{"command":"kubectl exec pod -- gh pr create"}}|R3 kubectl exec'
  '{"tool_name":"Bash","tool_input":{"command":"nsenter -t 1 -m gh pr create"}}|R3 nsenter'
  '{"tool_name":"Bash","tool_input":{"command":"socat EXEC:gh,pty -"}}|R3 socat EXEC'
)
for entry in "${R3_WRAPPERS[@]}"; do
  desc="${entry##*|}"; json="${entry%|*}"
  code=$(run_hook "$UPSTREAM" "$json")
  check "DENY  $desc" "2" "$code"
done

# ---- Round-3: gh subcommand owner gate extension ----
GH_WRITE_BYPASS=(
  '{"tool_name":"Bash","tool_input":{"command":"gh issue create --repo linux-system-roles/sudo --title x"}}|R3 gh issue create upstream'
  '{"tool_name":"Bash","tool_input":{"command":"gh issue close --repo linux-system-roles/sudo 42"}}|R3 gh issue close upstream'
  '{"tool_name":"Bash","tool_input":{"command":"gh release create --repo linux-system-roles/sudo v1.0"}}|R3 gh release create upstream'
  '{"tool_name":"Bash","tool_input":{"command":"gh workflow run --repo linux-system-roles/sudo ci.yml"}}|R3 gh workflow run upstream'
  '{"tool_name":"Bash","tool_input":{"command":"gh gist create file.txt"}}|R3 gh gist create (any)'
  '{"tool_name":"Bash","tool_input":{"command":"gh issue create --title hi"}}|R3 gh issue create no --repo'
)
for entry in "${GH_WRITE_BYPASS[@]}"; do
  desc="${entry##*|}"; json="${entry%|*}"
  code=$(run_hook "$UPSTREAM" "$json")
  check "DENY  $desc" "2" "$code"
done

# ---- Round-3: gh read-only subcommands against upstream must still ALLOW ----
GH_READ_OK=(
  '{"tool_name":"Bash","tool_input":{"command":"gh issue view 42 --repo linux-system-roles/sudo"}}|R3 gh issue view upstream'
  '{"tool_name":"Bash","tool_input":{"command":"gh issue list --repo linux-system-roles/sudo"}}|R3 gh issue list upstream'
  '{"tool_name":"Bash","tool_input":{"command":"gh release list --repo linux-system-roles/sudo"}}|R3 gh release list upstream'
)
for entry in "${GH_READ_OK[@]}"; do
  desc="${entry##*|}"; json="${entry%|*}"
  code=$(run_hook "$UPSTREAM" "$json")
  check "ALLOW $desc" "0" "$code"
done

# ---- Round-3: git editor-override escapes ----
GIT_EDITOR_BYPASS=(
  '{"tool_name":"Bash","tool_input":{"command":"git -c core.editor=ls commit -e -m hi"}}|R3 git -c core.editor'
  '{"tool_name":"Bash","tool_input":{"command":"git -c sequence.editor=ls rebase -i HEAD"}}|R3 git -c sequence.editor'
  '{"tool_name":"Bash","tool_input":{"command":"git config core.editor=ls"}}|R3 git config core.editor write'
)
for entry in "${GIT_EDITOR_BYPASS[@]}"; do
  desc="${entry##*|}"; json="${entry%|*}"
  code=$(run_hook "$UPSTREAM" "$json")
  check "DENY  $desc" "2" "$code"
done

# But `bash -c "..."` and bare `bash` must still DENY
BASH_BYPASS_RECONFIRM=(
  '{"tool_name":"Bash","tool_input":{"command":"bash -c \"echo hi\""}}|bash -c still denies'
  '{"tool_name":"Bash","tool_input":{"command":"bash -ic hi"}}|bash -ic still denies'
  '{"tool_name":"Bash","tool_input":{"command":"bash"}}|bare bash still denies'
  '{"tool_name":"Bash","tool_input":{"command":"bash <<EOF"}}|bash <<EOF still denies'
)
for entry in "${BASH_BYPASS_RECONFIRM[@]}"; do
  desc="${entry##*|}"; json="${entry%|*}"
  code=$(run_hook "$UPSTREAM" "$json")
  check "DENY  $desc" "2" "$code"
done

# Deny-list
DENY_CASES=(
  '{"tool_name":"Bash","tool_input":{"command":"gh pr create --repo linux-system-roles/sudo"}}|gh pr create against upstream'
  '{"tool_name":"Bash","tool_input":{"command":"gh pr create"}}|bare gh pr create'
  '{"tool_name":"Bash","tool_input":{"command":"gh pr merge 42 --repo Spectro34/sudo"}}|gh pr merge always blocked'
  '{"tool_name":"Bash","tool_input":{"command":"gh repo create SUSE/ansible-squid --public"}}|gh repo create outside Spectro34'
  '{"tool_name":"Bash","tool_input":{"command":"gh repo delete Spectro34/foo"}}|gh repo delete blocked'
  '{"tool_name":"Bash","tool_input":{"command":"osc sr -m hi devel:sap:ansible foo openSUSE:Factory"}}|osc sr'
  '{"tool_name":"Bash","tool_input":{"command":"osc submitrequest devel:sap:ansible foo openSUSE:Factory"}}|osc submitrequest'
  '{"tool_name":"Bash","tool_input":{"command":"osc createrequest -m hi"}}|osc createrequest'
  '{"tool_name":"Bash","tool_input":{"command":"osc copypac devel:sap:ansible foo openSUSE:Factory"}}|osc copypac'
  '{"tool_name":"Bash","tool_input":{"command":"git push --force origin main"}}|git push --force'
  '{"tool_name":"Bash","tool_input":{"command":"git push -f origin main"}}|git push -f'
  '{"tool_name":"Bash","tool_input":{"command":"git push upstream main"}}|git push to remote named upstream'
  '{"tool_name":"Bash","tool_input":{"command":"git push git@github.com:linux-system-roles/sudo.git fix/x"}}|git push to upstream URL'
  '{"tool_name":"Bash","tool_input":{"command":"git push https://github.com/linux-system-roles/sudo.git fix/x"}}|git push to upstream HTTPS URL'
  '{"tool_name":"Bash","tool_input":{"command":"false ; gh pr create --repo Foo/bar"}}|chained gh pr create after false'
  '{"tool_name":"Bash","tool_input":{"command":"true && osc sr -m hi"}}|chained osc sr after true'
  '{"tool_name":"Bash","tool_input":{"command":"FOO=bar gh pr create --repo Foo/bar"}}|env-prefixed gh pr create'
  '{"tool_name":"Bash","tool_input":{"command":"sudo zypper install -y something"}}|sudo always blocked'
  '{"tool_name":"Bash","tool_input":{"command":"zypper install foo"}}|zypper always blocked'
  '{"tool_name":"Bash","tool_input":{"command":"rm -rf /"}}|rm -rf /'
  '{"tool_name":"Bash","tool_input":{"command":"rm -rf $HOME"}}|rm -rf $HOME'
)
for entry in "${DENY_CASES[@]}"; do
  desc="${entry##*|}"; json="${entry%|*}"
  code=$(run_hook "$UPSTREAM" "$json")
  check "DENY  $desc" "2" "$code"
done

# ---------------------------------------------------------------- cred-leak
echo "== block-credential-leak.sh =="

CRED_ALLOW=(
  '{"tool_name":"Bash","tool_input":{"command":"echo hello"}}|plain echo'
  '{"tool_name":"Bash","tool_input":{"command":"cat README.md"}}|cat non-credential file'
  '{"tool_name":"Bash","tool_input":{"command":"gh auth status"}}|gh auth status'
  '{"tool_name":"Read","tool_input":{"file_path":"/home/spectro/github/lsr-maintainer-workspace/README.md"}}|Read normal file'
)
for entry in "${CRED_ALLOW[@]}"; do
  desc="${entry##*|}"; json="${entry%|*}"
  code=$(run_hook "$CRED" "$json")
  check "ALLOW $desc" "0" "$code"
done

# ---- C3 reviewer-found cred-leak bypasses ----
CRED_BYPASS=(
  '{"tool_name":"Bash","tool_input":{"command":"bash -c"}}|wrapper bash -c (any args)'
  '{"tool_name":"Bash","tool_input":{"command":"python3 -c x"}}|wrapper python3 -c (any args)'
  '{"tool_name":"Bash","tool_input":{"command":"perl -e x"}}|wrapper perl -e (any args)'
  '{"tool_name":"Bash","tool_input":{"command":"sudo cat hi"}}|wrapper sudo (any args)'
  '{"tool_name":"Bash","tool_input":{"command":"eval x"}}|wrapper eval (any args)'
  '{"tool_name":"Bash","tool_input":{"command":"source /home/spectro/.config/osc/oscrc"}}|source cred path'
  '{"tool_name":"Bash","tool_input":{"command":". /home/spectro/.config/osc/oscrc"}}|dot-source cred path'
  '{"tool_name":"Bash","tool_input":{"command":"echo hi $(cat hi)"}}|command substitution forbidden'
  '{"tool_name":"Bash","tool_input":{"command":"echo `cat hi`"}}|backtick forbidden'
  '{"tool_name":"Bash","tool_input":{"command":"xxd /home/spectro/.ssh/id_ed25519"}}|xxd cred path (path-based deny)'
  '{"tool_name":"Bash","tool_input":{"command":"od -c /home/spectro/.ssh/id_rsa"}}|od cred path'
  '{"tool_name":"Bash","tool_input":{"command":"cp /home/spectro/.ssh/id_rsa /tmp/x"}}|cp cred path'
  '{"tool_name":"Bash","tool_input":{"command":"tar cf /tmp/ss.tar /home/spectro/.ssh/id_rsa"}}|tar over cred path'
  '{"tool_name":"Bash","tool_input":{"command":"vim /home/spectro/.ssh/id_rsa"}}|vim cred path'
  '{"tool_name":"Bash","tool_input":{"command":"dd if=/home/spectro/.ssh/id_rsa"}}|dd cred path'
  '{"tool_name":"Bash","tool_input":{"command":"declare -p"}}|declare -p env dump'
  '{"tool_name":"Bash","tool_input":{"command":"typeset -x"}}|typeset -x env dump'
  '{"tool_name":"Bash","tool_input":{"command":"compgen -v"}}|compgen -v env dump'
  '{"tool_name":"Bash","tool_input":{"command":"cat /proc/self/environ"}}|/proc/self/environ dump'
  '{"tool_name":"Bash","tool_input":{"command":"head /proc/12345/environ"}}|/proc/<pid>/environ dump'
)
for entry in "${CRED_BYPASS[@]}"; do
  desc="${entry##*|}"; json="${entry%|*}"
  code=$(run_hook "$CRED" "$json")
  check "DENY  cred-bypass-fix $desc" "2" "$code"
done

CRED_DENY=(
  '{"tool_name":"Bash","tool_input":{"command":"env"}}|bare env'
  '{"tool_name":"Bash","tool_input":{"command":"printenv"}}|printenv'
  '{"tool_name":"Bash","tool_input":{"command":"printenv GITHUB_TOKEN"}}|printenv with arg'
  '{"tool_name":"Bash","tool_input":{"command":"echo $GITHUB_TOKEN"}}|echo $GITHUB_TOKEN'
  '{"tool_name":"Bash","tool_input":{"command":"echo \"$AWS_SECRET_ACCESS_KEY\""}}|echo quoted $AWS_SECRET_ACCESS_KEY'
  '{"tool_name":"Bash","tool_input":{"command":"echo ${OSC_PASSWORD}"}}|echo ${OSC_PASSWORD}'
  '{"tool_name":"Bash","tool_input":{"command":"cat /home/spectro/.config/osc/oscrc"}}|cat oscrc'
  '{"tool_name":"Bash","tool_input":{"command":"grep token /home/spectro/.config/gh/hosts.yml"}}|grep gh hosts.yml'
  '{"tool_name":"Bash","tool_input":{"command":"head -1 /home/spectro/.ssh/id_ed25519"}}|head ssh key'
  '{"tool_name":"Read","tool_input":{"file_path":"/home/spectro/.config/osc/oscrc"}}|Read oscrc'
  '{"tool_name":"Read","tool_input":{"file_path":"/home/spectro/.ssh/id_rsa"}}|Read ssh key'
  '{"tool_name":"Read","tool_input":{"file_path":"/home/spectro/.netrc"}}|Read netrc'
)
for entry in "${CRED_DENY[@]}"; do
  desc="${entry##*|}"; json="${entry%|*}"
  code=$(run_hook "$CRED" "$json")
  check "DENY  $desc" "2" "$code"
done

# ---------------------------------------------------------------- scrub-env
echo "== scrub-env.sh =="

# Should always exit 0 and emit JSON when secret vars present.
output="$(GITHUB_TOKEN="dummy_for_test_only" bash "$ENV_SCRUB")"
code=$?
check "ALLOW scrub-env exits 0" "0" "$code"
if echo "$output" | grep -q '"updateEnv"' && echo "$output" | grep -q 'GITHUB_TOKEN'; then
  check "scrub-env emits updateEnv for GITHUB_TOKEN" "0" "0"
else
  check "scrub-env emits updateEnv for GITHUB_TOKEN" "0" "1" "output=$output"
fi

# ---- R5: gh api write-method detection (must DENY -X POST/PUT/PATCH/DELETE) ----
echo "== R5: gh api write-method detection =="
GHAPI_WRITE_DENY=(
  '{"tool_name":"Bash","tool_input":{"command":"gh api repos/foo/bar/issues -X POST -f title=hi"}}|R5 gh api -X POST'
  '{"tool_name":"Bash","tool_input":{"command":"gh api repos/foo/bar -X PATCH"}}|R5 gh api -X PATCH'
  '{"tool_name":"Bash","tool_input":{"command":"gh api repos/foo/bar -X DELETE"}}|R5 gh api -X DELETE'
  '{"tool_name":"Bash","tool_input":{"command":"gh api --method PUT repos/foo/bar"}}|R5 gh api --method PUT'
  '{"tool_name":"Bash","tool_input":{"command":"gh api --repo linux-system-roles/sudo repos/{owner}/{repo}/issues -X POST"}}|R5 gh api -X POST upstream --repo'
)
for entry in "${GHAPI_WRITE_DENY[@]}"; do
  desc="${entry##*|}"; json="${entry%|*}"
  code=$(run_hook "$UPSTREAM" "$json")
  check "DENY  $desc" "2" "$code"
done

GHAPI_READ_OK=(
  '{"tool_name":"Bash","tool_input":{"command":"gh api user"}}|R5 gh api user (default GET)'
  '{"tool_name":"Bash","tool_input":{"command":"gh api repos/foo/bar"}}|R5 gh api repo (default GET)'
  '{"tool_name":"Bash","tool_input":{"command":"gh api -X GET repos/foo/bar"}}|R5 gh api explicit -X GET'
  '{"tool_name":"Bash","tool_input":{"command":"gh api --method GET repos/foo/bar"}}|R5 gh api --method GET'
)
for entry in "${GHAPI_READ_OK[@]}"; do
  desc="${entry##*|}"; json="${entry%|*}"
  code=$(run_hook "$UPSTREAM" "$json")
  check "ALLOW $desc" "0" "$code"
done

# ---- R5: git push to unknown remote without resolvable URL ----
echo "== R5: git push unknown-remote without URL =="
GIT_PUSH_UNKNOWN_DENY=(
  '{"tool_name":"Bash","tool_input":{"command":"git push some-random-remote main"}}|R5 git push unknown remote'
  '{"tool_name":"Bash","tool_input":{"command":"git push attacker-remote HEAD"}}|R5 git push attacker remote'
)
for entry in "${GIT_PUSH_UNKNOWN_DENY[@]}"; do
  desc="${entry##*|}"; json="${entry%|*}"
  code=$(run_hook "$UPSTREAM" "$json")
  check "DENY  $desc" "2" "$code"
done

GIT_PUSH_PLAUSIBLE_OK=(
  '{"tool_name":"Bash","tool_input":{"command":"git push origin main"}}|R5 git push origin OK'
  '{"tool_name":"Bash","tool_input":{"command":"git push fork main"}}|R5 git push fork OK'
)
# Run from a non-git tmpdir so `git remote get-url origin` fails and the hook
# falls into the "plausible-remote-name" fallback (which is what this test
# section verifies). Without this, the test result depends on whatever URL
# the host's workspace origin happens to point at — brittle across forks.
PUSH_TMPDIR="$(mktemp -d -t lsr-test-push.XXXXXX)"
for entry in "${GIT_PUSH_PLAUSIBLE_OK[@]}"; do
  desc="${entry##*|}"; json="${entry%|*}"
  code=$(cd "$PUSH_TMPDIR" && bash "$UPSTREAM" <<<"$json" >/dev/null 2>&1; echo $?)
  check "ALLOW $desc" "0" "$code"
done
rm -rf "$PUSH_TMPDIR"

# ---- Pre-init safety: with empty config, ALL writes must be blocked ----
echo "== pre-init safety (empty config blocks everything) =="
EMPTY_CONFIG="$(mktemp -t lsr-test-empty.XXXXXX.json)"
echo '{"version":1,"github":{"user":""},"obs":{"user":"","personal_project_root":""}}' > "$EMPTY_CONFIG"

PREINIT_DENY=(
  '{"tool_name":"Bash","tool_input":{"command":"git push origin main"}}|pre-init: any push blocked'
  '{"tool_name":"Bash","tool_input":{"command":"git push fork main"}}|pre-init: git push fork blocked'
  '{"tool_name":"Bash","tool_input":{"command":"gh repo create AnyUser/foo"}}|pre-init: repo create blocked'
  '{"tool_name":"Bash","tool_input":{"command":"osc ci -p home:anyuser:branches:x foo"}}|pre-init: osc ci blocked'
  '{"tool_name":"Bash","tool_input":{"command":"gh api repos/foo/bar -X POST"}}|pre-init: gh api -X POST blocked'
)
for entry in "${PREINIT_DENY[@]}"; do
  desc="${entry##*|}"; json="${entry%|*}"
  code=$(LSR_CONFIG_OVERRIDE="$EMPTY_CONFIG" bash "$UPSTREAM" <<<"$json" >/dev/null 2>&1; echo $?)
  check "DENY  $desc" "2" "$code"
done
rm -f "$EMPTY_CONFIG"

# ---- R5: dynamic-identity — same hook works with a DIFFERENT user ----
echo "== R5: alt-identity (alice/alice123) — dynamic resolution =="
ALT_CONFIG="$(mktemp -t lsr-test-alt.XXXXXX.json)"
cat > "$ALT_CONFIG" <<'EOF'
{"version":1,"github":{"user":"alice","fork_pattern":"{user}/{role}"},"obs":{"user":"alice123","personal_project_root":"home:alice"}}
EOF

ALT_ALLOW=(
  '{"tool_name":"Bash","tool_input":{"command":"gh pr view 12 --repo linux-system-roles/sudo"}}|alt: read-only gh pr view'
  '{"tool_name":"Bash","tool_input":{"command":"osc co home:alice:branches:devel:sap:ansible"}}|alt: osc co into home:alice'
  '{"tool_name":"Bash","tool_input":{"command":"osc ci -m hi -p home:alice:branches:devel:sap:ansible"}}|alt: osc ci in home:alice'
)
for entry in "${ALT_ALLOW[@]}"; do
  desc="${entry##*|}"; json="${entry%|*}"
  code=$(LSR_CONFIG_OVERRIDE="$ALT_CONFIG" bash "$UPSTREAM" <<<"$json" >/dev/null 2>&1; echo $?)
  check "ALLOW $desc" "0" "$code"
done

ALT_DENY=(
  '{"tool_name":"Bash","tool_input":{"command":"gh pr create --repo linux-system-roles/sudo"}}|alt: gh pr create still blocked'
  '{"tool_name":"Bash","tool_input":{"command":"gh repo create Spectro34/foo"}}|alt: Spectro34 is NOT the configured owner'
  '{"tool_name":"Bash","tool_input":{"command":"osc ci -m hi -p home:Spectro34:branches:foo"}}|alt: osc ci into wrong home: blocked'
)
for entry in "${ALT_DENY[@]}"; do
  desc="${entry##*|}"; json="${entry%|*}"
  code=$(LSR_CONFIG_OVERRIDE="$ALT_CONFIG" bash "$UPSTREAM" <<<"$json" >/dev/null 2>&1; echo $?)
  check "DENY  $desc" "2" "$code"
done
rm -f "$ALT_CONFIG"

# ---- C-PROD-1: block-self-modify.sh — Write/Edit against hooks/settings/config ----
echo "== C-PROD-1: block-self-modify on Write/Edit =="

SELFMOD_DENY=(
  '{"tool_name":"Write","tool_input":{"file_path":"'"$WORKSPACE"'/.claude/hooks/block-upstream-actions.sh","content":"x"}}|Write to upstream hook'
  '{"tool_name":"Edit","tool_input":{"file_path":"'"$WORKSPACE"'/.claude/settings.json","old_string":"a","new_string":"b"}}|Edit to settings.json'
  '{"tool_name":"Edit","tool_input":{"file_path":"'"$WORKSPACE"'/state/config.json","old_string":"a","new_string":"b"}}|Edit to state/config.json'
  '{"tool_name":"Write","tool_input":{"file_path":"'"$WORKSPACE"'/.gitmodules","content":"x"}}|Write to .gitmodules'
  '{"tool_name":"Write","tool_input":{"file_path":"'"$WORKSPACE"'/.mcp.json","content":"x"}}|Write to .mcp.json'
  '{"tool_name":"Write","tool_input":{"file_path":"'"$WORKSPACE"'/bin/lsr-maintainer-run.sh","content":"x"}}|Write to bin/'
  '{"tool_name":"Write","tool_input":{"file_path":"'"$WORKSPACE"'/tests/hooks/run-all.sh","content":"x"}}|Write to tests/hooks/'
  '{"tool_name":"Write","tool_input":{"file_path":"'"$WORKSPACE"'/orchestrator/config.py","content":"x"}}|Write to orchestrator/'
  '{"tool_name":"Write","tool_input":{"file_path":"/home/spectro/.bashrc","content":"x"}}|Write to ~/.bashrc'
  '{"tool_name":"Write","tool_input":{"file_path":"/home/spectro/.ssh/id_test","content":"x"}}|Write to ssh key path'
  '{"tool_name":"Write","tool_input":{"file_path":"/etc/cron.d/evil","content":"x"}}|Write to /etc/cron.d/'
  '{"tool_name":"Edit","tool_input":{"file_path":"/home/spectro/.config/osc/oscrc","old_string":"a","new_string":"b"}}|Edit to oscrc'
  '{"tool_name":"Edit","tool_input":{"file_path":"/home/spectro/.claude/settings.json","old_string":"a","new_string":"b"}}|Edit to user-global Claude settings'
  '{"tool_name":"NotebookEdit","tool_input":{"notebook_path":"'"$WORKSPACE"'/.claude/skills/lsr-maintainer/SKILL.md","new_source":"x"}}|NotebookEdit SKILL.md'
  '{"tool_name":"Write","tool_input":{"file_path":"'"$WORKSPACE"'/var/log/security.log","content":""}}|#16 Write to audit log forbidden'
  '{"tool_name":"Edit","tool_input":{"file_path":"'"$WORKSPACE"'/var/log/20260512T030700.jsonl","old_string":"a","new_string":""}}|#16 Edit transcript forbidden'
)
for entry in "${SELFMOD_DENY[@]}"; do
  desc="${entry##*|}"; json="${entry%|*}"
  code=$(run_hook "$SELFMOD" "$json")
  check "DENY  $desc" "2" "$code"
done

# Allow: state/ runtime artefacts (PENDING_REVIEW, state.json, run.pid, cache, worktrees)
# and arbitrary paths OUTSIDE the workspace (worktree fork branches, etc.)
SELFMOD_ALLOW=(
  '{"tool_name":"Write","tool_input":{"file_path":"'"$WORKSPACE"'/state/PENDING_REVIEW.md","content":"x"}}|Write PENDING_REVIEW.md'
  '{"tool_name":"Write","tool_input":{"file_path":"'"$WORKSPACE"'/state/.lsr-maintainer-state.json","content":"x"}}|Write state file'
  '{"tool_name":"Write","tool_input":{"file_path":"'"$WORKSPACE"'/state/.run.pid","content":"x"}}|Write pidfile'
  '{"tool_name":"Write","tool_input":{"file_path":"'"$WORKSPACE"'/state/worktrees/sudo/library/scan_sudoers.py","content":"x"}}|Write to a worktree'
  '{"tool_name":"Write","tool_input":{"file_path":"/tmp/somefile","content":"x"}}|Write to /tmp/'
  '{"tool_name":"Write","tool_input":{"file_path":"/home/spectro/github/linux-system-roles/sudo/library/scan_sudoers.py","content":"x"}}|Write to fork checkout'
  '{"tool_name":"Bash","tool_input":{"command":"echo hi"}}|non-Write/Edit ignored'
  '{"tool_name":"Read","tool_input":{"file_path":"'"$WORKSPACE"'/.claude/settings.json"}}|Read settings.json (selfmod ignores Read)'
)
for entry in "${SELFMOD_ALLOW[@]}"; do
  desc="${entry##*|}"; json="${entry%|*}"
  code=$(run_hook "$SELFMOD" "$json")
  check "ALLOW $desc" "0" "$code"
done

# ---- P-M4: osc commit without -p must verify cwd via .osc/_project ----
echo "== P-M4: osc commit without -p checks cwd's .osc/_project =="

# Create a fake home: checkout (allowed)
HOME_CO="$(mktemp -d -t lsr-test-home-osc.XXXXXX)"
mkdir -p "$HOME_CO/.osc"
echo "home:Spectro34:branches:devel:sap:ansible" > "$HOME_CO/.osc/_project"

# Create a fake upstream checkout (forbidden)
UP_CO="$(mktemp -d -t lsr-test-up-osc.XXXXXX)"
mkdir -p "$UP_CO/.osc"
echo "devel:sap:ansible" > "$UP_CO/.osc/_project"

# osc ci from home: cwd → ALLOW
code=$(cd "$HOME_CO" && bash "$UPSTREAM" <<<'{"tool_name":"Bash","tool_input":{"command":"osc ci -m hi"}}' >/dev/null 2>&1; echo $?)
check "ALLOW osc ci in home:* checkout (cwd)" "0" "$code"

# osc ci from upstream cwd → DENY
code=$(cd "$UP_CO" && bash "$UPSTREAM" <<<'{"tool_name":"Bash","tool_input":{"command":"osc ci -m hi"}}' >/dev/null 2>&1; echo $?)
check "DENY  osc ci in upstream checkout (cwd)" "2" "$code"

# osc ci from random cwd with no .osc → DENY
NOOSC="$(mktemp -d -t lsr-test-no-osc.XXXXXX)"
code=$(cd "$NOOSC" && bash "$UPSTREAM" <<<'{"tool_name":"Bash","tool_input":{"command":"osc ci -m hi"}}' >/dev/null 2>&1; echo $?)
check "DENY  osc ci in non-osc cwd" "2" "$code"

rm -rf "$HOME_CO" "$UP_CO" "$NOOSC"

# ---- C-PROD-3: gh api -X with lowercase / = forms ----
echo "== C-PROD-3: gh api -X lowercase/= forms =="
GHAPI_FORM_DENY=(
  '{"tool_name":"Bash","tool_input":{"command":"gh api -Xpost /repos/foo/bar/issues"}}|gh api -Xpost (no space, lower)'
  '{"tool_name":"Bash","tool_input":{"command":"gh api -X=POST /repos/foo/bar"}}|gh api -X=POST'
  '{"tool_name":"Bash","tool_input":{"command":"gh api --method=POST /repos/foo/bar"}}|gh api --method=POST'
  '{"tool_name":"Bash","tool_input":{"command":"gh api --method=post /repos/foo/bar"}}|gh api --method=post (lower)'
  '{"tool_name":"Bash","tool_input":{"command":"gh api --repo Foo/bar repos/foo/bar/issues -Xpatch"}}|gh api -Xpatch with --repo'
)
for entry in "${GHAPI_FORM_DENY[@]}"; do
  desc="${entry##*|}"; json="${entry%|*}"
  code=$(run_hook "$UPSTREAM" "$json")
  check "DENY  $desc" "2" "$code"
done

# ---- bin/_lib/paths.sh — workspace-relative path resolution ----
echo "== bin/_lib/paths.sh resolves paths under workspace =="
PATHS_RESULT=$(bash -c "source '$WORKSPACE/bin/_lib/paths.sh'; lsr_path iso_dir")
case "$PATHS_RESULT" in
  "$WORKSPACE"/var/iso)
    PASS=$((PASS+1))
    echo "PASS  lsr_path iso_dir → $PATHS_RESULT" ;;
  *)
    FAIL=$((FAIL+1))
    FAIL_LINES+=("FAIL  lsr_path iso_dir expected '$WORKSPACE/var/iso' got '$PATHS_RESULT'")
    echo "FAIL  lsr_path iso_dir expected '$WORKSPACE/var/iso' got '$PATHS_RESULT'" ;;
esac

LOG_RESULT=$(bash -c "source '$WORKSPACE/bin/_lib/paths.sh'; lsr_path log_dir")
case "$LOG_RESULT" in
  "$WORKSPACE"/var/log)
    PASS=$((PASS+1))
    echo "PASS  lsr_path log_dir → $LOG_RESULT" ;;
  *)
    FAIL=$((FAIL+1))
    FAIL_LINES+=("FAIL  lsr_path log_dir expected '$WORKSPACE/var/log' got '$LOG_RESULT'")
    echo "FAIL  lsr_path log_dir expected '$WORKSPACE/var/log' got '$LOG_RESULT'" ;;
esac

# ---- gh repo fork narrow whitelist ----
echo "== gh repo fork whitelist (managed roles only) =="
FORK_STATE="$(mktemp -t lsr-test-fork-state.XXXXXX.json)"
FORK_CONFIG="$(mktemp -t lsr-test-fork-config.XXXXXX.json)"
cat > "$FORK_STATE" <<'EOF'
{"version":1,"obs":{"managed_roles":[{"name":"sudo"},{"name":"logging"}]},"roles":{"sudo":{}}}
EOF
cat > "$FORK_CONFIG" <<'EOF'
{"version":3,"github":{"user":"Spectro34","tracked_extra_roles":["kernel_settings"]},"obs":{"user":"spectro34","personal_project_root":"home:Spectro34"}}
EOF

# Allowed: managed roles in state.obs.managed_roles[] and tracked_extra_roles in config.
FORK_ALLOW=(
  '{"tool_name":"Bash","tool_input":{"command":"gh repo fork linux-system-roles/sudo --clone=false"}}|fork sudo (in managed_roles)'
  '{"tool_name":"Bash","tool_input":{"command":"gh repo fork linux-system-roles/logging"}}|fork logging (in managed_roles)'
  '{"tool_name":"Bash","tool_input":{"command":"gh repo fork linux-system-roles/kernel_settings"}}|fork kernel_settings (in tracked_extra_roles)'
  '{"tool_name":"Bash","tool_input":{"command":"gh repo fork linux-system-roles/SUDO"}}|fork SUDO (case-insensitive match)'
  '{"tool_name":"Bash","tool_input":{"command":"gh  repo  fork  linux-system-roles/sudo"}}|fork double-space (whitespace bypass attempt)'
  '{"tool_name":"Bash","tool_input":{"command":"gh\trepo\tfork\tlinux-system-roles/sudo"}}|fork tab-separated args'
)
for entry in "${FORK_ALLOW[@]}"; do
  desc="${entry##*|}"; json="${entry%|*}"
  code=$(LSR_CONFIG_OVERRIDE="$FORK_CONFIG" LSR_STATE_OVERRIDE="$FORK_STATE" bash "$UPSTREAM" <<<"$json" >/dev/null 2>&1; echo $?)
  check "ALLOW $desc" "0" "$code"
done

# Denied: non-managed roles, non-LSR owners, hostile flags, missing state file (managed_roles unknown).
FORK_DENY=(
  '{"tool_name":"Bash","tool_input":{"command":"gh repo fork linux-system-roles/totally-fake"}}|fork unmanaged role'
  '{"tool_name":"Bash","tool_input":{"command":"gh repo fork some-other-org/sudo"}}|fork non-LSR upstream'
  '{"tool_name":"Bash","tool_input":{"command":"gh repo fork linux-system-roles/sudo --org evilorg"}}|fork --org hostile flag (space form)'
  '{"tool_name":"Bash","tool_input":{"command":"gh repo fork linux-system-roles/sudo --org=evilorg"}}|fork --org=evilorg (equals form)'
  '{"tool_name":"Bash","tool_input":{"command":"gh repo fork"}}|fork bare (no target)'
)
for entry in "${FORK_DENY[@]}"; do
  desc="${entry##*|}"; json="${entry%|*}"
  code=$(LSR_CONFIG_OVERRIDE="$FORK_CONFIG" LSR_STATE_OVERRIDE="$FORK_STATE" bash "$UPSTREAM" <<<"$json" >/dev/null 2>&1; echo $?)
  check "DENY  $desc" "2" "$code"
done

# Missing state file → no managed_roles known → only tracked_extra_roles allowed.
MISSING_STATE="/tmp/nonexistent-state-$$.json"
code=$(LSR_CONFIG_OVERRIDE="$FORK_CONFIG" LSR_STATE_OVERRIDE="$MISSING_STATE" bash "$UPSTREAM" \
  <<<'{"tool_name":"Bash","tool_input":{"command":"gh repo fork linux-system-roles/sudo"}}' >/dev/null 2>&1; echo $?)
check "DENY  fork without state.json (sudo not in tracked_extra_roles)" "2" "$code"
code=$(LSR_CONFIG_OVERRIDE="$FORK_CONFIG" LSR_STATE_OVERRIDE="$MISSING_STATE" bash "$UPSTREAM" \
  <<<'{"tool_name":"Bash","tool_input":{"command":"gh repo fork linux-system-roles/kernel_settings"}}' >/dev/null 2>&1; echo $?)
check "ALLOW fork without state.json (kernel_settings in tracked_extra_roles)" "0" "$code"

# Pre-init: empty github.user blocks ALL forks.
PREINIT_FORK_CFG="$(mktemp -t lsr-test-preinit-fork.XXXXXX.json)"
echo '{"version":3,"github":{"user":""}}' > "$PREINIT_FORK_CFG"
code=$(LSR_CONFIG_OVERRIDE="$PREINIT_FORK_CFG" LSR_STATE_OVERRIDE="$FORK_STATE" bash "$UPSTREAM" \
  <<<'{"tool_name":"Bash","tool_input":{"command":"gh repo fork linux-system-roles/sudo"}}' >/dev/null 2>&1; echo $?)
check "DENY  fork pre-init (empty github.user)" "2" "$code"
rm -f "$PREINIT_FORK_CFG"

rm -f "$FORK_STATE" "$FORK_CONFIG"

# ---- settings.json portability: no literal /home/<user>/ paths ----
echo "== .claude/settings.json portability =="
if grep -nE '/home/[a-zA-Z][a-zA-Z0-9._-]+/' "$WORKSPACE/.claude/settings.json" >/dev/null; then
  FAIL=$((FAIL+1))
  FAIL_LINES+=("FAIL  settings.json has hardcoded /home/<user>/ path:")
  FAIL_LINES+=("$(grep -nE '/home/[a-zA-Z][a-zA-Z0-9._-]+/' "$WORKSPACE/.claude/settings.json")")
  echo "FAIL  settings.json has hardcoded /home/<user>/ path"
else
  PASS=$((PASS+1))
  echo "PASS  settings.json has no hardcoded /home/<user>/ paths"
fi

# ---------------------------------------------------------------- summary
echo ""
echo "============================================"
echo "  PASS: $PASS    FAIL: $FAIL"
echo "============================================"
if [[ "$FAIL" -gt 0 ]]; then
  printf '%s\n' "${FAIL_LINES[@]}"
  exit 1
fi
exit 0

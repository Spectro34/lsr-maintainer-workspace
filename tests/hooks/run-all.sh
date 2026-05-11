#!/usr/bin/env bash
# tests/hooks/run-all.sh — fire synthetic tool-input JSON at each hook and
# assert exit codes. This must pass before anything else in the workspace runs.

set -u

WORKSPACE="$(cd "$(dirname "$0")/../.." && pwd)"
UPSTREAM="$WORKSPACE/.claude/hooks/block-upstream-actions.sh"
CRED="$WORKSPACE/.claude/hooks/block-credential-leak.sh"
ENV_SCRUB="$WORKSPACE/.claude/hooks/scrub-env.sh"

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

# Component: Security hooks

Three hook scripts in `.claude/hooks/`. They are the deterministic boundary that makes the agent safe to run with `--permission-mode=acceptEdits`.

## `block-upstream-actions.sh` — PreToolUse on Bash

Blocks:

| Action | Mechanism |
|---|---|
| `gh pr create` (any) | Pattern + chained-command detection |
| `gh pr merge` | Pattern |
| `gh repo create OWNER/...` where OWNER ≠ configured user | Owner extraction from `--repo` flag |
| `gh repo delete` | Pattern |
| `osc sr`, `submitrequest`, `submitreq`, `createrequest` | Pattern |
| `osc copypac` | Pattern |
| `osc delete`/`rdelete` outside `${obs_user_root}:*` | Project-name regex |
| `osc lock`/`unlock` | Pattern (shared-state change) |
| `git push --force` / `-f` / `--force-with-lease` | Pattern |
| `git push <remote>` where remote URL ∉ ${github_user}/* | Resolves `git remote get-url <name>`, compares against allowlist |
| `gh repo fork <something-not-in-managed-roles>` | Narrow whitelist: only `linux-system-roles/<role>` where `<role>` ∈ `state.obs.managed_roles[]` ∪ `state.roles[]` keys ∪ `config.github.tracked_extra_roles`. Hostile flags (`--org other`) and bare `gh repo fork` are blocked. |
| `git push <remote>` where remote name ∈ {upstream, original, UPSTREAM} | Name blacklist (defensive) |
| `rm -rf /`, `rm -rf $HOME`, `rm -rf ~` | Literal-string match |
| `sudo *`, `zypper`, `apt`, `dnf`, `yum` | Always blocked — agent surfaces install cmds, doesn't run them |

Allows (via the explicit allow list and bypassing the deny patterns):

- All read-only `gh` / `osc` / `git` commands (`view`, `list`, `diff`, `results`, `log`, `fetch`, etc.)
- `git push origin` (resolved to a ${github_user}/* URL)
- `osc ci` inside `${obs_user_root}:*` namespaces

### Adversarial cases handled

- **Command chaining**: `false ; gh pr create ...`, `true && osc sr ...` — split on `;`, `&&`, `||` and re-check each part.
- **Env-var prefix**: `FOO=bar gh pr create ...` — strip `[A-Z_]+=...` prefixes before parsing.
- **`--repo` flag with arbitrary spaces or `=`**: regex matches both `--repo X` and `--repo=X`.
- **Remote alias to upstream**: `git push origin` when `origin` URL is upstream — `git remote get-url` resolves the URL, hook compares.
- **`gh repo create SUSE/foo`**: blocked (only ${github_user}/* allowed).

### Failure mode

Exit 2 + JSON on stdout: `{"decision":"deny","reason":"..."}`. Claude Code surfaces the reason to the model so it knows to re-route to PENDING_REVIEW.md instead.

Every block is logged to `./var/log/security.log` with timestamp, reason, and the full attempted command.

## `block-credential-leak.sh` — PreToolUse on Bash + Read

Blocks:

| Pattern | Why |
|---|---|
| `env`, `printenv` (with or without args) | Dumps secret env vars |
| Bare `set` | Dumps env in many shells |
| `echo $X` / `echo ${X}` where X matches `*TOKEN*|*PASSWORD*|*SECRET*|*API_KEY*|*ACCESS_KEY*|*PRIVATE_KEY*|*AUTH*` | Secret leak |
| `cat`/`head`/`tail`/`less`/`more`/`grep`/`awk`/`sed`/`strings` against credential paths (oscrc, .netrc, .ssh/id_*, .gnupg/*, .aws/*, .azure/*, .kube/config, gh hosts.yml) | Direct file read |
| `Read()` against the same paths | Direct file read |

## `scrub-env.sh` — SessionStart

Emits a `updateEnv` directive on session start to set `GITHUB_TOKEN`, `GH_TOKEN`, `OSC_PASSWORD`, `OSC_USER`, `ANTHROPIC_API_KEY`, `OPENAI_API_KEY`, `AWS_*`, `AZURE_*`, `GCP_*`, `NPM_TOKEN`, `DOCKER_PASSWORD`, `TWILIO_AUTH_TOKEN` etc. to empty strings in the agent's environment view.

The on-disk credentials are untouched — `gh` and `osc` still read their own auth files when called from Bash sub-shells.

## Test harness

`tests/hooks/run-all.sh` fires synthetic tool-input JSON at each hook and asserts exit codes. Currently 46 cases (26 upstream-action, 16 credential-leak, 2 scrub-env, 2 negative scrub-env).

Run before any orchestrator code can be trusted:

```bash
make test-hooks
```

Output:
```
== block-upstream-actions.sh ==
  ok   ALLOW gh pr list
  ok   ALLOW read-only gh pr view ...
  ...
  ok   DENY  gh pr create against upstream
  ...
============================================
  PASS: 169   FAIL: 0
============================================
```

If any test fails, fix the hook before running the orchestrator. The hooks are the only thing preventing irreversible damage in autonomous mode.

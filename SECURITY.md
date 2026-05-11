# Security Model

This agent runs autonomously on a schedule with `--permission-mode=acceptEdits`. That is only safe because of the security model below. Every assumption here is enforced by a hook or permission rule, not by instructions to the LLM.

## Credentials policy

**The agent never sees a credential.** It calls authenticated CLIs (`gh`, `osc`, `git`) which read their own on-disk auth state. The agent has no path to those files.

| Credential | Where it lives | How the agent uses it |
|---|---|---|
| GitHub token | `~/.config/gh/hosts.yml` (encrypted by gh) | Via `gh` CLI — agent never reads the file |
| OBS password | `~/.config/osc/oscrc` (passx-encoded by osc) | Via `osc` CLI — agent never reads the file |
| SSH key | `~/.ssh/id_*` + ssh-agent | Via `git push` — agent never reads keys |
| GPG | `~/.gnupg/*` | Not used by the agent |

Enforced by:

- **Permission deny rules** in `.claude/settings.json` block `Read` against credential paths.
- **`block-credential-leak.sh` PreToolUse hook** blocks `cat`/`grep`/`head`/`tail`/`less` against the same paths and blocks `env`/`printenv`/`echo $X` for any X matching `*TOKEN*|*PASSWORD*|*SECRET*|*API_KEY*`.
- **`scrub-env.sh` SessionStart hook** unsets `GITHUB_TOKEN`, `GH_TOKEN`, `OSC_PASSWORD`, `OSC_USER`, `AWS_*`, `AZURE_*`, `GCP_*` from the agent's environment. The on-disk credentials remain for `gh`/`osc` to consume.

## Initial setup is interactive — the agent does not authenticate

`./bin/setup.sh` is the only place credentials enter the host. The script:

1. Prints the checklist of what's needed.
2. Runs `gh auth login` interactively — you paste a token or do the device flow in your browser. The agent is not running.
3. Runs `osc -A https://api.opensuse.org whois` once to trigger osc's interactive password prompt. You type it; osc encodes it; the agent is not running.
4. Verifies with `gh auth status` and `osc whois` (read-only — no tokens printed).
5. Writes a public-info-only `state/.setup-complete.json` (GitHub login, OBS user, timestamps; no secrets).

`/lsr-maintainer doctor` repeats step 4 on every scheduled run. If posture drifts (token revoked, oscrc missing, scopes changed), the run aborts and writes a PENDING_REVIEW entry pointing you back at `./bin/setup.sh`.

## Write-side guarantees

The agent can write to:

- Local git worktrees under `state/worktrees/` (sandboxed).
- Your fork branches (`Spectro34/<role>` on branches matching `fix/*`).
- OBS personal branches (`home:Spectro34:branches:*`).
- Local files in this workspace's `state/`, `state/cache/`, and `~/.cache/lsr-maintainer/`.

The agent **cannot**:

- Open or merge a PR (`gh pr create`, `gh pr merge` — denied + hook-blocked).
- Create or delete a GitHub repo (`gh repo create`, `gh repo delete` — denied).
- Submit an OBS request (`osc sr`, `osc submitrequest`, `osc submitreq`, `osc createrequest` — denied + hook-blocked).
- Copy or delete OBS packages (`osc copypac`, `osc delete`, `osc rdelete`, `osc undelete` — denied).
- Push to a non-fork remote (`git push upstream`, `git push --force` — denied + hook resolves remote URL to confirm).
- Run `sudo`, install OS packages (`zypper`, `apt`, `dnf` — denied; the agent emits the command for you to run).
- Read credentials (see above).

The `block-upstream-actions.sh` hook re-parses each Bash command (handles `;`, `&&`, `||`, env-var prefixes, `--repo OWNER/NAME` flags, alias expansion) and resolves git remotes via `git remote get-url` before allowing a push. A clever model that tries `git push or"igin"` or `gh pr create --repo "Spectro34/sudo --repo linux-system-roles/sudo"` is blocked by the parser-level hook even though the regex permission rule might miss it.

## Threat model

**Defended against:**

- LLM mistakes — misreading instructions and trying to act outside its sandbox.
- Prompt injection from external content (upstream commit messages, PR review bodies, package build logs containing crafted text that tries to manipulate the agent).
- Accidental upstream pushes from misconfigured remotes (e.g., `origin` pointing at upstream).
- Loss of credentials via accidental log capture or context-leak.

**NOT defended against (out of scope):**

- A malicious user with shell access on the same machine — they can run anything the agent can run, and more.
- A compromised `gh` or `osc` binary — the agent trusts the system's CLIs.
- An attacker with physical access to the host or its disk — they can read `~/.config/osc/oscrc` directly.
- A malicious upstream maintainer who merges a backdoored commit into a role and waits for the agent to pull it. (The review board provides some defense; tox tests provide more; ultimately you review patches before opening PRs.)

## Audit trail

Every scheduled run writes a full transcript to `~/.cache/lsr-maintainer/<timestamp>.jsonl` (stream-json format). This includes every tool call, every sub-agent invocation, and every hook decision. Use it for postmortem.

Hook-block events also append to `~/.cache/lsr-maintainer/security.log` with the attempted command and the reason it was blocked.

## Revocation

| To revoke | Run |
|---|---|
| Stop scheduled runs | `make uninstall` (removes cron, keeps workspace + state) |
| Revoke GitHub access | `gh auth logout` (independent of this workspace) |
| Revoke OBS access | edit `~/.config/osc/oscrc` (independent of this workspace) |
| Nuke local state | `make distclean` (state, worktrees, tox venv — keeps source) |
| Full uninstall | `make uninstall && rm -rf ~/path/to/lsr-maintainer-workspace` |

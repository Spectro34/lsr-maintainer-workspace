# lsr-maintainer-workspace

A scheduled, autonomous Claude Code agent that maintains your **Linux System Roles (LSR) forks** and the **`ansible-linux-system-roles` OBS package** for SLE 16 — without ever opening an upstream PR or OBS submit request on its own.

**Identity-agnostic.** No GitHub username or OBS user is hardcoded. Fork this workspace, run `./bin/setup.sh`, and it operates under YOUR detected `gh api user` / `osc whois` identity. The detected values land in `state/config.json` (gitignored); hooks and sub-agents read that file at runtime. Pre-init, all writes are blocked — uninitialized workspaces are safer than misconfigured ones.

This workspace pulls together everything needed to run the agent end-to-end on any machine: the orchestrator skill, deterministic security hooks, setup scripts, and the dependent projects.

**Dependent projects:**
- `projects/obs-package-skill/` — git submodule (autonomous OBS package maintenance skill)
- `projects/osc-mcp/` — git submodule (osc MCP server)
- `lsr-agent` — **inlined** at `.claude/skills/lsr-agent/`. Was previously a symlink to a `skill-lifecycle-framework` subdirectory; decoupled to make the workspace standalone. See [docs/feature-fork-sync.md](docs/feature-fork-sync.md) for the LSR knowledge surface and [docs/component-projects.md](docs/component-projects.md) for the migration history.

## What it does

- **Maintains your LSR fork branches** — watches upstream `linux-system-roles/*` for drift; when upstream touches a file you patched, rebases your patch and runs the regression matrix on the relevant SUSE targets.
- **Auto-fixes PR review feedback** — when an upstream reviewer leaves comments on one of your open PRs, drafts a fix, passes it through a 4-perspective review board (correctness, cross-OS impact, upstream-style, security), runs the tox regression matrix, and pushes to your fork branch. You re-request review.
- **Maintains the OBS package** — delegates to the embedded `obs-package-skill` to diagnose build failures on `${obs_branch_project}`, applies fixes iteratively, never submits a request.
- **Enables new roles on demand** — you say "add `squid` for SLE 16," it does the full port (vars/Suse.yml, set_vars.yml wiring, meta, tests, regression matrix) and stages the OBS spec bump.
- **Bootstraps a fresh VM** — `./bin/setup.sh && make install` is the entire onboarding.

## What it will never do

- Open a PR to any upstream repo (`gh pr create` blocked at the hook layer).
- Submit an OBS request (`osc sr` / `submitrequest` blocked).
- Push to any remote that is not `${github_user}/*` or `${obs_user_root}:*`.
- Read your credentials (`~/.config/osc/oscrc`, `~/.netrc`, `~/.ssh/id_*`, `GITHUB_TOKEN`, etc. — all blocked).
- Use sudo or change system packages without surfacing the exact command for you to run.

See [SECURITY.md](SECURITY.md) for the full threat model and hook semantics.

## Quickstart (new machine)

Manual-only by default. Cron is opt-in — you run the agent when you want.

### One-time setup

```bash
git clone --recurse-submodules git@github.com:Spectro34/lsr-maintainer-workspace.git
cd lsr-maintainer-workspace
./bin/setup.sh                      # interactive — you type gh + osc credentials directly
make install                         # host prep (dirs, venv, submodules). NO cron.
bash bin/doctor.sh                   # green/red posture check
```

That's it. No cron entry was installed; the agent does nothing until you tell it to.

### Run the agent (live, on demand)

```bash
make run
```

What happens:
- Runs `bin/lsr-maintainer-run.sh` (the same script cron would use)
- Permission mode: `--permission-mode acceptEdits` (hooks still active — see [SECURITY.md](SECURITY.md))
- Live narration scrolls in your terminal as the agent works
- Full transcript saved to `var/log/<timestamp>.jsonl` for audit + cost tracking
- Writes `state/PENDING_REVIEW.md` when done

To stop it: `Ctrl-C`. The orchestrator's pidfile + state-lock will recover cleanly on the next run.

### Read the report

```bash
make pending     # opens state/PENDING_REVIEW.md in $PAGER
```

Sections you'll see: 🚀 Ready to ship, 👀 Upstream review needs your eyes, 🏗 OBS package status, 🆕 New role ready, 🔱 Fork sync, 📋 Enablement queue, 🩺 Bootstrap status, ❗ Manual triage needed.

### Other one-liners

```bash
make doctor                       # fast bash posture check (<1s)
make dry-run                       # queue-refresh pipeline only; writes nothing
make enable-role ROLE=logging      # add a role to the SLE-enablement queue
make ack-enablement ROLE=logging   # remove a role from the queue
make status-all                    # workspace + submodule state
make test                          # 218 hook tests + orchestrator self-tests
```

### Schedule it later (optional)

If you decide you want nightly autonomous runs:

```bash
make install-cron      # installs a 03:07-local cron entry (idempotent)
```

To stop scheduled runs:
```bash
make uninstall-cron    # removes the cron entry; workspace + state untouched
```

To pause without removing the cron entry (e.g., on vacation):
```bash
touch state/.halt      # next cron tick exits cleanly without spawning the agent
rm state/.halt         # resume
```

### Where things live

All runtime data — QEMU images, role clones, tox venv, OBS checkout, worktrees, audit logs — lives in `./var/` inside this workspace. `rm -rf var/` is a full reset; `make distclean` wipes it for you. **No external dependencies** beyond standard system tools (`gh`, `osc`, `git`, `make`, `jq`, QEMU) — everything else stays inside the workspace tree.

See [SETUP.md](SETUP.md) for prerequisites (system packages, GitHub account, OBS membership, QEMU images) and Day-2 configuration (enablement queue, notifications, host-lock).

## Features

| Feature | Doc |
|---|---|
| PR-review auto-fix loop | [docs/feature-pr-feedback.md](docs/feature-pr-feedback.md) |
| New-role enablement | [docs/feature-new-role-enablement.md](docs/feature-new-role-enablement.md) |
| SLE role enablement queue | [docs/feature-role-enablement.md](docs/feature-role-enablement.md) |
| Auto-fork + nightly fork sync | [docs/feature-fork-sync.md](docs/feature-fork-sync.md) |
| OBS package maintenance | [docs/feature-obs-maintenance.md](docs/feature-obs-maintenance.md) |
| Self-bootstrap into fresh VM | [docs/feature-bootstrap.md](docs/feature-bootstrap.md) |
| Cost tracking per run | [docs/feature-cost-tracking.md](docs/feature-cost-tracking.md) |
| Out-of-band notifications | [docs/feature-notifications.md](docs/feature-notifications.md) |
| Same-machine host lock | [docs/feature-host-lock.md](docs/feature-host-lock.md) |

## Components

| Component | Doc |
|---|---|
| State file schema | [docs/component-state-file.md](docs/component-state-file.md) |
| Security hooks | [docs/component-hooks.md](docs/component-hooks.md) |
| Sub-agents | [docs/component-subagents.md](docs/component-subagents.md) |
| Managed projects (submodules) | [docs/component-projects.md](docs/component-projects.md) |
| Workspace config (`state/config.json`) | [docs/component-config.md](docs/component-config.md) |

## Architecture

See [ARCHITECTURE.md](ARCHITECTURE.md) for the full dataflow and per-component design.

## Status

This workspace is under active build-out. Track progress in `state/PENDING_REVIEW.md` (once the agent has run) or in commit history.

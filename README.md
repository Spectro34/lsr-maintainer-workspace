# lsr-maintainer-workspace

A scheduled, autonomous Claude Code agent that maintains your **Linux System Roles (LSR) forks** and the **`ansible-linux-system-roles` OBS package** for SLE 16 — without ever opening an upstream PR or OBS submit request on its own.

**Identity-agnostic.** No GitHub username or OBS user is hardcoded. Fork this workspace, run `./bin/setup.sh`, and it operates under YOUR detected `gh api user` / `osc whois` identity. The detected values land in `state/config.json` (gitignored); hooks and sub-agents read that file at runtime. Pre-init, all writes are blocked — uninitialized workspaces are safer than misconfigured ones.

This workspace pulls together everything needed to run the agent end-to-end on any machine: the orchestrator skill, deterministic security hooks, setup scripts, and the dependent projects.

**Dependent projects:**
- `projects/obs-package-skill/` — git submodule (autonomous OBS package maintenance skill)
- `projects/osc-mcp/` — git submodule (osc MCP server)
- `projects/lsr-agent/` — **symlink** to `../../rnd/lsr-agent/` (deep LSR knowledge skill). This subdir currently lives inside the `skill-lifecycle-framework` repo, so a fresh clone of this workspace requires that repo to be cloned as a sibling at `~/github/rnd/`. Carve-out to its own submodule is a tracked TODO in [projects/README.md](projects/README.md). `./bin/install-deps.sh` fails immediately if the symlink dangles.

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

```bash
# 0. lsr-agent dependency (until it's carved out into its own repo).
mkdir -p ~/github/rnd && cd ~/github/rnd
git clone <skill-lifecycle-framework-fork-url>  # provides ~/github/rnd/lsr-agent/

# 1. The workspace itself
cd ~/github && git clone --recurse-submodules <workspace-url> lsr-maintainer-workspace
cd lsr-maintainer-workspace
./bin/setup.sh                      # interactive — you authenticate gh and osc yourself
make install                         # idempotent host prep + cron install
bash bin/doctor.sh                   # fast green/red posture check (no claude -p)
make dry-run                         # see what tonight would do, change nothing
```

All runtime data — QEMU images, role clones, tox venv, OBS checkout, worktrees, audit logs — lives in `./var/` inside this workspace. `rm -rf var/` is a full reset; `make distclean` wipes it for you. The only external dependency is the `projects/lsr-agent` symlink (see step 0); everything else stays inside the workspace tree.

See [SETUP.md](SETUP.md) for prerequisites (system packages, GitHub account, OBS membership, QEMU images).

## Daily usage

Each morning, read:

```bash
make pending     # less state/PENDING_REVIEW.md
```

Anything ready to ship will be in the "Ready to ship" section with a one-line summary; you `gh pr create` it yourself. Anything that needs human triage is under "Manual triage needed."

Other useful one-liners:

```bash
make doctor                  # fast bash posture check (<1s; suitable for cron pre-flight)
make doctor-llm              # LLM-driven verbose check (slower, narrative)
make dry-run                 # exercise the queue-refresh pipeline; write nothing
make run                     # full nightly path on demand
make enable-role ROLE=squid  # enqueue a new-role port
make status-all              # workspace + submodule state
make test                    # 169 hook tests + orchestrator self-tests
```

To stop the agent: `make uninstall` removes the cron entry and leaves everything else intact.

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

# lsr-maintainer-workspace

A scheduled, autonomous Claude Code agent that maintains your **Linux System Roles (LSR) forks** and the **`ansible-linux-system-roles` OBS package** for SLE 16 — without ever opening an upstream PR or OBS submit request on its own.

This workspace pulls together everything needed to run the agent end-to-end on any machine: the orchestrator skill, deterministic security hooks, setup scripts, and the dependent projects (`lsr-agent` knowledge skill, `obs-package-skill`, `osc-mcp` MCP server) as **git submodules** so they stay independently versioned but get managed from one place.

## What it does

- **Maintains your LSR fork branches** — watches upstream `linux-system-roles/*` for drift; when upstream touches a file you patched, rebases your patch and runs the regression matrix on the relevant SUSE targets.
- **Auto-fixes PR review feedback** — when an upstream reviewer leaves comments on one of your open PRs, drafts a fix, passes it through a 4-perspective review board (correctness, cross-OS impact, upstream-style, security), runs the tox regression matrix, and pushes to your fork branch. You re-request review.
- **Maintains the OBS package** — delegates to the embedded `obs-package-skill` to diagnose build failures on `home:Spectro34:branches:devel:sap:ansible`, applies fixes iteratively, never submits a request.
- **Enables new roles on demand** — you say "add `squid` for SLE 16," it does the full port (vars/Suse.yml, set_vars.yml wiring, meta, tests, regression matrix) and stages the OBS spec bump.
- **Bootstraps a fresh VM** — `./bin/setup.sh && make install` is the entire onboarding.

## What it will never do

- Open a PR to any upstream repo (`gh pr create` blocked at the hook layer).
- Submit an OBS request (`osc sr` / `submitrequest` blocked).
- Push to any remote that is not `Spectro34/*` or `home:Spectro34:*`.
- Read your credentials (`~/.config/osc/oscrc`, `~/.netrc`, `~/.ssh/id_*`, `GITHUB_TOKEN`, etc. — all blocked).
- Use sudo or change system packages without surfacing the exact command for you to run.

See [SECURITY.md](SECURITY.md) for the full threat model and hook semantics.

## Quickstart (new machine)

```bash
git clone --recurse-submodules <workspace-url> lsr-maintainer-workspace
cd lsr-maintainer-workspace
./bin/setup.sh                      # interactive — you authenticate gh and osc yourself
make install                         # idempotent host prep + cron install
claude -p "/lsr-maintainer doctor"   # green/red posture check
make dry-run                         # see what tonight would do, change nothing
```

See [SETUP.md](SETUP.md) for prerequisites (system packages, GitHub account, OBS membership, QEMU images).

## Daily usage

Each morning, read:

```bash
make pending     # less state/PENDING_REVIEW.md
```

Anything ready to ship will be in the "Ready to ship" section with a one-line summary; you `gh pr create` it yourself. Anything that needs human triage is under "Manual triage needed."

To stop the agent: `make uninstall` removes the cron entry and leaves everything else intact.

## Features

| Feature | Doc |
|---|---|
| PR-review auto-fix loop | [docs/feature-pr-feedback.md](docs/feature-pr-feedback.md) |
| New-role enablement | [docs/feature-new-role-enablement.md](docs/feature-new-role-enablement.md) |
| OBS package maintenance | [docs/feature-obs-maintenance.md](docs/feature-obs-maintenance.md) |
| Self-bootstrap into fresh VM | [docs/feature-bootstrap.md](docs/feature-bootstrap.md) |

## Components

| Component | Doc |
|---|---|
| State file schema | [docs/component-state-file.md](docs/component-state-file.md) |
| Security hooks | [docs/component-hooks.md](docs/component-hooks.md) |
| Sub-agents | [docs/component-subagents.md](docs/component-subagents.md) |
| Managed projects (submodules) | [docs/component-projects.md](docs/component-projects.md) |

## Architecture

See [ARCHITECTURE.md](ARCHITECTURE.md) for the full dataflow and per-component design.

## Status

This workspace is under active build-out. Track progress in `state/PENDING_REVIEW.md` (once the agent has run) or in commit history.

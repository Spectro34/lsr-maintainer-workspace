# Component: Managed projects (submodules)

Each project in `projects/` is its own repo with its own commits, remotes, and CI. The workspace pins each via `.gitmodules`. Pin updates happen via `make pull-all` + commit.

## Current projects

### `projects/obs-package-skill/` — submodule

- **Upstream**: `git@github.com:<obs-package-skill source repo>.git`
- **What it provides**: Autonomous OBS package maintenance skill. Phase 0–4 workflow with built-in "never osc sr" guarantee.
- **Used by**: `obs-package-maintainer` sub-agent (delegates entirely).
- **When to bump pin**: when obs-package-skill ships a fix or new failure-pattern detector you want.
- **How to update**:
  ```bash
  cd projects/obs-package-skill && git pull origin main
  cd ../.. && git add projects/obs-package-skill && git commit -m "Bump obs-package-skill pin"
  ```

### `projects/osc-mcp/` — submodule

- **Upstream**: `git@github.com:<osc-mcp fork>.git`
- **What it provides**: The osc MCP server. Workspace's `.mcp.json` (when added) points at this checkout so the MCP server runs from a pinned commit.
- **Used by**: `obs-package-maintainer` via Skill() → obs-package-skill → MCP tools.
- **When to bump pin**: when osc-mcp adds new tools or fixes bugs.

### `lsr-agent/` — inlined skill (not a submodule)

- **Current state**: lives in-tree at `.claude/skills/lsr-agent/`. Discovered by Claude Code automatically as a project-scoped skill (name `lsr-agent`). No external dependency, no submodule, no symlink.
- **What it provides**: Deep `lsr-agent` skill knowledge (Role Status Matrix, SUSE pkg mappings, set_vars pattern, tox infra, upstream PR status, known bugs) + 3 specialist sub-agents (`check-suse-support`, `upstream-diff`, `test-role`) + a 164KB research knowledge base at `.claude/skills/lsr-agent/LSR_RESEARCH.md`.
- **Used by**: orchestrator (via `Skill(skill="lsr-agent", ...)`), `bug-fix-implementer`, `new-role-enabler`, all 5 reviewers.
- **History**: previously a symlink to `~/github/rnd/lsr-agent/` (a subdirectory of the user's `skill-lifecycle-framework` fork). Decoupled to make the workspace fully standalone — a single `git clone --recurse-submodules` is the entire onboarding. The append-only session log (`LSR_PROGRESS.md`) moved to `state/LSR_PROGRESS.md` (gitignored) to match the existing state-file pattern.

### `projects/ansible-host-scripts/` — not yet wired

- **Planned mechanism**: submodule pointing at a new `${github_user}/lsr-host-scripts` repo.
- **What it would provide**: `lsr-test.sh`, `run-all-tests.sh`, `retest-failing.sh`, `patch-tox-lsr.sh`, `cleanup-suseconnect.yml` — currently expected at `<paths.host_scripts>/` (default `./var/ansible/scripts/`).
- **Until then**: bootstrap-runner populates `<paths.host_scripts>/` (cloning the eventual repo, or symlinking from a pre-existing checkout the operator has on the host).

## Workspace ops across all projects

```bash
make status-all      # per-project git status one-liner
make pull-all        # fetch latest from each submodule's tracking branch
make sync-projects   # pull + commit pin bumps if anything moved
```

## When to descend into a sub-project

For normal agent operation: never. The Makefile orchestrates everything from the workspace root.

For development of a sub-project itself: cd into it, work normally, push to its own remote, then `make sync-projects` at the workspace level to update the pin.

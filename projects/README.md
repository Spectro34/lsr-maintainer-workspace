# Managed projects

This directory holds the dependent projects that the orchestrator integrates with. Each is independently versioned and developed; the workspace pins specific refs.

## Current state

| Project | Mechanism | Source | Notes |
|---|---|---|---|
| `obs-package-skill/` | git submodule | `<obs-package-skill source repo>` | Autonomous OBS package maintenance skill |
| `osc-mcp/` | git submodule | `<osc-mcp fork>` | osc MCP server (the workspace's `.mcp.json` points here) |
| `lsr-agent/` | **symlink** → `../../rnd/lsr-agent/` | (subdir of `<your fork of skill-lifecycle-framework>`) | **TODO: carve out into its own repo** |
| `ansible-host-scripts/` | not yet wired | (lives at `~/github/ansible/scripts/`) | Bootstrap symlinks these into expected paths |

## Carving out `lsr-agent`

The `lsr-agent` skill currently lives inside the `skill-lifecycle-framework` repo at `~/github/rnd/lsr-agent/`. To make the workspace fully portable, we need its own repo:

```bash
# Inside ~/github/rnd:
git subtree split --prefix=lsr-agent -b lsr-agent-extract
# Push the extracted branch to a new repo:
gh repo create ${github_user}/lsr-agent --public --source=. --remote=lsr-agent-upstream
git push lsr-agent-upstream lsr-agent-extract:main

# Then inside the workspace:
cd ~/github/lsr-maintainer-workspace
rm projects/lsr-agent           # remove symlink
git submodule add git@github.com:${github_user}/lsr-agent.git projects/lsr-agent
git commit -am "Promote lsr-agent symlink to submodule"
```

Until that's done, anyone cloning this workspace onto a different machine needs to also clone `<your fork of skill-lifecycle-framework>` at `~/github/rnd/` so the symlink resolves. The `bootstrap-runner` sub-agent surfaces this as a PENDING entry on hosts where the symlink target is missing.

## Updating pins

```bash
make pull-all        # fetch latest from each submodule's tracking branch
make sync-projects   # if anything moved, commit the new SHAs into the workspace
```

# Component: Workspace config (`state/config.json`)

The workspace is **identity-agnostic** until `./bin/setup.sh` runs. After init, a single file `state/config.json` holds the detected GitHub user, OBS user, paths, schedule, and target glob patterns. All hooks and sub-agents read from this file — there are no hardcoded usernames or namespaces in the codebase. Fork the workspace, run `./bin/setup.sh`, get a workspace that operates under YOUR account.

## Schema

```json
{
  "version": 1,
  "github": {
    "user":            "alice",
    "fork_pattern":    "{user}/{role}",
    "fork_branch":     "fix/suse-support",
    "upstream_orgs":   ["linux-system-roles"],
    "community_orgs":  ["geerlingguy", "robertdebock", "bertvv", "mrlesmithjr"],
    "suse_org":        "SUSE"
  },
  "obs": {
    "user":                    "alice123",
    "personal_project_root":   "home:alice123",
    "branch_project_pattern":  "home:{user}:branches:{source}",
    "source_project":          "devel:sap:ansible",
    "package_name":            "ansible-linux-system-roles",
    "api_url":                 "https://api.opensuse.org"
  },
  "paths": {
    "iso_dir":           "~/iso",
    "ansible_root":      "~/github/ansible",
    "lsr_clones_root":   "~/github/linux-system-roles",
    "worktrees_root":    "~/github/.lsr-maintainer-worktrees",
    "tox_venv":          "~/github/ansible/testing/tox-lsr-venv",
    "host_scripts":      "~/github/ansible/scripts",
    "obs_checkout_root": "~/github/ansible"
  },
  "test_targets": {
    "default_set":            ["sle-16", "leap-16.0", "sle-15-sp7", "leap-15.6"],
    "fallback":               {"sle-16": "leap-16.0"},
    "image_globs":            {"sle-16": ["SLES-16.0-*..."], ...},
    "ansible_core_versions":  {"sle-16": "2.20", ...},
    "auto_download":          {"leap-16.0": {"url": "...", "size_mb": 330}}
  },
  "schedule": {
    "cron_time":               "7 3 * * *",
    "time_budget_minutes":     90,
    "per_item_budgets":        {"pr_feedback_min": 15, ...}
  },
  "review_board": {
    "max_concern_iterations":  2,
    "concurrent_cap":          6
  }
}
```

## How identity is detected

`bin/setup.sh` step 5 calls `orchestrator.config.detect_identity()` which runs (read-only):

- `gh api user --jq .login` → `github.user`
- `osc whois` (first whitespace-separated token) → `obs.user`
- `git config --global user.email` / `user.name` → checked, surfaced as PENDING if empty

No credentials are read — only public login names from the authenticated CLIs.

The OBS personal project root is computed: `f"home:{obs.user}"`. Override in config if your OBS setup is non-standard.

## Pre-init safety

If `state/config.json` doesn't exist or has `github.user == ""`, the security hooks treat **all** GitHub URLs and OBS projects as upstream — blocking every write. This means an uninitialized workspace is safer than a misconfigured one: nothing destructive can happen before `./bin/setup.sh` runs.

The hook test harness verifies this in the `== pre-init safety ==` section.

## Per-host overrides

Config is gitignored (in `state/`). Different machines running the same workspace have different configs. Useful when you want:

- A laptop config with `auto_download_leap = false` (metered network).
- A workstation config with a different `source_project`.
- A CI runner config with extra `community_orgs` for testing.

## Reading config from hooks (bash)

```bash
CONFIG_JSON="${LSR_CONFIG_OVERRIDE:-${WORKSPACE_ROOT}/state/config.json}"
if [ -f "$CONFIG_JSON" ] && command -v jq >/dev/null 2>&1; then
  ALLOW_GH_OWNER="$(jq -r '.github.user // ""' "$CONFIG_JSON")"
fi
```

The `LSR_CONFIG_OVERRIDE` env var lets the test harness point hooks at a stub config.

## Reading config from Python (sub-agents)

```python
from orchestrator.config import load_config, github_user, fork_repo, obs_branch_project

cfg = load_config("state/config.json")
print(github_user(cfg))                # "alice"
print(fork_repo(cfg, "sudo"))           # "alice/sudo"
print(obs_branch_project(cfg))          # "home:alice123:branches:devel:sap:ansible"
```

## Updating config

Edit `state/config.json` directly, OR re-run `./bin/setup.sh` to refresh from detected identity (existing overrides like `source_project` are preserved via `init_from_identity()`).

## Schema evolution

`CONFIG_VERSION` in `orchestrator/config.py` is bumped when the schema changes incompatibly. `load_config()` runs `_migrate()` to upgrade older configs in place. Missing fields are always filled in from `default_config()` (forward-compatible).

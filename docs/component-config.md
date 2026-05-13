# Component: Workspace config (`state/config.json`)

The workspace is **identity-agnostic** until `./bin/setup.sh` runs. After init, a single file `state/config.json` holds the detected GitHub user, OBS user, paths, schedule, and target glob patterns. All hooks and sub-agents read from this file — there are no hardcoded usernames or namespaces in the codebase. Fork the workspace, run `./bin/setup.sh`, get a workspace that operates under YOUR account.

## Schema

```json
{
  "version": 3,
  "github": {
    "user":            "alice",
    "fork_pattern":    "{user}/{role}",
    "fork_branch":     "fix/suse-support",
    "upstream_orgs":   ["linux-system-roles"],
    "community_orgs":  ["geerlingguy", "robertdebock", "bertvv", "mrlesmithjr"],
    "suse_org":        "SUSE",
    "tracked_extra_roles": [
      "sudo", "kernel_settings", "ansible-sshd", "network", "logging",
      "metrics", "postgresql", "ad_integration"
    ]
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
    "iso_dir":           "{workspace}/var/iso",
    "ansible_root":      "{workspace}/var/ansible",
    "lsr_clones_root":   "{workspace}/var/clones",
    "worktrees_root":    "{workspace}/var/worktrees",
    "tox_venv":          "{workspace}/var/venv/tox-lsr",
    "host_scripts":      "{workspace}/var/ansible/scripts",
    "obs_checkout_root": "{workspace}/var/ansible",
    "log_dir":           "{workspace}/var/log",
    "cache_dir":         "{workspace}/var/cache"
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
  },
  "enablement": {
    "queue":                ["logging", "kdump"],
    "auto_enqueue_per_run": 1,
    "default_target":       "sle16"
  },
  "fork_sync": {
    "auto_push":   true,
    "max_per_run": 5
  },
  "security": {
    "enforce_host_lock": false
  },
  "notify": {
    "backend":  "",
    "events":   ["reject", "anomaly", "doctor_red", "halt", "daily_summary", "host_lock_mismatch"],
    "ntfy":     {"url": "", "priority": "default"},
    "email":    {"to": ""},
    "webhook":  {"url": ""}
  },
  "anomaly": {
    "enabled":               true,
    "default_sigma":         3.0,
    "min_samples":           7,
    "history_days":          14,
    "auto_halt_on_anomaly":  false
  }
}
```

## Fields you'll likely customize

Most of the defaults are sensible, but these are the typical overrides:

| Field | Why customize |
|---|---|
| `github.tracked_extra_roles` | Roles you maintain on personal forks that AREN'T in the OBS package manifest. Defaults to the canonical 8 (sudo, kernel_settings, ansible-sshd, network, logging, metrics, postgresql, ad_integration). Add hackweek/community roles here (squid, apache, nfs, samba, kea-dhcp, bind, snapper, tftpd). |
| `obs.source_project` | Default `devel:sap:ansible`. Change if you maintain the package in a different devel project. |
| `obs.package_name` | Default `ansible-linux-system-roles`. |
| `schedule.cron_time` | Default `7 3 * * *` (03:07 local). `install-cron.sh` reads this if present. |
| `paths.iso_dir` | Default `{workspace}/var/iso`. Change if QEMU images live elsewhere (e.g. `/mnt/big/iso`). |
| `paths.log_dir` | Default `{workspace}/var/log`. Hooks write `security.log` and the cron entry writes `<timestamp>.jsonl` transcripts here. |
| `paths.cache_dir` | Default `{workspace}/var/cache`. Per-package context for `obs-package-skill` (`obs-packages/context/<pkg>.md`) lives under here. |
| `test_targets.fallback` | Map target → fallback target when image is missing. Default `{sle-16: leap-16.0}`. |
| `test_targets.auto_download.leap-16.0` | URL and size_mb for auto-fetch. Set to `null` to disable. |
| `review_board.max_concern_iterations` | Default 2. How many re-iterations a `bug-fix-implementer` patch may go through before falling out to manual triage. |
| `enablement.queue` | User-editable list of role names to enable for SLE 16. Nightly run pops `auto_enqueue_per_run` per night. See [docs/feature-role-enablement.md](feature-role-enablement.md). |
| `fork_sync.auto_push` | Fast-forwarded fork mains auto-push to `${github_user}/<role>:main`. Default `true`. See [docs/feature-fork-sync.md](feature-fork-sync.md). |
| `fork_sync.max_per_run` | Cap on roles handled per nightly run. Default 5. |
| `security.enforce_host_lock` | Pin the workspace to its setup host. Default `false`. See [docs/feature-host-lock.md](feature-host-lock.md). |
| `notify.backend` | `ntfy`/`email`/`webhook`/`""`. See [docs/feature-notifications.md](feature-notifications.md). |

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

## Path resolution: the `{workspace}` placeholder

Every value under `paths.*` may contain the literal substring `{workspace}` — `orchestrator.config.get_path(cfg, key)` substitutes it with the workspace root (the parent dir of `orchestrator/`). It also calls `expanduser`, so `~/`-relative paths work too. Absolute paths (e.g. `/mnt/big/iso`) pass through untouched.

```python
from orchestrator.config import load_config, get_path
cfg = load_config("state/config.json")
get_path(cfg, "iso_dir")    # → "/home/alice/github/lsr-maintainer-workspace/var/iso"
```

Shell side: `source bin/_lib/paths.sh` then `lsr_path iso_dir`. The same resolver is used everywhere — config defaults, scripts, hooks, and skill MD agents all agree on the same canonical paths.

**Migration:** `_migrate()` upgrades v1 configs (which had `~/iso`, `~/github/ansible/...` literals) to the v2 `{workspace}` placeholders, but ONLY for values that still match the legacy defaults. Custom overrides are preserved verbatim. v3 just adds new sections (`enablement`, `fork_sync`, `security`) via `_merge_defaults` — no field rewrites.

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

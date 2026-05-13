#!/usr/bin/env bash
# bin/_lib/paths.sh — shell-side path resolver.
#
# Source this from any bin/*.sh script that needs to read paths.* from
# state/config.json. Sets:
#   WORKSPACE_ROOT — absolute path to the workspace (computed from this file's location)
#
# Defines:
#   lsr_path <key>      — print resolved absolute path for paths.<key>
#   lsr_ensure_var      — mkdir -p the standard var/* subdirs (idempotent)
#
# All paths resolve through orchestrator.config.get_path(), so the rule is:
# config.json values may be {workspace}-relative, ~-relative, or absolute, and
# they all come out as absolute here.

# Resolve workspace root from this file's location (bin/_lib/paths.sh → workspace).
WORKSPACE_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
export WORKSPACE_ROOT

# Print the resolved absolute path for a paths.<key> entry.
# Usage: iso="$(lsr_path iso_dir)"
lsr_path() {
  local key="$1"
  python3 - "$WORKSPACE_ROOT" "$key" <<'PY'
import os, sys
ws, key = sys.argv[1], sys.argv[2]
sys.path.insert(0, ws)
from orchestrator.config import load_config, get_path
cfg = load_config(os.path.join(ws, "state/config.json"))
print(get_path(cfg, key, ws))
PY
}

# Create the canonical var/* subdirs idempotently. Called by install-deps.sh
# and by anything that needs to write to var/log/var/cache before the first
# install run has happened.
lsr_ensure_var() {
  local keys=(iso_dir ansible_root lsr_clones_root worktrees_root host_scripts log_dir cache_dir)
  local k p
  for k in "${keys[@]}"; do
    p="$(lsr_path "$k")"
    [[ -n "$p" ]] && mkdir -p "$p"
  done
  # tox_venv parent (the venv itself is created by install-deps.sh, not us).
  local venv_parent
  venv_parent="$(dirname "$(lsr_path tox_venv)")"
  [[ -n "$venv_parent" ]] && mkdir -p "$venv_parent"
}

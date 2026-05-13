#!/usr/bin/env bash
# bin/status-all.sh — per-submodule git status one-liner + workspace status.

set -u

WORKSPACE="$(cd "$(dirname "$0")/.." && pwd)"
cd "$WORKSPACE" || exit 1

printf '== workspace ==\n'
git -C "$WORKSPACE" status --short --branch | head -20

printf '\n== submodules ==\n'
git submodule foreach --quiet '
  cd "$toplevel/$path"
  branch="$(git rev-parse --abbrev-ref HEAD 2>/dev/null)"
  sha="$(git rev-parse --short HEAD 2>/dev/null)"
  dirty=""
  if [ -n "$(git status --porcelain 2>/dev/null)" ]; then dirty=" (dirty)"; fi
  printf "  %-30s  %-25s  %s%s\n" "$name" "$branch" "$sha" "$dirty"
' || true

# (lsr-agent is now inlined at .claude/skills/lsr-agent/ — no longer an external dep)

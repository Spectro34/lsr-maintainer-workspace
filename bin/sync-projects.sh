#!/usr/bin/env bash
# bin/sync-projects.sh — verify on-disk submodule SHAs match the workspace's
# pinned SHAs. Does NOT pull --remote (that's `make submodule-bump` — a
# deliberate operator action). This script is read-only.

set -u

WORKSPACE="$(cd "$(dirname "$0")/.." && pwd)"
cd "$WORKSPACE" || exit 1

# Re-init from pinned SHAs (idempotent; pulls only if the submodule isn't
# checked out yet, doesn't touch already-correct submodules).
git submodule update --init --recursive

# Now verify each submodule is at the SHA the superproject recorded.
fail=0
while read -r mode sha _ path; do
  [[ -z "$path" ]] && continue
  actual="$(git -C "$path" rev-parse HEAD 2>/dev/null || echo '?')"
  if [[ "$sha" != "$actual" ]]; then
    echo "DRIFT: $path"
    echo "  pinned: $sha"
    echo "  actual: $actual"
    fail=1
  else
    echo "ok: $path @ ${sha:0:10}"
  fi
done < <(git ls-tree HEAD | awk '$2=="commit"')

if (( fail )); then
  echo ""
  echo "One or more submodules drifted from the pinned SHA."
  echo "Run 'make pull-all' to reset them to the pin, OR 'make submodule-bump'"
  echo "to deliberately advance and commit a new pin."
  exit 1
fi

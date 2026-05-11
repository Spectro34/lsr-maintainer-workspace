#!/usr/bin/env bash
# bin/sync-projects.sh — pull all submodules to their tracking branch, then
# stage and commit any pin movement in the workspace.

set -u

WORKSPACE="$(cd "$(dirname "$0")/.." && pwd)"
cd "$WORKSPACE" || exit 1

git submodule update --init --remote --recursive

# If submodule pins moved, surface a stageable diff.
if ! git diff --quiet --submodule=log; then
  echo ""
  echo "Submodule pins moved. To commit:"
  echo "  git add projects/"
  echo "  git commit -m \"Bump submodule pins\""
  echo ""
  echo "Diff summary:"
  git diff --submodule=log -- projects/
else
  echo "All submodule pins already current."
fi

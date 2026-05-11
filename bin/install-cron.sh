#!/usr/bin/env bash
# bin/install-cron.sh — idempotent crontab installer.
#
# Usage: install-cron.sh           # install/update the entry
#        install-cron.sh --remove  # remove the entry

set -u

WORKSPACE="$(cd "$(dirname "$0")/.." && pwd)"
RUNNER="$WORKSPACE/bin/lsr-maintainer-run.sh"
MARKER="# lsr-maintainer-workspace"
ENTRY="7 3 * * * ${RUNNER}  ${MARKER}"

REMOVE=0
[[ "${1:-}" == "--remove" ]] && REMOVE=1

current="$(crontab -l 2>/dev/null || true)"
filtered="$(printf '%s\n' "$current" | grep -v -F "$MARKER" || true)"

if (( REMOVE == 1 )); then
  if [[ "$current" == *"$MARKER"* ]]; then
    printf '%s\n' "$filtered" | crontab -
    echo "removed: $MARKER"
  else
    echo "nothing to remove."
  fi
  exit 0
fi

if [[ ! -x "$RUNNER" ]]; then
  echo "ERR: $RUNNER not executable — chmod +x and retry."
  exit 1
fi

# Append the entry to the filtered current crontab.
{ printf '%s\n' "$filtered"; printf '%s\n' "$ENTRY"; } | crontab -
echo "installed:"
echo "  $ENTRY"

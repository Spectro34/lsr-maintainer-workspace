#!/usr/bin/env bash
# bin/install-cron.sh — idempotent crontab installer.
#
# Usage: install-cron.sh           # install/update the entry
#        install-cron.sh --remove  # remove the entry

set -u

WORKSPACE="$(cd "$(dirname "$0")/.." && pwd)"
RUNNER="$WORKSPACE/bin/lsr-maintainer-run.sh"
MARKER="# lsr-maintainer-workspace"

# Detect the user's timezone so the cron entry fires at local time even when
# systemd-cron defaults to UTC. Override via LSR_CRON_TIME ("M H DoM Mon DoW")
# and LSR_CRON_TZ ("Asia/Kolkata" etc.).
CRON_TIME="${LSR_CRON_TIME:-7 3 * * *}"
CRON_TZ="${LSR_CRON_TZ:-$(timedatectl show -p Timezone --value 2>/dev/null || echo '')}"

# Read schedule from state/config.json if available (overridable per-host).
if [[ -f "$WORKSPACE/state/config.json" ]] && command -v jq >/dev/null 2>&1; then
  cfg_time="$(jq -r '.schedule.cron_time // ""' "$WORKSPACE/state/config.json" 2>/dev/null)"
  [[ -n "$cfg_time" ]] && CRON_TIME="$cfg_time"
fi

if [[ -n "$CRON_TZ" ]]; then
  TZ_LINE="CRON_TZ=$CRON_TZ"
  ENTRY="$TZ_LINE
$CRON_TIME ${RUNNER}  ${MARKER}"
else
  TZ_LINE=""
  ENTRY="$CRON_TIME ${RUNNER}  ${MARKER}"
fi

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

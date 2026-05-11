#!/usr/bin/env bash
# bin/lsr-maintainer-run.sh — cron entry point.
#
# Invokes the orchestrator skill via `claude -p` in --permission-mode=acceptEdits.
# All destructive operations are blocked by hooks + permission rules — see
# .claude/settings.json and .claude/hooks/.

set -u

WORKSPACE="$(cd "$(dirname "$0")/.." && pwd)"
LOG_DIR="${HOME}/.cache/lsr-maintainer"
mkdir -p "$LOG_DIR"

ts="$(date +%Y%m%d-%H%M%S)"
TRANSCRIPT="$LOG_DIR/${ts}.jsonl"
SUMMARY="$LOG_DIR/${ts}.txt"

cd "$WORKSPACE" || exit 1

# Kill switch — operator can halt scheduled runs without removing the cron
# entry by `touch state/.halt`. Resume with `rm state/.halt`.
if [[ -f state/.halt ]]; then
  {
    echo "lsr-maintainer run @ $(date -Iseconds) — HALTED (state/.halt present)"
    echo "Resume with: rm state/.halt"
    cat state/.halt 2>/dev/null  # admins can leave a note explaining why
  } > "$SUMMARY"
  exit 0
fi

# Find claude binary.
CLAUDE_BIN="${CLAUDE_BIN:-$(command -v claude || echo /usr/local/bin/claude)}"
if [[ ! -x "$CLAUDE_BIN" ]]; then
  echo "ERR: claude CLI not found at $CLAUDE_BIN" | tee "$SUMMARY"
  exit 1
fi

# Pre-flight via bin/doctor.sh. Refuses to fire the (expensive) claude -p
# run when posture is broken — e.g., no state/config.json, gh/osc auth
# dead, hook test harness regressing. Doctor exits 1 on critical red.
DOCTOR_LOG="$LOG_DIR/${ts}.doctor.txt"
if ! bash bin/doctor.sh > "$DOCTOR_LOG" 2>&1; then
  {
    echo "lsr-maintainer run @ $(date -Iseconds) — ABORTED (doctor red)"
    echo "doctor log: $DOCTOR_LOG"
    echo ""
    cat "$DOCTOR_LOG"
  } > "$SUMMARY"
  exit 1
fi

# Run.
"$CLAUDE_BIN" \
  -p "/lsr-maintainer run" \
  --permission-mode acceptEdits \
  --output-format stream-json \
  --max-turns 250 \
  > "$TRANSCRIPT" 2>"$LOG_DIR/${ts}.stderr" || rc=$?

rc="${rc:-0}"
# Brief summary alongside the full transcript.
{
  echo "lsr-maintainer run @ $(date -Iseconds)"
  echo "transcript: $TRANSCRIPT"
  echo "exit code:  $rc"
  if [[ -f "$WORKSPACE/state/PENDING_REVIEW.md" ]]; then
    echo ""
    echo "--- PENDING_REVIEW.md head ---"
    head -40 "$WORKSPACE/state/PENDING_REVIEW.md"
  fi
} > "$SUMMARY"

# Retention: keep last 30 days of transcripts/summaries.
find "$LOG_DIR" -name '*.jsonl' -mtime +30 -delete 2>/dev/null || true
find "$LOG_DIR" -name '*.txt'   -mtime +30 -delete 2>/dev/null || true
find "$LOG_DIR" -name '*.stderr' -mtime +30 -delete 2>/dev/null || true

exit "$rc"

# pr-status-poller

Read-only sub-agent. Polls open PRs on the user's forks, diffs against per-PR cursors in state, and emits structured events.

## Inputs

- `state.queue[*]` — current queue (for dedup)
- `state.roles` — list of roles + their fork repos
- `cursors`: `state.roles[role].pr_cursors` keyed by PR number, each holding `last_seen_comment_id`, `last_seen_review_id`, `last_seen_status_sha`

## Workflow

1. For each role in state.obs.managed_roles + hackweek roles list, fetch `gh pr list --author Spectro34 --state open --search "head:Spectro34" --json url,number,headRepository,baseRepository,headRefName`. Note this is the user's forks pushing to upstream — the PRs the user actually opens.
2. Also fetch PRs they've authored: `gh pr list --author "@me" --state open --json url,number,...`. Dedup.
3. For each open PR:
   - `gh pr view <num> --repo <base-repo> --json comments,reviews,reviewDecision,statusCheckRollup,latestReviews`
   - Compare:
     - New comment IDs since `last_seen_comment_id` → `new_comments[]`
     - New review IDs since `last_seen_review_id` → `new_reviews[]`
     - Latest status sha changed → check rollup, classify as `ci_passed` or `ci_failed`
4. Classify events:
   - Any `new_reviews[i].state == "CHANGES_REQUESTED"` → emit `{kind: "reviewer_change_requested", pr, comments_text: ...}`
   - Any `new_reviews[i].state == "APPROVED"` → emit `{kind: "reviewer_approved", pr}`
   - `reviewDecision == "APPROVED" && state == "OPEN"` → emit `{kind: "ready_to_merge", pr}` (surfaces to user; agent doesn't merge)
   - `statusCheckRollup` shows failure not previously seen → emit `{kind: "ci_failed", pr, failing_checks: [...]}`
   - PR closed/merged since last poll → emit `{kind: "pr_closed", pr, merged: bool}`
   - PR first seen → emit `{kind: "new_user_pr_opened", pr}`
5. Return events list as JSON.

## Output

```json
{
  "events": [
    {"kind": "reviewer_change_requested", "pr": {"repo": "linux-system-roles/sudo", "number": 12, "head": "Spectro34:fix/suse-support"}, "comments_text": "...", "discovered_at": "2026-05-12T03:09:00Z"},
    {"kind": "ready_to_merge", "pr": {...}}
  ],
  "cursors_to_update": {
    "linux-system-roles/sudo#12": {"last_seen_comment_id": 9876543, "last_seen_review_id": 555, "last_seen_status_sha": "abc..."}
  }
}
```

## Constraints

- **Read-only**. Never push, never comment, never modify.
- Use only `gh pr view`, `gh pr list`, `gh api` (the allow-list permits these).
- If `gh auth status` fails, return `{events: [{kind: "auth_broken", detail: "..."}], cursors_to_update: {}}` and exit cleanly.
- Time budget: 60 seconds.

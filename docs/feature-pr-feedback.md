# Feature: PR-review auto-fix loop

When an upstream reviewer leaves comments on one of your open PRs, the agent drafts the requested fix, validates it through a 4-perspective review board + tox regression matrix, then pushes to your fork branch. You re-request review. You never type the fix yourself.

## Flow

```
nightly run
   │
   ▼
pr-status-poller
   │  fetches gh pr view for each open PR on ${github_user}/*
   │  diffs against state.roles[role].pr_cursors
   │  emits events
   ▼
event: reviewer_change_requested
   │
   ▼
orchestrator pops queue item, lock acquired on (role, pr)
   │
   ▼
git worktree add state/worktrees/<role>-pr<N>/ <fork-branch>
   │
   ▼
bug-fix-implementer  ──(commit; do not push)──>  commit SHA
   │
   ▼
Review board (4 parallel sub-agents):
   ├─ reviewer-correctness
   ├─ reviewer-cross-os-impact
   ├─ reviewer-upstream-style
   └─ reviewer-security
   │
   ▼  verdicts merged
all pass?  ─no─> revert worktree; PENDING_REVIEW.md entry with findings
   │
   ▼ yes
multi-os-regression-guard  ──(parallel tox)──> per-target results
   │
   ▼
all baseline targets still PASS?  ─no─> revert; PENDING entry; do not push
   │
   ▼ yes
git push origin fix/suse-support
   │
   ▼
state cursor updated; queue item removed; LSR_PROGRESS.md appended
```

## Inputs the agent uses

- Open PR list: `gh pr list --author ${github_user} --state open --json url,number,baseRepository,...`
- Per-PR details: `gh pr view <num> --repo <base> --json comments,reviews,reviewDecision,statusCheckRollup`
- State cursors: `state.roles[role].pr_cursors[<num>] = {last_seen_comment_id, last_seen_review_id, last_seen_status_sha}`

## Outputs the agent produces

- Commit on fork branch: `${github_user}/<role>@fix/suse-support` (force-pushes blocked by hook)
- State update: cursor advanced, queue item removed
- `state/PENDING_REVIEW.md` entry under "👀 Upstream review needs your eyes" with auto-fix status
- Audit trail: full transcript at `~/.cache/lsr-maintainer/<ts>.jsonl`

## Boundaries

- The agent never edits the PR description, never adds review comments, never marks the PR ready for review. You do those manually after reviewing the diff.
- If a fix needs 2 iterations to pass review, that's allowed. Iteration 3+ → surface to PENDING_REVIEW.md as "manual triage."
- If the regression matrix shows a regression on a non-baseline target (e.g., previously N/A), it's reported but not blocking.

## Reading the morning report

In `state/PENDING_REVIEW.md`:

```markdown
## 👀 Upstream review needs your eyes
- [ ] **network** PR linux-system-roles/network#412
  - Auto-fix status: pushed (commit a3f1c2d), regression matrix green, please re-request review
- [ ] **firewall** PR linux-system-roles/firewall#88
  - Auto-fix status: rejected by review board — reviewer-cross-os-impact found the patch breaks RHEL when SUSE-conditional was removed. Manual triage needed.
```

## Tunables

In SKILL.md:
- Per-item time budget: 15 min (line "PR-feedback fix loop")
- Iteration cap for review concerns: 2
- Targets the regression matrix runs against: derived from Role Status Matrix in `lsr-agent` SKILL.md per-role

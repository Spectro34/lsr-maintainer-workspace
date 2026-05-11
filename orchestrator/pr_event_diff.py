"""Diff `gh pr view --json ...` output against per-PR cursors in state.

Emits structured events:
- reviewer_change_requested
- reviewer_approved
- ready_to_merge
- ci_failed
- ci_passed
- pr_closed
- new_user_pr_opened (first time the PR is seen)

Cursors stored per-PR keyed on (repo, number):
{
  "last_seen_comment_id": <int>,
  "last_seen_review_id": <int>,
  "last_seen_status_sha": <str>
}
"""
from __future__ import annotations

from datetime import datetime, timezone
from typing import Any


def _now() -> str:
    return datetime.now(timezone.utc).isoformat()


def diff_pr(
    pr_view: dict[str, Any],
    cursors: dict[str, Any] | None,
) -> tuple[list[dict[str, Any]], dict[str, Any]]:
    """Compare pr_view (output of `gh pr view --json comments,reviews,...`) against cursors.

    Returns (events, new_cursors).
    """
    events: list[dict[str, Any]] = []
    cursors = dict(cursors or {})
    pr_ref = {
        "repo": pr_view.get("baseRepository", {}).get("nameWithOwner")
        or pr_view.get("headRepository", {}).get("nameWithOwner"),
        "number": pr_view.get("number"),
        "head": (pr_view.get("headRepositoryOwner", {}).get("login", "?") + ":" + pr_view.get("headRefName", "?")),
        "url": pr_view.get("url"),
    }

    # First-sight event
    if not cursors:
        events.append({"kind": "new_user_pr_opened", "pr": pr_ref, "discovered_at": _now()})

    # Reviews
    reviews = pr_view.get("reviews") or pr_view.get("latestReviews") or []
    max_review_id = cursors.get("last_seen_review_id", 0) or 0
    for r in reviews:
        rid = _id_of(r)
        if rid > max_review_id:
            state = (r.get("state") or "").upper()
            if state == "CHANGES_REQUESTED":
                events.append(
                    {
                        "kind": "reviewer_change_requested",
                        "pr": pr_ref,
                        "reviewer": r.get("author", {}).get("login"),
                        "body": r.get("body", ""),
                        "discovered_at": _now(),
                    }
                )
            elif state == "APPROVED":
                events.append({"kind": "reviewer_approved", "pr": pr_ref, "discovered_at": _now()})
            max_review_id = rid
    cursors["last_seen_review_id"] = max_review_id

    # Top-level review comments
    comments = pr_view.get("comments") or []
    max_comment_id = cursors.get("last_seen_comment_id", 0) or 0
    for c in comments:
        cid = _id_of(c)
        if cid > max_comment_id:
            max_comment_id = cid
    cursors["last_seen_comment_id"] = max_comment_id

    # PR decision
    decision = (pr_view.get("reviewDecision") or "").upper()
    state_of_pr = (pr_view.get("state") or "").upper()
    if decision == "APPROVED" and state_of_pr == "OPEN":
        events.append({"kind": "ready_to_merge", "pr": pr_ref, "discovered_at": _now()})
    if state_of_pr in ("CLOSED", "MERGED"):
        events.append({"kind": "pr_closed", "pr": pr_ref, "merged": state_of_pr == "MERGED", "discovered_at": _now()})

    # CI rollup
    rollup = pr_view.get("statusCheckRollup") or []
    if rollup:
        # Most recent sha = the head commit sha; rollup is per commit.
        # Simple heuristic: any 'FAILURE' or 'ERROR' status not previously seen → ci_failed.
        head_sha = pr_view.get("headRefOid") or ""
        if head_sha and head_sha != cursors.get("last_seen_status_sha"):
            failures = [c for c in rollup if (c.get("conclusion") or c.get("state") or "").upper() in ("FAILURE", "ERROR", "TIMED_OUT")]
            if failures:
                events.append(
                    {
                        "kind": "ci_failed",
                        "pr": pr_ref,
                        "failing_checks": [c.get("name") or c.get("context") for c in failures],
                        "head_sha": head_sha,
                        "discovered_at": _now(),
                    }
                )
            else:
                events.append({"kind": "ci_passed", "pr": pr_ref, "head_sha": head_sha, "discovered_at": _now()})
            cursors["last_seen_status_sha"] = head_sha

    return events, cursors


def _id_of(obj: dict[str, Any]) -> int:
    """gh returns ids that are sometimes strings, sometimes ints. Coerce."""
    for k in ("id", "databaseId"):
        v = obj.get(k)
        if isinstance(v, int):
            return v
        if isinstance(v, str) and v.isdigit():
            return int(v)
    # Fallback: hash the body+author for a stable-ish id.
    s = (obj.get("body") or "") + (obj.get("author", {}).get("login", "") if isinstance(obj.get("author"), dict) else "")
    return hash(s) & 0xFFFFFFFF

# Feature: SLE role enablement queue

You maintain a list of LSR roles you want enabled for SLE 16. The agent picks one per nightly run and drives the full port through `new-role-enabler`. Successful enablements are auto-removed from the list; failures stay so the next night retries.

## The list

`state/config.json`:

```json
"enablement": {
  "queue": ["logging", "kdump", "selinux"],
  "auto_enqueue_per_run": 1,
  "default_target": "sle16"
}
```

Edit with any text editor — the file is gitignored so machine-specific lists stay out of the workspace repo. Add roles as you decide they're worth enabling; remove them with `make ack-enablement ROLE=<name>` or by hand.

## What happens per night

Phase 2 of `workflow-run.md` (after `manifest-syncer` runs and refreshes `state.obs.managed_roles[]`):

```python
for _ in range(cfg.enablement.auto_enqueue_per_run):
    role = pop_enablement_role(cfg, managed_names, queued_names)
    if not role: break
    enqueue({kind: "enable_role", role, target: cfg.enablement.default_target})
```

`pop_enablement_role` PEEKS (does not remove); it skips roles already in the OBS manifest and roles already queued this run.

Phase 3 fires `new-role-enabler` (60-min budget per item). On `verdict: "enabled"`, the orchestrator calls `ack_enablement_role(cfg_path, role)` which removes the role from the list. Any other verdict (`fork_needed`, `not_viable`, `review_rejected`, `regression`) leaves the role in place; the next nightly run retries.

## PENDING surfacing

`state/PENDING_REVIEW.md` gains a **📋 Enablement queue** section:

```markdown
## 📋 Enablement queue
- [ ] **logging** — pending enablement (pops 1/run by default)
- [ ] **kdump** — pending enablement
- [ ] **selinux** — pending enablement

Manual ack: `make ack-enablement ROLE=<name>` (or edit `state/config.json`).
```

## Tunables

- **`auto_enqueue_per_run`**: how many roles to pop per night. Default 1 (one 60-min enablement fits in the 90-min wall clock). Bump to 2–3 only if you have a long time budget.
- **`default_target`**: `sle16` is the standard; `all` includes Leap 15.6 + SLE 15 SP7. Per-item override via `/lsr-maintainer enable-role <name> --for <target>`.

## Comparison with the `enable-role` command

| Mechanism | When to use |
|---|---|
| Edit `config.enablement.queue[]` | Standing list. Set it once, forget it. Nightly runs work through it. |
| `make enable-role ROLE=squid` | One-shot. Enqueues `enable_role` for the next run only. Use when you want a specific role enabled tonight and not as a recurring intent. |
| Both | They coexist. The command-style adds a transient queue item; the list-style adds a recurring intent. The orchestrator de-dups by `enable_role:<role>` id. |

## Why the list, not just commands?

Operationally, you'll have ~5–15 candidate roles in flight as you work through SUSE certification. Re-running `make enable-role` every night for the same 5 roles is friction. The list keeps the intent declarative.

## Removing roles

- **Success**: automatic on `verdict: "enabled"`.
- **Manual**: `make ack-enablement ROLE=<name>`.
- **Bulk**: edit `state/config.json::enablement.queue` directly.

If you want to PAUSE enablement entirely (e.g. during a tight time budget week): set `auto_enqueue_per_run: 0`. The list stays intact; just nothing gets popped.

## State

`pop_enablement_role` returns the FIRST eligible role from the list each night. The list is FIFO; insert order matters. To prioritize, reorder the list.

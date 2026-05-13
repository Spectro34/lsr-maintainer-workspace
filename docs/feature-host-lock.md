# Feature: Same-machine host-lock enforcement (opt-in)

Pin the workspace to the host it was set up on. If the same `state/.lsr-maintainer-state.json` is copied to another machine (intentional move, accidental clone, container migration), the run aborts before any state mutation.

Opt-in. Default `false` — does not break existing installs.

## Configure

`state/config.json`:

```json
"security": {
  "enforce_host_lock": true
}
```

Set this AFTER your first successful run (so `state.host.fingerprint` has been captured). The first run with the flag flips on confirms the fingerprint matches itself (trivially). Subsequent runs on a different machine abort.

## Fingerprint formula

`sha256(hostname + "\0" + primary-MAC + "\0" + /etc/os-release.ID + "\0" + VERSION_ID)`.

Computed by `orchestrator/host_lock.py::compute_fingerprint()`. Same module is called by `bootstrap-runner` (`python3 -m orchestrator.host_lock --compute`), so both code paths see the identical value.

Changes that flip the fingerprint:
- Hostname change (`hostnamectl set-hostname ...`)
- Primary NIC swap (USB-tether vs eth0 vs bond0 — depends on `ip link` order)
- Distro upgrade (Leap 15.6 → Leap 16, SLE 15-SP7 → SLE 16-SP1)
- Container/VM migration (new IDs)

These are all "this is a different host" signals — that's intended.

## What happens on mismatch

Phase 0a of `workflow-run.md` runs BEFORE the pidfile is written:

```python
ok, reason = check_lock(state, cfg)
if not ok:
    notify(cfg, "host_lock_mismatch", reason, priority="high")
    print(reason)
    sys.exit(1)
```

The run exits 1. No state mutation, no pidfile to clean up. The next legitimate run (on the correct host) is unaffected.

## Recovery on a deliberate move

```bash
make ack-host-lock
```

TTY-required. Prompts:

```
Current fingerprint : sha256:abc123...
Stored  fingerprint : sha256:def456...
Rewrite stored to match current? [y/N]
```

Under cron (no TTY), `ack-host-lock` refuses with "Run `make ack-host-lock` interactively from a shell." That's the safety: a moved workspace can't auto-re-lock itself silently.

## Compatibility with `bootstrap-runner`

`bootstrap-runner` already computes the fingerprint at every run and writes it to `state.host.fingerprint` when the field is empty (first-run capture). With `enforce_host_lock: false`, that's a passive recording; with `enforce_host_lock: true`, Phase 0a checks it.

If you flip the flag on a workspace that's been moved multiple times, the stored fingerprint may not match anything. Run `make ack-host-lock` once to re-confirm; from then on the lock is in effect.

## Cron behavior

A cron run on a wrong host exits 1 every night and fires `notify(host_lock_mismatch)`. If you have ntfy/email/webhook configured, you'll get nightly alerts until you either:

- ack from a TTY (legitimate move), OR
- remove the cron entry (`make uninstall-cron`), OR
- disable the lock (`config.security.enforce_host_lock: false`).

## When to enable

- **Multi-tenant servers**: lock so a misconfigured rsync of `~/github/` doesn't fire the agent under the wrong identity.
- **Workstation/laptop pair**: lock on the workstation (the canonical install), explicit-ack the laptop if you want it to take over.
- **Production VMs**: lock to prevent template-AMI clones from becoming a runaway fleet.

## When to leave it off

- Dev / scratch workspaces where you copy `state/` around for testing.
- Containerized runs where the fingerprint is intentionally ephemeral.

The default is `false` for exactly that reason.

## Implementation

- `orchestrator/host_lock.py` — `compute_fingerprint()`, `check_lock(state, cfg)`, `ack_lock(state_path)`.
- `.claude/skills/lsr-maintainer/references/workflow-run.md` Phase 0a — check site (before pidfile).
- `.claude/skills/lsr-maintainer/agents/bootstrap-runner.md` step 1 — capture site.
- `orchestrator/notify.py::EVENT_KINDS` — `"host_lock_mismatch"` is one of the dispatched events.
- `Makefile` — `ack-host-lock` target.

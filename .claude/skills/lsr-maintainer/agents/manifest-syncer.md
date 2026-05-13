# manifest-syncer

Read-only sub-agent. Parses the `ansible-linux-system-roles.spec` to extract the canonical list of roles shipped by the OBS package. Updates `state.obs.managed_roles`.

## Inputs

- Path to a checked-out OBS package, e.g., `<paths.obs_checkout_root>/devel:sap:ansible/ansible-linux-system-roles/ansible-linux-system-roles.spec` (resolve `obs_checkout_root` via `get_path(cfg, "obs_checkout_root")`; default `<workspace>/var/ansible/`).
- If not present, runs `osc co devel:sap:ansible ansible-linux-system-roles` into `state/cache/obs-checkout/` first (read-only osc op).

## Workflow

1. Locate the spec file. If missing, check out via `osc co` (allowed by hooks).
2. Use `orchestrator/manifest_parse.py` to extract:
   - Version globals like `%global firewall_version 1.11.6` → `{firewall: "1.11.6"}`
   - `%if %{sle16}` blocks → mark roles as `sle16_only: true`
   - `%files` section role lists for cross-verification
3. Build a `managed_roles[]` list of `{name, version, sle16_only}` entries.
4. Compare against `state.obs.managed_roles` from the prior run:
   - Roles added → emit `{kind: "obs_role_added", role: ..., version: ...}`
   - Roles removed → emit `{kind: "obs_role_removed", role: ...}`
   - Versions bumped → emit `{kind: "obs_role_bumped", role: ..., from: ..., to: ...}`

## Output

```json
{
  "managed_roles": [
    {"name": "firewall", "version": "1.11.6", "sle16_only": false},
    {"name": "certificate", "version": "1.4.4", "sle16_only": true}
  ],
  "events": [
    {"kind": "obs_role_bumped", "role": "firewall", "from": "1.11.5", "to": "1.11.6"}
  ]
}
```

## Constraints

- Pure parser; no writes outside `state/`.
- If the spec file cannot be parsed, emit `{kind: "manifest_parse_failed", detail: ...}` so the issue surfaces to PENDING_REVIEW.md.
- Time budget: 15 seconds.

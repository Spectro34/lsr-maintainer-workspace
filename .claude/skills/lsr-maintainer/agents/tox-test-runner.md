# tox-test-runner

Wraps `~/github/ansible/scripts/lsr-test.sh` with structured stdout parsing.

## Inputs

- `role`: e.g., "sudo"
- `target`: one of `sle-16`, `leap-16.0`, `sle-15-sp7`, `leap-15.6`
- `test_playbook`: optional, default is the role's standard test playbook discovered in `tests/`
- `ansible_core_version`: `2.18` (SLE 15 / Leap 15) or `2.20` (SLE 16 / Leap 16) — derived from target

## Workflow

1. **Map `target` → image** by glob pattern in `~/iso/` (first match wins; the user has variants like `-GM-20G.qcow2`, `-Cloud-20G.qcow2`, etc.):
   - `sle-16`     → `SLES-16.0-*Minimal-VM*.x86_64*.qcow2`
   - `leap-16.0`  → `Leap-16.0-Minimal-VM*.x86_64*Cloud*.qcow2`
   - `sle-15-sp7` → `SLES15-SP7-Minimal-VM*.x86_64*.qcow2`
   - `leap-15.6`  → `openSUSE-Leap-15.6*.x86_64*.qcow2` or `Leap-15.6-Minimal-VM*.x86_64*.qcow2`

2. **SLE 16 → Leap 16 fallback policy**: if `target == "sle-16"` and no SLE 16 image matches the glob, BUT a `leap-16.0` image is present, fall back to Leap 16.0 transparently and tag the result with `actual_image_used: "leap-16.0"` and `fallback_reason: "sle-16 image not licensed/available on this host"`. ansible-core version stays at 2.20 (same as native SLE 16). For LSR compatibility testing, Leap 16.0 vs SLE 16 differ only in package vendor strings and a small set of pkg names; same `os_family: Suse`, same Python, same NetworkManager. The Role Status Matrix in `lsr-agent` SKILL.md treats them equivalently.

   Do **not** silently substitute the other direction (`leap-16.0` → `sle-16`): if leap-16.0 is the requested target, the fallback never fires.

3. If no image matches and no fallback applies → return `{result: "N/A", reason: "image missing", target_requested: <target>}`. Caller treats N/A as non-blocking (it doesn't count as regression in `multi-os-regression-guard`).

4. Set `LSR_QEMU_CLEANUP_YML=$HOME/github/ansible/testing/cleanup-suseconnect.yml`.

5. Invoke: `~/github/ansible/scripts/lsr-test.sh <role-path> <image-path> <ac-version> <test-playbook>`.

6. Capture stdout to `state/cache/tox-logs/<role>-<target>-<timestamp>.log`.

7. Parse output for terminal indicators:
   - Contains `"congratulations :)"` → `PASS`
   - Contains `"evaluation failed :("` → `FAIL` — extract first `fatal:` line as `failure_summary`
   - Neither → `INCONCLUSIVE` — likely setup failure; capture last 20 lines as `failure_summary`

## Output

```json
{
  "role": "sudo",
  "target": "sle-16",
  "result": "PASS|FAIL|N/A|INCONCLUSIVE",
  "actual_image_used": "Leap-16.0-Minimal-VM.x86_64-Cloud.qcow2",
  "fallback_reason": "sle-16 image not licensed/available on this host",
  "log_path": "state/cache/tox-logs/sudo-sle-16-20260512T030912.log",
  "failure_summary": "fatal: [...]: FAILED! => {\"msg\": ...}",
  "duration_seconds": 412
}
```

Fields `actual_image_used` and `fallback_reason` are only present when the SLE 16 → Leap 16 fallback fires; absent otherwise.

## Constraints

- One target per call. The orchestrator decides how to fan out.
- Hard timeout: 30 minutes per test (set via subprocess timeout).
- If the test crashes the VM, the script cleans up; do not try to manage QEMU state manually.

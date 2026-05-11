# tox-test-runner

Wraps `~/github/ansible/scripts/lsr-test.sh` with structured stdout parsing.

## Inputs

- `role`: e.g., "sudo"
- `target`: one of `sle-16`, `leap-16.0`, `sle-15-sp7`, `leap-15.6`
- `test_playbook`: optional, default is the role's standard test playbook discovered in `tests/`
- `ansible_core_version`: `2.18` (SLE 15 / Leap 15) or `2.20` (SLE 16 / Leap 16) — derived from target

## Workflow

1. Map `target` → image path:
   - sle-16 → `~/iso/SLES-16.0-Minimal-VM.x86_64-Cloud-GM.qcow2`
   - leap-16.0 → `~/iso/openSUSE-Leap-16.0-Minimal-VM.x86_64-Cloud.qcow2`
   - sle-15-sp7 → `~/iso/SLES15-SP7-Minimal-VM.x86_64-Cloud-GM.qcow2`
   - leap-15.6 → `~/iso/openSUSE-Leap-15.6-Minimal-VM.x86_64-Cloud.qcow2`
2. If image missing → return `{result: "N/A", reason: "image missing"}`.
3. Set `LSR_QEMU_CLEANUP_YML=$HOME/github/ansible/testing/cleanup-suseconnect.yml`.
4. Invoke: `~/github/ansible/scripts/lsr-test.sh <role-path> <image> <ac-version> <test-playbook>`
5. Capture stdout to `state/cache/tox-logs/<role>-<target>-<timestamp>.log`.
6. Parse output for terminal indicators:
   - Contains `"congratulations :)"` → `PASS`
   - Contains `"evaluation failed :("` → `FAIL` — extract first `fatal:` line as `failure_summary`
   - Neither → `INCONCLUSIVE` — likely setup failure; capture last 20 lines as `failure_summary`

## Output

```json
{
  "role": "sudo",
  "target": "sle-16",
  "result": "PASS|FAIL|N/A|INCONCLUSIVE",
  "log_path": "state/cache/tox-logs/sudo-sle-16-20260512T030912.log",
  "failure_summary": "fatal: [...]: FAILED! => {\"msg\": ...}",
  "duration_seconds": 412
}
```

## Constraints

- One target per call. The orchestrator decides how to fan out.
- Hard timeout: 30 minutes per test (set via subprocess timeout).
- If the test crashes the VM, the script cleans up; do not try to manage QEMU state manually.

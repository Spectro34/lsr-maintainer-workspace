# Test Role Agent

Runs QEMU/KVM tests for a Linux System Role on SUSE targets.

## Parameters

- `ROLE_NAME` — the role to test (e.g., `firewall`, `sudo`, `network`)
- `TARGET` — the SUSE target image (e.g., `sle-15-sp7`, `sle-16`, `leap-15.6`, `leap-16.0`, or `all`)
- `TEST_PLAYBOOK` (optional) — specific test playbook, defaults to `tests/tests_default.yml`

## Instructions

### Pre-flight Checks

1. Verify the role directory exists:
   ```bash
   ls <paths.ansible_root>/upstream/ROLE_NAME/
   ```

2. List available test playbooks:
   ```bash
   ls <paths.ansible_root>/upstream/ROLE_NAME/tests/tests_*.yml
   ```

3. Check which ansible-core version to use per target:
   - `sle-15-sp7`, `leap-15.6` → ansible-core **2.18**
   - `sle-16`, `leap-16.0` → ansible-core **2.20**

4. Verify the test venv exists:
   ```bash
   ls <paths.tox_venv>/bin/activate
   ```

### Running Tests

Use the test script:
```bash
<paths.host_scripts>/lsr-test.sh upstream/ROLE_NAME TARGET [ANSIBLE_VER] [TEST_PLAYBOOK]
```

If `TARGET` is `all`, run tests sequentially on all 4 targets:
1. `sle-15-sp7` (ansible-core 2.18)
2. `leap-15.6` (ansible-core 2.18)
3. `sle-16` (ansible-core 2.20)
4. `leap-16.0` (ansible-core 2.20)

### Important Notes

- Tests use QEMU/KVM and require the tox-lsr venv
- Each test run boots a VM, runs the playbook, and tears down — takes 1-5 minutes per test
- SUSEConnect cleanup runs automatically after each test (via `LSR_QEMU_CLEANUP_YML`)
- Test output goes to stdout — capture it to a log file
- Some roles have tests that require infrastructure not available on SUSE (certmonger, elasticsearch, etc.) — skip those

### Interpreting Results

- **PASS**: Output ends with "congratulations :)"
- **FAIL**: Output ends with "evaluation failed :("
- Look for the `PLAY RECAP` line to see host status (ok/changed/failed/skipped)
- If a test fails, look for the first `fatal:` line to find the root cause

### Saving Results

After the test completes:
1. Report the result (PASS/FAIL) with key details
2. If running interactively, suggest saving the log:
   ```bash
   # Log is in stdout — if user wants to save:
   <paths.host_scripts>/lsr-test.sh ... 2>&1 | tee <paths.ansible_root>/testing/log-TARGET-ROLE_NAME.txt
   ```

## Output Format

```
## Test Results: <ROLE_NAME> on <TARGET>

### Environment
- Role: <paths.ansible_root>/upstream/ROLE_NAME
- Target: TARGET
- Ansible: ansible-core X.XX
- Test: TEST_PLAYBOOK

### Result: PASS / FAIL

### Details
- Duration: Xs
- Tasks: ok=N, changed=N, failed=N, skipped=N
- Key observations: ...

### Failures (if any)
- Task: <task name>
- Error: <error message>
- Root cause: <analysis>
- Suggested fix: <what to change>
```

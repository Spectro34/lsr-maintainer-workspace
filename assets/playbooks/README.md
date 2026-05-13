# SCC registration playbooks (SLE-only)

Two ansible playbooks that handle SUSE Customer Center (SCC) registration around tox-lsr test runs:

- `register-suseconnect.yml` — runs **before** the role tests on each SLE VM. Reads encrypted `vault-suseconnect.yml`. No-op on Leap/openSUSE.
- `cleanup-suseconnect.yml` — runs **after** each test (via `LSR_QEMU_CLEANUP_YML`). No secrets required.
- `vault-suseconnect.yml.example` — template for SCC creds. Copy + encrypt + use.

`bin/install-deps.sh` copies these into `<paths.ansible_root>/testing/` (default `./var/ansible/testing/`) at install time. Tracked source here under `assets/playbooks/` so `make distclean` doesn't lose them.

## Why vault

SCC reg-codes are sensitive: a leak lets anyone burn entitlement on your account. We encrypt at rest, never commit plaintext, never let the hook layer or transcript see them (the register task uses `no_log: true`).

## One-time setup

```bash
cd <workspace>
make install-deps               # copies the playbooks + template into var/ansible/testing/
cd var/ansible/testing

# Pick a vault password and save it (gitignored — workspace-local).
# Use a long random string; this protects the encrypted SCC creds at rest.
read -s -p "vault password: " p && echo "$p" > .vault_pwd && chmod 600 .vault_pwd

# Initialize from template, encrypt.
cp vault-suseconnect.yml.example vault-suseconnect.yml
ansible-vault edit vault-suseconnect.yml --vault-password-file .vault_pwd
# (the editor opens with the template; replace REPLACE_* with real SCC values)
```

After this:
- `vault-suseconnect.yml` is encrypted at rest (the file starts with `$ANSIBLE_VAULT;1.1;AES256`).
- `.vault_pwd` is gitignored and chmod 600 (operator-only readable).

## Edit later

```bash
ansible-vault edit var/ansible/testing/vault-suseconnect.yml \
  --vault-password-file var/ansible/testing/.vault_pwd
```

Or via the Makefile shortcut: `make scc-vault-edit`.

## Verify the encryption looks right

```bash
head -1 var/ansible/testing/vault-suseconnect.yml
# expect: $ANSIBLE_VAULT;1.1;AES256
```

If it shows plaintext (`scc_regcode: ...`), you skipped the encrypt step. Re-run `ansible-vault encrypt`.

## Integration with tox-lsr

The cleanup playbook is already wired in your existing lsr-test.sh via `LSR_QEMU_CLEANUP_YML`. The register playbook needs to fire **before** the test runs.

### Option A — manual pre-test register (simplest)

When you run a SLE test, register the VM first:

```bash
ansible-playbook -i <vm-inv> var/ansible/testing/register-suseconnect.yml \
  --vault-password-file var/ansible/testing/.vault_pwd
# now run the test
bash var/ansible/scripts/lsr-test.sh upstream/<role> sle-16 ...
# cleanup-suseconnect.yml fires automatically via LSR_QEMU_CLEANUP_YML
```

### Option B — wrapper script (one-shot register + test + cleanup)

Create `var/ansible/scripts/lsr-test-sle.sh`:

```bash
#!/bin/bash
ROLE_DIR="$1"
TARGET="$2"
shift 2

BASEDIR="$(cd "$(dirname "$0")/.." && pwd)"

# Only register for SLE targets (Leap doesn't need it).
case "$TARGET" in
  sle-*)
    ansible-playbook -i "${INV:-localhost,}" \
      "$BASEDIR/testing/register-suseconnect.yml" \
      --vault-password-file "$BASEDIR/testing/.vault_pwd" \
      || { echo "SCC register failed; aborting test."; exit 1; }
    ;;
esac

# Pass through to the real test runner.
bash "$BASEDIR/scripts/lsr-test.sh" "$ROLE_DIR" "$TARGET" "$@"
```

Then the agent's `tox-test-runner` invokes `lsr-test-sle.sh` instead of `lsr-test.sh` for SLE targets. The cleanup still fires via `LSR_QEMU_CLEANUP_YML`.

### Option C — tox-lsr hook (if your tox-lsr version supports `LSR_QEMU_SETUP_YML`)

Some tox-lsr builds honor `LSR_QEMU_SETUP_YML` symmetrically with `LSR_QEMU_CLEANUP_YML`. If yours does:

```bash
export LSR_QEMU_SETUP_YML="$BASEDIR/testing/register-suseconnect.yml"
export ANSIBLE_VAULT_PASSWORD_FILE="$BASEDIR/testing/.vault_pwd"
# now any lsr-test.sh invocation auto-registers before + deregisters after
```

Check with `tox-lsr --help` or `grep -r SETUP_YML <tox-lsr-source>`.

## What to commit, what to gitignore

| File | Tracked? | Why |
|---|---|---|
| `assets/playbooks/register-suseconnect.yml` | ✓ tracked | logic, no secrets |
| `assets/playbooks/cleanup-suseconnect.yml` | ✓ tracked | logic, no secrets |
| `assets/playbooks/vault-suseconnect.yml.example` | ✓ tracked | template, no secrets |
| `assets/playbooks/README.md` | ✓ tracked | this file |
| `var/ansible/testing/{register,cleanup}-suseconnect.yml` | gitignored (var/) | copy of tracked playbooks |
| `var/ansible/testing/vault-suseconnect.yml` | gitignored (var/) | encrypted ciphertext |
| `var/ansible/testing/.vault_pwd` | gitignored (var/ + leading-dot, explicitly) | plaintext vault password |

`var/` is in `.gitignore` so nothing under `var/ansible/testing/` is at risk of accidental commit. Belt-and-suspenders: `.vault_pwd` is also a global gitignore pattern.

## Re-keying

If you suspect the vault password leaked, rotate:

```bash
ansible-vault rekey var/ansible/testing/vault-suseconnect.yml \
  --vault-password-file var/ansible/testing/.vault_pwd
# prompts for new password; update .vault_pwd with the new one
echo "<new-password>" > var/ansible/testing/.vault_pwd
chmod 600 var/ansible/testing/.vault_pwd
```

If you suspect the SCC reg-code itself leaked: regenerate it in https://scc.suse.com, then `ansible-vault edit vault-suseconnect.yml` and update.

## Why install-deps copies (not symlinks)

Copy semantics let you edit the workspace-local playbooks (`var/ansible/testing/*.yml`) without touching the committed `assets/playbooks/` source. Useful for per-host tweaks. Re-running `make install-deps` re-copies but with `cp -n` (no-clobber) — your local edits survive.

To reset a workspace-local playbook to the tracked version:

```bash
rm var/ansible/testing/register-suseconnect.yml
make install-deps    # re-copies from assets/
```

"""Host-fingerprint lock (issue: same-machine enforcement).

The fingerprint binds a workspace to the machine it was set up on:
  sha256(hostname + primary-MAC + /etc/os-release ID + VERSION_ID)

Opt-in via `config.security.enforce_host_lock`. When True, Phase 0 of
`workflow-run.md` calls `check_lock()` BEFORE writing the pidfile.
On mismatch the run exits 1 + `notify(host_lock_mismatch)`.

Recovery on a legitimate move: `make ack-host-lock` rewrites the stored
fingerprint after prompting from a TTY. Refuses under cron (no TTY) to
avoid silently re-locking after an unintended move.

Pure stdlib; no dependency on bootstrap-runner state — but the formula
is shared so the same value lands in `state.host.fingerprint` from
either entry point.
"""
from __future__ import annotations

import hashlib
import json
import os
import socket
import subprocess
import sys
from typing import Any


def _read_os_release() -> tuple[str, str]:
    """Extract ID and VERSION_ID from /etc/os-release."""
    os_id = ""
    version_id = ""
    try:
        with open("/etc/os-release") as f:
            for line in f:
                line = line.strip()
                if line.startswith("ID="):
                    os_id = line.split("=", 1)[1].strip().strip('"')
                elif line.startswith("VERSION_ID="):
                    version_id = line.split("=", 1)[1].strip().strip('"')
    except FileNotFoundError:
        pass
    return os_id, version_id


def _primary_mac() -> str:
    """Read MAC of the default-route interface (or first non-loopback as a
    fallback). Returns "" if not determinable (e.g. minimal container
    without ip(8)).

    The default-route preference avoids binding the fingerprint to a
    transient bridge (`docker0`, `virbr0`, `tap0`) that may not exist
    after a reboot — a docker install/uninstall would otherwise re-trip
    host-lock on a stable host.
    """
    ip_bin = "/usr/sbin/ip" if os.path.exists("/usr/sbin/ip") else "/sbin/ip"
    if not os.path.exists(ip_bin):
        # Try PATH fallback for unusual layouts (e.g. NixOS, cron stripped PATH).
        import shutil
        ip_bin = shutil.which("ip") or ""
    if not ip_bin:
        return ""

    # Pass 1: find the default-route interface.
    iface = ""
    try:
        r = subprocess.run(
            [ip_bin, "-o", "route", "show", "default"],
            capture_output=True, text=True, timeout=5,
        )
        if r.returncode == 0 and r.stdout.strip():
            # "default via 1.2.3.4 dev eth0 proto dhcp metric 100"
            parts = r.stdout.split()
            if "dev" in parts:
                idx = parts.index("dev")
                if idx + 1 < len(parts):
                    iface = parts[idx + 1]
    except Exception:
        pass

    # Pass 2: read link table; prefer iface from pass 1, else first non-loopback.
    try:
        r = subprocess.run(
            [ip_bin, "-o", "link", "show"],
            capture_output=True, text=True, timeout=5,
        )
        if r.returncode != 0:
            return ""
        fallback = ""
        for line in r.stdout.splitlines():
            if "link/loopback" in line or "link/ether" not in line:
                continue
            # Format: "2: eth0: <...> link/ether aa:bb:cc:dd:ee:ff brd ff:..."
            parts = line.split()
            try:
                mac = parts[parts.index("link/ether") + 1]
            except (ValueError, IndexError):
                continue
            # Interface name is parts[1] minus trailing colon.
            this_iface = parts[1].rstrip(":") if len(parts) > 1 else ""
            if iface and this_iface == iface:
                return mac
            if not fallback:
                fallback = mac
        return fallback
    except Exception:
        pass
    return ""


def compute_fingerprint() -> str:
    """Return sha256 hex digest of (hostname, primary-mac, ID, VERSION_ID).

    Deterministic on a given host. Hardware change (NIC swap, distro
    upgrade) WILL change the fingerprint — that's the intended behavior;
    user runs `make ack-host-lock` to re-confirm.
    """
    hostname = socket.gethostname()
    mac = _primary_mac()
    os_id, version_id = _read_os_release()
    data = f"{hostname}\0{mac}\0{os_id}\0{version_id}".encode()
    return "sha256:" + hashlib.sha256(data).hexdigest()


def check_lock(state: dict[str, Any], cfg: dict[str, Any]) -> tuple[bool, str]:
    """Compare the current host's fingerprint against `state.host.fingerprint`.

    Returns `(ok, reason)`:
      - `ok=True,  reason=""`     — lock disabled, or fingerprint matches,
                                    or no stored fingerprint yet (first run).
      - `ok=False, reason=...`    — fingerprint mismatch.

    Stored-but-empty fingerprint counts as "first run" and passes; the
    caller (orchestrator Phase 0) is expected to persist the current
    fingerprint into state on first successful run.
    """
    if not (cfg.get("security") or {}).get("enforce_host_lock"):
        return True, ""
    stored = (state.get("host") or {}).get("fingerprint") or ""
    if not stored:
        return True, ""  # first run / not yet locked
    current = compute_fingerprint()
    if stored == current:
        return True, ""
    return False, (
        f"host_lock_mismatch: stored fingerprint {stored[:20]}... does not match "
        f"current {current[:20]}... — run `make ack-host-lock` from a TTY if this "
        f"move is intentional."
    )


def ack_lock(state_path: str) -> bool:
    """Rewrite `state.host.fingerprint` with the current value.

    Refuses under cron / no TTY. Returns True on success.
    """
    if not os.isatty(0):
        sys.stderr.write(
            "ack_lock: refusing without a TTY. Run `make ack-host-lock` "
            "interactively from a shell.\n"
        )
        return False
    if not os.path.exists(state_path):
        sys.stderr.write(f"ack_lock: state file not found: {state_path}\n")
        return False
    with open(state_path) as f:
        state = json.load(f)
    current = compute_fingerprint()
    old = (state.get("host") or {}).get("fingerprint") or "(none)"
    sys.stdout.write(
        f"Current fingerprint : {current}\n"
        f"Stored  fingerprint : {old}\n"
        "Rewrite stored to match current? [y/N] "
    )
    sys.stdout.flush()
    answer = sys.stdin.readline().strip().lower()
    if answer not in ("y", "yes"):
        sys.stdout.write("aborted.\n")
        return False
    state.setdefault("host", {})["fingerprint"] = current
    # Atomic-ish rewrite. We don't take state_lock here — the caller is
    # interactive and shouldn't be racing the cron run; if cron fires
    # mid-ack the lock check at Phase 0 will simply re-fail this cycle.
    tmp = state_path + ".ack.tmp"
    with open(tmp, "w") as f:
        json.dump(state, f, indent=2, sort_keys=True)
        f.write("\n")
    os.replace(tmp, state_path)
    sys.stdout.write(f"OK — wrote {current} to {state_path}\n")
    return True


# CLI for shell scripts: `python3 -m orchestrator.host_lock --compute`
def _main(argv: list[str]) -> int:
    if len(argv) >= 2 and argv[1] == "--compute":
        print(compute_fingerprint())
        return 0
    if len(argv) >= 2 and argv[1] == "--ack":
        state_path = argv[2] if len(argv) >= 3 else "state/.lsr-maintainer-state.json"
        return 0 if ack_lock(state_path) else 1
    sys.stderr.write("usage: python3 -m orchestrator.host_lock --compute | --ack [state_path]\n")
    return 2


if __name__ == "__main__":
    # Self-test when invoked without args (so `make test-orchestrator` works).
    if len(sys.argv) == 1:
        fp1 = compute_fingerprint()
        fp2 = compute_fingerprint()
        assert fp1 == fp2, f"fingerprint must be deterministic: {fp1} vs {fp2}"
        assert fp1.startswith("sha256:"), fp1
        assert len(fp1) == len("sha256:") + 64, f"unexpected length: {len(fp1)}"

        # Lock disabled → always ok.
        ok, reason = check_lock({"host": {"fingerprint": "garbage"}}, {})
        assert ok is True and reason == "", (ok, reason)

        # Lock enabled + matching → ok.
        ok, reason = check_lock(
            {"host": {"fingerprint": fp1}},
            {"security": {"enforce_host_lock": True}},
        )
        assert ok is True and reason == "", (ok, reason)

        # Lock enabled + empty stored → ok (first-run).
        ok, reason = check_lock(
            {"host": {"fingerprint": ""}},
            {"security": {"enforce_host_lock": True}},
        )
        assert ok is True and reason == "", (ok, reason)

        # Lock enabled + mismatching → not ok.
        ok, reason = check_lock(
            {"host": {"fingerprint": "sha256:" + "0" * 64}},
            {"security": {"enforce_host_lock": True}},
        )
        assert ok is False and "host_lock_mismatch" in reason, (ok, reason)

        print("OK host_lock self-test")
        sys.exit(0)
    sys.exit(_main(sys.argv))

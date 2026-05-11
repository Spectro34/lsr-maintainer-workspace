"""Sanitization of attacker-controlled text before passing to sub-agents.

The orchestrator wraps PR comments, commit messages, build logs, and other
external text in <UNTRUSTED_*> delimiters and runs it through `sanitize()`
to strip ANSI control sequences and other terminal-trickery characters.

Closes issue #12 (P-M1) — defense against prompt injection from upstream
maintainers, hostile reviewers, or compromised content sources.
"""
from __future__ import annotations

import re

# ANSI escape sequences: ESC followed by CSI (Control Sequence Introducer)
# or OSC (Operating System Command) etc. Strip the lot.
_ANSI = re.compile(
    r'\x1b(?:'
        r'\[[0-?]*[ -/]*[@-~]'  # CSI sequences
        r'|\][^\x07\x1b]*(?:\x07|\x1b\\)'  # OSC sequences
        r'|[@-_]'  # single-character escapes
    r')'
)

# Other terminal-trickery characters.
_CONTROL = re.compile(r'[\x00-\x08\x0b\x0c\x0e-\x1f\x7f]')


def sanitize(text: str) -> str:
    """Strip ANSI escape sequences and most control characters from text.

    Preserves: printable ASCII + Unicode, plus newline (\\x0a), tab (\\x09),
    carriage-return (\\x0d). Strips everything else in the C0 / C1 control
    ranges, plus DEL.

    Idempotent: sanitize(sanitize(x)) == sanitize(x).
    """
    if not text:
        return text
    text = _ANSI.sub('', text)
    text = _CONTROL.sub('', text)
    return text


def wrap_untrusted(text: str, source: str = "external") -> str:
    """Wrap text in clear delimiters and apply sanitization. The orchestrator
    uses this when passing external content to a sub-agent's prompt."""
    clean = sanitize(text)
    return (
        f"<UNTRUSTED_CONTENT source={source!r}>\n"
        f"{clean}\n"
        f"</UNTRUSTED_CONTENT>"
    )


if __name__ == "__main__":
    # Self-test.
    # ANSI red + "x" + ANSI reset
    s = "\x1b[31mhello\x1b[0m"
    assert sanitize(s) == "hello", repr(sanitize(s))
    # OSC sequence
    s = "\x1b]0;hijack window title\x07normal text"
    assert sanitize(s) == "normal text", repr(sanitize(s))
    # Control characters
    s = "line1\nline2\ttab\x07bell"
    assert sanitize(s) == "line1\nline2\ttabbell", repr(sanitize(s))
    # Preserves Unicode
    s = "\x1b[32m✓ unicode preserved\x1b[0m"
    assert sanitize(s) == "✓ unicode preserved", repr(sanitize(s))
    # Idempotence
    s = "\x1b[1m\x1b]0;x\x07bold\x1b[0m"
    assert sanitize(sanitize(s)) == sanitize(s)
    # Wrap
    w = wrap_untrusted("attacker text", "PR comment by @anon")
    assert "<UNTRUSTED_CONTENT" in w and "attacker text" in w
    assert w.startswith("<UNTRUSTED_CONTENT source='PR comment by @anon'>")
    print("OK sanitize self-test")

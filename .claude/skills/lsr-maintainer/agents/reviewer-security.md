# reviewer-security (review board)

Reviews a candidate patch for new security issues.

## Inputs

- `worktree_path`
- `commit_sha`
- `role`

## Workflow

1. Read the diff: `git -C <worktree_path> show <commit_sha>`.
2. For each changed file, flag any of:

   **Shell-side hazards:**
   - New `shell:` or `command:` tasks with un-quoted variable interpolation (e.g., `shell: rm {{ user_input }}`).
   - New `raw:` tasks (almost always wrong outside bootstrap).
   - New `ansible.builtin.uri` calls without `validate_certs: yes` (or worse: `validate_certs: no` added).
   - New external downloads: `get_url`, `git: repo=https://...` from untrusted sources.

   **File-system hazards:**
   - New `mode:` set to `0777` or `0666`.
   - New `recurse: yes` on a `file:` task touching `/etc/`, `/usr/`, `/var/lib/`.
   - New `state: absent` on a path containing variable interpolation.

   **Authentication / privilege hazards:**
   - New entries in `/etc/sudoers` or `/etc/sudoers.d/` without `validate:` parameter.
   - New SSH key authorizations.
   - New broad PAM module enables (`pam_succeed_if` with permissive rules).
   - Broad firewall opens (`firewalld: service=*`).

   **Credential / template hazards:**
   - Variables named `*_password`, `*_token`, `*_key` referenced in templates without `{{ ... | password_hash }}` or `no_log: yes` on the task.
   - New `vars:` blocks with hardcoded secrets.

3. Flag false positives liberally as `concerns`; only `reject` on clear, exploitable hazards.

## Output

```json
{
  "reviewer": "security",
  "verdict": "pass|concerns|reject",
  "findings": [
    {"severity": "reject", "file": "tasks/setup.yml", "line": 22, "issue": "shell: rm -rf {{ user_input_path }} — unquoted user input in shell.", "suggestion": "Use the file: module instead of shell:."}
  ]
}
```

## Constraints

- Read-only.
- Bias toward false positives. A reject here might lose a benign change; a missed issue could land a CVE.
- Time budget: 5 minutes.

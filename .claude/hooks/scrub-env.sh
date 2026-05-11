#!/usr/bin/env bash
# scrub-env.sh — SessionStart hook.
#
# Emits a JSON updateEnv directive so Claude Code unsets secret-y env vars
# before any tool call runs. The on-disk credentials remain — only the
# agent's view of the environment is scrubbed.

set -u

# Variables to clear. Match: anything that looks like a credential.
# Be conservative: do NOT touch PATH, HOME, USER, LANG, etc.
SECRET_VARS=(
  GITHUB_TOKEN
  GH_TOKEN
  GH_ENTERPRISE_TOKEN
  OSC_PASSWORD
  OSC_USER
  OBS_PASSWORD
  ANSIBLE_VAULT_PASSWORD
  ANTHROPIC_API_KEY
  OPENAI_API_KEY
  AWS_ACCESS_KEY_ID
  AWS_SECRET_ACCESS_KEY
  AWS_SESSION_TOKEN
  AZURE_CLIENT_SECRET
  AZURE_TENANT_ID
  GCP_CREDENTIALS
  GOOGLE_APPLICATION_CREDENTIALS
  NPM_TOKEN
  DOCKER_PASSWORD
  TWILIO_AUTH_TOKEN
)

# Emit the directive (Claude Code reads updateEnv from SessionStart hook stdout).
python3 - <<'PY'
import json, os
secret_keys = [
    "GITHUB_TOKEN","GH_TOKEN","GH_ENTERPRISE_TOKEN",
    "OSC_PASSWORD","OSC_USER","OBS_PASSWORD",
    "ANSIBLE_VAULT_PASSWORD",
    "ANTHROPIC_API_KEY","OPENAI_API_KEY",
    "AWS_ACCESS_KEY_ID","AWS_SECRET_ACCESS_KEY","AWS_SESSION_TOKEN",
    "AZURE_CLIENT_SECRET","AZURE_TENANT_ID",
    "GCP_CREDENTIALS","GOOGLE_APPLICATION_CREDENTIALS",
    "NPM_TOKEN","DOCKER_PASSWORD","TWILIO_AUTH_TOKEN",
]
# Map each present secret to empty string (Claude Code passes this env to tools).
update = {k: "" for k in secret_keys if k in os.environ}
if update:
    print(json.dumps({"hookSpecificOutput": {"hookEventName": "SessionStart", "updateEnv": update}}))
PY

exit 0

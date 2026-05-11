.DEFAULT_GOAL := help
SHELL := /bin/bash
WORKSPACE := $(shell pwd)

# ---------------------------------------------------------------------------
# Setup & install
# ---------------------------------------------------------------------------

.PHONY: help
help: ## Show this help
	@awk 'BEGIN {FS = ":.*?## "; printf "Targets:\n"} \
	  /^[a-zA-Z_-]+:.*?## / {printf "  %-22s %s\n", $$1, $$2}' $(MAKEFILE_LIST)

.PHONY: setup
setup: ## Run interactive auth setup (gh + osc) — never sees credentials
	@bash bin/setup.sh

.PHONY: install
install: install-deps install-cron ## Bootstrap host + schedule nightly run

.PHONY: install-deps
install-deps: ## Idempotent host prep — directories, tox venv, submodule checkout
	@bash bin/install-deps.sh

.PHONY: install-cron
install-cron: ## Install nightly cron entry (idempotent)
	@bash bin/install-cron.sh

.PHONY: uninstall
uninstall: ## Remove cron entry — leaves workspace + state intact
	@bash bin/install-cron.sh --remove

# ---------------------------------------------------------------------------
# Workspace ops across managed projects
# ---------------------------------------------------------------------------

.PHONY: pull-all
pull-all: ## Check out submodules at the PINNED SHAs (NOT branch HEAD — see submodule-bump for that)
	@git submodule update --init --recursive

.PHONY: submodule-bump
submodule-bump: ## DELIBERATE: pull each submodule's tracked-branch HEAD. Review the diff before committing.
	@echo "WARNING: this pulls upstream HEAD of every submodule. Inspect 'git diff' before committing."
	@git submodule update --init --remote --recursive
	@echo ""
	@echo "Pin diffs (commit these to lock in the new SHAs):"
	@git diff --submodule=log -- projects/

.PHONY: status-all
status-all: ## Per-submodule git status one-liner + workspace status
	@bash bin/status-all.sh

.PHONY: sync-projects
sync-projects: ## Verify on-disk submodule SHAs match the workspace pin (no --remote pull)
	@bash bin/sync-projects.sh

# ---------------------------------------------------------------------------
# Daily ops
# ---------------------------------------------------------------------------

.PHONY: doctor
doctor: ## Fast static posture check (bash, no claude -p)
	@bash bin/doctor.sh

.PHONY: doctor-llm
doctor-llm: ## LLM-driven posture check (slower, more verbose narrative)
	@claude -p "/lsr-maintainer doctor"

.PHONY: run
run: ## Full nightly run (use cron entry for unattended scheduling)
	@claude -p "/lsr-maintainer run"

.PHONY: dry-run
dry-run: ## Show what tonight would do, change nothing
	@claude -p "/lsr-maintainer run --dry-run"

.PHONY: status
status: ## Show queue and last-run summary
	@claude -p "/lsr-maintainer status"

.PHONY: pending
pending: ## View state/PENDING_REVIEW.md
	@if [ -f state/PENDING_REVIEW.md ]; then less state/PENDING_REVIEW.md; \
	else echo "No PENDING_REVIEW.md yet — run 'make dry-run' or wait for nightly run."; fi

.PHONY: enable-role
enable-role: ## Enqueue a new-role enablement. Usage: make enable-role ROLE=squid FOR=sle16
	@if [ -z "$(ROLE)" ]; then echo "Usage: make enable-role ROLE=<name> [FOR=sle16|all]"; exit 1; fi
	@claude -p "/lsr-maintainer enable-role $(ROLE) --for $(or $(FOR),sle16)"

# ---------------------------------------------------------------------------
# Tests
# ---------------------------------------------------------------------------

.PHONY: test
test: test-hooks test-orchestrator ## Run all workspace tests

.PHONY: test-hooks
test-hooks: ## Unit-test security hooks against synthetic inputs (must pass before run)
	@bash tests/hooks/run-all.sh

.PHONY: test-orchestrator
test-orchestrator: ## Run orchestrator Python self-tests (config + state + manifest)
	@echo "== orchestrator/config self-test =="
	@python3 -m orchestrator.config
	@echo "== orchestrator/state_schema self-test =="
	@python3 -m orchestrator.state_schema
	@echo "== orchestrator/manifest_parse smoke (requires real spec) =="
	@spec=$$(find $$HOME/github/ansible -name 'ansible-linux-system-roles.spec' 2>/dev/null | head -1); \
	if [ -n "$$spec" ]; then \
	  python3 orchestrator/manifest_parse.py "$$spec" >/dev/null && echo "OK manifest parse ($$spec)"; \
	else \
	  echo "SKIP manifest parse (no spec file on this host — first 'osc co' will fetch it)"; \
	fi

.PHONY: test-all
test-all: test ## Alias: run workspace tests AND per-project tests
	@for d in projects/*/; do \
	  if [ -f "$$d/Makefile" ]; then echo "==> $$d"; $(MAKE) -C "$$d" test || true; fi; \
	done

# ---------------------------------------------------------------------------
# Hygiene
# ---------------------------------------------------------------------------

.PHONY: clean
clean: ## Remove state runtime artefacts (keeps workspace + submodules)
	@rm -f state/.lsr-maintainer-state.json state/.bootstrap-state.json state/PENDING_REVIEW.md
	@rm -rf state/cache

.PHONY: distclean
distclean: clean ## Also wipe tox venv and worktrees
	@rm -rf state/worktrees
	@rm -rf ~/.cache/lsr-maintainer
	@echo "tox venv at ~/github/ansible/testing/tox-lsr-venv/ NOT removed — delete manually if you want."

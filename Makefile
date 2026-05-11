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
pull-all: ## git submodule update --remote --recursive
	@git submodule update --init --remote --recursive

.PHONY: status-all
status-all: ## Per-submodule git status one-liner + workspace status
	@bash bin/status-all.sh

.PHONY: sync-projects
sync-projects: pull-all ## Pull all submodules and commit a pin bump if anything moved
	@bash bin/sync-projects.sh

# ---------------------------------------------------------------------------
# Daily ops
# ---------------------------------------------------------------------------

.PHONY: doctor
doctor: ## Green/red posture check (read-only, no install)
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
test-orchestrator: ## Smoke-test orchestrator Python modules
	@if [ -d orchestrator ] && ls orchestrator/*.py >/dev/null 2>&1; then \
	  cd orchestrator && python3 -m pytest -q || true; \
	else echo "No orchestrator tests yet — skipping."; fi

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

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
install: install-deps ## One-time host prep (dirs, venv, submodules). Does NOT install cron — manual-only by default. To schedule nightly runs later: `make install-cron`.

.PHONY: install-deps
install-deps: ## Idempotent host prep — directories, tox venv, submodule checkout
	@bash bin/install-deps.sh

.PHONY: install-cron
install-cron: ## OPT-IN: install nightly cron entry (03:07 local by default). Idempotent.
	@bash bin/install-cron.sh

.PHONY: uninstall-cron
uninstall-cron: ## Remove cron entry — leaves workspace + state intact
	@bash bin/install-cron.sh --remove

.PHONY: uninstall
uninstall: uninstall-cron ## Alias for uninstall-cron (back-compat)

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
run: ## Full run on demand. Live narration to terminal; full transcript + cost meter via bin/lsr-maintainer-run.sh.
	@bash bin/lsr-maintainer-run.sh

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

.PHONY: ack-enablement
ack-enablement: ## Remove a role from config.enablement.queue. Usage: make ack-enablement ROLE=logging
	@if [ -z "$(ROLE)" ]; then echo "Usage: make ack-enablement ROLE=<name>"; exit 1; fi
	@python3 -c "from orchestrator.config import ack_enablement_role; r=ack_enablement_role('state/config.json', '$(ROLE)'); print('OK removed' if r else 'NOOP not in queue')"

.PHONY: ack-host-lock
ack-host-lock: ## Re-confirm host fingerprint after a workspace move (TTY-only). Pairs with config.security.enforce_host_lock.
	@python3 -m orchestrator.host_lock --ack state/.lsr-maintainer-state.json

# ---------------------------------------------------------------------------
# Tests
# ---------------------------------------------------------------------------

.PHONY: test
test: test-hooks test-orchestrator ## Run all workspace tests

.PHONY: test-hooks
test-hooks: ## Unit-test security hooks against synthetic inputs (must pass before run)
	@bash tests/hooks/run-all.sh

.PHONY: test-orchestrator
test-orchestrator: ## Run orchestrator Python self-tests (config + state + manifest + anomaly + notify)
	@echo "== orchestrator/config self-test =="
	@python3 -m orchestrator.config
	@echo "== orchestrator/state_schema self-test =="
	@python3 -m orchestrator.state_schema
	@echo "== orchestrator/anomaly self-test =="
	@python3 -m orchestrator.anomaly
	@echo "== orchestrator/notify self-test =="
	@python3 -m orchestrator.notify
	@echo "== orchestrator/sanitize self-test =="
	@python3 -m orchestrator.sanitize
	@echo "== orchestrator/cost_meter self-test =="
	@python3 -m orchestrator.cost_meter
	@echo "== orchestrator/host_lock self-test =="
	@python3 -m orchestrator.host_lock
	@echo "== orchestrator/role_domains self-test =="
	@python3 -m orchestrator.role_domains
	@echo "== orchestrator/pending_review_render self-test =="
	@python3 -m orchestrator.pending_review_render
	@echo "== orchestrator/manifest_parse smoke (requires real spec) =="
	@ansible_root=$$(python3 -c "import sys; sys.path.insert(0,'.'); from orchestrator.config import load_config, get_path; print(get_path(load_config('state/config.json'), 'ansible_root'))"); \
	spec=$$(find "$$ansible_root" -name 'ansible-linux-system-roles.spec' 2>/dev/null | head -1); \
	if [ -n "$$spec" ]; then \
	  python3 orchestrator/manifest_parse.py "$$spec" >/dev/null && echo "OK manifest parse ($$spec)"; \
	else \
	  echo "SKIP manifest parse (no spec file under $$ansible_root — first 'osc co' will fetch it)"; \
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
clean: ## Remove state runtime artefacts (keeps workspace + var/ + submodules)
	@rm -f state/.lsr-maintainer-state.json state/.bootstrap-state.json state/PENDING_REVIEW.md
	@rm -rf state/cache

.PHONY: clean-var
clean-var: ## Reset mutable runtime data — wipes var/{iso,worktrees,cache}; preserves var/{log,venv} + clones
	@rm -rf var/iso/* var/worktrees/* var/cache/* 2>/dev/null || true
	@echo "var/log/ and var/venv/ preserved. To re-download Leap 16: rm var/iso/.leap-16.0-download-attempted then make install-deps."

.PHONY: distclean
distclean: clean ## Also wipe var/ entirely (logs, venv, clones, ISO, everything)
	@rm -rf state/worktrees
	@rm -rf var/
	@tox_venv=$$(python3 -c "import sys; sys.path.insert(0,'.'); from orchestrator.config import load_config, get_path; print(get_path(load_config('state/config.json'), 'tox_venv'))"); \
	echo "Removed var/. Tox venv at $$tox_venv is gone too — 'make install-deps' will recreate."

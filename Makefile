# Makefile for sharedactions-action-release-creator
# Run `make help` for available targets.

SHELL := /usr/bin/env bash
.DEFAULT_GOAL := help

SCRIPTS_DIR := scripts
TESTS_DIR   := tests

# ── Help ─────────────────────────────────────────────────────────────────────
.PHONY: help
help: ## Show this help message
	@grep -E '^[a-zA-Z_-]+:.*?## .*$$' $(MAKEFILE_LIST) \
		| awk 'BEGIN {FS = ":.*?## "}; {printf "  \033[36m%-20s\033[0m %s\n", $$1, $$2}'

# ── Setup ─────────────────────────────────────────────────────────────────────
.PHONY: setup
setup: ## Make all test scripts executable
	@find $(TESTS_DIR) -name '*.sh' -exec chmod +x {} \;
	@find $(SCRIPTS_DIR) -name '*.sh' -exec chmod +x {} \;
	@echo "Permissions set."

# ── Linting ───────────────────────────────────────────────────────────────────
.PHONY: shellcheck
shellcheck: ## Run ShellCheck on all shell scripts
	@command -v shellcheck >/dev/null 2>&1 || { echo "shellcheck not found. Install: brew install shellcheck"; exit 1; }
	@echo "Running ShellCheck..."
	@find $(SCRIPTS_DIR) $(TESTS_DIR) -name '*.sh' | sort | xargs shellcheck --shell=bash --severity=warning
	@echo "ShellCheck passed."

# ── Testing ───────────────────────────────────────────────────────────────────
.PHONY: test-all
test-all: setup ## Run all test suites (unit + integration + bats if available)
	@cd $(TESTS_DIR) && bash run_tests.sh

.PHONY: test-unit
test-unit: setup ## Run unit tests only
	@cd $(TESTS_DIR) && bash run_tests.sh unit

.PHONY: test-integration
test-integration: setup ## Run integration tests only
	@cd $(TESTS_DIR) && bash run_tests.sh integration

.PHONY: test-bats
test-bats: setup ## Run BATS tests (requires bats-core)
	@command -v bats >/dev/null 2>&1 || { echo "bats not found. Install: brew install bats-core"; exit 1; }
	@cd $(TESTS_DIR) && bash run_tests.sh bats

# ── Coverage ──────────────────────────────────────────────────────────────────
COVERAGE_THRESHOLD ?= 70

.PHONY: coverage
coverage: setup ## Measure script coverage with kcov (requires kcov + bats, Linux only)
	@command -v kcov >/dev/null 2>&1 \
		|| { echo "kcov not found (Linux only). Install: sudo apt-get install kcov"; exit 1; }
	@command -v bats >/dev/null 2>&1 \
		|| { echo "bats not found. Install: brew install bats-core"; exit 1; }
	@echo "Running kcov coverage (threshold: $(COVERAGE_THRESHOLD)%)..."
	@rm -rf coverage/
	@# Each BATS test invocation wraps script calls via tests/run-script.sh.
	@# This lets kcov instrument each subprocess without bats clearing BASH_ENV.
	@COVERAGE_DIR=$(CURDIR)/coverage bats tests/bats/release.bats
	@echo "Coverage report: coverage/ (open coverage/*/index.html in a browser)"
	@COVERAGE=$$(find coverage -name 'cobertura.xml' 2>/dev/null \
		| xargs -r grep -l 'generate-notes' 2>/dev/null \
		| head -1 \
		| xargs -r grep -oP 'line-rate="\K[0-9.]+' 2>/dev/null \
		| head -1 \
		| awk '{printf "%d", $$1 * 100}'); \
	if [ -z "$$COVERAGE" ]; then \
		echo "Warning: could not determine coverage percentage from cobertura.xml"; \
	elif [ "$$COVERAGE" -lt "$(COVERAGE_THRESHOLD)" ]; then \
		echo "Coverage $$COVERAGE% is below threshold $(COVERAGE_THRESHOLD)% — failing"; \
		exit 1; \
	else \
		echo "Coverage $$COVERAGE% meets threshold $(COVERAGE_THRESHOLD)%"; \
	fi

# ── Dependencies ─────────────────────────────────────────────────────────────
.PHONY: install-deps
install-deps: ## Install optional test dependencies (macOS; kcov requires Linux)
	@command -v brew >/dev/null 2>&1 || { echo "Homebrew not found. See https://brew.sh"; exit 1; }
	brew install bats-core shellcheck

# ── Clean ─────────────────────────────────────────────────────────────────────
.PHONY: clean
clean: ## Remove temporary test artifacts and coverage directory
	@rm -rf /tmp/release-creator-test-* /tmp/rc_test_* coverage/
	@echo "Cleaned."

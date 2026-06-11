#!/usr/bin/env bash
# tests/run_tests.sh — Primary test entry point for sharedactions-action-release-creator
#
# Usage:
#   ./run_tests.sh              # Run all suites
#   ./run_tests.sh unit         # Unit tests only
#   ./run_tests.sh integration  # Integration tests only
#   ./run_tests.sh bats         # BATS tests only (requires bats-core)

set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
TESTS_DIR="${REPO_ROOT}/tests"

SUITE="${1:-all}"
PASS=0
FAIL=0
SKIP=0

# ── Colour helpers ─────────────────────────────────────────────────────────
GREEN='\033[0;32m'
RED='\033[0;31m'
YELLOW='\033[1;33m'
NC='\033[0m'

pass() { echo -e "${GREEN}PASS${NC} $*"; ((PASS++)) || true; }
fail() { echo -e "${RED}FAIL${NC} $*"; ((FAIL++)) || true; }
skip() { echo -e "${YELLOW}SKIP${NC} $*"; ((SKIP++)) || true; }

run_suite() {
  local name="$1"
  local script="$2"
  if [[ -f "${script}" ]]; then
    echo ""
    echo "══════════════════════════════════════════"
    echo "  Suite: ${name}"
    echo "══════════════════════════════════════════"
    bash "${script}"
  else
    skip "Suite ${name}: ${script} not found"
  fi
}

# ── Ensure git config is set (required for tests that create commits) ───────
if ! git config user.name &>/dev/null || [[ -z "$(git config user.name)" ]]; then
  git config --global user.name "Release Creator Test"
fi
if ! git config user.email &>/dev/null || [[ -z "$(git config user.email)" ]]; then
  git config --global user.email "test@example.com"
fi

echo "════════════════════════════════════════════"
echo "  Release Creator — Test Suite"
echo "  Repo: ${REPO_ROOT}"
echo "════════════════════════════════════════════"

if [[ "${SUITE}" == "unit" || "${SUITE}" == "all" ]]; then
  run_suite "Unit: detect-prerelease" "${TESTS_DIR}/unit/test_detect_prerelease.sh"
  run_suite "Unit: filter-commits"    "${TESTS_DIR}/unit/test_filter_commits.sh"
  run_suite "Unit: generate-notes"    "${TESTS_DIR}/unit/test_generate_notes.sh"
fi

if [[ "${SUITE}" == "integration" || "${SUITE}" == "all" ]]; then
  run_suite "Integration: create-release" "${TESTS_DIR}/integration/test_create_release.sh"
fi

if [[ "${SUITE}" == "bats" || "${SUITE}" == "all" ]]; then
  if command -v bats &>/dev/null; then
    echo ""
    echo "══════════════════════════════════════════"
    echo "  Suite: BATS"
    echo "══════════════════════════════════════════"
    bats "${TESTS_DIR}/bats/" --tap || { echo "BATS tests failed"; exit 1; }
    echo "  Note: BATS results shown in TAP output above; not included in totals below."
  else
    skip "BATS tests: bats-core not installed (brew install bats-core)"
  fi
fi

echo ""
echo "════════════════════════════════════════════"
echo -e "  Results: ${GREEN}${PASS} passed${NC}  ${RED}${FAIL} failed${NC}  ${YELLOW}${SKIP} skipped${NC}"
echo "════════════════════════════════════════════"

[[ ${FAIL} -eq 0 ]]

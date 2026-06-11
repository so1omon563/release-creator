#!/usr/bin/env bash
# tests/run-script.sh
#
# Thin runner for any script under scripts/.
#
# When COVERAGE_DIR is set, wraps the target script with kcov so each
# individual test invocation is instrumented directly. This bypasses the
# kcov subprocess-tracking limitation where bats clears BASH_ENV before
# spawning child processes, which prevents coverage data from reaching
# the production script when kcov wraps bats at the top level.
#
# Usage:
#   tests/run-script.sh scripts/generate-notes.sh   [args...]
#   COVERAGE_DIR=/tmp/cov tests/run-script.sh scripts/filter-commits.sh
#
# Environment:
#   COVERAGE_DIR   When set, kcov is used to instrument the script.
#                  Multiple invocations merge into the same directory.

set -euo pipefail

SCRIPT="${1}"
shift

if [ -n "${COVERAGE_DIR:-}" ] && command -v kcov >/dev/null 2>&1; then
  # Run the script directly (not via 'bash script') so kcov reads the shebang
  # and activates its bash-script engine rather than treating bash as an ELF binary.
  exec kcov \
    --include-path="${SCRIPT}" \
    "${COVERAGE_DIR}" \
    "${SCRIPT}" "$@"
else
  exec bash "${SCRIPT}" "$@"
fi

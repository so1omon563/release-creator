#!/usr/bin/env bash
# tests/unit/test_detect_prerelease.sh
# Unit tests for scripts/detect-prerelease.sh

set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
# shellcheck source=../../scripts/detect-prerelease.sh
source "${REPO_ROOT}/scripts/detect-prerelease.sh"

PASS=0
FAIL=0

check() {
  local desc="$1"
  local expected="$2"
  local actual="$3"
  if [[ "${actual}" == "${expected}" ]]; then
    echo "  PASS: ${desc}"
    ((PASS++)) || true
  else
    echo "  FAIL: ${desc}"
    echo "        expected='${expected}' got='${actual}'"
    ((FAIL++)) || true
  fi
}

echo "--- detect-prerelease unit tests ---"

# ── Common pre-release suffixes → true ──────────────────────────────────────
check "alpha suffix"       "true" "$(is_prerelease "v1.0.0-alpha")"
check "alpha.1 suffix"     "true" "$(is_prerelease "v1.0.0-alpha.1")"
check "beta suffix"        "true" "$(is_prerelease "v1.0.0-beta")"
check "beta.2 suffix"      "true" "$(is_prerelease "v1.0.0-beta.2")"
check "rc suffix"          "true" "$(is_prerelease "v1.0.0-rc.1")"
check "rc no number"       "true" "$(is_prerelease "v1.0.0-rc")"
check "pre suffix"         "true" "$(is_prerelease "v1.0.0-pre")"
check "pre.1 suffix"       "true" "$(is_prerelease "v1.0.0-pre.1")"
check "preview suffix"     "true" "$(is_prerelease "v2.0.0-preview")"
check "dev suffix"         "true" "$(is_prerelease "v1.0.0-dev")"
check "snapshot suffix"    "true" "$(is_prerelease "v1.0.0-snapshot")"
check "canary suffix"      "true" "$(is_prerelease "v1.0.0-canary")"
check "next suffix"        "true" "$(is_prerelease "v2.0.0-next")"
check "nightly suffix"     "true" "$(is_prerelease "v1.0.0-nightly")"

# ── Arbitrary SemVer §9 pre-release identifiers → true ──────────────────────
# sharedactions-action-custom-semver-bumper supports custom allowed_prerelease_suffixes
# (e.g. enterprise, team-blue, canary). Any hyphenated identifier is SemVer pre-release.
check "arbitrary identifier"         "true" "$(is_prerelease "v1.2.3-enterprise.1")"
check "hyphenated identifier"        "true" "$(is_prerelease "v1.2.3-team-blue.3")"
check "numeric pre-release"          "true" "$(is_prerelease "v1.2.3-1")"
check "custom nightly identifier"    "true" "$(is_prerelease "v1.0.0-nightly.20260101")"

# ── SemVer §10 build metadata — stable unless also has pre-release label ────
check "build metadata only (stable)"         "false" "$(is_prerelease "v1.2.3+sha.abc1234")"
check "build metadata only v prefix"         "false" "$(is_prerelease "v2.0.0+build.42")"
check "pre-release + build metadata (true)"  "true"  "$(is_prerelease "v1.2.3-alpha.1+sha.abc1234")"
check "rc + build metadata (true)"           "true"  "$(is_prerelease "v1.0.0-rc.2+sha.def5678")"
check "enterprise + build metadata (true)"   "true"  "$(is_prerelease "v1.0.0-enterprise.1+sha.abc")"

# ── Stable tags → false ─────────────────────────────────────────────────────
check "stable semver"      "false" "$(is_prerelease "v1.0.0")"
check "stable v2"          "false" "$(is_prerelease "v2.3.4")"
check "no v prefix"        "false" "$(is_prerelease "1.0.0")"
check "patch release"      "false" "$(is_prerelease "v0.1.5")"

# ── With tag prefix stripping ────────────────────────────────────────────────
check "prefix stripped stable"     "false" "$(is_prerelease "app/v1.0.0" "app/")"
check "prefix stripped prerelease" "true"  "$(is_prerelease "app/v1.0.0-rc.1" "app/")"

# ── Direct execution exit code behaviour ────────────────────────────────────
# Pre-release tags exit 0; stable tags exit 1 (from: [[ result == "true" ]])
pre_exit=0
DETECT_TAG="v1.0.0-rc.1" bash "${REPO_ROOT}/scripts/detect-prerelease.sh" > /dev/null || pre_exit=$?
check "direct exec: pre-release tag exits 0" "0" "${pre_exit}"

stable_exit=0
DETECT_TAG="v1.0.0" bash "${REPO_ROOT}/scripts/detect-prerelease.sh" > /dev/null || stable_exit=$?
check "direct exec: stable tag exits 1" "1" "${stable_exit}"

echo ""
echo "detect-prerelease: ${PASS} passed, ${FAIL} failed"
[[ ${FAIL} -eq 0 ]]

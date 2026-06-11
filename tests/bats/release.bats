#!/usr/bin/env bats
# tests/bats/release.bats
# BATS tests for the release creator action scripts.
# Requires: bats-core (brew install bats-core)

REPO_ROOT="$(cd "$(dirname "${BATS_TEST_FILENAME}")/../.." && pwd)"

setup() {
  TMPDIR="$(mktemp -d /tmp/rc_bats_XXXXXX)"
  cd "${TMPDIR}"
  git init -q
  git config user.email "bats@test.com"
  git config user.name "Bats Test"

  echo "init" > README.md
  git add README.md
  git commit -q -m "chore: initial commit"
  git tag v1.0.0

  echo "a" > a.txt; git add a.txt; git commit -q -m "feat: implement search"
  echo "b" > b.txt; git add b.txt; git commit -q -m "fix(api): handle timeout"
  echo "c" > c.txt; git add c.txt; git commit -q -m "docs: update contributing guide"
  echo "d" > d.txt; git add d.txt; git commit -q -m "breaking change without conventional prefix"
  git tag v1.1.0

  export ACTION_PATH="${REPO_ROOT}"
  export RUN_SCRIPT="${REPO_ROOT}/tests/run-script.sh"
}

teardown() {
  rm -rf "${TMPDIR}"
}

# ── detect-prerelease ──────────────────────────────────────────────────────
@test "detect-prerelease: rc tag returns true" {
  source "${REPO_ROOT}/scripts/detect-prerelease.sh"
  result="$(is_prerelease "v2.0.0-rc.1")"
  [ "${result}" = "true" ]
}

@test "detect-prerelease: stable tag returns false" {
  source "${REPO_ROOT}/scripts/detect-prerelease.sh"
  result="$(is_prerelease "v2.0.0")"
  [ "${result}" = "false" ]
}

@test "detect-prerelease: alpha returns true" {
  source "${REPO_ROOT}/scripts/detect-prerelease.sh"
  result="$(is_prerelease "v1.0.0-alpha.3")"
  [ "${result}" = "true" ]
}

@test "detect-prerelease: nightly returns true" {
  source "${REPO_ROOT}/scripts/detect-prerelease.sh"
  result="$(is_prerelease "v1.0.0-nightly")"
  [ "${result}" = "true" ]
}

@test "detect-prerelease: DETECT_TAG env var works" {
  run env DETECT_TAG="v3.0.0-beta.1" \
    "${RUN_SCRIPT}" "${REPO_ROOT}/scripts/detect-prerelease.sh"
  [ "${output}" = "true" ]
}

@test "detect-prerelease: missing DETECT_TAG exits with code 2" {
  run "${RUN_SCRIPT}" "${REPO_ROOT}/scripts/detect-prerelease.sh"
  [ "${status}" -eq 2 ]
}

# ── filter-commits ─────────────────────────────────────────────────────────
@test "filter-commits: returns commits in range" {
  output="$(FROM_TAG="v1.0.0" TO_TAG="v1.1.0" PATH_FILTER="" TAG_PREFIX="" \
    "${RUN_SCRIPT}" "${REPO_ROOT}/scripts/filter-commits.sh")"
  echo "${output}" | grep -q "feat: implement search"
}

@test "filter-commits: excludes out-of-range commits" {
  output="$(FROM_TAG="v1.0.0" TO_TAG="v1.1.0" PATH_FILTER="" TAG_PREFIX="" \
    "${RUN_SCRIPT}" "${REPO_ROOT}/scripts/filter-commits.sh")"
  ! echo "${output}" | grep -q "chore: initial commit"
}

@test "filter-commits: empty range returns no output" {
  output="$(FROM_TAG="v1.1.0" TO_TAG="v1.1.0" PATH_FILTER="" TAG_PREFIX="" \
    "${RUN_SCRIPT}" "${REPO_ROOT}/scripts/filter-commits.sh" || true)"
  [ -z "${output}" ]
}

@test "filter-commits: missing TO_TAG exits with code 2" {
  run env FROM_TAG="" TO_TAG="" PATH_FILTER="" TAG_PREFIX="" \
    "${RUN_SCRIPT}" "${REPO_ROOT}/scripts/filter-commits.sh"
  [ "${status}" -eq 2 ]
}

@test "filter-commits: path filter scopes commits" {
  mkdir -p svc; echo "x" > svc/x.sh; git add svc/; git commit -q -m "feat(svc): add svc"
  git tag v1.2.0

  output="$(FROM_TAG="v1.1.0" TO_TAG="v1.2.0" PATH_FILTER="svc" TAG_PREFIX="" \
    "${RUN_SCRIPT}" "${REPO_ROOT}/scripts/filter-commits.sh")"
  echo "${output}" | grep -q "feat(svc)"
}

# ── generate-notes ─────────────────────────────────────────────────────────
@test "generate-notes: grouped format has emoji headers" {
  output="$(FROM_TAG="v1.0.0" TO_TAG="v1.1.0" NOTES_FORMAT="grouped" \
    PATH_FILTER="" TAG_PREFIX="" ACTION_PATH="${REPO_ROOT}" \
    "${RUN_SCRIPT}" "${REPO_ROOT}/scripts/generate-notes.sh")"
  echo "${output}" | grep -q "🚀 Features"
  echo "${output}" | grep -q "🐛 Bug Fixes"
}

@test "generate-notes: conventional format preserves type prefix" {
  output="$(FROM_TAG="v1.0.0" TO_TAG="v1.1.0" NOTES_FORMAT="conventional" \
    PATH_FILTER="" TAG_PREFIX="" ACTION_PATH="${REPO_ROOT}" \
    "${RUN_SCRIPT}" "${REPO_ROOT}/scripts/generate-notes.sh")"
  echo "${output}" | grep -q "feat: implement search"
}

@test "generate-notes: flat format strips type prefix" {
  # Use $() to capture stdout only — generate-notes.sh logs commit subjects to
  # stderr (via its log helpers), which would otherwise pollute ${output} and
  # cause the negation check below to incorrectly fail.
  output="$(FROM_TAG="v1.0.0" TO_TAG="v1.1.0" NOTES_FORMAT="flat" \
    PATH_FILTER="" TAG_PREFIX="" ACTION_PATH="${REPO_ROOT}" \
    "${RUN_SCRIPT}" "${REPO_ROOT}/scripts/generate-notes.sh")"
  echo "${output}" | grep -q "implement search"
  ! echo "${output}" | grep -q "feat:"
}

@test "generate-notes: github-native outputs --generate-notes flag" {
  output="$(FROM_TAG="v1.0.0" TO_TAG="v1.1.0" NOTES_FORMAT="github-native" \
    PATH_FILTER="" TAG_PREFIX="" ACTION_PATH="${REPO_ROOT}" \
    "${RUN_SCRIPT}" "${REPO_ROOT}/scripts/generate-notes.sh")"
  [ "${output}" = "--generate-notes" ]
}

@test "generate-notes: empty commit range returns fallback message" {
  output="$(FROM_TAG="v1.1.0" TO_TAG="v1.1.0" NOTES_FORMAT="grouped" \
    PATH_FILTER="" TAG_PREFIX="" ACTION_PATH="${REPO_ROOT}" \
    "${RUN_SCRIPT}" "${REPO_ROOT}/scripts/generate-notes.sh" || true)"
  echo "${output}" | grep -qi "no changes"
}

@test "generate-notes: unknown format exits non-zero" {
  run env FROM_TAG="v1.0.0" TO_TAG="v1.1.0" NOTES_FORMAT="invalid" \
    PATH_FILTER="" TAG_PREFIX="" ACTION_PATH="${REPO_ROOT}" \
    "${RUN_SCRIPT}" "${REPO_ROOT}/scripts/generate-notes.sh"
  [ "${status}" -ne 0 ]
}

@test "generate-notes: non-conventional commits grouped under Other" {
  output="$(FROM_TAG="v1.0.0" TO_TAG="v1.1.0" NOTES_FORMAT="grouped" \
    PATH_FILTER="" TAG_PREFIX="" ACTION_PATH="${REPO_ROOT}" \
    "${RUN_SCRIPT}" "${REPO_ROOT}/scripts/generate-notes.sh")"
  echo "${output}" | grep -q "📦 Other Changes"
}

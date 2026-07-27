#!/usr/bin/env bash
# tests/unit/test_filter_commits.sh
# Unit tests for scripts/filter-commits.sh

set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
FILTER_SCRIPT="${REPO_ROOT}/scripts/filter-commits.sh"

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
    echo "        expected: '${expected}'"
    echo "        got:      '${actual}'"
    ((FAIL++)) || true
  fi
}

check_contains() {
  local desc="$1"
  local needle="$2"
  local haystack="$3"
  if echo "${haystack}" | grep -qF -- "${needle}"; then
    echo "  PASS: ${desc}"
    ((PASS++)) || true
  else
    echo "  FAIL: ${desc}"
    echo "        expected to find: '${needle}'"
    echo "        in: '${haystack}'"
    ((FAIL++)) || true
  fi
}

check_not_contains() {
  local desc="$1"
  local needle="$2"
  local haystack="$3"
  if ! echo "${haystack}" | grep -qF -- "${needle}"; then
    echo "  PASS: ${desc}"
    ((PASS++)) || true
  else
    echo "  FAIL: ${desc}"
    echo "        expected NOT to find: '${needle}'"
    echo "        in: '${haystack}'"
    ((FAIL++)) || true
  fi
}

# ── Setup a temporary git repo for testing ──────────────────────────────────
echo "--- filter-commits unit tests ---"

TMPDIR="$(mktemp -d /tmp/rc_test_filter_XXXXXX)"
# shellcheck disable=SC2064
trap "rm -rf '${TMPDIR}'" EXIT

cd "${TMPDIR}"
git init -q
git config user.email "test@example.com"
git config user.name "Test"

echo "init" > README.md
git add README.md
git commit -q -m "chore: initial commit"
git tag v0.1.0

echo "feat1" > feat1.txt
git add feat1.txt
git commit -q -m "feat: add feature one"

echo "fix1" > fix1.txt
git add fix1.txt
git commit -q -m "fix: resolve issue one"

mkdir -p service-a
echo "a" > service-a/code.sh
git add service-a/
git commit -q -m "feat(service-a): add service a"

git tag v0.2.0

echo "chore1" > chore1.txt
git add chore1.txt
git commit -q -m "chore: maintenance work"

mkdir -p service-b
echo "b" > service-b/code.sh
git add service-b/
git commit -q -m "feat(service-b): add service b"

git tag v0.3.0

# Test: commit range without path filter
output="$(FROM_TAG="v0.2.0" TO_TAG="v0.3.0" PATH_FILTER="" TAG_PREFIX="" \
  bash "${FILTER_SCRIPT}")"
check_contains "range includes chore commit"       "chore: maintenance work"   "${output}"
check_contains "range includes service-b commit"   "feat(service-b): add service b" "${output}"
check_not_contains "range excludes pre-range commits" "feat: add feature one" "${output}"

# Test: path filter scopes to subdirectory
output_filtered="$(FROM_TAG="v0.1.0" TO_TAG="v0.2.0" PATH_FILTER="service-a" TAG_PREFIX="" \
  bash "${FILTER_SCRIPT}")"
check_contains "path filter includes service-a commit" "feat(service-a): add service a" "${output_filtered}"
check_not_contains "path filter excludes other commits"  "feat: add feature one" "${output_filtered}"

# Test: no FROM_TAG includes full history
output_auto="$(FROM_TAG="" TO_TAG="v0.3.0" PATH_FILTER="" TAG_PREFIX="" \
  bash "${FILTER_SCRIPT}")"
check_contains "empty FROM_TAG: includes latest commit" "feat(service-b)" "${output_auto}"
check_contains "empty FROM_TAG: includes pre-tag history" "feat: add feature one" "${output_auto}"

# Test: empty range returns empty output
output_empty="$(FROM_TAG="v0.3.0" TO_TAG="v0.3.0" PATH_FILTER="" TAG_PREFIX="" \
  bash "${FILTER_SCRIPT}" || true)"
check "empty range: returns empty output" "" "${output_empty}"

# Test: merge commits are excluded by --no-merges
initial_branch="$(git branch --show-current)"
git checkout -q -b merge-test-branch
echo "feature" > merge_feature.txt
git add merge_feature.txt
git commit -q -m "feat(merge-test): add feature in separate branch"
git checkout -q "${initial_branch}"
git merge --no-ff merge-test-branch -q -m "Merge branch merge-test-branch"
git tag v0.4.0

output_merge="$(FROM_TAG="v0.3.0" TO_TAG="v0.4.0" PATH_FILTER="" TAG_PREFIX="" \
  bash "${FILTER_SCRIPT}")"
check_contains "merge: feature commit included"  "feat(merge-test)"  "${output_merge}"
check_not_contains "merge: merge commit excluded" "Merge branch"     "${output_merge}"

# Test: prefixed tag names work in explicit ranges
git tag app/v0.1.0 v0.3.0^{}  # point app prefix tag at the v0.3.0 commit
echo "app_feat" > app_feat.txt
git add app_feat.txt
git commit -q -m "feat(app): add app feature"
git tag app/v0.2.0

output_prefix="$(FROM_TAG="app/v0.1.0" TO_TAG="app/v0.2.0" PATH_FILTER="" TAG_PREFIX="app/" \
  bash "${FILTER_SCRIPT}")"
check_contains "prefixed range: includes commit after app/v0.1.0" "feat(app): add app feature" "${output_prefix}"
check_not_contains "prefixed range: excludes commits before app/v0.1.0" "feat(service-b)" "${output_prefix}"

echo ""
echo "filter-commits: ${PASS} passed, ${FAIL} failed"
[[ ${FAIL} -eq 0 ]]

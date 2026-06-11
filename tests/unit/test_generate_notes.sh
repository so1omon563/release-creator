#!/usr/bin/env bash
# tests/unit/test_generate_notes.sh
# Unit tests for scripts/generate-notes.sh

set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
GENERATE_SCRIPT="${REPO_ROOT}/scripts/generate-notes.sh"

PASS=0
FAIL=0

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
    echo "        in:"
    echo "${haystack}" | head -20 | sed 's/^/          /'
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
    ((FAIL++)) || true
  fi
}

echo "--- generate-notes unit tests ---"

TMPDIR="$(mktemp -d /tmp/rc_test_notes_XXXXXX)"
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

echo "a" > a.txt; git add a.txt; git commit -q -m "feat: add new user export"
echo "b" > b.txt; git add b.txt; git commit -q -m "fix: handle nil pointer in parser"
echo "c" > c.txt; git add c.txt; git commit -q -m "docs: update README with examples"
echo "d" > d.txt; git add d.txt; git commit -q -m "chore: bump dependencies"
echo "e" > e.txt; git add e.txt; git commit -q -m "feat(api): add pagination support"
echo "f" > f.txt; git add f.txt; git commit -q -m "fix(auth): resolve token expiry race condition"
echo "g" > g.txt; git add g.txt; git commit -q -m "not a conventional commit"

git tag v0.2.0

# ── grouped format ────────────────────────────────────────────────────────
notes_grouped="$(FROM_TAG="v0.1.0" TO_TAG="v0.2.0" NOTES_FORMAT="grouped" \
  PATH_FILTER="" TAG_PREFIX="" ACTION_PATH="${REPO_ROOT}" \
  bash "${GENERATE_SCRIPT}")"

check_contains "grouped: Features section header"    "🚀 Features"             "${notes_grouped}"
check_contains "grouped: Bug Fixes section header"   "🐛 Bug Fixes"            "${notes_grouped}"
check_contains "grouped: Documentation header"       "📖 Documentation"        "${notes_grouped}"
check_contains "grouped: Chores header"              "🧹 Chores"               "${notes_grouped}"
check_contains "grouped: feat description present"   "add new user export"     "${notes_grouped}"
check_contains "grouped: fix description present"    "handle nil pointer"      "${notes_grouped}"
check_contains "grouped: non-conventional in Other"  "not a conventional commit" "${notes_grouped}"
check_not_contains "grouped: no raw type prefix feat:" "feat:" "${notes_grouped}"

# ── conventional format ───────────────────────────────────────────────────
notes_conv="$(FROM_TAG="v0.1.0" TO_TAG="v0.2.0" NOTES_FORMAT="conventional" \
  PATH_FILTER="" TAG_PREFIX="" ACTION_PATH="${REPO_ROOT}" \
  bash "${GENERATE_SCRIPT}")"

check_contains "conventional: has feat: prefix"  "feat: add new user export"  "${notes_conv}"
check_contains "conventional: has fix: prefix"   "fix: handle nil pointer"    "${notes_conv}"
check_contains "conventional: has scoped entry"  "feat(api): add pagination"  "${notes_conv}"
check_contains "conventional: has short sha"     '`'                          "${notes_conv}"

# ── flat format ───────────────────────────────────────────────────────────
notes_flat="$(FROM_TAG="v0.1.0" TO_TAG="v0.2.0" NOTES_FORMAT="flat" \
  PATH_FILTER="" TAG_PREFIX="" ACTION_PATH="${REPO_ROOT}" \
  bash "${GENERATE_SCRIPT}")"

check_contains "flat: shows description"      "add new user export"       "${notes_flat}"
check_contains "flat: shows fix description"  "handle nil pointer"        "${notes_flat}"
check_not_contains "flat: no feat: prefix"    "feat:"                     "${notes_flat}"
check_not_contains "flat: no fix: prefix"     "fix:"                      "${notes_flat}"

# ── github-native format ──────────────────────────────────────────────────
notes_native="$(FROM_TAG="v0.1.0" TO_TAG="v0.2.0" NOTES_FORMAT="github-native" \
  PATH_FILTER="" TAG_PREFIX="" ACTION_PATH="${REPO_ROOT}" \
  bash "${GENERATE_SCRIPT}")"

check_contains "github-native: outputs flag" "--generate-notes" "${notes_native}"

# ── empty range ───────────────────────────────────────────────────────────
notes_empty="$(FROM_TAG="v0.2.0" TO_TAG="v0.2.0" NOTES_FORMAT="grouped" \
  PATH_FILTER="" TAG_PREFIX="" ACTION_PATH="${REPO_ROOT}" \
  bash "${GENERATE_SCRIPT}")"

check_contains "empty range: fallback message" "No changes" "${notes_empty}"

# ── Additional grouped type coverage ─────────────────────────────────────
# Extend the repo with commits covering all remaining conventional types
echo "p"  > p.txt;  git add p.txt;  git commit -q -m "perf: optimize database query"
echo "rf" > rf.txt; git add rf.txt; git commit -q -m "refactor: extract helper functions"
echo "t"  > t.txt;  git add t.txt;  git commit -q -m "test: add integration test for auth"
echo "ci" > ci.txt; git add ci.txt; git commit -q -m "ci: add github actions workflow"
echo "bd" > bd.txt; git add bd.txt; git commit -q -m "build: update webpack config"
echo "st" > st.txt; git add st.txt; git commit -q -m "style: format with prettier"
echo "rv" > rv.txt; git add rv.txt; git commit -q -m "revert: undo previous change"
echo "bp" > bp.txt; git add bp.txt; git commit -q -m "feat!: remove deprecated login endpoint"
git tag v0.3.0

notes_types="$(FROM_TAG="v0.2.0" TO_TAG="v0.3.0" NOTES_FORMAT="grouped" \
  PATH_FILTER="" TAG_PREFIX="" ACTION_PATH="${REPO_ROOT}" \
  bash "${GENERATE_SCRIPT}")"

check_contains "grouped: perf section header"     "⚡ Performance"        "${notes_types}"
check_contains "grouped: refactor section header" "Refactor"             "${notes_types}"
check_contains "grouped: test section header"     "🧪 Tests"             "${notes_types}"
check_contains "grouped: ci section header"       "🔧 CI/CD"             "${notes_types}"
check_contains "grouped: build section header"    "Build"                "${notes_types}"
check_contains "grouped: style section header"    "💅 Style"             "${notes_types}"
check_contains "grouped: revert section header"   "⏪ Reverts"           "${notes_types}"
check_contains "grouped: breaking feat in Features section" \
  "remove deprecated login endpoint"              "${notes_types}"
check_contains "grouped: perf description present"     "optimize database query"      "${notes_types}"
check_contains "grouped: refactor description present" "extract helper functions"     "${notes_types}"

echo ""
echo "generate-notes: ${PASS} passed, ${FAIL} failed"
[[ ${FAIL} -eq 0 ]]

#!/usr/bin/env bash
# tests/integration/test_create_release.sh
# Integration tests for scripts/create-release.sh using a mocked gh CLI.

set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"

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

# ── Setup test environment ────────────────────────────────────────────────
TMPDIR="$(mktemp -d /tmp/rc_test_integration_XXXXXX)"
# shellcheck disable=SC2064
trap "rm -rf '${TMPDIR}'" EXIT

# Set up a fake git repo
cd "${TMPDIR}"
git init -q
git config user.email "test@example.com"
git config user.name "Test"

echo "init" > README.md
git add README.md
git commit -q -m "chore: initial commit"
git tag v0.1.0

echo "a" > a.txt; git add a.txt; git commit -q -m "feat: add export feature"
echo "b" > b.txt; git add b.txt; git commit -q -m "fix: correct null check"
git tag v0.2.0

# Mock gh CLI
MOCK_GH="${TMPDIR}/bin/gh"
mkdir -p "${TMPDIR}/bin"
cat > "${MOCK_GH}" << 'EOF'
#!/usr/bin/env bash
# Mock gh CLI that records invocations and returns fake JSON

CALL_LOG="${MOCK_GH_CALL_LOG:-/tmp/mock_gh_calls.log}"

case "${1:-}" in
  release)
    case "${2:-}" in
      view)
        # Handle --json id,url,uploadUrl (post-create metadata fetch)
        if [[ "${*}" == *"--json"* && "${*}" == *"uploadUrl"* ]]; then
          _tag="${3}"
          echo '{"id":12345,"url":"https://github.com/test/repo/releases/tag/'"${_tag}"'","uploadUrl":"https://uploads.github.com/repos/test/repo/releases/12345/assets{?name,label}"}'
          exit 0
        fi
        # Simulate "release not found" unless MOCK_RELEASE_EXISTS=true
        if [[ "${MOCK_RELEASE_EXISTS:-false}" == "true" ]]; then
          echo '{"tagName":"'"${3}"'"}'
          exit 0
        else
          echo "release not found" >&2
          exit 1
        fi
        ;;
      list)
        if [[ "${MOCK_RELEASE_LIST_FAIL:-false}" == "true" ]]; then
          echo "authentication failed" >&2
          exit 1
        fi
        printf '%s\n' "${MOCK_RELEASE_TAGS:-${MOCK_PREVIOUS_RELEASE_TAG:-}}"
        exit 0
        ;;
      create)
        if [[ "${MOCK_CREATE_FAIL:-false}" == "true" ]]; then
          echo "error: release creation failed" >&2
          exit 1
        fi
        echo "$@" >> "${CALL_LOG}"
        # gh release create outputs the release URL to stdout
        echo "https://github.com/test/repo/releases/tag/v0.2.0"
        exit 0
        ;;
    esac
    ;;
  api)
    # Handle gh api calls for floating tag ref creation/update
    echo "$@" >> "${CALL_LOG}"
    if [[ "${2:-}" == "repos/{owner}/{repo}" ]]; then
      echo "main"
      exit 0
    fi
    if [[ "${2:-}" == "repos/{owner}/{repo}/commits/"* ]]; then
      printf '%s\n' "${MOCK_TARGET_SHA:-$(git rev-parse HEAD)}"
      exit 0
    fi
    if [[ "${*}" == *"/releases/generate-notes"* ]]; then
      if [[ "${MOCK_NATIVE_NOTES_FAIL:-false}" == "true" ]]; then
        echo "release notes generation failed" >&2
        exit 1
      fi
      printf '%s\n' "${MOCK_NATIVE_NOTES:-Generated GitHub-native notes}"
      exit 0
    fi
    # PATCH repos/.../git/refs/tags/... — update existing ref
    # POST  repos/.../git/refs         — create new ref
    # Both succeed silently
    exit 0
    ;;
esac
echo "mock gh: unhandled command $*" >&2
exit 1
EOF
chmod +x "${MOCK_GH}"
export PATH="${TMPDIR}/bin:${PATH}"

CALL_LOG="${TMPDIR}/gh_calls.log"
export MOCK_GH_CALL_LOG="${CALL_LOG}"
export GH_TOKEN="test-token"
export GITHUB_OUTPUT="${TMPDIR}/github_output.txt"
export ACTION_PATH="${REPO_ROOT}"

run_create_release() {
  "${REPO_ROOT}/tests/run-script.sh" "${REPO_ROOT}/scripts/create-release.sh"
}

echo "--- integration: create-release ---"

# ── Test 1: Basic release creation ───────────────────────────────────────
: > "${CALL_LOG}"
: > "${GITHUB_OUTPUT}"

INPUT_TAG="v0.2.0" \
INPUT_RELEASE_NAME="" \
INPUT_BODY="" \
INPUT_DRAFT="false" \
INPUT_PRERELEASE="auto" \
INPUT_TARGET_COMMITISH="" \
INPUT_NOTES_FORMAT="grouped" \
INPUT_FROM_TAG="v0.1.0" \
INPUT_TO_TAG="v0.2.0" \
INPUT_ASSET_PATHS="" \
INPUT_SKIP_IF_RELEASE_EXISTS="false" \
INPUT_PATH_FILTER="" \
INPUT_TAG_PREFIX="" \
INPUT_FAIL_ON_ERROR="true" \
run_create_release

output_content="$(cat "${GITHUB_OUTPUT}")"
check_contains "basic: created=true in output"   "created"    "${output_content}"
check_contains "basic: tag-name in output"        "v0.2.0"     "${output_content}"
check_contains "basic: release-url in output"     "releases"   "${output_content}"

# ── Test 2: Pre-release auto-detection ────────────────────────────────────
: > "${GITHUB_OUTPUT}"

git tag v0.3.0-rc.1

INPUT_TAG="v0.3.0-rc.1" \
INPUT_RELEASE_NAME="" \
INPUT_BODY="" \
INPUT_DRAFT="false" \
INPUT_PRERELEASE="auto" \
INPUT_TARGET_COMMITISH="" \
INPUT_NOTES_FORMAT="flat" \
INPUT_FROM_TAG="v0.2.0" \
INPUT_TO_TAG="v0.3.0-rc.1" \
INPUT_ASSET_PATHS="" \
INPUT_SKIP_IF_RELEASE_EXISTS="false" \
INPUT_PATH_FILTER="" \
INPUT_TAG_PREFIX="" \
INPUT_FAIL_ON_ERROR="true" \
run_create_release

gh_call="$(cat "${CALL_LOG}")"
check_contains "prerelease: --prerelease flag passed" "--prerelease" "${gh_call}"

# ── Test 3: skip-if-release-exists=true when release exists ─────────────
: > "${GITHUB_OUTPUT}"
export MOCK_RELEASE_EXISTS="true"

INPUT_TAG="v0.2.0" \
INPUT_RELEASE_NAME="" \
INPUT_BODY="" \
INPUT_DRAFT="false" \
INPUT_PRERELEASE="false" \
INPUT_TARGET_COMMITISH="" \
INPUT_NOTES_FORMAT="grouped" \
INPUT_FROM_TAG="" \
INPUT_TO_TAG="" \
INPUT_ASSET_PATHS="" \
INPUT_SKIP_IF_RELEASE_EXISTS="true" \
INPUT_PATH_FILTER="" \
INPUT_TAG_PREFIX="" \
INPUT_FAIL_ON_ERROR="true" \
run_create_release

skip_output="$(cat "${GITHUB_OUTPUT}")"
check_contains "skip: skipped=true in output"  "skipped" "${skip_output}"
check_contains "skip: created=false in output" "false"   "${skip_output}"

unset MOCK_RELEASE_EXISTS

# ── Test 4: tag-push ref is inferred when INPUT_TAG is empty ──────────────
: > "${CALL_LOG}"
: > "${GITHUB_OUTPUT}"

INPUT_TAG="" \
GITHUB_REF_TYPE="tag" \
GITHUB_REF_NAME="v0.2.0" \
INPUT_BODY="tag push release" \
INPUT_PRERELEASE="false" \
INPUT_FAIL_ON_ERROR="true" \
run_create_release

check_contains "tag-ref: inferred tag passed to gh" \
  "release create v0.2.0" "$(cat "${CALL_LOG}")"

# ── Test 4b: branch ref is rejected when INPUT_TAG is empty ───────────────
: > "${CALL_LOG}"
exit_code=0
branch_ref_output="$(
  INPUT_TAG="" \
  GITHUB_REF_TYPE="branch" \
  GITHUB_REF_NAME="main" \
  INPUT_BODY="branch release" \
  INPUT_FAIL_ON_ERROR="true" \
  run_create_release 2>&1
)" || exit_code=$?

check "branch-ref: exits non-zero" "1" "${exit_code}"
check_contains "branch-ref: reports missing tag" \
  "tag input is required" "${branch_ref_output}"
check_not_contains "branch-ref: release not created" \
  "release create" "$(cat "${CALL_LOG}")"

# ── Test 4c: pull-request ref is rejected when INPUT_TAG is empty ─────────
: > "${CALL_LOG}"
exit_code=0
pr_ref_output="$(
  INPUT_TAG="" \
  GITHUB_REF_TYPE="branch" \
  GITHUB_REF_NAME="2/merge" \
  INPUT_BODY="pull request release" \
  INPUT_FAIL_ON_ERROR="true" \
  run_create_release 2>&1
)" || exit_code=$?

check "pull-request-ref: exits non-zero" "1" "${exit_code}"
check_contains "pull-request-ref: reports missing tag" \
  "tag input is required" "${pr_ref_output}"
check_not_contains "pull-request-ref: release not created" \
  "release create" "$(cat "${CALL_LOG}")"

# ── Test 4d: fail-on-error=false swallows errors ──────────────────────────
: > "${GITHUB_OUTPUT}"

# Pass an invalid token scenario — just test the output fields.
INPUT_TAG="" \
GITHUB_REF_TYPE="branch" \
GITHUB_REF_NAME="2/merge" \
INPUT_RELEASE_NAME="" \
INPUT_BODY="" \
INPUT_DRAFT="false" \
INPUT_PRERELEASE="false" \
INPUT_TARGET_COMMITISH="" \
INPUT_NOTES_FORMAT="grouped" \
INPUT_FROM_TAG="" \
INPUT_TO_TAG="" \
INPUT_ASSET_PATHS="" \
INPUT_SKIP_IF_RELEASE_EXISTS="false" \
INPUT_PATH_FILTER="" \
INPUT_TAG_PREFIX="" \
INPUT_FAIL_ON_ERROR="false" \
run_create_release || true

soft_fail_output="$(cat "${GITHUB_OUTPUT}")"
check_contains "soft-fail: created=false" "false" "${soft_fail_output}"

# ── Test 5: Explicit prerelease=true ─────────────────────────────────────
: > "${CALL_LOG}"
: > "${GITHUB_OUTPUT}"

INPUT_TAG="v0.2.0" \
INPUT_RELEASE_NAME="" \
INPUT_BODY="explicit body" \
INPUT_DRAFT="false" \
INPUT_PRERELEASE="true" \
INPUT_TARGET_COMMITISH="" \
INPUT_NOTES_FORMAT="grouped" \
INPUT_FROM_TAG="" \
INPUT_TO_TAG="" \
INPUT_ASSET_PATHS="" \
INPUT_SKIP_IF_RELEASE_EXISTS="false" \
INPUT_PATH_FILTER="" \
INPUT_TAG_PREFIX="" \
INPUT_FAIL_ON_ERROR="true" \
run_create_release

check_contains "prerelease=true: --prerelease flag present" "--prerelease" "$(cat "${CALL_LOG}")"

# ── Test 6: Explicit prerelease=false ────────────────────────────────────
: > "${CALL_LOG}"

INPUT_TAG="v0.2.0" \
INPUT_RELEASE_NAME="" \
INPUT_BODY="explicit body" \
INPUT_DRAFT="false" \
INPUT_PRERELEASE="false" \
INPUT_TARGET_COMMITISH="" \
INPUT_NOTES_FORMAT="grouped" \
INPUT_FROM_TAG="" \
INPUT_TO_TAG="" \
INPUT_ASSET_PATHS="" \
INPUT_SKIP_IF_RELEASE_EXISTS="false" \
INPUT_PATH_FILTER="" \
INPUT_TAG_PREFIX="" \
INPUT_FAIL_ON_ERROR="true" \
run_create_release

check_not_contains "prerelease=false: no --prerelease flag" "--prerelease" "$(cat "${CALL_LOG}")"

# ── Test 7: draft=true ───────────────────────────────────────────────────
: > "${CALL_LOG}"

INPUT_TAG="v0.2.0" \
INPUT_RELEASE_NAME="" \
INPUT_BODY="explicit body" \
INPUT_DRAFT="true" \
INPUT_PRERELEASE="false" \
INPUT_TARGET_COMMITISH="" \
INPUT_NOTES_FORMAT="grouped" \
INPUT_FROM_TAG="" \
INPUT_TO_TAG="" \
INPUT_ASSET_PATHS="" \
INPUT_SKIP_IF_RELEASE_EXISTS="false" \
INPUT_PATH_FILTER="" \
INPUT_TAG_PREFIX="" \
INPUT_FAIL_ON_ERROR="true" \
run_create_release

check_contains "draft=true: --draft flag present" "--draft" "$(cat "${CALL_LOG}")"

# ── Test 8: target-commitish set ─────────────────────────────────────────
: > "${CALL_LOG}"

INPUT_TAG="v0.2.0" \
INPUT_RELEASE_NAME="" \
INPUT_BODY="explicit body" \
INPUT_DRAFT="false" \
INPUT_PRERELEASE="false" \
INPUT_TARGET_COMMITISH="some-branch" \
INPUT_NOTES_FORMAT="grouped" \
INPUT_FROM_TAG="" \
INPUT_TO_TAG="" \
INPUT_ASSET_PATHS="" \
INPUT_SKIP_IF_RELEASE_EXISTS="false" \
INPUT_PATH_FILTER="" \
INPUT_TAG_PREFIX="" \
INPUT_FAIL_ON_ERROR="true" \
run_create_release

check_contains "target-commitish: --target flag present"  "--target"    "$(cat "${CALL_LOG}")"
check_contains "target-commitish: target value present"   "some-branch" "$(cat "${CALL_LOG}")"

# ── Test 9: asset-paths with flat glob pattern ───────────────────────────
: > "${CALL_LOG}"
mkdir -p "${TMPDIR}/dist"
echo "binary content" > "${TMPDIR}/dist/app.tar.gz"

INPUT_TAG="v0.2.0" \
INPUT_RELEASE_NAME="" \
INPUT_BODY="explicit body" \
INPUT_DRAFT="false" \
INPUT_PRERELEASE="false" \
INPUT_TARGET_COMMITISH="" \
INPUT_NOTES_FORMAT="grouped" \
INPUT_FROM_TAG="" \
INPUT_TO_TAG="" \
INPUT_ASSET_PATHS="dist/app.tar.gz" \
INPUT_SKIP_IF_RELEASE_EXISTS="false" \
INPUT_PATH_FILTER="" \
INPUT_TAG_PREFIX="" \
INPUT_FAIL_ON_ERROR="true" \
run_create_release

check_contains "assets-flat: file appended to gh args" "app.tar.gz" "$(cat "${CALL_LOG}")"

# ── Test 10: asset-paths with ** recursive glob (regression for globstar fix)
: > "${CALL_LOG}"
mkdir -p "${TMPDIR}/dist/nested"
echo "wheel content" > "${TMPDIR}/dist/nested/app.whl"

INPUT_TAG="v0.2.0" \
INPUT_RELEASE_NAME="" \
INPUT_BODY="explicit body" \
INPUT_DRAFT="false" \
INPUT_PRERELEASE="false" \
INPUT_TARGET_COMMITISH="" \
INPUT_NOTES_FORMAT="grouped" \
INPUT_FROM_TAG="" \
INPUT_TO_TAG="" \
INPUT_ASSET_PATHS="dist/**/*.whl" \
INPUT_SKIP_IF_RELEASE_EXISTS="false" \
INPUT_PATH_FILTER="" \
INPUT_TAG_PREFIX="" \
INPUT_FAIL_ON_ERROR="true" \
run_create_release

check_contains "assets-glob: ** recursive pattern finds nested file" "app.whl" "$(cat "${CALL_LOG}")"

# ── Test 10b: asset-paths starting with ** (no leading dir) ─────────────
# Pattern "**/*.whl" should search from current directory, not "**" directory.
: > "${CALL_LOG}"
mkdir -p "${TMPDIR}/rootlevel"
echo "root wheel" > "${TMPDIR}/rootlevel/root.whl"

INPUT_TAG="v0.2.0" \
INPUT_RELEASE_NAME="" \
INPUT_BODY="explicit body" \
INPUT_DRAFT="false" \
INPUT_PRERELEASE="false" \
INPUT_TARGET_COMMITISH="" \
INPUT_NOTES_FORMAT="grouped" \
INPUT_FROM_TAG="" \
INPUT_TO_TAG="" \
INPUT_ASSET_PATHS="**/*.whl" \
INPUT_SKIP_IF_RELEASE_EXISTS="false" \
INPUT_PATH_FILTER="" \
INPUT_TAG_PREFIX="" \
INPUT_FAIL_ON_ERROR="true" \
run_create_release

check_contains "assets-glob-root: **/*.whl matches files from cwd" "root.whl" "$(cat "${CALL_LOG}")"

# ── Test 11: gh release create fails with fail-on-error=true ─────────────
: > "${GITHUB_OUTPUT}"
export MOCK_CREATE_FAIL="true"

exit_code=0
INPUT_TAG="v0.2.0" \
INPUT_RELEASE_NAME="" \
INPUT_BODY="explicit body" \
INPUT_DRAFT="false" \
INPUT_PRERELEASE="false" \
INPUT_TARGET_COMMITISH="" \
INPUT_NOTES_FORMAT="grouped" \
INPUT_FROM_TAG="" \
INPUT_TO_TAG="" \
INPUT_ASSET_PATHS="" \
INPUT_SKIP_IF_RELEASE_EXISTS="false" \
INPUT_PATH_FILTER="" \
INPUT_TAG_PREFIX="" \
INPUT_FAIL_ON_ERROR="true" \
run_create_release 2>/dev/null || exit_code=$?

check "gh-fail: exits non-zero with fail-on-error=true" "1" "${exit_code}"
unset MOCK_CREATE_FAIL

# ── Test 12: BODY explicitly set bypasses generate-notes ─────────────────
: > "${CALL_LOG}"

INPUT_TAG="v0.2.0" \
INPUT_RELEASE_NAME="" \
INPUT_BODY="My hand-written release notes." \
INPUT_DRAFT="false" \
INPUT_PRERELEASE="false" \
INPUT_TARGET_COMMITISH="" \
INPUT_NOTES_FORMAT="github-native" \
INPUT_FROM_TAG="" \
INPUT_TO_TAG="" \
INPUT_ASSET_PATHS="" \
INPUT_SKIP_IF_RELEASE_EXISTS="false" \
INPUT_PATH_FILTER="" \
INPUT_TAG_PREFIX="" \
INPUT_FAIL_ON_ERROR="true" \
run_create_release

check_contains "explicit-body: --notes flag in gh args"      "--notes"                       "$(cat "${CALL_LOG}")"
check_contains "explicit-body: body content passed to gh"    "My hand-written release notes" "$(cat "${CALL_LOG}")"
check_not_contains "explicit-body: native preview skipped" \
  "releases/generate-notes" "$(cat "${CALL_LOG}")"
check_not_contains "explicit-body: empty target not passed" \
  "--target" "$(cat "${CALL_LOG}")"

# ── Test 13: set_output fallback to stdout when GITHUB_OUTPUT unset ──────
stdout_output="$(
  GITHUB_OUTPUT="" \
  INPUT_TAG="v0.2.0" \
  INPUT_RELEASE_NAME="" \
  INPUT_BODY="test body" \
  INPUT_DRAFT="false" \
  INPUT_PRERELEASE="false" \
  INPUT_TARGET_COMMITISH="" \
  INPUT_NOTES_FORMAT="grouped" \
  INPUT_FROM_TAG="" \
  INPUT_TO_TAG="" \
  INPUT_ASSET_PATHS="" \
  INPUT_SKIP_IF_RELEASE_EXISTS="false" \
  INPUT_PATH_FILTER="" \
  INPUT_TAG_PREFIX="" \
  INPUT_FAIL_ON_ERROR="true" \
  run_create_release 2>/dev/null
)"

check_contains "set_output-fallback: stdout has OUTPUT key=value" "OUTPUT release-url=" "${stdout_output}"

# ── Test 14: move-major-tag moves the major floating pointer tag ───────────
# No bare repo needed - tag movement now goes through gh api (not git push)
: > "${CALL_LOG}"
: > "${GITHUB_OUTPUT}"
move_major_output="$(
  INPUT_TAG="v0.2.0" \
  INPUT_RELEASE_NAME="" \
  INPUT_BODY="stable release" \
  INPUT_DRAFT="false" \
  INPUT_PRERELEASE="false" \
  INPUT_TARGET_COMMITISH="" \
  INPUT_NOTES_FORMAT="grouped" \
  INPUT_FROM_TAG="" \
  INPUT_TO_TAG="" \
  INPUT_ASSET_PATHS="" \
  INPUT_SKIP_IF_RELEASE_EXISTS="false" \
  INPUT_PATH_FILTER="" \
  INPUT_TAG_PREFIX="v" \
  INPUT_FAIL_ON_ERROR="true" \
  INPUT_MOVE_MAJOR_TAG="true" \
  INPUT_MOVE_MINOR_TAG="false" \
  GITHUB_REPOSITORY="test/repo" \
  run_create_release 2>&1
)"

check_contains "move-major-tag: log says Moved v0" "Moved v0." "${move_major_output}"
check_contains "move-major-tag: gh api called for v0" "git/refs" "$(cat "${CALL_LOG}")"

# ── Test 15: move-minor-tag moves the minor floating pointer tag ───────────
: > "${CALL_LOG}"
: > "${GITHUB_OUTPUT}"
move_minor_output="$(
  INPUT_TAG="v0.2.0" \
  INPUT_RELEASE_NAME="" \
  INPUT_BODY="stable release" \
  INPUT_DRAFT="false" \
  INPUT_PRERELEASE="false" \
  INPUT_TARGET_COMMITISH="" \
  INPUT_NOTES_FORMAT="grouped" \
  INPUT_FROM_TAG="" \
  INPUT_TO_TAG="" \
  INPUT_ASSET_PATHS="" \
  INPUT_SKIP_IF_RELEASE_EXISTS="false" \
  INPUT_PATH_FILTER="" \
  INPUT_TAG_PREFIX="v" \
  INPUT_FAIL_ON_ERROR="true" \
  INPUT_MOVE_MAJOR_TAG="false" \
  INPUT_MOVE_MINOR_TAG="true" \
  GITHUB_REPOSITORY="test/repo" \
  run_create_release 2>&1
)"

check_contains "move-minor-tag: log says Moved v0.2" "Moved v0.2." "${move_minor_output}"
check_contains "move-minor-tag: gh api called for v0.2" "git/refs" "$(cat "${CALL_LOG}")"

# ── Test 16: floating tags skipped for pre-release ────────────────────────
git tag v0.4.0-rc.1
: > "${CALL_LOG}"
: > "${GITHUB_OUTPUT}"
prerelease_move_output="$(
  INPUT_TAG="v0.4.0-rc.1" \
  INPUT_RELEASE_NAME="" \
  INPUT_BODY="pre-release" \
  INPUT_DRAFT="false" \
  INPUT_PRERELEASE="auto" \
  INPUT_TARGET_COMMITISH="" \
  INPUT_NOTES_FORMAT="grouped" \
  INPUT_FROM_TAG="" \
  INPUT_TO_TAG="" \
  INPUT_ASSET_PATHS="" \
  INPUT_SKIP_IF_RELEASE_EXISTS="false" \
  INPUT_PATH_FILTER="" \
  INPUT_TAG_PREFIX="v" \
  INPUT_FAIL_ON_ERROR="true" \
  INPUT_MOVE_MAJOR_TAG="true" \
  INPUT_MOVE_MINOR_TAG="true" \
  run_create_release 2>&1
)"

check_contains "floating-tags-prerelease: skip log message present" "Skipping floating pointer tag movement" "${prerelease_move_output}"
check_not_contains "floating-tags-prerelease: v0 not moved" "Moved v0." "${prerelease_move_output}"

# ── Test 17: major-only tag (e.g. "v1") with move-minor-tag does not produce bogus minor tag
git tag v5
: > "${CALL_LOG}"
: > "${GITHUB_OUTPUT}"
major_only_output="$(
  INPUT_TAG="v5" \
  INPUT_RELEASE_NAME="" \
  INPUT_BODY="major-only tag test" \
  INPUT_DRAFT="false" \
  INPUT_PRERELEASE="false" \
  INPUT_TARGET_COMMITISH="" \
  INPUT_NOTES_FORMAT="grouped" \
  INPUT_FROM_TAG="" \
  INPUT_TO_TAG="" \
  INPUT_ASSET_PATHS="" \
  INPUT_SKIP_IF_RELEASE_EXISTS="false" \
  INPUT_PATH_FILTER="" \
  INPUT_TAG_PREFIX="v" \
  INPUT_FAIL_ON_ERROR="true" \
  INPUT_MOVE_MAJOR_TAG="false" \
  INPUT_MOVE_MINOR_TAG="true" \
  run_create_release 2>&1
)"

check_contains "major-only-tag: warns could not parse MAJOR.MINOR" "Could not parse MAJOR.MINOR" "${major_only_output}"
check_not_contains "major-only-tag: no bogus Moved v5.5 tag" "Moved v5.5" "${major_only_output}"

# ── Test 18: missing from-tag uses the previous published release ──────────
: > "${CALL_LOG}"
: > "${GITHUB_OUTPUT}"
export MOCK_PREVIOUS_RELEASE_TAG="v0.1.0"

previous_release_output="$(
  INPUT_TAG="v0.2.0" \
  INPUT_RELEASE_NAME="" \
  INPUT_BODY="" \
  INPUT_DRAFT="false" \
  INPUT_PRERELEASE="false" \
  INPUT_TARGET_COMMITISH="" \
  INPUT_NOTES_FORMAT="grouped" \
  INPUT_FROM_TAG="" \
  INPUT_TO_TAG="" \
  INPUT_ASSET_PATHS="" \
  INPUT_SKIP_IF_RELEASE_EXISTS="false" \
  INPUT_PATH_FILTER="" \
  INPUT_TAG_PREFIX="" \
  INPUT_FAIL_ON_ERROR="true" \
  run_create_release 2>&1
)"

check_contains "previous-release: published tag selected" \
  "Using previous published release as from-tag: v0.1.0" "${previous_release_output}"
unset MOCK_PREVIOUS_RELEASE_TAG

# ── Test 19: github-native forwards explicit from-tag ──────────────────────
: > "${CALL_LOG}"
: > "${GITHUB_OUTPUT}"
native_existing_tag_sha="$(git rev-parse 'v0.2.0^{commit}')"

INPUT_TAG="v0.2.0" \
INPUT_RELEASE_NAME="" \
INPUT_BODY="" \
INPUT_DRAFT="false" \
INPUT_PRERELEASE="false" \
INPUT_TARGET_COMMITISH="" \
INPUT_NOTES_FORMAT="github-native" \
INPUT_FROM_TAG="v0.1.0" \
INPUT_TO_TAG="v0.2.0" \
INPUT_ASSET_PATHS="" \
INPUT_SKIP_IF_RELEASE_EXISTS="false" \
INPUT_PATH_FILTER="" \
INPUT_TAG_PREFIX="" \
INPUT_FAIL_ON_ERROR="true" \
run_create_release

native_call="$(cat "${CALL_LOG}")"
check_contains "github-native: preview endpoint called" \
  "repos/{owner}/{repo}/releases/generate-notes" "${native_call}"
check_contains "github-native: previous tag forwarded" \
  "previous_tag_name=v0.1.0" "${native_call}"
check_contains "github-native: existing tag commit forwarded" \
  "target_commitish=${native_existing_tag_sha}" "${native_call}"
check_contains "github-native: local tag pins remote creation" \
  "--target ${native_existing_tag_sha}" "${native_call}"
check_contains "github-native: generated body passed to release" \
  "--notes Generated GitHub-native notes" "${native_call}"
check_not_contains "github-native: server-side generation disabled" \
  "--generate-notes" "${native_call}"

# ── Test 19b: new native tag pins ancestry, notes, and creation to one SHA
: > "${CALL_LOG}"
: > "${GITHUB_OUTPUT}"
export MOCK_RELEASE_TAGS="v0.1.0"
MOCK_TARGET_SHA="$(git rev-parse HEAD)"
export MOCK_TARGET_SHA

new_native_output="$(
  INPUT_TAG="v9.0.0" \
  INPUT_RELEASE_NAME="" \
  INPUT_BODY="" \
  INPUT_DRAFT="false" \
  INPUT_PRERELEASE="false" \
  INPUT_TARGET_COMMITISH="" \
  INPUT_NOTES_FORMAT="github-native" \
  INPUT_FROM_TAG="" \
  INPUT_TO_TAG="" \
  INPUT_ASSET_PATHS="" \
  INPUT_SKIP_IF_RELEASE_EXISTS="false" \
  INPUT_PATH_FILTER="" \
  INPUT_TAG_PREFIX="v" \
  INPUT_FAIL_ON_ERROR="true" \
  run_create_release 2>&1
)"

new_native_call="$(cat "${CALL_LOG}")"
check_contains "github-native-new-tag: previous ancestor selected" \
  "Using previous published release as from-tag: v0.1.0" "${new_native_output}"
check_contains "github-native-new-tag: notes pinned to target SHA" \
  "target_commitish=${MOCK_TARGET_SHA}" "${new_native_call}"
check_contains "github-native-new-tag: release pinned to target SHA" \
  "--target ${MOCK_TARGET_SHA}" "${new_native_call}"
unset MOCK_RELEASE_TAGS MOCK_TARGET_SHA

# ── Test 19c: unavailable native target fails before range generation ─────
: > "${CALL_LOG}"
: > "${GITHUB_OUTPUT}"
export MOCK_RELEASE_TAGS="v0.1.0"
export MOCK_TARGET_SHA="1111111111111111111111111111111111111111"
exit_code=0
missing_native_target_output="$(
  INPUT_TAG="v9.0.0" \
  INPUT_BODY="" \
  INPUT_PRERELEASE="false" \
  INPUT_TARGET_COMMITISH="" \
  INPUT_NOTES_FORMAT="github-native" \
  INPUT_FROM_TAG="" \
  INPUT_TO_TAG="" \
  INPUT_TAG_PREFIX="v" \
  INPUT_FAIL_ON_ERROR="true" \
  run_create_release 2>&1
)" || exit_code=$?

check "github-native-missing-target: exits non-zero" "1" "${exit_code}"
check_contains "github-native-missing-target: actionable local-history error" \
  "not available locally for from-tag inference" "${missing_native_target_output}"
check_not_contains "github-native-missing-target: preview not called" \
  "releases/generate-notes" "$(cat "${CALL_LOG}")"
check_not_contains "github-native-missing-target: release create not called" \
  "release create" "$(cat "${CALL_LOG}")"
unset MOCK_RELEASE_TAGS MOCK_TARGET_SHA

# ── Test 20: github-native rejects a different to-tag ──────────────────────
: > "${CALL_LOG}"
exit_code=0
native_to_tag_output="$(
  INPUT_TAG="v0.2.0" \
  INPUT_BODY="" \
  INPUT_PRERELEASE="false" \
  INPUT_NOTES_FORMAT="github-native" \
  INPUT_FROM_TAG="v0.1.0" \
  INPUT_TO_TAG="v0.1.0" \
  INPUT_PATH_FILTER="" \
  INPUT_FAIL_ON_ERROR="true" \
  run_create_release 2>&1
)" || exit_code=$?

check "github-native-to-tag: exits non-zero" "1" "${exit_code}"
check_contains "github-native-to-tag: actionable error" \
  "to-tag cannot differ from tag" "${native_to_tag_output}"
check "github-native-to-tag: gh create not called" "" "$(cat "${CALL_LOG}")"

# ── Test 21: github-native rejects path-filter ─────────────────────────────
: > "${CALL_LOG}"
exit_code=0
native_path_output="$(
  INPUT_TAG="v0.2.0" \
  INPUT_BODY="" \
  INPUT_PRERELEASE="false" \
  INPUT_NOTES_FORMAT="github-native" \
  INPUT_FROM_TAG="v0.1.0" \
  INPUT_TO_TAG="v0.2.0" \
  INPUT_PATH_FILTER="service-a" \
  INPUT_FAIL_ON_ERROR="true" \
  run_create_release 2>&1
)" || exit_code=$?

check "github-native-path: exits non-zero" "1" "${exit_code}"
check_contains "github-native-path: actionable error" \
  "path-filter is not supported" "${native_path_output}"
check "github-native-path: gh create not called" "" "$(cat "${CALL_LOG}")"

# ── Test 22: oversized explicit body fails before gh create ────────────────
: > "${CALL_LOG}"
printf -v oversized_body '%*s' 125001 ''
exit_code=0
oversized_body_output="$(
  INPUT_TAG="v0.2.0" \
  INPUT_BODY="${oversized_body}" \
  INPUT_PRERELEASE="false" \
  INPUT_FAIL_ON_ERROR="true" \
  run_create_release 2>&1
)" || exit_code=$?

check "oversized-explicit-body: exits non-zero" "1" "${exit_code}"
check_contains "oversized-explicit-body: actionable error" \
  "GitHub allows at most 125000" "${oversized_body_output}"
check "oversized-explicit-body: gh create not called" "" "$(cat "${CALL_LOG}")"

# ── Test 23: oversized generated body fails before gh create ───────────────
: > "${CALL_LOG}"
oversized_action_path="${TMPDIR}/oversized-action"
mkdir -p "${oversized_action_path}/scripts"
cat > "${oversized_action_path}/scripts/generate-notes.sh" <<'EOF'
#!/usr/bin/env bash
printf '%125001s' ''
EOF
chmod +x "${oversized_action_path}/scripts/generate-notes.sh"

exit_code=0
oversized_generated_output="$(
  ACTION_PATH="${oversized_action_path}" \
  INPUT_TAG="v0.2.0" \
  INPUT_BODY="" \
  INPUT_PRERELEASE="false" \
  INPUT_NOTES_FORMAT="grouped" \
  INPUT_FROM_TAG="v0.1.0" \
  INPUT_TO_TAG="v0.2.0" \
  INPUT_PATH_FILTER="" \
  INPUT_FAIL_ON_ERROR="true" \
  run_create_release 2>&1
)" || exit_code=$?

check "oversized-generated-body: exits non-zero" "1" "${exit_code}"
check_contains "oversized-generated-body: actionable error" \
  "GitHub allows at most 125000" "${oversized_generated_output}"
check "oversized-generated-body: gh create not called" "" "$(cat "${CALL_LOG}")"

# ── Test 24: inferred release stays within the configured tag prefix ──────
mkdir -p api web
git tag api/v1.0.0
echo "endpoint" > api/endpoint.txt
git add api/endpoint.txt
git commit -q -m "feat(api): add endpoint"
echo "release" > web/release.txt
git add web/release.txt
git commit -q -m "chore(web): publish release"
git tag web/v2.0.0
git tag api/v2.0.0

: > "${CALL_LOG}"
: > "${GITHUB_OUTPUT}"
export MOCK_RELEASE_TAGS=$'web/v2.0.0\napi/v1.0.0'

interleaved_output="$(
  INPUT_TAG="api/v2.0.0" \
  INPUT_BODY="" \
  INPUT_PRERELEASE="false" \
  INPUT_NOTES_FORMAT="flat" \
  INPUT_FROM_TAG="" \
  INPUT_TO_TAG="" \
  INPUT_PATH_FILTER="api" \
  INPUT_TAG_PREFIX="api/" \
  INPUT_FAIL_ON_ERROR="true" \
  run_create_release 2>&1
)"

check_contains "interleaved-releases: matching stream selected" \
  "Using previous published release as from-tag: api/v1.0.0" "${interleaved_output}"
check_contains "interleaved-releases: component commit retained" \
  "add endpoint" "$(cat "${CALL_LOG}")"
unset MOCK_RELEASE_TAGS

# ── Test 25: inferred release skips a newer non-ancestor tag ──────────────
side_tree="$(git rev-parse 'v0.1.0^{tree}')"
side_commit="$(printf 'side release\n' | git commit-tree "${side_tree}" -p v0.1.0)"
git tag api/v9.0.0 "${side_commit}"

: > "${CALL_LOG}"
export MOCK_RELEASE_TAGS=$'api/v9.0.0\napi/v1.0.0'

nonancestor_output="$(
  INPUT_TAG="api/v2.0.0" \
  INPUT_BODY="" \
  INPUT_PRERELEASE="false" \
  INPUT_NOTES_FORMAT="flat" \
  INPUT_FROM_TAG="" \
  INPUT_TO_TAG="" \
  INPUT_PATH_FILTER="api" \
  INPUT_TAG_PREFIX="api/" \
  INPUT_FAIL_ON_ERROR="true" \
  run_create_release 2>&1
)"

check_contains "non-ancestor-release: older ancestor selected" \
  "Using previous published release as from-tag: api/v1.0.0" "${nonancestor_output}"
unset MOCK_RELEASE_TAGS

# ── Test 26: missing local release tag fails with fetch guidance ──────────
: > "${CALL_LOG}"
export MOCK_RELEASE_TAGS="api/v8.0.0"
exit_code=0
missing_release_tag_output="$(
  INPUT_TAG="api/v2.0.0" \
  INPUT_BODY="" \
  INPUT_PRERELEASE="false" \
  INPUT_NOTES_FORMAT="flat" \
  INPUT_FROM_TAG="" \
  INPUT_TO_TAG="" \
  INPUT_TAG_PREFIX="api/" \
  INPUT_FAIL_ON_ERROR="true" \
  run_create_release 2>&1
)" || exit_code=$?

check "missing-release-tag: exits non-zero" "1" "${exit_code}"
check_contains "missing-release-tag: actionable fetch guidance" \
  "fetch-depth: 0" "${missing_release_tag_output}"
check "missing-release-tag: gh create not called" "" "$(cat "${CALL_LOG}")"
unset MOCK_RELEASE_TAGS

# ── Test 27: release-list auth failure is actionable ──────────────────────
: > "${CALL_LOG}"
export MOCK_RELEASE_LIST_FAIL="true"
exit_code=0
release_list_failure_output="$(
  INPUT_TAG="api/v2.0.0" \
  INPUT_BODY="" \
  INPUT_PRERELEASE="false" \
  INPUT_NOTES_FORMAT="flat" \
  INPUT_FROM_TAG="" \
  INPUT_TO_TAG="" \
  INPUT_TAG_PREFIX="api/" \
  INPUT_FAIL_ON_ERROR="true" \
  run_create_release 2>&1
)" || exit_code=$?

check "release-list-failure: exits non-zero" "1" "${exit_code}"
check_contains "release-list-failure: mentions authentication" \
  "permissions/authentication" "${release_list_failure_output}"
check_contains "release-list-failure: suggests explicit range" \
  "set from-tag explicitly" "${release_list_failure_output}"
unset MOCK_RELEASE_LIST_FAIL

# ── Test 28: oversized GitHub-native body fails before release creation ───
: > "${CALL_LOG}"
printf -v oversized_native_notes '%*s' 125001 ''
export MOCK_NATIVE_NOTES="${oversized_native_notes}"
exit_code=0
oversized_native_output="$(
  INPUT_TAG="v0.2.0" \
  INPUT_BODY="" \
  INPUT_PRERELEASE="false" \
  INPUT_NOTES_FORMAT="github-native" \
  INPUT_FROM_TAG="v0.1.0" \
  INPUT_TO_TAG="v0.2.0" \
  INPUT_FAIL_ON_ERROR="true" \
  run_create_release 2>&1
)" || exit_code=$?

check "oversized-native-body: exits non-zero" "1" "${exit_code}"
check_contains "oversized-native-body: actionable error" \
  "GitHub allows at most 125000" "${oversized_native_output}"
check_not_contains "oversized-native-body: release create not called" \
  "release create" "$(cat "${CALL_LOG}")"
unset MOCK_NATIVE_NOTES

echo ""
echo "integration: ${PASS} passed, ${FAIL} failed"
[[ ${FAIL} -eq 0 ]]

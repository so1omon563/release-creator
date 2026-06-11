#!/usr/bin/env bash
# scripts/create-release.sh
# Orchestrate GitHub Release creation for the sharedactions-action-release-creator
# composite action.
#
# All inputs are read from environment variables (GitHub Actions convention):
#
#   GH_TOKEN                  - GitHub token (required)
#   INPUT_TAG                 - Tag name for the release
#   INPUT_RELEASE_NAME        - Display name (defaults to tag)
#   INPUT_BODY                - Explicit release body (overrides auto-notes)
#   INPUT_DRAFT               - true|false
#   INPUT_PRERELEASE          - true|false|auto
#   INPUT_TARGET_COMMITISH    - Branch or SHA to tag from
#   INPUT_NOTES_FORMAT        - grouped|conventional|flat|github-native
#   INPUT_FROM_TAG            - Start of commit range for notes
#   INPUT_TO_TAG              - End of commit range (defaults to INPUT_TAG)
#   INPUT_ASSET_PATHS         - Newline-separated glob patterns for assets
#   INPUT_SKIP_IF_RELEASE_EXISTS - true|false
#   INPUT_PATH_FILTER         - Monorepo path filter
#   INPUT_TAG_PREFIX          - Prefix to strip for version comparisons
#   INPUT_FAIL_ON_ERROR       - true|false
#   ACTION_PATH               - Path to action root directory
#
# Outputs are written to $GITHUB_OUTPUT.

set -euo pipefail

# ── Helpers ──────────────────────────────────────────────────────────────────
log()  { echo "[release-creator] $*"; }
warn() { echo "[release-creator] WARNING: $*" >&2; }
die()  {
  echo "[release-creator] ERROR: $*" >&2
  if [[ "${FAIL_ON_ERROR:-true}" == "true" ]]; then
    exit 1
  else
    set_output "created" "false"
    set_output "skipped" "false"
    exit 0
  fi
}

set_output() {
  local key="$1"
  local value="$2"
  if [[ -n "${GITHUB_OUTPUT:-}" ]]; then
    # Multi-line safe using heredoc delimiter
    {
      echo "${key}<<EOF_OUTPUT"
      echo "${value}"
      echo "EOF_OUTPUT"
    } >> "${GITHUB_OUTPUT}"
  else
    echo "OUTPUT ${key}=${value}"
  fi
}

# ── Read inputs ──────────────────────────────────────────────────────────────
ACTION_PATH="${ACTION_PATH:-$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)}"
TAG="${INPUT_TAG:-${GITHUB_REF_NAME:-}}"
RELEASE_NAME="${INPUT_RELEASE_NAME:-}"
BODY="${INPUT_BODY:-}"
DRAFT="${INPUT_DRAFT:-false}"
PRERELEASE="${INPUT_PRERELEASE:-auto}"
TARGET_COMMITISH="${INPUT_TARGET_COMMITISH:-}"
NOTES_FORMAT="${INPUT_NOTES_FORMAT:-grouped}"
FROM_TAG="${INPUT_FROM_TAG:-}"
TO_TAG="${INPUT_TO_TAG:-}"
ASSET_PATHS="${INPUT_ASSET_PATHS:-}"
SKIP_IF_EXISTS="${INPUT_SKIP_IF_RELEASE_EXISTS:-false}"
PATH_FILTER="${INPUT_PATH_FILTER:-}"
TAG_PREFIX="${INPUT_TAG_PREFIX:-}"
FAIL_ON_ERROR="${INPUT_FAIL_ON_ERROR:-true}"
MOVE_MAJOR_TAG="${INPUT_MOVE_MAJOR_TAG:-false}"
MOVE_MINOR_TAG="${INPUT_MOVE_MINOR_TAG:-false}"

# ── Validate required inputs ─────────────────────────────────────────────────
if [[ -z "${TAG}" ]]; then
  die "tag input is required. Set it explicitly or trigger via a tag push."
fi

if [[ -z "${GH_TOKEN:-}" ]]; then
  die "token input is required."
fi

log "Processing release for tag: ${TAG}"

# ── Check for duplicate release ───────────────────────────────────────────────
if [[ "${SKIP_IF_EXISTS}" == "true" ]]; then
  if gh release view "${TAG}" --json tagName --jq '.tagName' &>/dev/null; then
    log "Release ${TAG} already exists and skip-if-release-exists is true. Skipping."
    set_output "created" "false"
    set_output "skipped" "true"
    set_output "tag-name" "${TAG}"
    exit 0
  fi
fi

# ── Resolve TO_TAG ────────────────────────────────────────────────────────────
if [[ -z "${TO_TAG}" ]]; then
  TO_TAG="${TAG}"
fi

# ── Determine pre-release status ──────────────────────────────────────────────
if [[ "${PRERELEASE}" == "auto" ]]; then
  # shellcheck source=scripts/detect-prerelease.sh
  source "${ACTION_PATH}/scripts/detect-prerelease.sh"
  PRERELEASE="$(is_prerelease "${TAG}" "${TAG_PREFIX}")"
  log "Pre-release auto-detected: ${PRERELEASE}"
fi

# ── Generate release notes ────────────────────────────────────────────────────
NOTES_ARGS=()
if [[ -z "${BODY}" ]]; then
  if [[ "${NOTES_FORMAT}" == "github-native" ]]; then
    NOTES_ARGS+=("--generate-notes")
    log "Using GitHub-native release notes generation."
  else
    log "Generating release notes (format: ${NOTES_FORMAT})..."
    export FROM_TAG TO_TAG NOTES_FORMAT PATH_FILTER TAG_PREFIX ACTION_PATH
    BODY="$(bash "${ACTION_PATH}/scripts/generate-notes.sh")"
    log "Release notes generated (${#BODY} chars)."
  fi
else
  log "Using explicit release body (overrides auto-generated notes)."
fi

# ── Build gh release create arguments ─────────────────────────────────────────
GH_ARGS=(
  "${TAG}"
  "--title" "${RELEASE_NAME:-${TAG}}"
)

if [[ "${DRAFT}" == "true" ]]; then
  GH_ARGS+=("--draft")
fi

if [[ "${PRERELEASE}" == "true" ]]; then
  GH_ARGS+=("--prerelease")
fi

if [[ -n "${TARGET_COMMITISH}" ]]; then
  GH_ARGS+=("--target" "${TARGET_COMMITISH}")
fi

if [[ "${#NOTES_ARGS[@]}" -gt 0 ]]; then
  GH_ARGS+=("${NOTES_ARGS[@]}")
elif [[ -n "${BODY}" ]]; then
  GH_ARGS+=("--notes" "${BODY}")
fi

# ── Resolve asset globs ────────────────────────────────────────────────────────
asset_files=()
if [[ -n "${ASSET_PATHS}" ]]; then
  while IFS= read -r pattern; do
    [[ -z "${pattern}" ]] && continue
    if [[ "${pattern}" == *"**"* ]]; then
      # Recursive glob: derive base directory and filename pattern from ** syntax
      # e.g. dist/**/*.whl → find dist -name "*.whl" -type f
      # e.g. **/*.whl      → find .    -name "*.whl" -type f
      dir="${pattern%%/**}"
      name="${pattern##**/}"
      # If the pattern starts with "**" (no leading directory), dir becomes "**"
      # rather than empty — treat both as "search from current directory".
      [[ -z "${dir}" || "${dir}" == "**" ]] && dir="."
      while IFS= read -r file; do
        [[ -f "${file}" ]] && asset_files+=("${file}")
      done < <(find "${dir}" -name "${name}" -type f 2>/dev/null || true)
    else
      # Flat pattern: find -path handles single-level wildcards (e.g. dist/*.tar.gz)
      while IFS= read -r -d $'\0' file; do
        [[ -f "${file}" ]] && asset_files+=("${file}")
      done < <(find . -path "./${pattern}" -print0 2>/dev/null || true)
    fi
  done <<< "${ASSET_PATHS}"

  if [[ "${#asset_files[@]}" -gt 0 ]]; then
    log "Assets to upload: ${asset_files[*]}"
    GH_ARGS+=("${asset_files[@]}")
  else
    warn "No files matched asset-paths patterns."
  fi
fi

# ── Create the release ────────────────────────────────────────────────────────
log "Creating GitHub release..."
release_url="$(gh release create "${GH_ARGS[@]}")" || {
  die "gh release create failed (see output above)"
}

log "Release created: ${release_url}"

# Fetch structured metadata for outputs via a separate view call.
release_json="$(gh release view "${TAG}" --json id,url,uploadUrl 2>/dev/null || echo '{}')"
release_id="$(echo "${release_json}" | python3 -c "import sys,json; print(json.load(sys.stdin)['id'])" 2>/dev/null || \
  echo "${release_json}" | sed -n 's/.*"id"[[:space:]]*:[[:space:]]*\([0-9][0-9]*\).*/\1/p' | head -1)"
upload_url="$(echo "${release_json}" | python3 -c "import sys,json; print(json.load(sys.stdin).get('uploadUrl',''))" 2>/dev/null || \
  echo "${release_json}" | sed -n 's/.*"uploadUrl"[[:space:]]*:[[:space:]]*"\([^"]*\)".*/\1/p' | head -1)"

# ── Move floating pointer tags ────────────────────────────────────────────────
# Only move floating tags for stable releases. Pre-releases must not update
# floating pointer tags because consumers who pin to @v1 expect stability.
if [[ "${MOVE_MAJOR_TAG}" == "true" || "${MOVE_MINOR_TAG}" == "true" ]]; then
  if [[ "${PRERELEASE}" == "true" ]]; then
    log "Skipping floating pointer tag movement for pre-release tag ${TAG}."
  else
    # Parse MAJOR and MINOR from the tag.
    # Strip prefix → strip build metadata → strip pre-release label → split on '.'
    _version="${TAG#"${TAG_PREFIX}"}"
    _version="${_version%%+*}"
    _version="${_version%%-*}"
    # Strip any remaining non-numeric leading characters (e.g. bare 'v' when
    # TAG_PREFIX is empty and the user didn't set it)
    _version="${_version#"${_version%%[0-9]*}"}"
    _major="${_version%%.*}"
    _rest="${_version#*.}"
    # If no dot exists in _version, _rest equals _version (bash parameter
    # expansion returns the original string when the pattern is not found).
    # In that case there is no minor component — set _minor="" so the guard
    # below triggers the "Could not parse" warning and skips tag movement.
    if [[ "${_rest}" == "${_version}" ]]; then
      _minor=""
    else
      _minor="${_rest%%.*}"
    fi

    if [[ -z "${_major}" || -z "${_minor}" ]]; then
      warn "Could not parse MAJOR.MINOR from tag ${TAG} — skipping floating tag movement."
    else
      # Resolve commit SHA and GitHub repo slug for API-based tag movement.
      # Using the GitHub REST API avoids git-push permission restrictions that
      # GitHub Actions GITHUB_TOKEN has for refs containing workflow files.
      _commit_sha="$(git rev-parse "${TAG}^{}" 2>/dev/null || git rev-parse "${TAG}")"
      _gh_repo="${GITHUB_REPOSITORY:-}"
      if [[ -z "${_gh_repo}" ]]; then
        _remote_url="$(git remote get-url origin 2>/dev/null || true)"
        _gh_repo="$(echo "${_remote_url}" | sed 's|.*github\.com[:/]\(.*\)\.git|\1|;s|.*github\.com[:/]\(.*\)|\1|')"
      fi

      _move_tag() {
        local _tag_name="$1"
        log "Moving ${_tag_name} → ${TAG}..."
        # Try to update an existing ref first; fall back to creating a new one.
        if gh api --method PATCH \
            "repos/${_gh_repo}/git/refs/tags/${_tag_name}" \
            -f sha="${_commit_sha}" \
            -F force=true \
            --silent 2>/dev/null \
           || gh api --method POST \
            "repos/${_gh_repo}/git/refs" \
            -f ref="refs/tags/${_tag_name}" \
            -f sha="${_commit_sha}" \
            --silent 2>/dev/null; then
          log "Moved ${_tag_name}."
        else
          warn "Failed to move ${_tag_name} via API — release was created but floating tag not moved."
        fi
      }

      if [[ "${MOVE_MAJOR_TAG}" == "true" ]]; then
        _major_tag="${TAG_PREFIX}${_major}"
        _move_tag "${_major_tag}"
      fi

      if [[ "${MOVE_MINOR_TAG}" == "true" ]]; then
        _minor_tag="${TAG_PREFIX}${_major}.${_minor}"
        _move_tag "${_minor_tag}"
      fi
    fi
  fi
fi

# ── Emit outputs ──────────────────────────────────────────────────────────────
set_output "release-url"  "${release_url}"
set_output "release-id"   "${release_id}"
set_output "upload-url"   "${upload_url}"
set_output "tag-name"     "${TAG}"
set_output "created"      "true"
set_output "skipped"      "false"

log "Done."

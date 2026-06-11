#!/usr/bin/env bash
# scripts/generate-notes.sh
# Generate release notes from a commit range in one of four formats:
#
#   grouped        - Commits grouped by conventional type with emoji headers
#   conventional   - Flat list preserving conventional commit type prefix
#   flat           - Plain commit message list, no type grouping
#   github-native  - Outputs the flag "--generate-notes" for gh CLI delegation
#
# Environment variables:
#   FROM_TAG        - start of commit range (exclusive)
#   TO_TAG          - end of commit range (inclusive)
#   NOTES_FORMAT    - one of: grouped, conventional, flat, github-native
#   PATH_FILTER     - optional path to scope commits (monorepo)
#   TAG_PREFIX      - optional prefix to strip before version comparisons
#   ACTION_PATH     - path to the action root (used to call filter-commits.sh)

set -euo pipefail

NOTES_FORMAT="${NOTES_FORMAT:-grouped}"
FROM_TAG="${FROM_TAG:-}"
TO_TAG="${TO_TAG:-}"
PATH_FILTER="${PATH_FILTER:-}"
TAG_PREFIX="${TAG_PREFIX:-}"
ACTION_PATH="${ACTION_PATH:-$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)}"

# For github-native, just output the marker and exit — caller handles it
if [[ "${NOTES_FORMAT}" == "github-native" ]]; then
  echo "--generate-notes"
  exit 0
fi

# Fetch commits
commits="$(FROM_TAG="${FROM_TAG}" TO_TAG="${TO_TAG}" PATH_FILTER="${PATH_FILTER}" \
  TAG_PREFIX="${TAG_PREFIX}" bash "${ACTION_PATH}/scripts/filter-commits.sh")"

if [[ -z "${commits}" ]]; then
  echo "_No changes in this release._"
  exit 0
fi

# ── Helpers ──────────────────────────────────────────────────────────────────
parse_type() {
  local subject="$1"
  # Use sed for bash 3 compatibility — extract the conventional type prefix
  local type
  type="$(echo "${subject}" | sed -nE 's/^([a-z]+)(\([^)]*\))?!?: .*/\1/p')"
  if [[ -n "${type}" ]]; then
    echo "${type}"
  else
    echo "other"
  fi
}

strip_type_prefix() {
  local subject="$1"
  # Remove type(scope)!: prefix
  local description
  description="$(echo "${subject}" | sed -nE 's/^[a-z]+(\([^)]*\))?!?: (.*)/\2/p')"
  if [[ -n "${description}" ]]; then
    echo "${description}"
  else
    echo "${subject}"
  fi
}

# Map a commit type to its emoji section header (bash 3 compatible)
type_to_header() {
  local type="$1"
  case "${type}" in
    feat)     echo "🚀 Features" ;;
    fix)      echo "🐛 Bug Fixes" ;;
    perf)     echo "⚡ Performance" ;;
    refactor) echo "♻️  Refactor" ;;
    docs)     echo "📖 Documentation" ;;
    test)     echo "🧪 Tests" ;;
    ci)       echo "🔧 CI/CD" ;;
    chore)    echo "🧹 Chores" ;;
    build)    echo "🏗️  Build" ;;
    style)    echo "💅 Style" ;;
    revert)   echo "⏪ Reverts" ;;
    *)        echo "📦 Other Changes" ;;
  esac
}

# ── Build output ─────────────────────────────────────────────────────────────
case "${NOTES_FORMAT}" in
  grouped)
    # Ordered list of types for section output
    TYPE_ORDER="feat fix perf refactor docs test ci chore build style revert other"

    # Temp files per section (bash 3 compatible alternative to assoc arrays)
    tmpdir="$(mktemp -d /tmp/rc_notes_XXXXXX)"
    # shellcheck disable=SC2064
    trap "rm -rf '${tmpdir}'" EXIT

    while IFS= read -r line; do
      [[ -z "${line}" ]] && continue
      sha="${line%% *}"
      subject="${line#* }"
      short_sha="${sha:0:7}"
      type="$(parse_type "${subject}")"
      description="$(strip_type_prefix "${subject}")"

      # Normalize unknown types to "other"
      case "${type}" in
        feat|fix|perf|refactor|docs|test|ci|chore|build|style|revert) ;;
        *) type="other" ;;
      esac

      echo "- ${description} (\`${short_sha}\`)" >> "${tmpdir}/${type}.txt"
    done <<< "${commits}"

    output=""
    for type in ${TYPE_ORDER}; do
      section_file="${tmpdir}/${type}.txt"
      if [[ -f "${section_file}" ]]; then
        header="$(type_to_header "${type}")"
        output+="### ${header}"$'\n'
        output+="$(cat "${section_file}")"$'\n\n'
      fi
    done

    echo "${output%$'\n\n'}"
    ;;

  conventional)
    while IFS= read -r line; do
      [[ -z "${line}" ]] && continue
      sha="${line%% *}"
      subject="${line#* }"
      short_sha="${sha:0:7}"
      echo "- ${subject} (\`${short_sha}\`)"
    done <<< "${commits}"
    ;;

  flat)
    while IFS= read -r line; do
      [[ -z "${line}" ]] && continue
      sha="${line%% *}"
      subject="${line#* }"
      short_sha="${sha:0:7}"
      description="$(strip_type_prefix "${subject}")"
      echo "- ${description} (\`${short_sha}\`)"
    done <<< "${commits}"
    ;;

  *)
    echo "ERROR: Unknown notes-format '${NOTES_FORMAT}'. Valid: grouped, conventional, flat, github-native" >&2
    exit 1
    ;;
esac

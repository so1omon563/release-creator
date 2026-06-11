#!/usr/bin/env bash
# scripts/detect-prerelease.sh
# Detect whether a tag should be treated as a pre-release.
#
# Usage:
#   source scripts/detect-prerelease.sh
#   is_prerelease "v1.2.3-rc.1"   # prints true or false
#   is_prerelease "v1.2.3"         # prints false
#
# Or run directly:
#   DETECT_TAG="v1.0.0-beta.1" scripts/detect-prerelease.sh
#
# Exit code 0 = pre-release, exit code 1 = stable release.
#
# Alignment note (sharedactions-action-custom-semver-bumper):
#   The semver bumper supports arbitrary pre-release suffixes (e.g. enterprise,
#   team-blue, nightly) and SemVer §10 build metadata (e.g. +sha.a1b2c3d).
#   This script follows SemVer §9: any hyphen-separated label after the numeric
#   version (e.g. v1.2.3-anything) is a pre-release. Build metadata (the +...
#   portion) is stripped first — a tag with metadata but no pre-release label
#   (e.g. v1.2.3+sha.abc1234) is treated as stable.

set -euo pipefail

# is_prerelease <tag> [prefix]
# Prints "true" or "false" to stdout. Always returns exit code 0.
is_prerelease() {
  local tag="${1:-}"
  local prefix="${2:-}"

  # Strip tag prefix for version inspection
  local version="${tag#"${prefix}"}"

  # Strip SemVer §10 build metadata (+sha.abc1234) before checking for
  # pre-release identifiers. Build metadata alone does not indicate pre-release.
  # e.g. v1.2.3+sha.abc → v1.2.3  (stable)
  # e.g. v1.2.3-alpha.1+sha.abc → v1.2.3-alpha.1  (pre-release)
  version="${version%%+*}"

  # Strip any non-numeric prefix characters (e.g. 'v' in 'v1.2.3') so the
  # regex anchors correctly. This handles prefixes not covered by the prefix
  # parameter (users may omit tag-prefix even when using a 'v' prefix).
  version="${version#"${version%%[0-9]*}"}"

  # Per SemVer §9, a pre-release version is indicated by a hyphen immediately
  # following the patch version number (e.g. 1.2.3-alpha.1, 1.2.3-rc.1,
  # 1.2.3-enterprise.2, 1.2.3-team-blue.1). Any hyphenated identifier counts.
  if [[ "${version}" =~ ^[0-9]+\.[0-9]+\.[0-9]+- ]]; then
    echo "true"
  else
    echo "false"
  fi
  return 0
}

# When executed directly (not sourced), use DETECT_TAG env var
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
  tag="${DETECT_TAG:-}"
  prefix="${DETECT_TAG_PREFIX:-}"

  if [[ -z "${tag}" ]]; then
    echo "ERROR: DETECT_TAG must be set" >&2
    exit 2
  fi

  result="$(is_prerelease "${tag}" "${prefix}")"
  echo "${result}"
  [[ "${result}" == "true" ]]
fi

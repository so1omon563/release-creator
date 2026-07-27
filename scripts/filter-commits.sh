#!/usr/bin/env bash
# scripts/filter-commits.sh
# Return commits in a range, optionally scoped to a path (monorepo support).
#
# Environment variables:
#   FROM_TAG       - start of range (exclusive). If empty, uses the full history
#                    up to TO_TAG.
#   TO_TAG         - end of range (inclusive). Required.
#   PATH_FILTER    - optional directory/file path to scope commits
#
# Output: newline-separated list of "<sha> <subject>" lines.
#
# Alignment note (custom-semver-bumper):
#   The semver bumper can produce tags with SemVer §10 build metadata, e.g.
#   v1.3.0+sha.a1b2c3d. Git allows the '+' character in tag names, so
#   "git log v1.2.0..v1.3.0+sha.a1b2c3d" is valid.

set -euo pipefail

FROM_TAG="${FROM_TAG:-}"
TO_TAG="${TO_TAG:-}"
PATH_FILTER="${PATH_FILTER:-}"

if [[ -z "${TO_TAG}" ]]; then
  echo "ERROR: TO_TAG must be set" >&2
  exit 2
fi

# Build git log range
if [[ -n "${FROM_TAG}" ]]; then
  range="${FROM_TAG}..${TO_TAG}"
else
  range="${TO_TAG}"
fi

# Build path filter argument
path_args=()
if [[ -n "${PATH_FILTER}" ]]; then
  path_args+=("--" "${PATH_FILTER}")
fi

git log \
  --no-merges \
  --format="%H %s" \
  "${range}" \
  "${path_args[@]+"${path_args[@]}"}"

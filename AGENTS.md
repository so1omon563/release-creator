# Repository Guidelines

## Project Structure & Module Organization

This repository is a composite GitHub Action for creating GitHub Releases.
The action contract is in `action.yml`; keep inputs, outputs, and environment
variables synchronized with the implementation in `scripts/create-release.sh`.
Reusable Bash helpers are in `scripts/`, including release note generation,
commit filtering, and prerelease detection. Tests live under `tests/`: unit
tests in `tests/unit/`, integration tests in `tests/integration/`, and BATS
coverage in `tests/bats/`. Workflow examples are in `docs/examples/`.

## Build, Test, and Development Commands

- `make help` lists available Make targets.
- `make setup` makes scripts and test files executable; run once after cloning.
- `make test-all` runs unit, integration, and optional BATS tests.
- `make test-unit` runs the Bash unit test scripts only.
- `make test-integration` runs the release creation integration suite.
- `make test-bats` runs `tests/bats/release.bats` and requires `bats-core`.
- `make shellcheck` runs ShellCheck over `scripts/` and `tests/`.
- `make coverage` runs kcov-based coverage on Linux with `kcov` and `bats`.
- `make clean` removes temporary test artifacts and `coverage/`.

## Coding Style & Naming Conventions

Use Bash with `set -euo pipefail` in executable scripts. Prefer small functions,
clear variable names, and quoted expansions. Keep indentation at two spaces in
shell scripts, matching the existing tests. File names use lowercase words with
hyphens, for example `generate-notes.sh`. Inputs in `action.yml` use kebab-case;
their corresponding environment variables use uppercase `INPUT_` names.

## Testing Guidelines

Add tests for every behavior change. Update `tests/unit/test_filter_commits.sh`
for commit selection rules, `tests/unit/test_generate_notes.sh` for note
formatting, `tests/unit/test_detect_prerelease.sh` for prerelease parsing, and
`tests/integration/test_create_release.sh` for end-to-end release behavior. Add
BATS coverage in `tests/bats/release.bats` for new action inputs or important
script interactions. Run `make test-all` and `make shellcheck` before opening a
pull request.

## Commit & Pull Request Guidelines

Use Conventional Commits: `type(scope): short description`. Common types are
`feat`, `fix`, `docs`, `refactor`, `test`, `chore`, `ci`, `perf`, and `style`.
Common scopes include `action`, `scripts`, `tests`, `workflows`, and `docs`.
Examples: `feat(scripts): add grouped release notes` or
`fix(action): handle missing tag input`.

Create focused branches such as `feat/add-assets-upload` or `fix/prerelease-tag`.
Pull requests should describe the change, explain test coverage, link related
issues when applicable, and include workflow snippets only when action behavior
changes.

## Security & Configuration Tips

Do not hard-code tokens. The action expects `token` to be provided by the caller
and passes it to `gh` through `GH_TOKEN`. Preserve `contents: write` guidance in
examples, and keep release logic compatible with full tag history
(`fetch-depth: 0`).

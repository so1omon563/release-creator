# Contributing to release-creator

Thank you for contributing to this project. This guide covers how to get started,
our development standards, and the process for submitting changes.

## Who Can Contribute

This repository is open to contributions from anyone — but **only designated maintainers
can push branches or open PRs directly**. If you are not a maintainer, please contribute
via a fork (see [Fork Workflow](#fork-workflow) below).

> **Requesting maintainer access in order to contribute is not the right path.**
> The fork workflow described in this guide is the standard way to contribute to this
> project, just as it is for any open-source project hosted on GitHub.

## Prerequisites

- Bash (macOS or Linux)
- Git (with `user.name` and `user.email` configured — required for the test suite)
- `make` (standard on macOS/Linux)
- **GitHub CLI (`gh`)** — required for release creation functionality
- **Optional:** `bats-core` for full BATS test coverage (`brew install bats-core` on macOS)

## Getting Started

### External contributors (fork required)

If you are not a repository maintainer, start by forking the repository on GitHub first,
then clone your fork:

```bash
# Clone YOUR fork (replace <your-username>)
git clone https://github.com/<your-username>/release-creator.git
cd release-creator

# Add the upstream remote so you can sync with the original repo
git remote add upstream https://github.com/so1omon563/release-creator.git

# Make test scripts executable (run once after cloning)
make setup
```

For the full fork-based contribution workflow, see [Fork Workflow](#fork-workflow) under
Development Workflow below.

### Maintainers (direct clone)

```bash
# Clone the repository
git clone https://github.com/so1omon563/release-creator.git
cd release-creator

# Make test scripts executable (run once after cloning)
make setup
```

## Development Workflow

This repository follows a trunk-based development model. All changes must be made on
feature branches and submitted via pull request.

### Fork Workflow

If you are not a repository maintainer, follow these steps to contribute:

**1. Fork the repository**

Click **Fork** on the [repository page](https://github.com/so1omon563/release-creator)
to create your own copy under your GitHub account.

**2. Clone your fork**

```bash
git clone https://github.com/<your-username>/release-creator.git
cd release-creator
```

**3. Add the upstream remote**

```bash
git remote add upstream https://github.com/so1omon563/release-creator.git
```

**4. Create a feature branch**

```bash
git checkout -b feat/your-short-description
```

Follow the [branch naming conventions](#branch-naming) below.

**5. Make your changes and commit**

Follow the [commit conventions](#commit-conventions) below. Run tests and linting before
committing:

```bash
make setup        # first time only — makes test scripts executable
make test-all
make shellcheck
```

**6. Push to your fork and open a pull request**

```bash
git push origin feat/your-short-description
```

Then open a pull request on GitHub from your fork branch targeting `main` on the upstream
repository. Fill in the pull request template and follow the [PR process](#pull-request-process).

**7. Keep your fork in sync**

Before starting new work, sync your fork's `main` with upstream:

```bash
git checkout main
git fetch upstream
git merge upstream/main
git push origin main
```

### Branch Naming

Use the following prefixes when creating branches:

| Prefix      | Use case                                    |
| ----------- | ------------------------------------------- |
| `feat/`     | New features or capabilities                |
| `fix/`      | Bug fixes                                   |
| `docs/`     | Documentation-only changes                  |
| `refactor/` | Code restructuring without behaviour change |
| `chore/`    | Maintenance, dependency updates             |
| `ci/`       | CI/CD pipeline changes                      |
| `test/`     | Test additions or updates                   |

**Format:** `<prefix>/<short-description>`

**Format:** `<prefix>/<short-description>`

**Example:** `feat/add-release-notes-grouping`

### Making Changes

Maintainers push branches directly. External contributors should follow the
[Fork Workflow](#fork-workflow) above.

1. Create a branch from `main`
2. Make your changes in focused, logical commits (see below)
3. Ensure all tests and linting pass
4. Open a pull request targeting `main`

### Commit Conventions

This repository follows the [Conventional Commits](https://www.conventionalcommits.org/)
standard:

```text
<type>(<scope>): <short description>

[optional body]

[optional footer(s)]
```

**Types:** `feat`, `fix`, `docs`, `refactor`, `test`, `chore`, `ci`, `perf`, `style`

**Scopes:** `action`, `scripts`, `tests`, `workflows`, `docs`

**Examples:**

```text
feat(scripts): add grouping of commits by conventional type
fix(action): handle missing git tag gracefully
docs: update README with new input parameters
```

## Code Standards

### Linting and Formatting

Run the following before committing:

```bash
make shellcheck
```

### Testing

Run the full suite before committing:

```bash
# Run all tests (primary command)
make test-all

# Run specific suites
make test-unit         # Core logic tests
make test-integration  # Integration tests
make test-bats         # BATS framework tests (requires bats-core)
```

All new features and bug fixes must include tests. The test suite must pass in full before a
PR is opened.

### What to test and where

#### Changing release note or commit logic in `scripts/`

| Change type                       | Where to add tests                                              |
| --------------------------------- | --------------------------------------------------------------- |
| Commit filtering or parsing rules | `tests/unit/test_filter_commits.sh` + `tests/bats/release.bats` |
| Release note generation logic     | `tests/unit/test_generate_notes.sh` + `tests/bats/release.bats` |
| Pre-release detection             | `tests/unit/test_detect_prerelease.sh`                          |
| Full release creation flow        | `tests/integration/test_create_release.sh`                      |
| New action input (`action.yml`)   | `tests/bats/release.bats` — add coverage for the new input      |

#### BATS tests (`tests/bats/release.bats`) — highest confidence

`tests/bats/release.bats` tests invoke the action scripts directly in isolated environments.
These are the highest-confidence tests because they exercise the actual production scripts.

If you add a new code path to any script in `scripts/`, add a corresponding BATS test:

```bash
@test "your scenario description" {
    # arrange — set up git state and inputs
    git tag -a "v1.0.0" -m "Version 1.0.0"

    # act — invoke the script under test
    run bash "$BATS_TEST_DIRNAME/../scripts/generate-notes.sh"

    # assert
    [ "$status" -eq 0 ]
    [[ "$output" == *"your expected output"* ]]
}
```

## Pull Request Process

1. Ensure your branch is up to date with `main` before opening your PR
2. Fill in all required sections of the pull request template
3. Link any related issue references (e.g., `#123`)
4. Run `make test-all` and confirm it passes
5. Run `make shellcheck` and confirm it passes
6. Request review from a maintainer

PRs that do not pass CI checks will not be merged.

When merging, include a version bump marker in the squash commit message:

- `#major` — breaking changes
- `#minor` — backward-compatible new features
- `#patch` — bug fixes and minor updates
- `#skip` — no version tag (documentation-only changes)

## GitHub Copilot Skills (Not Included Here)

This repository no longer includes project-specific Copilot skill configuration.

You can still use editor tooling or GitHub Copilot Chat generally, but there are no repo-specific skill commands defined for this project.

## Feature Request Policy

Before opening a feature request, read the [Project Scope][scope] section of the
README. It defines exactly what this action does and does not do.

**In short:** this action creates GitHub Releases with release notes from conventional
commits. It accepts whatever tag you provide — creating the tag as part of the release
if it does not exist yet — but it does not compute version numbers from commit history,
deploy artifacts, update version manifests, or manage existing releases. Requests for
those capabilities will be closed without merging.

### What makes a valid feature request

A valid feature request improves or extends the core behaviour of the action:
generating release notes from commits and publishing a GitHub Release.

Examples of in-scope requests:

- Support for a new release note format or grouping strategy
- A new output variable that exposes information the action already computes
- A new input that controls existing release creation behaviour
- Improved pre-release detection patterns or tag suffix handling
- Improved error handling or edge case coverage
- Moving floating pointer tags (`v1`, `v1.3`) to the release commit

### What makes an out-of-scope request

If the request is about semver auto-incrementing, deployment, or managing releases
after they are published, it is out of scope.

Examples of out-of-scope requests (will be closed):

- **Semver auto-incrementing** — computing `v1.2.3 → v1.2.4` from commit history; use
  [custom-semver-bumper](https://github.com/so1omon563/custom-semver-bumper)
  for this
- Publishing to package registries or deploying to environments
- Updating `package.json`, `pyproject.toml`, or other version manifest files
- Editing or deleting existing GitHub Releases
- Branch-specific release rules — use `if:` conditions in your workflow instead

### Alternative tools

- **[`gh release create`][gh-cli]** — GitHub CLI for one-off release creation
- **[GitHub Releases API][gh-releases]** — REST API for programmatic release management
- **[custom-semver-bumper][semver-bumper]** — semver auto-incrementing and tag creation

[scope]: https://github.com/so1omon563/release-creator#project-scope
[gh-cli]: https://cli.github.com/manual/gh_release
[gh-releases]: https://docs.github.com/en/repositories/releasing-projects-on-github/managing-releases-in-a-repository
[semver-bumper]: https://github.com/so1omon563/custom-semver-bumper

## Reporting Issues

Open a [GitHub Issue](https://github.com/so1omon563/release-creator/issues)
to report bugs or request features.

For security vulnerabilities, open a
[private security advisory](https://github.com/so1omon563/release-creator/security/advisories/new)
rather than a public issue.

## Questions and Support

Reach out to a maintainer on the repository, or open a
GitHub Issue for general questions.

# Release Creator

[![Test](https://github.com/so1omon563/sharedactions-action-release-creator/actions/workflows/test.yml/badge.svg)](https://github.com/so1omon563/sharedactions-action-release-creator/actions/workflows/test.yml)
[![Coverage](https://img.shields.io/badge/coverage-0%25-red)](https://github.com/so1omon563/sharedactions-action-release-creator/actions/workflows/test.yml)

A composite GitHub Action that creates GitHub Releases with auto-generated release notes
from conventional commit history. Works standalone (on tag push or manual dispatch) or
chained with
[sharedactions-action-custom-semver-bumper](https://github.com/so1omon563/custom-semver-bumper).

## Table of Contents

- [Release Creator](#release-creator)
  - [Table of Contents](#table-of-contents)
  - [Project Scope](#project-scope)
    - [In Scope](#in-scope)
    - [Out of Scope](#out-of-scope)
    - [The Key Distinction: Release Creation vs Semver Bumping](#the-key-distinction-release-creation-vs-semver-bumping)
  - [Is This Action Right for You?](#is-this-action-right-for-you)
  - [Quick Start](#quick-start)
  - [How It Works](#how-it-works)
  - [Requirements](#requirements)
  - [Configuration](#configuration)
    - [Inputs](#inputs)
    - [Outputs](#outputs)
  - [Usage Examples](#usage-examples)
    - [Chained with the Semver Bumper](#chained-with-the-semver-bumper)
    - [Conditional Release (skip when bumper skips)](#conditional-release-skip-when-bumper-skips)
    - [On Tag Push (External Tag Workflows)](#on-tag-push-external-tag-workflows)
    - [Manual Dispatch](#manual-dispatch)
    - [Using Release Outputs](#using-release-outputs)
  - [Release Note Formats](#release-note-formats)
  - [Pre-release Auto-detection](#pre-release-auto-detection)
  - [Monorepo Support](#monorepo-support)
  - [Moving Floating Pointer Tags](#moving-floating-pointer-tags)
  - [Asset Upload](#asset-upload)
  - [Chaining with the Semver Bumper](#chaining-with-the-semver-bumper)
  - [Development](#development)
    - [Release Process](#release-process)
    - [Contributing](#contributing)
    - [Testing](#testing)

## Project Scope

**This action creates GitHub Releases with auto-generated release notes from conventional
commit history.**

It reads a commit range, generates structured release notes grouped by conventional commit
type, and publishes a GitHub Release via the `gh` CLI. The release tag may already exist
or may be created as part of the release — `gh release create` creates the tag if it does
not exist yet, using `target-commitish` to determine where it points. What this action
does not do is determine *what the next version number should be* based on commit history.

### In Scope

- Generating release notes from conventional commits in a given tag range
- Four release note formats: `grouped`, `conventional`, `flat`, `github-native`
- Creating a GitHub Release via the `gh` CLI (including creating the tag if it does not
  yet exist, via `target-commitish`)
- Auto-detecting pre-release status from any SemVer §9 pre-release identifier
- Moving floating pointer tags (`v1`, `v1.3`) to the release commit
- Uploading release assets via file glob patterns
- Skipping creation when a release already exists (`skip-if-release-exists`)
- Scoping release notes to a monorepo subdirectory via `path-filter`

### Out of Scope

The following will never be added to this action. They belong in separate tooling:

- **Semver auto-incrementing** — reading commit history to determine the next version
  number (`v1.2.3 → v1.2.4`) and pushing a new tag is the responsibility of
  [sharedactions-action-custom-semver-bumper](https://github.com/so1omon563/custom-semver-bumper).
  This action accepts whatever tag you give it; it does not compute version numbers.
- **Deployment or publishing artifacts**
- **Version manifest updates** — updating `package.json`, `pyproject.toml`, or similar
- **Managing existing releases** — editing, deleting, or re-publishing
- **Branch-based release gating** — use `if:` conditions in your workflow
- **Notifications or third-party integrations**

### The Key Distinction: Release Creation vs Semver Bumping

This action creates a GitHub Release for a given tag. You provide the tag — either one
that already exists, or a new one that this action will create when it runs. What you
choose to name that tag, and how you increment it, is entirely your concern.

If you want automatic version number computation based on commit messages, compose this
action with [sharedactions-action-custom-semver-bumper](https://github.com/so1omon563/custom-semver-bumper)
upstream in your workflow. If you manage version numbers yourself (manually, via a script,
or from a CI pipeline), pass the tag directly — no dependency on the bumper required.

## Is This Action Right for You?

Use this action when you want to publish a **curated GitHub Release** — with structured
release notes and optional assets — at an **explicit, intentional point in your workflow**.

**This action is a good fit if:**

- You want to publish a GitHub Release with human-readable, grouped release notes
  (by commit type: features, fixes, etc.) rather than a raw commit list.
- You create releases on-demand — triggered by a tag push, a manual dispatch, or a
  downstream step in a pipeline — rather than on every merge.
- You want to upload release assets (binaries, packages, archives) alongside the
  release notes.
- You work in a monorepo and need release notes scoped to a specific subdirectory.
- You want to move floating pointer tags (`v1`, `v1.3`) as part of the release step
  without needing a separate action.

**This action is not the right tool if:**

- You only need a Git tag — no GitHub Release entry, no release notes, no assets.
  In that case, use `git tag` directly or
  [sharedactions-action-custom-semver-bumper](https://github.com/so1omon563/custom-semver-bumper).
- You want every merge to `main` to be automatically tagged and versioned, even when
  no explicit release is intended. That is a tagging automation concern; use the
  semver bumper for it.
- You want to automatically compute the next version number (`v1.2.3 → v1.2.4`) from
  commit history without specifying it explicitly. This action accepts whatever tag
  you give it; use the semver bumper to calculate the next version first.

> **In short:** if you already know the version and want to publish a release, this
> action is for you. If you need something to decide what the next version should be,
> pair it with (or replace it with)
> [sharedactions-action-custom-semver-bumper](https://github.com/so1omon563/custom-semver-bumper).

## Quick Start

### Standalone — on tag push

```yaml
on:
  push:
    tags:
      - 'v*'

jobs:
  release:
    runs-on: ubuntu-latest
    permissions:
      contents: write
    steps:
      - uses: actions/checkout@v6
        with:
          fetch-depth: 0

      - uses: so1omon563/sharedactions-action-release-creator@v1
        with:
          token: ${{ secrets.GITHUB_TOKEN }}
```

### Chained — semver bumper creates the tag, this action creates the release

```yaml
jobs:
  bump-and-release:
    runs-on: ubuntu-latest
    permissions:
      contents: write
    steps:
      - uses: actions/checkout@v6
        with:
          fetch-depth: 0

      - name: Bump version
        id: bump
        uses: so1omon563/custom-semver-bumper@v1
        with:
          GITHUB_TOKEN: ${{ secrets.GITHUB_TOKEN }}

      - name: Create release
        if: steps.bump.outputs.skipped == 'false'
        uses: so1omon563/sharedactions-action-release-creator@v1
        with:
          token: ${{ secrets.GITHUB_TOKEN }}
          tag: ${{ steps.bump.outputs.new_version }}
          from-tag: ${{ steps.bump.outputs.previous_version }}
```

> **Note:** The semver bumper outputs are `new_version` and `previous_version`
> (underscores, not hyphens). Use `steps.<id>.outputs.new_version` in your workflow.

## How It Works

1. Reads the tag input (or infers it from `github.ref_name` on tag-push triggers)
2. Resolves the commit range (`from-tag` to `to-tag`), auto-detecting `from-tag` when
   omitted by looking at the tag immediately preceding `to-tag`
3. Filters commits in that range (excludes merge commits; optionally scopes to a path)
4. Parses [Conventional Commits][cc-spec] to group by type
5. Generates release notes in the requested format
6. Auto-detects whether the tag is a pre-release (any SemVer §9 identifier)
7. Creates the GitHub Release via `gh release create`
8. Optionally uploads assets to the release

## Requirements

- **`gh` CLI** — pre-installed on all GitHub-hosted runners
- **`fetch-depth: 0`** — required for full tag history access
- **`contents: write` permission** — required to create releases

## Configuration

### Inputs

| Input | Required | Default | Description |
| ----- | -------- | ------- | ----------- |
| `token` | ✅ | — | GitHub token with `contents: write` |
| `tag` | — | `github.ref_name` | Tag name for the release (e.g. `v1.2.3`) |
| `release-name` | — | tag value | Display name for the release |
| `body` | — | `''` | Explicit release body; overrides auto-generated notes |
| `draft` | — | `false` | Create the release as a draft |
| `prerelease` | — | `auto` | `true`, `false`, or `auto` (inspect tag — see [Pre-release Auto-detection](#pre-release-auto-detection)) |
| `target-commitish` | — | `''` | Branch or SHA to tag from |
| `notes-format` | — | `grouped` | `grouped`, `conventional`, `flat`, or `github-native` |
| `from-tag` | — | auto | Start of commit range for notes (exclusive) |
| `to-tag` | — | `tag` value | End of commit range for notes (inclusive) |
| `asset-paths` | — | `''` | Newline-separated glob patterns for assets to upload |
| `skip-if-release-exists` | — | `false` | Exit successfully without error if release already exists |
| `path-filter` | — | `''` | Scope release notes to commits touching this path |
| `tag-prefix` | — | `''` | Prefix to strip for version comparisons (e.g. `v`). Match this to `tag_prefix` in the semver bumper when chaining. |
| `fail-on-error` | — | `true` | Fail the step on error; `false` logs and exits cleanly |
| `move-major-tag` | — | `false` | Move the major floating pointer tag (e.g. `v1`) to the release commit. Skipped automatically for pre-releases. |
| `move-minor-tag` | — | `false` | Move the minor floating pointer tag (e.g. `v1.3`) to the release commit. Skipped automatically for pre-releases. |

### Outputs

| Output | Description |
| ------ | ----------- |
| `release-url` | HTML URL of the created GitHub Release |
| `release-id` | Numeric ID of the release |
| `upload-url` | Upload URL template for additional assets |
| `tag-name` | The tag name used for the release |
| `created` | `true` when a new release was created |
| `skipped` | `true` when `skip-if-release-exists` was triggered |

## Usage Examples

### Chained with the Semver Bumper

The semver bumper produces several outputs. Here is how to consume them:

```yaml
jobs:
  bump-and-release:
    if: github.event.pull_request.merged == true
    runs-on: ubuntu-latest
    permissions:
      contents: write
    steps:
      - uses: actions/checkout@v6
        with:
          fetch-depth: 0

      - name: Bump version
        id: bump
        uses: so1omon563/custom-semver-bumper@v1
        with:
          GITHUB_TOKEN: ${{ secrets.GITHUB_TOKEN }}
          # Do NOT set move_major_tag/move_minor_tag here — the release-creator
          # owns floating pointer tags and moves them only when a release is published.

      - name: Create release
        # Skip if the bumper was told to skip (e.g. commit message contains #skip)
        if: steps.bump.outputs.skipped == 'false'
        uses: so1omon563/sharedactions-action-release-creator@v1
        with:
          token: ${{ secrets.GITHUB_TOKEN }}
          tag: ${{ steps.bump.outputs.new_version }}
          from-tag: ${{ steps.bump.outputs.previous_version }}
          move-major-tag: 'true'
          move-minor-tag: 'true'
          # notes-format: grouped  # default — grouped by conventional commit type
```

**Semver bumper outputs reference:**

| Output | Example value | Notes |
| ------ | ------------- | ----- |
| `new_version` | `v1.3.0` | Full tag name including prefix — pass directly to `tag:` |
| `previous_version` | `v1.2.4` | Pass directly to `from-tag:` |
| `bump_type` | `minor` | `major`, `minor`, `patch`, `prerelease`, or `skip` |
| `skipped` | `false` | `true` when bump was skipped — gate the release step on this |

> **Build metadata:** When the bumper is configured with `build_metadata: sha`, tags
> include a `+sha.abc1234` suffix (e.g. `v1.3.0+sha.a1b2c3d`). This action handles
> such tags correctly — tags with build metadata only are treated as stable; tags with
> both a pre-release label and build metadata (e.g. `v1.2.3-alpha.1+sha.abc`) are
> flagged as pre-release.

### Conditional Release (skip when bumper skips)

```yaml
- name: Create release
  if: steps.bump.outputs.skipped == 'false'
  uses: so1omon563/sharedactions-action-release-creator@v1
  with:
    token: ${{ secrets.GITHUB_TOKEN }}
    tag: ${{ steps.bump.outputs.new_version }}
    from-tag: ${{ steps.bump.outputs.previous_version }}
```

### On Tag Push (External Tag Workflows)

> **Note:** This action no longer uses `push: tags:` for its own releases.
> The automated flow is owned by `bump.yml` (see [Chaining with the Semver Bumper](#chaining-with-the-semver-bumper)).
> `push: tags:` is useful when tags are pushed by a PAT rather than `GITHUB_TOKEN`.

Trigger on every stable semver tag and skip pre-releases.

```yaml
on:
  push:
    tags:
      - 'v[0-9]*.[0-9]*.[0-9]*'   # stable semver tags only

jobs:
  release:
    name: Create GitHub Release
    # Skip pre-release tags (e.g. v1.3.0-rc.1)
    if: "!contains(github.ref_name, '-')"
    runs-on: ubuntu-latest
    permissions:
      contents: write
    steps:
      - uses: actions/checkout@v6
        with:
          fetch-depth: 0

      - uses: so1omon563/sharedactions-action-release-creator@v1
        with:
          token: ${{ secrets.GITHUB_TOKEN }}
          tag: ${{ github.ref_name }}
          tag-prefix: v
          notes-format: grouped
          move-major-tag: 'true'
          move-minor-tag: 'true'
```

If you also use the semver bumper, do NOT set `move_major_tag` / `move_minor_tag` on
the bumper — let this action own the floating tags so they only move when a release is
intentionally published.

### Manual Dispatch

```yaml
on:
  workflow_dispatch:
    inputs:
      tag:
        description: Tag to release
        required: true
      from-tag:
        description: Previous tag (start of commit range)
        required: false

jobs:
  release:
    runs-on: ubuntu-latest
    permissions:
      contents: write
    steps:
      - uses: actions/checkout@v6
        with:
          fetch-depth: 0

      - uses: so1omon563/sharedactions-action-release-creator@v1
        with:
          token: ${{ secrets.GITHUB_TOKEN }}
          tag: ${{ inputs.tag }}
          from-tag: ${{ inputs.from-tag }}
          notes-format: conventional
```

### Using Release Outputs

```yaml
- name: Create release
  id: release
  uses: so1omon563/sharedactions-action-release-creator@v1
  with:
    token: ${{ secrets.GITHUB_TOKEN }}
    tag: v1.0.0

- name: Print release URL
  run: echo "Released at ${{ steps.release.outputs.release-url }}"

- name: Upload extra asset
  if: steps.release.outputs.created == 'true'
  run: |
    gh release upload v1.0.0 dist/checksums.sha256 \
      --repo ${{ github.repository }}
  env:
    GH_TOKEN: ${{ secrets.GITHUB_TOKEN }}
```

## Release Note Formats

### `grouped` (default)

Commits are grouped by conventional commit type with emoji section headers:

```markdown
### 🚀 Features

- add user export endpoint (`abc1234`)
- implement pagination support (`def5678`)

### 🐛 Bug Fixes

- resolve null pointer in parser (`aaa1111`)

### 📖 Documentation

- update README with examples (`bbb2222`)
```

Supported section headers: 🚀 Features, 🐛 Bug Fixes, ⚡ Performance, ♻️ Refactor,
📖 Documentation, 🧪 Tests, 🔧 CI/CD, 🧹 Chores, 🏗️ Build, 💅 Style, ⏪ Reverts,
📦 Other Changes.

### `conventional`

Flat list preserving the conventional commit type prefix:

```markdown
- feat: add user export endpoint (`abc1234`)
- fix: resolve null pointer in parser (`aaa1111`)
- docs: update README with examples (`bbb2222`)
```

### `flat`

Plain descriptions with no type prefix:

```markdown
- add user export endpoint (`abc1234`)
- resolve null pointer in parser (`aaa1111`)
- update README with examples (`bbb2222`)
```

### `github-native`

Delegates entirely to GitHub's built-in release notes generator
(`gh release create --generate-notes`). Useful when you prefer GitHub's
default PR-based grouping.

## Pre-release Auto-detection

When `prerelease: auto` (the default), the action follows **SemVer §9**: any
hyphen-separated label immediately after the patch version is treated as a pre-release
identifier. This means **any custom suffix** produced by the semver bumper — including
`enterprise`, `team-blue`, `canary`, or any value set via `allowed_prerelease_suffixes` —
is correctly detected.

| Tag format | Pre-release? | Notes |
| ---------- | ------------ | ----- |
| `v1.2.3` | No | Stable |
| `v1.2.3-alpha.1` | Yes | Standard pre-release |
| `v1.2.3-rc.2` | Yes | Standard pre-release |
| `v1.2.3-enterprise.1` | Yes | Custom suffix (semver bumper) |
| `v1.2.3-team-blue.3` | Yes | Custom suffix (semver bumper) |
| `v1.2.3+sha.abc1234` | No | Build metadata only — stable |
| `v1.2.3-alpha.1+sha.abc` | Yes | Pre-release label + build metadata |

Set `prerelease: true` or `prerelease: false` to override auto-detection.

## Monorepo Support

Use `path-filter` to scope release notes to commits that touch files under a specific
directory:

```yaml
- uses: so1omon563/sharedactions-action-release-creator@v1
  with:
    token: ${{ secrets.GITHUB_TOKEN }}
    tag: services/auth/v2.1.0
    tag-prefix: services/auth/
    from-tag: services/auth/v2.0.0
    path-filter: services/auth
```

## Moving Floating Pointer Tags

Floating pointer tags (`v1`, `v1.3`) are convenience refs that always point to the
latest stable release at a given major or minor version. They are useful for GitHub
Actions consumers who pin to `@v1` and want to receive patch updates automatically.

Enable them with `move-major-tag` and/or `move-minor-tag`:

```yaml
- uses: so1omon563/sharedactions-action-release-creator@v1
  with:
    token: ${{ secrets.GITHUB_TOKEN }}
    tag: v1.3.2
    tag-prefix: v
    move-major-tag: 'true'   # v1 → v1.3.2's commit
    move-minor-tag: 'true'   # v1.3 → v1.3.2's commit
```

Both inputs are **skipped automatically for pre-release tags** (any tag with a SemVer §9
pre-release identifier, e.g. `-rc.1`). Floating pointer tags must only reference stable
commits — moving `v1` to a `-rc.1` commit would break consumers who pin to `@v1`.

**When using with [`sharedactions-action-custom-semver-bumper`](https://github.com/so1omon563/custom-semver-bumper):**
Always set `move-major-tag` / `move-minor-tag` here in the release creator, **not** on
the bumper. The bumper creates a tag on every merge — you only want floating pointer tags
to advance when a release is intentionally published. Do not set `move_major_tag` or
`move_minor_tag` on the bumper when both actions are used together.

## Asset Upload

Provide newline-separated glob patterns to attach files to the release:

```yaml
- uses: so1omon563/sharedactions-action-release-creator@v1
  with:
    token: ${{ secrets.GITHUB_TOKEN }}
    tag: v1.0.0
    asset-paths: |
      dist/*.tar.gz
      dist/*.zip
      dist/**/*.whl
      checksums.txt
```

## Chaining with the Semver Bumper

When you use [`sharedactions-action-custom-semver-bumper`](https://github.com/so1omon563/custom-semver-bumper)
to auto-tag every PR merge, you can trigger a GitHub Release from the same workflow run
by including a release marker in the PR title or body.

### Trigger markers

| Marker     | Forces stable tag? | Creates GitHub Release? |
| ---------- | ------------------ | ----------------------- |
| `#stable`  | ✅ Yes              | ❌ No                    |
| `#release` | ✅ Yes              | ✅ Yes                   |
| `#publish` | ❌ No change        | ✅ Yes                   |
| `#ship`    | ❌ No change        | ✅ Yes                   |

All markers are **case-insensitive**.

> **Why the same workflow run?** Tags pushed by `GITHUB_TOKEN` cannot trigger other
> workflows. The release job must live in the same workflow as the bump job.

### Pre-release support

If the bumper produces a pre-release tag (e.g. `v1.2.0-alpha.1`), including any of the
release markers will create a **pre-release** GitHub Release. The release creator detects
this automatically via `prerelease: auto`.

### Setting it up

**Step 1** — Ensure you are using semver-bumper `v1.5.0` or later (which emits the
`should_release` output).

**Step 2** — Replace your existing `bump.yml` with the pattern below:

```yaml
jobs:
  bump-version:
    if: github.event.pull_request.merged == true
    runs-on: ubuntu-latest
    permissions:
      contents: write
    outputs:
      new_tag: ${{ steps.bump.outputs.new_version }}
      skipped: ${{ steps.bump.outputs.skipped }}
      release_requested: ${{ steps.bump.outputs.should_release }}
    steps:
      - uses: actions/checkout@v6
        with:
          fetch-depth: 0
      - id: bump
        uses: so1omon563/custom-semver-bumper@v1
        with:
          GITHUB_TOKEN: ${{ secrets.GITHUB_TOKEN }}
          # Do NOT set move_major_tag/move_minor_tag here — the release-creator owns them.

  create-release:
    needs: bump-version
    if: |
      needs.bump-version.outputs.release_requested == 'true' &&
      needs.bump-version.outputs.skipped != 'true'
    runs-on: ubuntu-latest
    permissions:
      contents: write
    steps:
      - uses: actions/checkout@v6
        with:
          fetch-depth: 0
      - uses: so1omon563/sharedactions-action-release-creator@v1
        with:
          token: ${{ secrets.GITHUB_TOKEN }}
          tag: ${{ needs.bump-version.outputs.new_tag }}
          tag-prefix: v
          notes-format: grouped
          move-major-tag: 'true'
          move-minor-tag: 'true'
```

**Step 3** — In your next PR, add `#release`, `#publish`, or `#ship` to the title or body.
The bump creates the tag and the release job creates the GitHub Release immediately after,
all in the same workflow run.

## Development

### Release Process

This action manages its own releases using itself (true dogfooding).

**Automated releases (normal flow):**

1. A PR is merged to `main`. The semver bumper (`bump.yml`) reads the commit message for
   a version marker (`#major`, `#minor`, `#patch`) and pushes a new semver tag (e.g.
   `v1.3.0`).
2. If the PR title or body contains `#release`, `#publish`, or `#ship`, the `create-release`
   job in `bump.yml` runs immediately after the bump in the same workflow run. It calls
   `uses: ./` (dogfood), generates grouped release notes, publishes the GitHub Release, and
   moves the `v1` and `v1.3` floating pointer tags to the release commit.
3. If no release marker is present, the tag is created but no release is published yet.

**Manual / escape-hatch releases:**

Use `release.yml` (workflow_dispatch) to publish a release for any existing tag at any time —
whether the tag was bumped without a `#release` marker, a previous release run failed, or a
tag was pushed outside the normal bump flow.

**Pre-releases are not automatically published.** Tags with a pre-release identifier (e.g.
`v1.3.0-rc.1`) will create a pre-release GitHub Release if `#release` is included, but the
floating pointer tags (`v1`, `v1.3`) are never moved to a pre-release commit.

**Floating tag ownership:** `v1` and `v1.3` are managed by the release-creator (both in the
`create-release` job in `bump.yml` and in `release.yml`) — never by the semver bumper.
They advance only when a GitHub Release is intentionally published.

**Self-referential:** Both `bump.yml` and `release.yml` use `uses: ./` to call the action
from the local checkout — true dogfooding with no branch or tag pin needed.

### Contributing

See [CONTRIBUTING.md](CONTRIBUTING.md) for full contribution guidelines including branch
naming conventions, commit standards, and the pull request process.

### Testing

```bash
# Make test scripts executable (run once after cloning)
make setup

# Run the full test suite
make test-all

# Run individual suites
make test-unit
make test-integration
make test-bats         # requires bats-core (brew install bats-core)

# Lint shell scripts
make shellcheck

# Measure coverage (requires kcov and bats-core)
make coverage
```

Tests require `git user.name` and `git user.email` to be set. The test runner
configures these automatically if missing.

[cc-spec]: https://www.conventionalcommits.org/en/v1.0.0/

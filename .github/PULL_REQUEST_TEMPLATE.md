# Pull Request Description

## Summary

Please provide a clear and concise description of what this change achieves and why it's needed.

## Changes Made

- [ ] Added new functionality
- [ ] Modified existing functionality
- [ ] Fixed a bug
- [ ] Updated documentation
- [ ] Refactored code
- [ ] Updated dependencies
- [ ] Other: _please specify_

## Issues Resolved

List any related GitHub Issues this PR resolves (e.g., "Closes #123").

## Testing

Describe how you tested these changes:

- [ ] Unit tests pass (`make test-unit`)
- [ ] Integration tests pass (`make test-integration`)
- [ ] BATS tests pass (`make test-bats`)
- [ ] Full suite passes (`make test-all`)
- [ ] N/A

## Checklist

Please ensure all applicable items are completed before submitting this PR:

- [ ] I have read and followed the [Contributing Guidelines](../CONTRIBUTING.md)
- [ ] Documentation has been provided or updated for any new or modified behaviour
- [ ] Code follows the existing Bash scripting patterns (`set -e`, quiet flags, temp dir cleanup)
- [ ] ShellCheck passes (`make shellcheck`)
- [ ] Test scripts are executable (`make setup`)
- [ ] Git config is set (required for test suite to run correctly)
- [ ] Breaking changes are clearly documented

## Version Bump

When merging this PR, include one of the following in your merge commit message to trigger automatic version tagging:

- `#major` — breaking changes (e.g., 1.0.0 → 2.0.0)
- `#minor` — backward-compatible new features (e.g., 1.0.0 → 1.1.0)
- `#patch` — backward-compatible bug fixes (e.g., 1.0.0 → 1.0.1)
- `#skip` — no version tag (e.g., documentation-only changes)

If no marker is specified, a patch-level bump is applied by default.

## Additional Notes

_Optional: Add any additional context, screenshots, or notes that reviewers should know._

---

**For Reviewers:**

- Run `make test-all` to verify the full test suite passes
- Check that any new edge cases are covered by unit tests
- Verify BATS tests cover the new behaviour

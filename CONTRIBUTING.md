# Contributing to Bananapeel

Thanks for your interest in improving Bananapeel. This guide explains how to propose changes, run tests, and get credit for your contributions.

## How to Contribute
- Fork the repository and create a feature branch:
  - `git checkout -b feat/my-change`
- Make focused changes with clear commit messages (see Commit Style).
- Run tests locally (see Testing) and ensure CI is green.
- Open a pull request with:
  - What changed and why
  - Test plan (commands + output)
  - Any security implications

## Commit Style (Conventional Commits)
Use Conventional Commits for clarity and better release notes:
- Types: `feat:`, `fix:`, `docs:`, `chore:`, `refactor:`, `test:`, `build:`, `ci:`
- Optional scope examples: `setup`, `maintenance`, `packaging`, `wrapper`, `status`
- Examples:
  - `feat(setup): add cross‑platform installer flags`
  - `fix(wrapper): block symlink traversal with readlink -f`

## Development & Style
- Language: Bash (shebang `#!/bin/bash`), prefer POSIX where reasonable.
- Safety: `set -e` (or `set -euo pipefail` for entrypoints), validate inputs, no hardcoded secrets.
- Indentation: 2 spaces; no tabs; lines ≤ 100 chars when possible.
- Filenames: kebab-case (e.g., `optimize-tripwire-policy.sh`). Functions/vars: snake_case.
- Recommended tools:
  - `shellcheck script.sh` (lint)
  - `shfmt -w -i 2 script.sh` (format)

## Testing
- Base tests: `make test`
  - Lints and syntax-checks all scripts.
- Functional tests: `make test-functional`
  - Uses mocks; safe to run without root. Some tests are best-effort.
- Packaging prep (no network builds):
  - `make package-prep-deb package-prep-rpm`
  - Artifacts appear under `build/`.

## Security
- Never commit secrets or environment-specific credentials.
- Prefer testing changes in a VM or container.
- When reporting a potential security issue, open an issue with minimal details and request a maintainer contact for follow‑up.

## Credit
- GitHub records authorship for commits and PRs.
- Use `Co-authored-by:` trailers in commit messages to credit collaborators.
- We summarize notable contributions in release notes.

## Code of Conduct
- Be respectful and constructive. Focus feedback on code and outcomes.

Thanks again for contributing!

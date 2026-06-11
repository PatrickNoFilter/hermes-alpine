# Changelog

All notable changes to hermes-alpine will be documented in this file.

## [Unreleased]

### Added

- Ecosystem integration layer: `install-skills.sh`, `install-plugins.sh`,
  `configure-mcp.py`, `verify-integration.sh`
- `Makefile` with full lifecycle targets (install, verify, bootstrap, …)
- GitHub CI workflow (shellcheck, lint, Docker build)
- Issue templates (bug report, feature request, skill request)
- PR template
- `CONTRIBUTING.md` with contributor workflow and code style guide
- Repo-specific `AGENTS.md` and `ARCHITECTURE.md`

### Changed

- `README.md` rewritten with accurate skill counts (129 total, 19 categories,
  22 standalone) and full ecosystem documentation
- `setup-ecosystem.sh` now calls ecosystem integration scripts after
  Hermes Agent installation
- `update-external.sh` refactored to use `$HOME` instead of hardcoded `/root/`
- `CHANGELOG.md` now tracks hermes-alpine releases (was Hermes WebUI changelog)

### Fixed

- `install-skills.sh`: `find` now uses `-L` to follow symlinks; subshell
  variable counting fixed
- `configure-mcp.py`: `--force` mode preserves server name lines with correct
  indentation; idempotency improved
- `verify-integration.sh`: uses `find -L` for symlink-following counts

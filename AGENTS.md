# AGENTS.md — Agent instructions for hermes-alpine

This file is the shared entry point for AI assistants working in this
repository. Keep it project-specific and safe to publish.

## Read first

Before making changes, read:

1. `README.md` — overview, architecture, counts, quick start
2. `CONTRIBUTING.md` — contributor workflow, PR expectations
3. `ARCHITECTURE.md` — design decisions, file inventory, constraints

## Project overview

`hermes-alpine` packages the Hermes Agent ecosystem for Alpine Linux (and other
distros). It provides:

- **129 skills** organized under 19 categories + 22 standalone skills
- **2 plugins** (hermes-lcm, rtk-rewrite)
- **5 MCP server** configurations
- **One-shot installer** (`setup-ecosystem.sh`) that detects the distro and
  installs everything

Key constraint: this repo ships what users install. Every script should work
on Alpine Linux (apk), Debian/Ubuntu (apt), Fedora (dnf), and Arch (pacman).

## Conventions

- Skills live in `skills/<category>/<name>/SKILL.md` or `skills/<name>/SKILL.md`
  for standalone skills. The install-skills.sh script symlinks them to
  `~/.hermes/skills/` preserving the category structure.
- Plugins live in `plugins/<name>/` with a `plugin.yaml` manifest and
  `__init__.py`. install-plugins.sh symlinks them to `~/.hermes/plugins/`.
- MCP server definitions go in `config.yaml.example` (the canonical source)
  and are merged into the user's `~/.hermes/config.yaml` by `configure-mcp.py`.
- Shell scripts must work with both bash and sh (Alpine uses BusyBox ash).
- Python scripts target Python 3.11+ (no walrus operator or 3.12-only features
  unless a version guard exists).

## When adding new content

- **Adding a skill**: Add `skills/<category>/<name>/SKILL.md` following the
  Hermes Agent skill format (YAML frontmatter with name, description, tools,
  then markdown body). Update the skill count in README.md if needed.
- **Adding a plugin**: Add `plugins/<name>/` with `plugin.yaml` and
  `__init__.py`. Update README.md plugin reference.
- **Adding an MCP server**: Add the server config block below the
  `mcp_servers:` key in `config.yaml.example`. Add it to
  `ECOSYSTEM_MCP_SERVERS` in `scripts/configure-mcp.py`. Update README.md
  MCP server table.
- **Adding a dependency**: Update `package.json`, `requirements.txt`, or
  `requirements-mcp.txt` as appropriate. Update `setup-ecosystem.sh` if the
  new dep needs installation steps.

## Testing before commit

```sh
make verify                  # All checks must pass
bash scripts/install-skills.sh --dry-run   # Verify skill links
bash scripts/install-plugins.sh --dry-run  # Verify plugin links
python3 scripts/configure-mcp.py --dry-run  # Verify MCP merge
```

## Reporting changes

- Keep one logical change per PR
- Update `CHANGELOG.md` for user-visible changes (new skills, scripts, fixes)
- Never commit `config.yaml`, `.env`, or files with live credentials

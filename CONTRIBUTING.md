# Contributing to hermes-alpine

Thanks for your interest! This document covers the contributor workflow and
expectations.

## Quick start

```sh
git clone https://github.com/PatrickNoFilter/hermes-alpine.git
cd hermes-alpine
make verify
```

## Reporting issues

Use one of the issue templates:

- **Bug report** — something doesn't work on your distro
- **Feature request** — idea for a new capability
- **Skill request** — propose adding a new Hermes skill to the repo

Include:
- Your distro and version (Alpine 3.21, Debian 12, etc.)
- The exact command you ran and its output
- For setup bugs: paste the full terminal output (use `<details>` in the issue)

## Submitting changes

### Branching

```sh
git checkout -b fix/description   # bug fix
git checkout -b feat/description  # new feature
git checkout -b skill/name        # new skill
git checkout -b docs/description  # documentation
```

### Before opening a PR

```sh
make verify                              # Must pass with 0 warnings
bash scripts/install-skills.sh --dry-run # Check skill links
bash scripts/install-plugins.sh --dry-run# Check plugin links
python3 scripts/configure-mcp.py --dry-run # Check MCP merge
shellcheck scripts/*.sh                  # Lint shell scripts
ruff check scripts/*.py                  # Lint Python scripts
```

### PR requirements

1. One logical change per PR. Split unrelated changes.
2. Update `README.md` if adding skills, plugins, or MCP servers.
3. Update skill counts in README if adding/removing skills.
4. Update `CHANGELOG.md` for user-visible changes.
5. PR template must be filled out completely.
6. CI must pass (lint, validation, config checks).

## Adding skills

1. Create `skills/<category>/<name>/SKILL.md` (or `skills/<name>/SKILL.md`
   for standalone skills without a category).
2. Follow the Hermes Agent skill format: YAML frontmatter with `name`,
   `description`, optional `toolsets`, then markdown body.
3. Run `bash scripts/install-skills.sh --dry-run` to verify it's picked up.
4. Update the skill count in `README.md` if this changes the total.
5. Update the category table in `README.md` if adding a new category.
6. Commit with message: `skill: add <name> (<category>)`

## Adding plugins

1. Create `plugins/<name>/` with:
   - `plugin.yaml` — Hermes plugin manifest (name, version, description)
   - `__init__.py` — plugin entry point with hook functions
2. The plugin entry point can define:
   - `on_load()` — called when plugin is loaded
   - `pre_tool_call(tool_name, kwargs)` — hook before tool exec
   - `post_tool_call(tool_name, kwargs, result)` — hook after tool exec
3. Run `bash scripts/install-plugins.sh --dry-run` to verify.
4. Update the plugin reference section in `README.md`.
5. Commit with message: `plugin: add <name>`

## Adding MCP servers

1. Add the server config block under `mcp_servers:` in `config.yaml.example`.
2. Add the server name to the `ECOSYSTEM_MCP_SERVERS` set in
   `scripts/configure-mcp.py`.
3. If the server needs a wrapper script (bash/node/python), add it to
   `scripts/` and update `notion-mcp.sh` or `slm-mcp.sh` as a pattern.
4. Update the MCP server table in `README.md`.
5. Run `python3 scripts/configure-mcp.py --dry-run` to verify merge.
6. Commit with message: `mcp: add <name> server`

## Code style

### Shell scripts

- Target POSIX sh (ash on Alpine). Avoid bashisms:
  - Use `[ ]` not `[[ ]]`
  - Use `=` not `==` for string comparison
  - Use `$(...)` not backticks
  - Use `printf` for formatted output
  - Use `read -r` for reading lines
  - No arrays (`${arr[@]}`)
  - No `<<<` heredocs
- Use `set -e` for fatal errors, `|| true` for non-fatal
- Prefer `--dry-run` support in all destructive scripts
- Use `$HOME` over `~` for portability

### Python scripts

- Target Python 3.11+ (no 3.12-only features like `itertools.batched`)
- Use `pathlib.Path` over `os.path`
- Use `argparse` for CLI arguments
- Include `--dry-run` flag for write operations
- Prefer stdlib over third-party packages

## Testing

- Run `make verify` after any change — it checks all 9 integration points
- For installer changes, test on Alpine (apk), Debian/Ubuntu (apt), and
  Fedora (dnf) if possible
- For MCP config changes, verify both `--dry-run` and `--force` modes
- For skill/plugin changes, verify dry-run outputs show the expected names

## Getting help

Open a GitHub issue with the question label, or reach out via the
[hermes-alpine repository](https://github.com/PatrickNoFilter/hermes-alpine).

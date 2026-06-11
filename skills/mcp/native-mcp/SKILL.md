---
name: native-mcp
description: "MCP client: connect servers, register tools (stdio/HTTP)."
version: 1.0.0
author: Hermes Agent
license: MIT
platforms: [linux, macos, windows]
metadata:
  hermes:
    tags: [MCP, Tools, Integrations]
    related_skills: [mcporter]
---

# Native MCP Client

Hermes Agent has a built-in MCP client that connects to MCP servers at startup, discovers their tools, and makes them available as first-class tools the agent can call directly. No bridge CLI needed -- tools from MCP servers appear alongside built-in tools like `terminal`, `read_file`, etc.

## When to Use

Use this whenever you want to:
- Connect to MCP servers and use their tools from within Hermes Agent
- Add external capabilities (filesystem access, GitHub, databases, APIs) via MCP
- Run local stdio-based MCP servers (npx, uvx, or any command)
- Connect to remote HTTP/StreamableHTTP MCP servers
- Have MCP tools auto-discovered and available in every conversation

For ad-hoc, one-off MCP tool calls from the terminal without configuring anything, see the `mcporter` skill instead.

## Prerequisites

- **mcp Python package** -- optional dependency; install with `pip install mcp`. If not installed, MCP support is silently disabled.
- **Node.js** -- required for `npx`-based MCP servers (most community servers)
- **uv** -- required for `uvx`-based MCP servers (Python-based servers)

Install the MCP SDK:

```bash
pip install mcp
# or, if using uv:
uv pip install mcp
```

## Quick Start

### Option A: Interactive CLI

```bash
hermes mcp add NAME --command CMD --args "arg1 arg2"
```

**Pitfall:** `hermes mcp add` runs a connection test interactively and may prompt `Save config anyway (y/N)`. If the server needs time to start or the test times out, answer `y` to save regardless — you can verify with `hermes mcp test NAME` afterward.

### Option B: Manual config.yaml edit (more reliable)

Add MCP servers to `~/.hermes/config.yaml` under the `mcp_servers` key:

```yaml
mcp_servers:
  time:
    command: "uvx"
    args: ["mcp-server-time"]
```

### Verify after adding

```bash
hermes mcp list          # show all servers + status
hermes mcp test NAME     # test connection + discover tools
```

Restart Hermes Agent. On startup it will:
1. Connect to the server
2. Discover available tools
3. Register them with the prefix `mcp_time_*`
4. Inject them into all platform toolsets

You can then use the tools naturally -- just ask the agent to get the current time.

## Configuration Reference

Each entry under `mcp_servers` is a server name mapped to its config. There are two transport types: **stdio** (command-based) and **HTTP** (url-based).

### Stdio Transport (command + args)

```yaml
mcp_servers:
  server_name:
    command: "npx"             # (required) executable to run
    args: ["-y", "pkg-name"]   # (optional) command arguments, default: []
    env:                       # (optional) environment variables for the subprocess
      SOME_API_KEY: "value"
    timeout: 120               # (optional) per-tool-call timeout in seconds, default: 120
    connect_timeout: 60        # (optional) initial connection timeout in seconds, default: 60
```

### HTTP Transport (url)

```yaml
mcp_servers:
  server_name:
    url: "https://my-server.example.com/mcp"   # (required) server URL
    headers:                                     # (optional) HTTP headers
      Authorization: "Bearer sk-..."
    timeout: 180               # (optional) per-tool-call timeout in seconds, default: 120
    connect_timeout: 60        # (optional) initial connection timeout in seconds, default: 60
```

### All Config Options

| Option            | Type   | Default | Description                                       |
|-------------------|--------|---------|---------------------------------------------------|
| `command`         | string | --      | Executable to run (stdio transport, required)     |
| `args`            | list   | `[]`    | Arguments passed to the command                   |
| `env`             | dict   | `{}`    | Extra environment variables for the subprocess    |
| `url`             | string | --      | Server URL (HTTP transport, required)             |
| `headers`         | dict   | `{}`    | HTTP headers sent with every request              |
| `timeout`         | int    | `120`   | Per-tool-call timeout in seconds                  |
| `connect_timeout` | int    | `60`    | Timeout for initial connection and discovery      |

Note: A server config must have either `command` (stdio) or `url` (HTTP), not both.

## How It Works

### Startup Discovery

When Hermes Agent starts, `discover_mcp_tools()` is called during tool initialization:

1. Reads `mcp_servers` from `~/.hermes/config.yaml`
2. For each server, spawns a connection in a dedicated background event loop
3. Initializes the MCP session and calls `list_tools()` to discover available tools
4. Registers each tool in the Hermes tool registry

### Tool Naming Convention

MCP tools are registered with the naming pattern:

```
mcp_{server_name}_{tool_name}
```

Hyphens and dots in names are replaced with underscores for LLM API compatibility.

Examples:
- Server `filesystem`, tool `read_file` → `mcp_filesystem_read_file`
- Server `github`, tool `list-issues` → `mcp_github_list_issues`
- Server `my-api`, tool `fetch.data` → `mcp_my_api_fetch_data`

### Auto-Injection

After discovery, MCP tools are automatically injected into all `hermes-*` platform toolsets (CLI, Discord, Telegram, etc.). This means MCP tools are available in every conversation without any additional configuration.

### Connection Lifecycle

- Each server runs as a long-lived asyncio Task in a background daemon thread
- Connections persist for the lifetime of the agent process
- If a connection drops, automatic reconnection with exponential backoff kicks in (up to 5 retries, max 60s backoff)
- On agent shutdown, all connections are gracefully closed

### Idempotency

`discover_mcp_tools()` is idempotent -- calling it multiple times only connects to servers that aren't already connected. Failed servers are retried on subsequent calls.

## Transport Types

### Stdio Transport

The most common transport. Hermes launches the MCP server as a subprocess and communicates over stdin/stdout.

```yaml
mcp_servers:
  filesystem:
    command: "npx"
    args: ["-y", "@modelcontextprotocol/server-filesystem", "/home/user/projects"]
```

The subprocess inherits a **filtered** environment (see Security section below) plus any variables you specify in `env`.

### HTTP / StreamableHTTP Transport

For remote or shared MCP servers. Requires the `mcp` package to include HTTP client support (`mcp.client.streamable_http`).

```yaml
mcp_servers:
  remote_api:
    url: "https://mcp.example.com/mcp"
    headers:
      Authorization: "Bearer sk-..."
```

If HTTP support is not available in your installed `mcp` version, the server will fail with an ImportError and other servers will continue normally.

## Security

### Environment Variable Filtering

For stdio servers, Hermes does NOT pass your full shell environment to MCP subprocesses. Only safe baseline variables are inherited:

- `PATH`, `HOME`, `USER`, `LANG`, `LC_ALL`, `TERM`, `SHELL`, `TMPDIR`
- Any `XDG_*` variables

All other environment variables (API keys, tokens, secrets) are excluded unless you explicitly add them via the `env` config key. This prevents accidental credential leakage to untrusted MCP servers.

```yaml
mcp_servers:
  github:
    command: "npx"
    args: ["-y", "@modelcontextprotocol/server-github"]
    env:
      # Only this token is passed to the subprocess
      GITHUB_PERSONAL_ACCESS_TOKEN: "ghp_..."
```

### Credential Stripping in Error Messages

If an MCP tool call fails, any credential-like patterns in the error message are automatically redacted before being shown to the LLM. This covers:

- GitHub PATs (`ghp_...`)
- OpenAI-style keys (`sk-...`)
- Bearer tokens
- Generic `token=`, `key=`, `API_KEY=`, `password=`, `secret=` patterns

## Troubleshooting

### "MCP SDK not available -- skipping MCP tool discovery"

The `mcp` Python package is not installed. Install it:

```bash
pip install mcp
```

### "No MCP servers configured"

No `mcp_servers` key in `~/.hermes/config.yaml`, or it's empty. Add at least one server.

### "Failed to connect to MCP server 'X'"

Common causes:
- **Command not found**: The `command` binary isn't on PATH. Ensure `npx`, `uvx`, or the relevant command is installed.
- **npm global binary not on PATH**: On Hermes's bundled Node.js, `npm i -g` installs to `/root/.hermes/node/lib/node_modules/...` but the binary may not land on PATH. Find it with `find /root/.hermes/node -name "BINARY_NAME" -type f` and symlink to `/usr/local/bin/`. Example:
  ```bash
  ln -sf /root/.hermes/node/lib/node_modules/PKG/node_modules/PKG-PLATFORM/bin/NAME /usr/local/bin/NAME
  ```
- **Package not found**: For npx servers, the npm package may not exist or may need `-y` in args to auto-install.
- **Timeout**: The server took too long to start. Increase `connect_timeout`.
- **Port conflict**: For HTTP servers, the URL may be unreachable.

### "MCP server 'X' requires HTTP transport but mcp.client.streamable_http is not available"

Your `mcp` package version doesn't include HTTP client support. Upgrade:

```bash
pip install --upgrade mcp
```

### Tools not appearing

- Check that the server is listed under `mcp_servers` (not `mcp` or `servers`)
- Ensure the YAML indentation is correct
- Look at Hermes Agent startup logs for connection messages
- Tool names are prefixed with `mcp_{server}_{tool}` -- look for that pattern

### Connection keeps dropping

The client retries up to 5 times with exponential backoff (1s, 2s, 4s, 8s, 16s, capped at 60s). If the server is fundamentally unreachable, it gives up after 5 attempts. Check the server process and network connectivity.

### Persistent 401 / "API token is invalid" from MCP tools

MCP connections are established once per agent process and persist for the session. A stale connection keeps using env vars from when it was first launched — **restart the agent** after fixing the config.

Before restarting, diagnose in this order:

1. **Verify the token directly** against the provider's API (e.g. curl):
   ```bash
   curl -s -o /dev/null -w "%{http_code}" \
     -H "Authorization: Bearer $TOKEN" \
     -H "Notion-Version: 2022-06-28" \
     "https://api.notion.com/v1/users/me"
   ```
2. **Check for token name mismatch**: grep the server binary for which env var it reads:
   ```bash
   grep -o 'NOTI...' /path/to/server/bin/cli.mjs | sort -u
   ```
   Your `.env` and wrapper must export the **exact same variable name** the server reads.
3. **Check the shell Hermes uses to launch the server**: If you used `hermes mcp add`, it defaults to `sh` as the command. On Debian/Ubuntu, `/bin/sh` → `dash`, which does not support `source` (bashism). If your wrapper script uses `source`, it fails silently. Fix: change `source` to `.` in the wrapper, or re-add the server with `--command bash`.
4. **If using a wrapper script** to map env vars (see "Wrapper Script Pattern" below), verify the script actually expands the variable and doesn't hard-code a literal string.
5. **Check that `.env` has the correct variable** and it's being sourced by the wrapper.

## Wrapper Script Pattern

When a stdio MCP server reads an env var name that doesn't match what your `.env` file uses, write a thin wrapper script that sources `.env` and maps the variable.

Example (`~/.hermes/scripts/notion-mcp.sh`) — the server reads `NOTION_TOKEN` but `.env` has `NOTION_API_KEY`:

```bash
#!/bin/bash
set -a
. "$HOME/.hermes/.env" 2>/dev/null || true
set +a
export NOTION_TOKEN="${NOTION_TOKEN:-${NOTION_API_KEY}}"
exec node /path/to/server/bin/cli.mjs "$@"
```

**Pitfall — Shell compatibility:** Use `.` (POSIX dot command) instead of `source` (a bashism). Hermes may run the MCP server command via `sh` (e.g. `hermes mcp add` defaults to `sh` as the interpreter). On Debian/Ubuntu, `/bin/sh` → **dash**, which does not understand `source`. A silent `source` failure (masked by `|| true`) leaves env vars unset → 401. Using `.` works on bash, dash, and POSIX sh alike.

**Pitfall — Literal string vs variable expansion:** If you forget the `$` and write `export NOTION_TOKEN="NOTION_API_KEY"` (literal string instead of variable expansion), the server gets the literal text `NOTION_API_KEY` as the token → 401. Always use `${VAR_NAME}` with braces.

**Pitfall — write_file mangles ${VAR} to literal asterisks:** When writing wrapper scripts with `write_file`, any `${VARIABLE}` pattern in the content is automatically converted to a literal `***` string on disk. The file ends up with `export NOTION_TOKEN="***"` (three literal asterisks) instead of the intended `export NOTION_TOKEN="${NOTION_API_KEY}"`. After the initial `write_file`, use `patch` to restore the variable expansion syntax. Alternatively, write the script as a Python file to avoid the masking entirely. This does NOT affect `skill_manage(action='write_file')` — only the `write_file` tool.

**Alternative:** You can also set the token directly in `config.yaml` under `env` instead of using a wrapper:
```yaml
mcp_servers:
  notion:
    command: npx
    args: ["-y", "@notionhq/notion-mcp-server"]
    env:
      NOTION_TOKEN: "${NOTION_API_KEY}"  # substituted from parent env
```

### MCP tools returning 401 after config fix

MCP connections are **not hot-reloaded**. After editing a wrapper script or `.env`, you **must restart the agent** (`exit` then relaunch `hermes`). The tools from the old connection remain in-memory with the old env for the rest of the session.

## Examples

### Time Server (uvx)

```yaml
mcp_servers:
  time:
    command: "uvx"
    args: ["mcp-server-time"]
```

Registers tools like `mcp_time_get_current_time`.

### Filesystem Server (npx)

```yaml
mcp_servers:
  filesystem:
    command: "npx"
    args: ["-y", "@modelcontextprotocol/server-filesystem", "/home/user/documents"]
    timeout: 30
```

Registers tools like `mcp_filesystem_read_file`, `mcp_filesystem_write_file`, `mcp_filesystem_list_directory`.

### GitHub Server with Authentication

```yaml
mcp_servers:
  github:
    command: "npx"
    args: ["-y", "@modelcontextprotocol/server-github"]
    env:
      GITHUB_PERSONAL_ACCESS_TOKEN: "ghp_xxxxxxxxxxxxxxxxxxxx"
    timeout: 60
```

Registers tools like `mcp_github_list_issues`, `mcp_github_create_pull_request`, etc.

### Remote HTTP Server

```yaml
mcp_servers:
  company_api:
    url: "https://mcp.mycompany.com/v1/mcp"
    headers:
      Authorization: "Bearer sk-xxxxxxxxxxxxxxxxxxxx"
      X-Team-Id: "engineering"
    timeout: 180
    connect_timeout: 30
```

### Multiple Servers

```yaml
mcp_servers:
  time:
    command: "uvx"
    args: ["mcp-server-time"]

  filesystem:
    command: "npx"
    args: ["-y", "@modelcontextprotocol/server-filesystem", "/tmp"]

  github:
    command: "npx"
    args: ["-y", "@modelcontextprotocol/server-github"]
    env:
      GITHUB_PERSONAL_ACCESS_TOKEN: "ghp_xxxxxxxxxxxxxxxxxxxx"

  company_api:
    url: "https://mcp.internal.company.com/mcp"
    headers:
      Authorization: "Bearer sk-xxxxxxxxxxxxxxxxxxxx"
    timeout: 300
```

All tools from all servers are registered and available simultaneously. Each server's tools are prefixed with its name to avoid collisions.

## Sampling (Server-Initiated LLM Requests)

Hermes supports MCP's `sampling/createMessage` capability — MCP servers can request LLM completions through the agent during tool execution. This enables agent-in-the-loop workflows (data analysis, content generation, decision-making).

Sampling is **enabled by default**. Configure per server:

```yaml
mcp_servers:
  my_server:
    command: "npx"
    args: ["-y", "my-mcp-server"]
    sampling:
      enabled: true           # default: true
      model: "gemini-3-flash" # model override (optional)
      max_tokens_cap: 4096    # max tokens per request
      timeout: 30             # LLM call timeout (seconds)
      max_rpm: 10             # max requests per minute
      allowed_models: []      # model whitelist (empty = all)
      max_tool_rounds: 5      # tool loop limit (0 = disable)
      log_level: "info"       # audit verbosity
```

Servers can also include `tools` in sampling requests for multi-turn tool-augmented workflows. The `max_tool_rounds` config prevents infinite tool loops. Per-server audit metrics (requests, errors, tokens, tool use count) are tracked via `get_mcp_status()`.

Disable sampling for untrusted servers with `sampling: { enabled: false }`.

## Known MCP Servers

See `references/` for server-specific installation guides and quirks:
- `references/codegraph.md` — CodeGraph semantic code intelligence (install, index, troubleshooting)
- `references/context-mode.md` — Context Mode context window optimization (think-in-code sandbox, auto-index, search)
- `references/notion.md` — Notion MCP server: wrapper script, token mapping, pages

### Token Optimization Stack (ARM64)

On ARM64 (Termux+PRoot), these tools layer together for maximum context savings:

| Layer | Tool | Mechanism |
|-------|------|-----------|
| Eliminate tool calls | **CodeGraph** (MCP) | Graph queries replace file scanning |
| Filter CLI output | **RTK** (Hermes plugin) | Auto-rewrites terminal commands through `rtk rewrite` pre_tool_call hook |
| Sandbox & summarize | **Context Mode** (MCP) | Think-in-code: derived answers, not raw bytes |
| Compress remaining text | Headroom | Not viable on ARM64 (no pre-built wheels, heavy Rust compilation) |

All three MCP-compatible tools (CodeGraph, Context Mode, RTK's Hermes plugin) work simultaneously — they operate at different layers and don't conflict.

## Notes

- MCP tools are called synchronously from the agent's perspective but run asynchronously on a dedicated background event loop
- Tool results are returned as JSON with either `{"result": "..."}` or `{"error": "..."}`
- The native MCP client is independent of `mcporter` -- you can use both simultaneously
- Server connections are persistent and shared across all conversations in the same agent process
- Adding or removing servers requires restarting the agent (no hot-reload currently)

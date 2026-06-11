# External Components Inventory

Last audited: 2026-05-29

## MCP Servers

| Name | Transport | Install Method | Update Method |
|---|---|---|---|
| context-mode | `npx -y context-mode` | npx (auto) | Auto-updates each run |
| agentmemory | `npx -y @agentmemory/mcp` | npx (auto) | Auto-updates each run |
| codegraph | `codegraph serve --mcp` | npm global `@colbymchenry/codegraph` | `npm -g install @colbymchenry/codegraph@latest` |

## Standalone Binaries

| Name | Path | Install Source | Update Method |
|---|---|---|---|
| rtk | `~/.local/bin/rtk` | GitHub release binary (`rtk-ai/rtk`) | Re-download from GitHub releases |

Current versions (2026-05-29):
- rtk: v0.42.0 (latest)
- codegraph: 0.9.7 (latest)

## Plugins

| Name | Path | Type | Notes |
|---|---|---|---|
| rtk-rewrite | `~/.hermes/plugins/rtk-rewrite/` | Local plugin (v0.1.0) | Bridges Hermes `pre_tool_call` hook to `rtk rewrite`. Requires rtk binary in PATH. |

## Local Skills

| Name | Category | Notes |
|---|---|---|
| external-project-setup | devops | Local skill for evaluating/setting up external open-source projects |

## npm Global Packages (Hermes-scoped)

Hermes uses its own npm prefix at `~/.hermes/node/lib/` (not system npm).

```
npm -g --prefix ~/.hermes/node ls
```

Known packages:
- `@colbymchenry/codegraph` — installed at `~/.hermes/node/lib/node_modules/@colbymchenry/codegraph`
  - Symlinked to `/usr/local/bin/codegraph`

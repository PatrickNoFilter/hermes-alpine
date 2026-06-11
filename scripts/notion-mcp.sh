#!/bin/bash
set -a
. /root/.hermes/.env 2>/dev/null || true
set +a
# MCP server reads NOTION_TOKEN — map NOTION_API_KEY to it
export NOTION_TOKEN="${NOTION_API_KEY}"
exec node /tmp/node_modules/@notionhq/notion-mcp-server/bin/cli.mjs "$@"

#!/bin/sh
# Wrapper for @notionhq/notion-mcp-server
# Reads NOTION_API_KEY from .env and passes it as NOTION_TOKEN

ENV_FILE="${HOME}/.hermes/.env"

if [ -f "$ENV_FILE" ]; then
    eval "$(grep '^NOTION_API_KEY=' "$ENV_FILE" | sed 's/^export //')"
fi

export NOTION_TOKEN="${NOTION_TOKEN:-$NOTION_API_KEY}"

exec /usr/bin/env node /usr/local/lib/node_modules/@notionhq/notion-mcp-server/dist/index.js "$@"

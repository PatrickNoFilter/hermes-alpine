#!/bin/sh
# Wrapper for firecrawl-mcp MCP server
# Sources FIRECRAWL_API_KEY from .env

ENV_FILE="${HOME}/.hermes/.env"

if [ -f "$ENV_FILE" ]; then
    eval "$(grep '^FIRECRAWL_API_KEY=' "$ENV_FILE" | sed 's/^export //')"
fi

exec /usr/bin/env npx -y firecrawl-mcp "$@"

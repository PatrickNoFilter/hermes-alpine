#!/bin/sh
# Wrapper for superlocalmemory MCP server
# SuperLocalMemory V3 - Python-based MCP server

exec /usr/bin/env node /usr/local/lib/node_modules/superlocalmemory/bin/slm-npm "$@"

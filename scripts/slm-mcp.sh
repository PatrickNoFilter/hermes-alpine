#!/bin/bash
# SuperLocalMemory MCP server wrapper for Hermes
export PATH="/root/.hermes/node/bin:$PATH"
SLM_PKG=/root/.hermes/node/lib/node_modules/superlocalmemory
PYTHONPATH="$SLM_PKG/src" exec /root/.hermes/slm-env/bin/python -m superlocalmemory.cli.main mcp

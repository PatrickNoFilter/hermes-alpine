#!/usr/bin/env bash
# onex-search.sh — Search and install security tools via onex
# Usage: onex-search.sh <search|install|list> [tool_name]

set -e

ONEX_BIN=$(command -v onex 2>/dev/null || echo "")

usage() {
    echo "Usage: $0 <search|install|list> [tool_name]"
    echo ""
    echo "Commands:"
    echo "  search <query>   Search for a tool by name"
    echo "  install <tool>   Install a tool"
    echo "  list             List all available tools"
    echo ""
    echo "Examples:"
    echo "  $0 search nmap"
    echo "  $0 install sqlmap"
    echo "  $0 list"
}

if [ $# -lt 1 ]; then
    usage
    exit 1
fi

# If onex is not installed, clone and install it
if [ -z "$ONEX_BIN" ]; then
    echo "[*] onex not found. Installing..."
    ONEX_DIR="$HOME/onex"
    if [ ! -d "$ONEX_DIR" ]; then
        git clone https://github.com/jackind424/onex.git "$ONEX_DIR"
    fi
    chmod +x "$ONEX_DIR/install"
    cd "$ONEX_DIR" && sh install
    ONEX_BIN="$ONEX_DIR/onex"
fi

case "$1" in
    search)
        if [ -z "$2" ]; then
            echo "Error: provide a search term"
            usage
            exit 1
        fi
        "$ONEX_BIN" search "$2"
        ;;
    install)
        if [ -z "$2" ]; then
            echo "Error: provide a tool name"
            usage
            exit 1
        fi
        "$ONEX_BIN" install "$2"
        ;;
    list)
        "$ONEX_BIN" list -a
        ;;
    *)
        usage
        exit 1
        ;;
esac

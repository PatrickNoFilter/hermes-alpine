#!/bin/bash
# ============================================================================
# install-plugins.sh — Install Hermes plugins from the repo to HERMES_HOME
# ============================================================================
# Symlinks every plugin directory from plugins/ into ~/.hermes/plugins/,
# making their tools and hooks available to the Hermes Agent.
#
# Usage:
#   ./scripts/install-plugins.sh             # default: ~/.hermes/plugins/
#   HERMES_HOME=/custom/path ./scripts/install-plugins.sh
#   ./scripts/install-plugins.sh --copy       # copy instead of symlink
#   ./scripts/install-plugins.sh --dry-run    # show what would happen
# ============================================================================
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
HERMES_HOME="${HERMES_HOME:-${HOME}/.hermes}"
HERMES_PLUGINS_DIR="${HERMES_HOME}/plugins"
PLUGIN_SOURCE_DIR="${REPO_ROOT}/plugins"

MODE="symlink"
DRY_RUN=false

for arg in "$@"; do
    case "$arg" in
        --copy)    MODE="copy"   ;;
        --symlink) MODE="symlink" ;;
        --dry-run) DRY_RUN=true   ;;
    esac
done

if [ ! -d "$PLUGIN_SOURCE_DIR" ]; then
    echo "[install-plugins] ERROR: plugin source directory not found: $PLUGIN_SOURCE_DIR"
    exit 1
fi

mkdir -p "$HERMES_PLUGINS_DIR"

INSTALLED=0
SKIPPED=0

echo "[install-plugins] Installing plugins to $HERMES_PLUGINS_DIR"
echo "[install-plugins] Mode: $MODE"

# Iterate over plugin directories (name/plugin.yaml)
for plugin_yaml in "$PLUGIN_SOURCE_DIR"/*/plugin.yaml; do
    [ -f "$plugin_yaml" ] || continue

    plugin_dir="$(dirname "$plugin_yaml")"
    plugin_name="$(basename "$plugin_dir")"
    target_dir="$HERMES_PLUGINS_DIR/$plugin_name"

    # Read plugin metadata
    plugin_version="$(grep -E '^version:' "$plugin_yaml" | head -1 | sed 's/^version:[[:space:]]*//' | tr -d '"'"'"  || echo 'unknown')"
    plugin_desc="$(grep -E '^description:' "$plugin_yaml" | head -1 | sed 's/^description:[[:space:]]*//' | tr -d '"'"'"  || echo '')"

    if [ "$DRY_RUN" = true ]; then
        echo "  [DRY-RUN] $plugin_name (v$plugin_version) — $plugin_desc"
        continue
    fi

    # Check if already installed and up to date
    if [ -d "$target_dir" ] && [ "$MODE" = "symlink" ] && [ -L "$target_dir" ]; then
        existing_target="$(readlink "$target_dir")"
        if [ "$existing_target" = "$plugin_dir" ]; then
            echo "  ✓ $plugin_name (already linked)"
            SKIPPED=$((SKIPPED + 1))
            continue
        fi
    fi

    if [ -d "$target_dir" ] && [ "$MODE" = "symlink" ] && [ ! -L "$target_dir" ]; then
        echo "  ! $plugin_name — replacing real directory with symlink"
        rm -rf "$target_dir"
    fi

    [ -d "$target_dir" ] && rm -rf "$target_dir"
    rm -f "$target_dir" 2>/dev/null || true

    mkdir -p "$HERMES_PLUGINS_DIR"

    if [ "$MODE" = "copy" ]; then
        cp -r "$plugin_dir" "$target_dir"
        echo "  + $plugin_name (copied)"
    else
        ln -sf "$plugin_dir" "$target_dir"
        echo "  + $plugin_name (symlinked)"
    fi
    INSTALLED=$((INSTALLED + 1))
done

if [ "$DRY_RUN" = true ]; then
    echo "[install-plugins] DRY-RUN complete — no changes made."
    exit 0
fi

echo ""
echo "[install-plugins] Complete!"
echo "  Plugins installed:  ${INSTALLED:-?}"
echo "  Plugins up-to-date: ${SKIPPED:-?}"

# Verify with hermes plugins list if available
if command -v hermes &>/dev/null && [ "$INSTALLED" -gt 0 ]; then
    echo "[install-plugins] Verifying with 'hermes plugins list'..."
    hermes plugins list 2>/dev/null | head -10 || true
fi

# Write marker
HERMES_VERSION_FILE="${HERMES_PLUGINS_DIR}/.ecosystem-version"
echo "plugin_count=$INSTALLED" > "$HERMES_VERSION_FILE"
echo "installed_at=$(date -u +%Y-%m-%dT%H:%M:%SZ)" >> "$HERMES_VERSION_FILE"
echo "source=hermes-alpine" >> "$HERMES_VERSION_FILE"

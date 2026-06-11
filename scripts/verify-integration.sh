#!/bin/bash
# ============================================================================
# verify-integration.sh — Verify the Hermes ecosystem is properly integrated
# ============================================================================
# Checks that skills, plugins, MCP servers, and scripts are all correctly
# wired into the Hermes Agent installation.
#
# Usage:
#   ./scripts/verify-integration.sh           # verify everything
#   ./scripts/verify-integration.sh --verbose # detailed output
#   ./scripts/verify-integration.sh --skills  # only check skills
#   ./scripts/verify-integration.sh --plugins # only check plugins
#   ./scripts/verify-integration.sh --mcp     # only check MCP servers
# ============================================================================
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
HERMES_HOME="${HERMES_HOME:-${HOME}/.hermes}"

VERBOSE=false
CHECK_SKILLS=true
CHECK_PLUGINS=true
CHECK_MCP=true

# Stats
PASS=0
FAIL=0
WARN=0

pass() { PASS=$((PASS + 1)); }
fail() { FAIL=$((FAIL + 1)); echo "  FAIL: $1"; }
warn() { WARN=$((WARN + 1)); echo "  WARN: $1"; }

ok()   { echo "  ✓ $1"; }
info() { echo "  · $1"; }

for arg in "$@"; do
    case "$arg" in
        --verbose) VERBOSE=true ;;
        --skills)  CHECK_PLUGINS=false; CHECK_MCP=false ;;
        --plugins) CHECK_SKILLS=false; CHECK_MCP=false ;;
        --mcp)     CHECK_SKILLS=false; CHECK_PLUGINS=false ;;
    esac
done

echo "============================================"
echo "  Hermes Ecosystem Integration Verification"
echo "============================================"
echo "  Repo root:   $REPO_ROOT"
echo "  Hermes home: $HERMES_HOME"
echo ""

# ============================================================================
# Pre-checks
# ============================================================================
echo "--- Pre-checks ---"

# Check repo structure
if [ ! -d "$REPO_ROOT/skills" ]; then
    fail "Skills directory not found at $REPO_ROOT/skills"
    CHECK_SKILLS=false
fi
if [ ! -d "$REPO_ROOT/plugins" ]; then
    fail "Plugins directory not found at $REPO_ROOT/plugins"
    CHECK_PLUGINS=false
fi

# Check Hermes CLI
HERMES_CLI=""
if command -v hermes &>/dev/null; then
    HERMES_CLI="$(command -v hermes)"
    pass
    info "Hermes CLI found: $HERMES_CLI"
else
    warn "Hermes CLI not in PATH — checking common locations..."
    for candidate in \
        "$HERMES_HOME/bin/hermes" \
        "$HOME/.local/bin/hermes" \
        "$REPO_ROOT/hermes-agent/cli.py" \
        /usr/local/lib/hermes-agent/cli.py; do
        if [ -f "$candidate" ]; then
            HERMES_CLI="$candidate"
            pass
            info "Hermes CLI found: $HERMES_CLI"
            break
        fi
    done
    if [ -z "$HERMES_CLI" ]; then
        warn "Hermes CLI not found — skill/plugin verification will be partial"
    fi
fi

echo ""

# ============================================================================
# Skills Check
# ============================================================================
if [ "$CHECK_SKILLS" = true ]; then
    echo "--- Skills ---"

    SKILL_COUNT_REPO=$(find -L "$REPO_ROOT/skills" -maxdepth 3 -name 'SKILL.md' | wc -l)
    info "Skills in repo: $SKILL_COUNT_REPO"

    if [ -d "$HERMES_HOME/skills" ]; then
        SKILL_COUNT_INSTALLED=$(find -L "$HERMES_HOME/skills" -maxdepth 4 -name 'SKILL.md' | wc -l)
        info "Skills in HERMES_HOME: $SKILL_COUNT_INSTALLED"

        if [ "$SKILL_COUNT_INSTALLED" -ge "$SKILL_COUNT_REPO" ]; then
            pass
            ok "All $SKILL_COUNT_REPO skills are installed in Hermes skills directory"
        else
            MISSING=$((SKILL_COUNT_REPO - SKILL_COUNT_INSTALLED))
            warn "Only $SKILL_COUNT_INSTALLED of $SKILL_COUNT_REPO skills installed ($MISSING missing)"
        fi

        # Spot-check some key skills
        for required in \
            autonomous-ai-agents/hermes-agent \
            devops/hermes-webui \
            mlops; do
            if [ -d "$HERMES_HOME/skills/$required" ] || [ -L "$HERMES_HOME/skills/$required" ]; then
                if [ "$VERBOSE" = true ]; then
                    ok "Required skill '$required' found"
                fi
            else
                warn "Required skill '$required' not found in $HERMES_HOME/skills/"
            fi
        done

        # Check symlink integrity
        LINK_ISSUES=0
        while IFS= read -r -d '' link; do
            if [ ! -e "$link" ]; then
                warn "Broken symlink: $link"
                LINK_ISSUES=$((LINK_ISSUES + 1))
            fi
        done < <(find "$HERMES_HOME/skills" -type l -name 'SKILL.md' -print0 2>/dev/null || true)
        if [ "$LINK_ISSUES" -eq 0 ] && [ "$VERBOSE" = true ]; then
            ok "All skill symlinks intact"
        fi

        # Check .ecosystem-version marker
        if [ -f "$HERMES_HOME/skills/.ecosystem-version" ]; then
            if [ "$VERBOSE" = true ]; then
                info "Ecosystem marker: $(head -1 "$HERMES_HOME/skills/.ecosystem-version")"
            fi
        fi
    else
        warn "Skills directory not found at $HERMES_HOME/skills/ — skills not installed"
        info "Run: ./scripts/install-skills.sh"
    fi

    echo ""
fi

# ============================================================================
# Plugins Check
# ============================================================================
if [ "$CHECK_PLUGINS" = true ]; then
    echo "--- Plugins ---"

    PLUGIN_COUNT_REPO=$(find "$REPO_ROOT/plugins" -maxdepth 2 -name 'plugin.yaml' | wc -l)
    info "Plugins in repo: $PLUGIN_COUNT_REPO"

    if [ -d "$HERMES_HOME/plugins" ]; then
        PLUGIN_COUNT_INSTALLED=$(find -L "$HERMES_HOME/plugins" -maxdepth 2 -name 'plugin.yaml' | wc -l)
        info "Plugins in HERMES_HOME: $PLUGIN_COUNT_INSTALLED"

        if [ "$PLUGIN_COUNT_INSTALLED" -ge "$PLUGIN_COUNT_REPO" ]; then
            pass
            ok "All plugins installed"
        else
            warn "Expected $PLUGIN_COUNT_REPO plugins, found $PLUGIN_COUNT_INSTALLED"
        fi

        # Verify each plugin has functional __init__.py
        for plugin_path in "$HERMES_HOME/plugins"/*/; do
            [ -d "$plugin_path" ] || continue
            pname="$(basename "$plugin_path")"
            py="$plugin_path/__init__.py"
            yaml="$plugin_path/plugin.yaml"
            if [ -f "$py" ] && [ -f "$yaml" ]; then
                if [ "$VERBOSE" = true ]; then
                    ok "Plugin '$pname': __init__.py + plugin.yaml present"
                fi
            else
                if [ ! -f "$py" ]; then
                    warn "Plugin '$pname': missing __init__.py"
                fi
                if [ ! -f "$yaml" ]; then
                    warn "Plugin '$pname': missing plugin.yaml"
                fi
            fi
        done
    else
        warn "Plugins directory not found at $HERMES_HOME/plugins/ — plugins not installed"
        info "Run: ./scripts/install-plugins.sh"
    fi

    echo ""
fi

# ============================================================================
# MCP Check
# ============================================================================
if [ "$CHECK_MCP" = true ]; then
    echo "--- MCP Servers ---"

    CONFIG_PATH="$HERMES_HOME/config.yaml"

    # Check MCP config
    if [ -f "$CONFIG_PATH" ]; then
        if grep -q "mcp_servers:" "$CONFIG_PATH" 2>/dev/null; then
            pass
            ok "MCP servers section found in $CONFIG_PATH"

            # Check each ecosystem MCP server
            for server in codegraph context-mode firecrawl notion superlocalmemory; do
                if grep -q "  $server:" "$CONFIG_PATH" 2>/dev/null; then
                    if [ "$VERBOSE" = true ]; then
                        ok "MCP server '$server' configured"
                    fi
                else
                    warn "Ecosystem MCP server '$server' not found in config"
                    info "  Run: python3 scripts/configure-mcp.py"
                fi
            done
        else
            warn "No mcp_servers section in $CONFIG_PATH"
            info "  Run: python3 scripts/configure-mcp.py"
        fi
    else
        warn "Hermes config not found at $CONFIG_PATH"
        info "  Create from: cp $REPO_ROOT/config.yaml.example $CONFIG_PATH"
    fi

    # Check MCP wrapper scripts are present and executable
    for mcp_script in scripts/notion-mcp.sh scripts/slm-mcp.sh; do
        if [ -f "$REPO_ROOT/$mcp_script" ]; then
            if [ -x "$REPO_ROOT/$mcp_script" ]; then
                if [ "$VERBOSE" = true ]; then
                    ok "MCP wrapper '$mcp_script' is executable"
                fi
            else
                warn "MCP wrapper '$mcp_script' is not executable"
            fi
        else
            warn "MCP wrapper '$mcp_script' missing from repo"
        fi
    done

    # Check npm MCP packages
    if [ -f "$REPO_ROOT/package.json" ]; then
        for pkg in notion-mcp-server superlocalmemory codegraph; do
            if grep -q "\"$pkg\"" "$REPO_ROOT/package.json" 2>/dev/null; then
                if [ "$VERBOSE" = true ]; then
                    ok "MCP npm package '$pkg' declared in package.json"
                fi
            fi
        done
    fi

    echo ""
fi

# ============================================================================
# Scripts Check
# ============================================================================
echo "--- Ecosystem Scripts ---"

for script in \
    scripts/install-skills.sh \
    scripts/install-plugins.sh \
    scripts/configure-mcp.py \
    scripts/verify-integration.sh \
    scripts/update-external.sh; do
    if [ -f "$REPO_ROOT/$script" ]; then
        if [ -x "$REPO_ROOT/$script" ] || [[ "$script" == *.py ]]; then
            pass
            if [ "$VERBOSE" = true ]; then
                ok "Script '$script' present"
            fi
        else
            warn "Script '$script' not executable (chmod +x recommended)"
        fi
    else
        fail "Script '$script' missing from repo"
    fi
done

echo ""
echo "============================================"
echo "  Results: $PASS passed, $WARN warnings, $FAIL failures"
echo "============================================"

if [ "$FAIL" -gt 0 ]; then
    exit 1
elif [ "$WARN" -gt 0 ]; then
    exit 0  # warnings are informational
fi

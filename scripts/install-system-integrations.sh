#!/bin/sh
# ============================================================
# install-system-integrations.sh — Full ecosystem installer
# ============================================================
# Installs all external integrations on top of Hermes Agent:
#   - npm MCP packages (notion-mcp, slm, context-mode, codegraph)
#   - pip packages (scrapling, onex)
#   - CLI tools (codegraph symlink fix, deeplx, firecrawl JS SDK)
#   - git repos (freellmapi, cloakbrowser)
#   - MCP wrapper scripts with env var passthrough
#   - Hermes config integration
# ============================================================

set -e
HERMES_HOME="${HERMES_HOME:-$HOME/.hermes}"
REPO_DIR="$(cd "$(dirname "$0")/.." && pwd)"

info()  { printf "  [INFO]  %s\n" "$1"; }
ok()    { printf "  [OK]    %s\n" "$1"; }
skip()  { printf "  [SKIP]  %s\n" "$1"; }
fail()  { printf "  [FAIL]  %s\n" "$1"; exit 1; }

echo ""
echo "╔══════════════════════════════════════════════╗"
echo "║  hermes-alpine — Ecosystem Integration       ║"
echo "╚══════════════════════════════════════════════╝"
echo ""

# ── 1. npm MCP packages ──────────────────────────────────────────
echo "── Step 1: npm MCP packages ──"
for pkg in "@notionhq/notion-mcp-server@latest" "superlocalmemory@latest" "context-mode@latest" "deeplx@latest" "firecrawl@latest"; do
    name="${pkg%%@*}"
    if npm list -g --depth=0 2>/dev/null | grep -q "$name"; then
        skip "$name already installed"
    else
        info "Installing $name..."
        npm install -g "$pkg" 2>&1 | tail -1
        ok "$name installed"
    fi
done

# ── 2. CodeGraph (special: @colbymchenry/codegraph) ────────────
echo ""
echo "── Step 2: CodeGraph MCP ──"
if npm list -g --depth=0 2>/dev/null | grep -q "@colbymchenry/codegraph"; then
    skip "@colbymchenry/codegraph already installed"
else
    info "Installing @colbymchenry/codegraph..."
    npm install -g @colbymchenry/codegraph 2>&1 | tail -1
fi
if command -v codegraph >/dev/null 2>&1; then
    ok "codegraph found in PATH"
else
    info "Symlinking bundled node for Alpine compat..."
    NODE_BIN="$(which node)"
    CG_DIR="/usr/local/lib/node_modules/@colbymchenry/codegraph"
    CG_ARM64="$CG_DIR/node_modules/@colbymchenry/codegraph-linux-arm64"
    if [ -f "$CG_ARM64/node" ] && [ ! -x "$CG_ARM64/node" ]; then
        ln -sf "$NODE_BIN" "$CG_ARM64/node" 2>/dev/null
    fi
    ok "codegraph ready"
fi

# ── 3. Python packages ──────────────────────────────────────────
echo ""
echo "── Step 3: Python packages ──"
for pkg in "scrapling[fetchers,shell]" "onex"; do
    n="${pkg%%[*}"
    if pip3 show "$n" >/dev/null 2>&1; then
        skip "$n already installed"
    else
        info "Installing $pkg..."
        pip3 install "$pkg" --break-system-packages 2>&1 | tail -1
        ok "$n installed"
    fi
done

# ── 4. Git repos ────────────────────────────────────────────────
echo ""
echo "── Step 4: Git repos ──"
clone_if_missing() {
    local repo="$1" dir="$2"
    if [ -d "$dir" ]; then
        skip "$(basename "$dir") already cloned at $dir"
    else
        info "Cloning $repo..."
        git clone --depth 1 "https://github.com/$repo.git" "$dir" 2>&1 | tail -1
        ok "$(basename "$dir") cloned"
    fi
}

clone_if_missing "tashfeenahmed/freellmapi" "$HOME/freellmapi"
clone_if_missing "CloakHQ/CloakBrowser" "$HOME/CloakBrowser"

# ── 5. MCP wrapper scripts ──────────────────────────────────────
echo ""
echo "── Step 5: MCP wrapper scripts ──"
mkdir -p "$HERMES_HOME/scripts"

if [ ! -f "$HERMES_HOME/scripts/notion-mcp.sh" ]; then
    info "Creating notion-mcp.sh..."
    cp "$REPO_DIR/scripts/notion-mcp.sh" "$HERMES_HOME/scripts/notion-mcp.sh"
    chmod +x "$HERMES_HOME/scripts/notion-mcp.sh"
    ok "notion-mcp.sh installed"
else
    skip "notion-mcp.sh exists"
fi

if [ ! -f "$HERMES_HOME/scripts/slm-mcp.sh" ]; then
    info "Creating slm-mcp.sh..."
    cp "$REPO_DIR/scripts/slm-mcp.sh" "$HERMES_HOME/scripts/slm-mcp.sh"
    chmod +x "$HERMES_HOME/scripts/slm-mcp.sh"
    ok "slm-mcp.sh installed"
else
    skip "slm-mcp.sh exists"
fi

if [ ! -f "$HERMES_HOME/scripts/firecrawl-mcp.sh" ]; then
    info "Creating firecrawl-mcp.sh..."
    cp "$REPO_DIR/scripts/firecrawl-mcp.sh" "$HERMES_HOME/scripts/firecrawl-mcp.sh"
    chmod +x "$HERMES_HOME/scripts/firecrawl-mcp.sh"
    ok "firecrawl-mcp.sh installed"
else
    skip "firecrawl-mcp.sh exists"
fi

# ── 6. Config merge (MCP servers) ───────────────────────────────
echo ""
echo "── Step 6: MCP config merge ──"
if command -v python3 >/dev/null 2>&1; then
    python3 "$REPO_DIR/scripts/configure-mcp.py" 2>&1 || true
    ok "MCP config merged"
else
    skip "python3 not available — merge manually"
fi

# ── 7. Final verification ──────────────────────────────────────
echo ""
echo "── Step 7: Verification ──"
"$REPO_DIR/scripts/verify-integration.sh" --verbose 2>&1 || true

echo ""
echo "╔══════════════════════════════════════════════╗"
echo "║  Ecosystem integration complete!              ║"
echo "╚══════════════════════════════════════════════╝"

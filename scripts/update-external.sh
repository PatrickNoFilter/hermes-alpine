#!/bin/bash
# ============================================================
# update-external.sh — Update all Hermes external integrations
# ============================================================
# Run this anytime you add a new MCP server or external dep.
# No args needed. Run: bash ~/.hermes/scripts/update-external.sh
# ============================================================

set -e

echo "=== 1. NPM Global Packages ==="
npm update -g 2>&1 | grep -v 'hyperframes\|EINVALID\|\.hyperframes\|\.corepack\|corepack-dT' | tail -5 || true
echo "   ✓ npm global updated"

echo ""
echo "=== 2. SLM Venv (Python MCP SDK) ==="
UV_LINK_MODE=copy uv pip install --upgrade mcp --python /root/.hermes/slm-env/bin/python 2>&1 | tail -3
echo "   ✓ slm-env updated"

echo ""
echo "=== 3. System Python MCP SDK ==="
pip3 install --upgrade mcp --no-deps 2>&1 | tail -3
echo "   ✓ system pip mcp updated"

echo ""
echo "=== 4. RTK CLI (ARM64) ==="
CURRENT=$(/root/.local/bin/rtk --version 2>/dev/null | head -1)
echo "   Current: $CURRENT"
LATEST=$(curl -sL https://api.github.com/repos/rtk-ai/rtk/releases/latest 2>/dev/null | python3 -c "import sys,json; print(json.load(sys.stdin).get('tag_name','unknown'))" 2>/dev/null || echo "unknown")
echo "   Latest:  $LATEST"
if [ "$LATEST" != "unknown" ]; then
    TAG="${LATEST#v}"
    CUR_TAG="${CURRENT#rtk }"
    if [ "$CUR_TAG" != "$TAG" ]; then
        echo "   → Updating to $LATEST..."
        cd /tmp
        curl -sL "https://github.com/rtk-ai/rtk/releases/download/$LATEST/rtk-aarch64-unknown-linux-gnu.tar.gz" -o rtk-update.tar.gz
        tar xzf rtk-update.tar.gz
        mv rtk /root/.local/bin/rtk
        chmod +x /root/.local/bin/rtk
        rm -f rtk-update.tar.gz
        echo "   ✓ RTK updated to $(/root/.local/bin/rtk --version)"
    else
        echo "   ✓ RTK already latest"
    fi
fi

echo ""
echo "=== 5. CodeGraph (npm) ==="
CG_VER=$(npm list -g @colbymchenry/codegraph 2>/dev/null | grep codegraph | head -1 | sed 's/.*@//')
echo "   Current: v$CG_VER"
CG_LATEST=$(curl -sL https://api.github.com/repos/colbymchenry/codegraph/releases/latest 2>/dev/null | python3 -c "import sys,json; print(json.load(sys.stdin).get('tag_name','unknown'))" 2>/dev/null || echo "unknown")
echo "   Latest:  $CG_LATEST"
if [ "$CG_LATEST" != "unknown" ]; then
    CG_NUM="${CG_LATEST#v}"
    if [ "$CG_VER" != "$CG_NUM" ]; then
        echo "   → Updating to $CG_LATEST..."
        npm install -g "@colbymchenry/codegraph@$CG_LATEST" 2>&1 | tail -3
        echo "   ✓ CodeGraph updated to $(npm list -g @colbymchenry/codegraph 2>/dev/null | grep codegraph | head -1)"
    else
        echo "   ✓ CodeGraph already latest"
    fi
fi

echo ""
echo "=== 6. Context Mode (npx — auto latest) ==="
echo "   (dijalankan via npx, selalu ambil versi terbaru)"
CM_LATEST=$(curl -sL https://api.github.com/repos/mksglu/context-mode/releases/latest 2>/dev/null | python3 -c "import sys,json; print(json.load(sys.stdin).get('tag_name','unknown'))" 2>/dev/null || echo "unknown")
echo "   Latest:  $CM_LATEST"

echo ""
echo "=== 7. last30days Skill ==="
SKILL_DIR="$HOME/.hermes/skills/research/last30days"
echo "   Target: $SKILL_DIR"
LD_LATEST=$(curl -sL https://api.github.com/repos/mvanhorn/last30days-skill/releases/latest 2>/dev/null | python3 -c "import sys,json; print(json.load(sys.stdin).get('tag_name','unknown'))" 2>/dev/null || echo "unknown")
echo "   Latest:  $LD_LATEST"
# Check current version from SKILL.md or files
CUR_LD_VER=$(grep -m1 '^version:' "$SKILL_DIR/SKILL.md" 2>/dev/null | sed 's/version:[^"]*"\([^"]*\)".*/\1/' || echo "unknown")
echo "   Current: $CUR_LD_VER"
if [ "$LD_LATEST" != "unknown" ]; then
    # Compare versions (simple string, assume tag like v3.3.0)
    LD_VERSION="${LD_LATEST#v}"
    if [ "$CUR_LD_VER" != "$LD_VERSION" ]; then
        echo "   → Updating to $LD_LATEST..."
        cd /tmp
        curl -sL "https://github.com/mvanhorn/last30days-skill/archive/refs/tags/$LD_LATEST.tar.gz" -o last30days-update.tar.gz
        EXTRACTED=$(tar tzf last30days-update.tar.gz | head -1 | cut -d/ -f1)
        tar xzf last30days-update.tar.gz
        # Copy skill files (inside skills/last30days/ in the archive)
        rm -rf "$SKILL_DIR" 2>/dev/null || true
        mkdir -p "$(dirname "$SKILL_DIR")"
        if [ -d "/tmp/$EXTRACTED/skills/last30days" ]; then
            mv "/tmp/$EXTRACTED/skills/last30days" "$SKILL_DIR"
        else
            echo "   ⚠ Unexpected archive structure, creating fresh"
            mkdir -p "$SKILL_DIR"
            mv "/tmp/$EXTRACTED"/* "$SKILL_DIR"/ 2>/dev/null || true
        fi
        rm -rf "/tmp/$EXTRACTED" last30days-update.tar.gz
        echo "   ✓ last30days skill updated to $LD_LATEST"
    else
        echo "   ✓ last30days already latest"
    fi
fi

echo ""
echo "=== 8. Notion MCP Server ==="
NM_CUR=$(node -e 'console.log(require("/tmp/node_modules/@notionhq/notion-mcp-server/package.json").version)' 2>/dev/null || echo "0")
NM_LATEST=$(npm show @notionhq/notion-mcp-server version 2>/dev/null || echo "0")
echo "   Current: $NM_CUR"
echo "   Latest:  $NM_LATEST"
if [ "$NM_CUR" != "$NM_LATEST" ] && [ "$NM_LATEST" != "0" ]; then
    echo "   → Updating to $NM_LATEST..."
    npm install @notionhq/notion-mcp-server@latest --prefix /tmp 2>&1 | tail -3
    NM_CUR=$(node -e 'console.log(require("/tmp/node_modules/@notionhq/notion-mcp-server/package.json").version)' 2>/dev/null || echo "?")
    echo "   ✓ Notion MCP updated to $NM_CUR"
else
    echo "   ✓ Notion MCP already latest"
fi

echo ""
echo "=== 9. DeepLX (ARM64 binary) ==="
DLX_CUR=$(/usr/local/bin/deeplx -h 2>&1 | head -1 || echo "unknown")
echo "   Binary: /usr/local/bin/deeplx"
DLX_LATEST=$(curl -sL https://api.github.com/repos/OwO-Network/DeepLX/releases/latest 2>/dev/null | python3 -c "
import sys,json
try:
    d=json.load(sys.stdin)
    for a in d.get('assets',[]):
        n=a.get('name','')
        if 'linux_arm64' in n:
            print(d.get('tag_name',''))
            break
except: print('unknown')" 2>/dev/null || echo "unknown")
echo "   Latest:  $DLX_LATEST"
if [ "$DLX_LATEST" != "unknown" ] && [ -n "$DLX_LATEST" ]; then
    echo "   ✓ DeepLX update check OK (manual update via GitHub release)"
fi

# NPM versions
echo "--- NPM Globals ---"
for pkg in superlocalmemory @notionhq/notion-mcp-server @colbymchenry/codegraph; do
    ver=$(npm list -g "$pkg" 2>/dev/null | grep "$pkg" | head -1)
    echo "   $ver"
done

# Python versions
echo ""
echo "--- Python MCP SDK ---"
echo "   pip: mcp=$(pip3 show mcp 2>/dev/null | grep Version | cut -d' ' -f2)"
/root/.hermes/slm-env/bin/python -c "import mcp; print(f'   venv: mcp={mcp.__version__}')" 2>/dev/null || true

# RTK version
echo ""
echo "--- Lainnya ---"
/root/.local/bin/rtk --version 2>/dev/null

# CodeGraph version
codegraph --version 2>/dev/null && echo ""

# last30days version
grep -m1 'version:' "$SKILL_DIR/SKILL.md" 2>/dev/null && echo ""

echo ""
echo "=== Selesai! Restart Hermes untuk apply ==="
echo "   exit → hermes"

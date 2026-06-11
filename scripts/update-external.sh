#!/bin/sh
# ============================================================
# update-external.sh — Update all Hermes external integrations
# ============================================================
# Run this anytime you add a new MCP server or external dep.
# Usage: bash ~/.hermes/scripts/update-external.sh
# ============================================================

set -e

HERMES_HOME="${HERMES_HOME:-$HOME/.hermes}"
LOCAL_BIN="${HOME}/.local/bin"
NODE_GLOBAL="${HERMES_HOME}/node/lib/node_modules"

echo "=== 1. NPM Global Packages ==="
npm update -g 2>&1 | grep -v 'hyperframes\|EINVALID\|\.hyperframes\|\.corepack\|corepack-dT' | tail -5 || true
echo "   ✓ npm global updated"

echo ""
echo "=== 2. SLM Venv (Python MCP SDK) ==="
if [ -f "${HERMES_HOME}/slm-env/bin/python" ]; then
    UV_LINK_MODE=copy uv pip install --upgrade mcp --python "${HERMES_HOME}/slm-env/bin/python" 2>&1 | tail -3
    echo "   ✓ slm-env updated"
else
    echo "   ⚠ slm-env not found — skipping. Run setup-ecosystem.sh first."
fi

echo ""
echo "=== 3. System Python MCP SDK ==="
pip3 install --upgrade mcp --no-deps 2>&1 | tail -3
echo "   ✓ system pip mcp updated"

echo ""
echo "=== 4. RTK CLI ==="
if [ -x "${LOCAL_BIN}/rtk" ]; then
    CURRENT=$("${LOCAL_BIN}/rtk" --version 2>/dev/null | head -1)
    echo "   Current: $CURRENT"
    LATEST=$(curl -sL https://api.github.com/repos/rtk-ai/rtk/releases/latest 2>/dev/null \
        | python3 -c "import sys,json; print(json.load(sys.stdin).get('tag_name','unknown'))" 2>/dev/null || echo "unknown")
    echo "   Latest:  $LATEST"
    if [ "$LATEST" != "unknown" ]; then
        TAG="${LATEST#v}"
        CUR_TAG="${CURRENT#rtk }"
        if [ "$CUR_TAG" != "$TAG" ]; then
            echo "   → Updating to $LATEST..."
            cd /tmp
            curl -sL "https://github.com/rtk-ai/rtk/releases/download/$LATEST/rtk-aarch64-unknown-linux-gnu.tar.gz" -o rtk-update.tar.gz
            tar xzf rtk-update.tar.gz
            mv rtk "${LOCAL_BIN}/rtk"
            chmod +x "${LOCAL_BIN}/rtk"
            rm -f rtk-update.tar.gz
            echo "   ✓ RTK updated to $("${LOCAL_BIN}/rtk" --version)"
        else
            echo "   ✓ RTK already latest"
        fi
    fi
else
    echo "   ⚠ rtk not found in ${LOCAL_BIN} — skipping"
fi

echo ""
echo "=== 5. CodeGraph (npm) ==="
CG_VER=$(npm list -g @colbymchenry/codegraph 2>/dev/null | grep codegraph | head -1 | sed 's/.*@//')
echo "   Current: v${CG_VER}"
CG_LATEST=$(curl -sL https://api.github.com/repos/colbymchenry/codegraph/releases/latest 2>/dev/null \
    | python3 -c "import sys,json; print(json.load(sys.stdin).get('tag_name','unknown'))" 2>/dev/null || echo "unknown")
echo "   Latest:  $CG_LATEST"
if [ "$CG_LATEST" != "unknown" ]; then
    CG_NUM="${CG_LATEST#v}"
    if [ "$CG_VER" != "$CG_NUM" ]; then
        echo "   → Updating to $CG_LATEST..."
        npm install -g "@colbymchenry/codegraph@$CG_LATEST" 2>&1 | tail -3
        echo "   ✓ CodeGraph updated"
    else
        echo "   ✓ CodeGraph already latest"
    fi
fi

echo ""
echo "=== 6. Context Mode (npx) ==="
echo "   (runs via npx — always fetches latest)"
CM_LATEST=$(curl -sL https://api.github.com/repos/mksglu/context-mode/releases/latest 2>/dev/null \
    | python3 -c "import sys,json; print(json.load(sys.stdin).get('tag_name','unknown'))" 2>/dev/null || echo "unknown")
echo "   Latest:  $CM_LATEST"

echo ""
echo "=== 7. last30days Skill ==="
SKILL_DIR="${HERMES_HOME}/skills/research/last30days"
echo "   Target: $SKILL_DIR"
LD_LATEST=$(curl -sL https://api.github.com/repos/mvanhorn/last30days-skill/releases/latest 2>/dev/null \
    | python3 -c "import sys,json; print(json.load(sys.stdin).get('tag_name','unknown'))" 2>/dev/null || echo "unknown")
echo "   Latest:  $LD_LATEST"
CUR_LD_VER=$(grep -m1 '^version:' "${SKILL_DIR}/SKILL.md" 2>/dev/null | sed 's/version:[^"]*"\([^"]*\)".*/\1/' || echo "unknown")
echo "   Current: $CUR_LD_VER"
if [ "$LD_LATEST" != "unknown" ]; then
    LD_VERSION="${LD_LATEST#v}"
    if [ "$CUR_LD_VER" != "$LD_VERSION" ]; then
        echo "   → Updating to $LD_LATEST..."
        cd /tmp
        curl -sL "https://github.com/mvanhorn/last30days-skill/archive/refs/tags/$LD_LATEST.tar.gz" -o last30days-update.tar.gz
        EXTRACTED=$(tar tzf last30days-update.tar.gz | head -1 | cut -d/ -f1)
        tar xzf last30days-update.tar.gz
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
NM_PATH="${NODE_GLOBAL}/@notionhq/notion-mcp-server/package.json"
if [ -f "$NM_PATH" ]; then
    NM_CUR=$(node -e "console.log(require('${NM_PATH}').version)" 2>/dev/null || echo "0")
else
    NM_CUR="(not installed)"
fi
NM_LATEST=$(npm show @notionhq/notion-mcp-server version 2>/dev/null || echo "0")
echo "   Current: $NM_CUR"
echo "   Latest:  $NM_LATEST"
if [ "$NM_CUR" != "$NM_LATEST" ] && [ "$NM_LATEST" != "0" ] && [ "$NM_CUR" != "(not installed)" ]; then
    echo "   → Updating to $NM_LATEST..."
    npm install -g "@notionhq/notion-mcp-server@latest" 2>&1 | tail -3
    echo "   ✓ Notion MCP updated"
elif [ "$NM_CUR" = "(not installed)" ]; then
    echo "   → Installing Notion MCP for the first time..."
    npm install -g "@notionhq/notion-mcp-server@latest" 2>&1 | tail -3
    echo "   ✓ Notion MCP installed"
else
    echo "   ✓ Notion MCP already latest"
fi

echo ""
echo "=== 9. DeepLX (ARM64 binary) ==="
if [ -x /usr/local/bin/deeplx ]; then
    DLX_CUR=$(/usr/local/bin/deeplx -h 2>&1 | head -1 || echo "unknown")
    echo "   Binary: /usr/local/bin/deeplx"
else
    DLX_CUR="not installed"
    echo "   Binary: not installed — skipping"
fi
DLX_LATEST=$(curl -sL https://api.github.com/repos/OwO-Network/DeepLX/releases/latest 2>/dev/null \
    | python3 -c "
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

# Version summary
echo ""
echo "--- NPM Globals ---"
for pkg in superlocalmemory @notionhq/notion-mcp-server @colbymchenry/codegraph; do
    ver=$(npm list -g "$pkg" 2>/dev/null | grep "$pkg" | head -1)
    echo "   $ver"
done

echo ""
echo "--- Python MCP SDK ---"
echo "   pip: mcp=$(pip3 show mcp 2>/dev/null | grep Version | cut -d' ' -f2)"
if [ -f "${HERMES_HOME}/slm-env/bin/python" ]; then
    "${HERMES_HOME}/slm-env/bin/python" -c "import mcp; print(f'   venv: mcp={mcp.__version__}')" 2>/dev/null || true
fi

echo ""
echo "--- Other ---"
if [ -x "${LOCAL_BIN}/rtk" ]; then
    "${LOCAL_BIN}/rtk" --version 2>/dev/null
fi
codegraph --version 2>/dev/null && echo ""
grep -m1 'version:' "${SKILL_DIR}/SKILL.md" 2>/dev/null && echo ""

echo ""
echo "=== Done! Restart Hermes to apply ==="
echo "   exit → hermes"

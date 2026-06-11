#!/bin/bash
# =============================================================================
# Hermes Ecosystem — One-shot installer
# =============================================================================
# Installs the entire Hermes ecosystem in correct dependency order:
#   1. System build dependencies (Alpine / Debian/Ubuntu / Fedora)
#   2. Node.js runtime (if missing or old)
#   3. Python venv + pip + build toolchain
#   4. Python runtime dependencies (requirements.txt)
#   5. Python MCP package (requirements-mcp.txt)
#   6. npm production dependencies (package.json)
#   7. npm optional: better-sqlite3 rebuild
#   8. Hermes Python package (editable)
# =============================================================================

set -e

HERMES_SRC="${HERMES_SRC:-$(cd "$(dirname "$0")" && pwd)}"
VENV="${VENV:-$HERMES_SRC/venv}"

echo "=========================================="
echo "  Hermes Ecosystem — One-shot Install"
echo "=========================================="
echo "  HERMES_SRC : $HERMES_SRC"
echo "  VENV       : $VENV"
echo ""

# =============================================================================
# Step 0: Detect OS
# =============================================================================
detect_os() {
    if [ -f /etc/os-release ]; then
        . /etc/os-release
        case "$ID" in
            alpine)        echo "alpine" ;;
            ubuntu|debian) echo "debian" ;;
            fedora|rhel|rocky|almalinux|centos) echo "fedora" ;;
            arch)          echo "arch" ;;
            *)             echo "unknown:$ID" ;;
        esac
    else
        echo "unknown"
    fi
}

OS=$(detect_os)
echo "▸ OS detected: $OS"

# =============================================================================
# Step 1: System build dependencies
# =============================================================================
echo ""
echo "=== Step 1: System build dependencies ==="

install_alpine_deps() {
    apk add --no-cache \
        nodejs npm \
        python3 py3-pip py3-virtualenv \
        build-base python3-dev musl-dev linux-headers \
        git curl bash \
        libffi-dev openssl-dev \
        cargo rust
}

install_debian_deps() {
    apt-get update -qq
    apt-get install -y -qq \
        nodejs npm \
        python3 python3-venv python3-dev \
        build-essential \
        git curl bash \
        libffi-dev libssl-dev \
        pkg-config
}

install_fedora_deps() {
    dnf install -y -q \
        nodejs npm \
        python3 python3-pip \
        gcc gcc-c++ make \
        python3-devel \
        git curl bash \
        libffi-devel openssl-devel \
        cargo rust
}

install_arch_deps() {
    pacman -Sy --noconfirm \
        nodejs npm \
        python python-pip \
        base-devel \
        git curl bash \
        libffi \
        rust
}

case "$OS" in
    alpine)
        install_alpine_deps
        ;;
    debian)
        install_debian_deps
        ;;
    fedora)
        install_fedora_deps
        ;;
    arch)
        install_arch_deps
        ;;
    unknown:*)
        echo "⚠  Unknown OS ($OS). Skipping system deps — install Node.js and Python manually."
        ;;
esac

# =============================================================================
# Step 2: Node.js check
# =============================================================================
echo ""
echo "=== Step 2: Node.js ==="

NODE_VERSION=$(node --version 2>/dev/null || echo "none")
NPM_VERSION=$(npm --version 2>/dev/null || echo "none")
echo "▸ Node $NODE_VERSION / npm $NPM_VERSION"

if [ "$NODE_VERSION" = "none" ] || [ "$NODE_VERSION" \< "v18" ]; then
    echo "⚠  Node.js missing or too old. Install Node.js 18+ and re-run."
    echo "   On Alpine:  apk add nodejs npm"
    echo "   On Debian:  curl -fsSL https://deb.nodesource.com/setup_20.x | bash -"
fi

# =============================================================================
# Step 3: Python venv
# =============================================================================
echo ""
echo "=== Step 3: Python venv ==="

if [ ! -d "$VENV" ]; then
    echo "▸ Creating venv at $VENV"
    python3 -m venv "$VENV"
else
    echo "▸ Venv already exists at $VENV"
fi

# Activate venv for remaining steps
source "$VENV/bin/activate"

# =============================================================================
# Step 4: Python build toolchain
# =============================================================================
echo ""
echo "=== Step 4: Python build toolchain ==="

pip install --upgrade pip setuptools wheel

# UV_LINK_MODE=copy for Termux/PRoot compatibility
export UV_LINK_MODE="${UV_LINK_MODE:-copy}"
export UV_NO_BUILD_ISOLATION="${UV_NO_BUILD_ISOLATION:-1}"
export PIP_NO_BUILD_ISOLATION=1

# =============================================================================
# Step 5: Python runtime dependencies
# =============================================================================
echo ""
echo "=== Step 5: Python runtime dependencies ==="

REQUIREMENTS="$HERMES_SRC/requirements.txt"
if [ -f "$REQUIREMENTS" ]; then
    echo "▸ Installing $REQUIREMENTS"
    pip install -r "$REQUIREMENTS"
else
    echo "▸ $REQUIREMENTS not found — skipping"
fi

# =============================================================================
# Step 6: Python MCP package
# =============================================================================
echo ""
echo "=== Step 6: Python MCP package ==="

REQUIREMENTS_MCP="$HERMES_SRC/requirements-mcp.txt"
if [ -f "$REQUIREMENTS_MCP" ]; then
    echo "▸ Installing $REQUIREMENTS_MCP"
    pip install -r "$REQUIREMENTS_MCP"
else
    echo "▸ $REQUIREMENTS_MCP not found — skipping"
fi

# =============================================================================
# Step 7: npm production dependencies
# =============================================================================
echo ""
echo "=== Step 7: npm dependencies ==="

if [ -f "$HERMES_SRC/package.json" ]; then
    echo "▸ Installing npm packages from $HERMES_SRC/package.json"
    cd "$HERMES_SRC"
    npm install --omit=dev
    echo "▸ Running postinstall (native module rebuild)..."
    npm rebuild better-sqlite3 || true
    echo "▸ npm install complete"
else
    echo "▸ $HERMES_SRC/package.json not found — skipping"
fi

# =============================================================================
# Step 8: Hermes Python package (editable)
# =============================================================================
echo ""
echo "=== Step 8: Hermes Agent (editable) ==="

if [ -f "$HERMES_SRC/pyproject.toml" ]; then
    echo "▸ Installing hermes-agent (editable)"
    pip install -e "$HERMES_SRC"
else
    echo "▸ $HERMES_SRC/pyproject.toml not found — skipping"
fi

# =============================================================================
# Done
# =============================================================================
echo ""
echo "=========================================="
echo "  ✓ Ecosystem install complete"
echo "=========================================="
echo ""
echo "Next steps:"
echo "  1. Copy config.yaml.example → config.yaml and add your API keys"
echo "  2. Activate venv:  source $VENV/bin/activate"
echo "  3. Start Hermes:  hermes"
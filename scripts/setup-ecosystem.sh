#!/bin/bash
# =============================================================================
# Hermes Ecosystem — One-shot installer
# =============================================================================
# Installs the entire Hermes ecosystem in correct dependency order.
# Works two ways:
#   A) Piped from GitHub:  curl -fsSL .../setup-ecosystem.sh | bash
#      (script auto-fetches its sibling files from GitHub)
#   B) From cloned repo:  ./scripts/setup-ecosystem.sh
#      (uses local files)
#
# Dependency order:
#   1. System build deps (Alpine / Debian / Fedora / Arch, auto-detected)
#   2. Node.js runtime
#   3. Python venv + pip + build toolchain
#   4. Python runtime dependencies
#   5. Python MCP package
#   6. npm production dependencies
#   7. Hermes Python package (editable)
# =============================================================================

set -e

REPO_URL="${REPO_URL:-https://raw.githubusercontent.com/PatrickNoFilter/hermes-alpine/main}"
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
HERMES_SRC="${HERMES_SRC:-$SCRIPT_DIR}"
VENV="${VENV:-$HERMES_SRC/venv}"

echo "=========================================="
echo "  Hermes Ecosystem — One-shot Install"
echo "=========================================="
echo "  HERMES_SRC : $HERMES_SRC"
echo "  VENV       : $VENV"
echo ""

# =============================================================================
# Helper: fetch a file from REPO_URL if it doesn't exist locally
# =============================================================================
fetch_if_missing() {
    local src="$1"
    local dst="$HERMES_SRC/$(basename "$src")"
    if [ ! -f "$dst" ]; then
        echo "▸ Fetching $src"
        curl -fsSL "$REPO_URL/$src" -o "$dst"
    fi
}

# =============================================================================
# If running via pipe (no local files), create a working dir and fetch all files
# =============================================================================
if [ ! -f "$HERMES_SRC/package.json" ] && [ ! -f "$HERMES_SRC/requirements.txt" ]; then
    echo "▸ No local repo detected — fetching files from GitHub..."
    mkdir -p "$HERMES_SRC"
    fetch_if_missing "requirements.txt"
    fetch_if_missing "requirements-mcp.txt"
    fetch_if_missing "package.json"
    fetch_if_missing "config.yaml.example"
    echo ""
fi

# =============================================================================
# Clone hermes-agent from upstream if not already present
# =============================================================================
HERMES_AGENT_DIR="${HERMES_AGENT_DIR:-$HERMES_SRC/hermes-agent}"
if [ ! -d "$HERMES_AGENT_DIR/.git" ]; then
    echo ""
    echo "=== Cloning hermes-agent (upstream) ==="
    git clone --depth=1 https://github.com/nousresearch/hermes-agent.git "$HERMES_AGENT_DIR"
else
    echo ""
    echo "=== hermes-agent already present at $HERMES_AGENT_DIR ==="
fi

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
    echo "▸ npm install complete"
else
    echo "▸ $HERMES_SRC/package.json not found — skipping"
fi

# =============================================================================
# Step 8: Hermes Python package (editable)
# =============================================================================
echo ""
echo "=== Step 8: Hermes Agent (editable) ==="

if [ -f "$HERMES_AGENT_DIR/pyproject.toml" ]; then
    # Widen requires-python to allow Python 3.14 (Alpine ships 3.14).
    # hermes-agent caps at <3.14 to avoid pydantic-core cp314 wheel gaps, but
    # Alpine has Rust + cargo so source builds work fine.
    echo "▸ Patching requires-python to allow Python 3.14+"
    sed -i 's/requires-python = ">=3.11,<3.14"/requires-python = ">=3.11"/' \
        "$HERMES_AGENT_DIR/pyproject.toml"

    echo "▸ Installing hermes-agent (editable)"
    pip install -e "$HERMES_AGENT_DIR"
    HERMES_CLI="$HERMES_AGENT_DIR/cli.py"
    if [ -f "$HERMES_CLI" ]; then
        echo "▸ Symlinking 'hermes' CLI to ~/.local/bin"
        mkdir -p "$HOME/.local/bin"
        ln -sf "$HERMES_CLI" "$HOME/.local/bin/hermes"
    fi
else
    echo "▸ $HERMES_AGENT_DIR/pyproject.toml not found — skipping"
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
echo "  1. cp $HERMES_SRC/config.yaml.example ~/.hermes/config.yaml"
echo "     then add your API keys to ~/.hermes/config.yaml"
echo "  2. Add to PATH:  export PATH=\"\$HOME/.local/bin:\$PATH\""
echo "     (add to ~/.bashrc to persist)"
echo "  3. Activate venv:  source $VENV/bin/activate"
echo "  4. Start Hermes:   hermes"
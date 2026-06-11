#!/bin/bash
# Post-hermes-update Termux/PRoot repair
# Re-applies Termux-specific fixes that git pull overwrites.
# Run after:  hermes update
set -e

HERMES_SRC="/usr/local/lib/hermes-agent"
VENV="$HERMES_SRC/venv"

echo "=== Post-update Termux Repair ==="

# --- Global env vars (persist across git resets) ---
for rc in ~/.bashrc ~/.hermes/.env; do
    grep -q 'UV_LINK_MODE' "$rc" 2>/dev/null || echo 'export UV_LINK_MODE=copy' >> "$rc"
    grep -q 'UV_NO_BUILD_ISOLATION' "$rc" 2>/dev/null || echo 'export UV_NO_BUILD_ISOLATION=1' >> "$rc"
done
echo "✓ Global env vars in ~/.bashrc + ~/.hermes/.env"

# --- Venv: pin setuptools + ensure build deps ---
echo "→ Pinning setuptools to 81.x..."
UV_LINK_MODE=copy VIRTUAL_ENV="$VENV" uv pip install 'setuptools<82' jaraco-util more_itertools 2>&1 | tail -2

# --- Source patches (re-applied after git pull overwritten them) ---
PYPROJ="$HERMES_SRC/pyproject.toml"
MAINPY="$HERMES_SRC/hermes_cli/main.py"

# Patch pyproject.toml: add more_itertools to build-system.requires
if ! grep -q 'more_itertools' "$PYPROJ"; then
    echo "→ Patching pyproject.toml..."
    sed -i 's/requires = \["setuptools>=77.0,<83"\]/requires = ["setuptools>=77.0,<83", "more_itertools>=10.0"]/' "$PYPROJ"
fi

# Patch main.py: UV_LINK_MODE=copy + no_build_isolation for Termux
if ! grep -q 'UV_LINK_MODE.*copy' "$MAINPY"; then
    echo "→ Patching main.py (UV_LINK_MODE)..."
    sed -i '/uv_env.pop("PYTHONHOME", None)/a\                uv_env["UV_LINK_MODE"] = "copy"' "$MAINPY"
fi
if ! grep -q 'no_build_isolation = True' "$MAINPY"; then
    echo "→ Patching main.py (--no-build-isolation)..."
    sed -i '/install_group = "termux-all"/a\                no_build_isolation = True' "$MAINPY"
    sed -i '/^            _install_python_dependencies_with_optional_fallback(/{n;s/)/,\\n                no_build_isolation=no_build_isolation)/}' "$MAINPY"
fi

# --- Reinstall Hermes ---
echo ""
echo "→ Reinstalling Hermes..."
UV_LINK_MODE=copy VIRTUAL_ENV="$VENV" uv pip install -e "$HERMES_SRC" 2>&1 | tail -3

echo ""
echo "✓ Done. Restart Hermes with:  exit → hermes"

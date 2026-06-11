#!/bin/bash
# ============================================================================
# install-skills.sh — Install Hermes skills from the repo to HERMES_HOME
# ============================================================================
# Symlinks every skill directory from skills/ into ~/.hermes/skills/,
# making them available to the Hermes Agent session system.
#
# Usage:
#   ./scripts/install-skills.sh              # default: ~/.hermes/skills/
#   HERMES_HOME=/custom/path ./scripts/install-skills.sh
#   ./scripts/install-skills.sh --copy       # copy instead of symlink
#   ./scripts/install-skills.sh --dry-run    # show what would happen
# ============================================================================
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
HERMES_HOME="${HERMES_HOME:-${HOME}/.hermes}"
HERMES_SKILLS_DIR="${HERMES_HOME}/skills"
SKILL_SOURCE_DIR="${REPO_ROOT}/skills"

MODE="symlink"  # or "copy"
DRY_RUN=false

# Parse args
for arg in "$@"; do
    case "$arg" in
        --copy)    MODE="copy"   ;;
        --symlink) MODE="symlink" ;;
        --dry-run) DRY_RUN=true   ;;
    esac
done

if [ ! -d "$SKILL_SOURCE_DIR" ]; then
    echo "[install-skills] ERROR: skill source directory not found: $SKILL_SOURCE_DIR"
    echo "[install-skills] Run this script from the repository root or check REPO_ROOT."
    exit 1
fi

mkdir -p "$HERMES_SKILLS_DIR"

# Count total skills
TOTAL_SKILLS=$(find -L "$SKILL_SOURCE_DIR" -maxdepth 3 -name 'SKILL.md' | wc -l)
INSTALLED=0
SKIPPED=0
UPDATED=0

echo "[install-skills] Installing $TOTAL_SKILLS skills to $HERMES_SKILLS_DIR"
echo "[install-skills] Mode: $MODE"

# Iterate over skill directories (category/name/SKILL.md) — use process substitution
# to avoid the subshell variable scoping bug in bash
while IFS= read -r -d '' skill_file; do
    skill_dir="$(dirname "$skill_file")"
    relative_path="${skill_dir#$SKILL_SOURCE_DIR/}"
    target_dir="$HERMES_SKILLS_DIR/$relative_path"

    if [ "$DRY_RUN" = true ]; then
        if [ "$MODE" = "copy" ]; then
            echo "  [DRY-RUN] Would copy $relative_path → $target_dir"
        else
            echo "  [DRY-RUN] Would symlink $relative_path → $target_dir"
        fi
        continue
    fi

    # Check if already installed (and up to date)
    if [ -d "$target_dir" ] && [ "$MODE" = "symlink" ] && [ -L "$target_dir" ]; then
        existing_target="$(readlink "$target_dir")"
        if [ "$existing_target" = "$skill_dir" ]; then
            echo "  ✓ $relative_path (already linked)"
            SKIPPED=$((SKIPPED + 1))
            continue
        fi
    fi

    if [ -d "$target_dir" ] && [ "$MODE" = "symlink" ] && [ ! -L "$target_dir" ]; then
        echo "  ! $relative_path — removing real directory, replacing with symlink"
        rm -rf "$target_dir"
    fi

    # Remove old symlink/dir before creating new one
    [ -d "$target_dir" ] && rm -rf "$target_dir"
    rm -f "$target_dir" 2>/dev/null || true

    mkdir -p "$(dirname "$target_dir")"

    if [ "$MODE" = "copy" ]; then
        cp -r "$skill_dir" "$target_dir"
        echo "  + $relative_path (copied)"
    else
        ln -sf "$skill_dir" "$target_dir"
        echo "  + $relative_path (symlinked)"
    fi
    INSTALLED=$((INSTALLED + 1))
done < <(find -L "$SKILL_SOURCE_DIR" -maxdepth 3 -name 'SKILL.md' -print0)

if [ "$DRY_RUN" = true ]; then
    echo "[install-skills] DRY-RUN complete — no changes made."
    exit 0
fi

echo ""
echo "[install-skills] Complete!"
echo "  Skills installed: ${INSTALLED:-?}"
echo "  Skills up-to-date: ${SKIPPED:-?}"

# Verify skills are loadable by checking hermes agent
if command -v hermes &>/dev/null; then
    echo "[install-skills] Verifying with 'hermes skills list'..."
    hermes skills list 2>/dev/null | head -5 || true
fi

# Write a marker file so the update script can check version
HERMES_VERSION_FILE="${HERMES_SKILLS_DIR}/.ecosystem-version"
echo "skill_count=$TOTAL_SKILLS" > "$HERMES_VERSION_FILE"
echo "installed_at=$(date -u +%Y-%m-%dT%H:%M:%SZ)" >> "$HERMES_VERSION_FILE"
echo "source=hermes-alpine" >> "$HERMES_VERSION_FILE"

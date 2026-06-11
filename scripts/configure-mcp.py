#!/usr/bin/env python3
"""
configure-mcp.py — Merge ecosystem MCP server definitions into Hermes config.yaml.

Reads the MCP server blocks from config.yaml.example and merges them
into ~/.hermes/config.yaml, preserving existing config and user-customized MCP servers.

Usage:
  python3 scripts/configure-mcp.py
  HERMES_HOME=/custom/path python3 scripts/configure-mcp.py
  python3 scripts/configure-mcp.py --dry-run
  python3 scripts/configure-mcp.py --force   # overwrite existing ecosystem MCP servers
"""
import argparse
import os
import re
import shutil
import sys
from difflib import unified_diff
from pathlib import Path

SCRIPT_DIR = Path(__file__).resolve().parent
REPO_ROOT = SCRIPT_DIR.parent
HERMES_HOME = Path(os.environ.get("HERMES_HOME", Path.home() / ".hermes"))

# Ecosystem MCP servers defined in config.yaml.example
ECOSYSTEM_MCP_SERVERS = {
    "codegraph",
    "context-mode",
    "firecrawl",
    "notion",
    "superlocalmemory",
}


def find_yaml_section(lines: list[str], section_name: str) -> int | None:
    """Find the line index of a top-level YAML key (no leading whitespace)."""
    for i, line in enumerate(lines):
        stripped = line.strip()
        if stripped == f"{section_name}:" and not line[0:1] in (" ", "\t"):
            return i
    return None


def find_next_top_key(lines: list[str], start: int) -> int:
    """Find the next top-level YAML key after `start`, or len(lines) if none."""
    for i in range(start, len(lines)):
        line = lines[i]
        stripped = line.strip()
        if stripped and not line[0:1] in (" ", "\t") and stripped.endswith(":"):
            return i
    return len(lines)


def extract_ecosystem_servers() -> str:
    """Extract the ecosystem MCP server block from config.yaml.example as a string."""
    example_path = REPO_ROOT / "config.yaml.example"
    if not example_path.exists():
        print(f"[configure-mcp] ERROR: {example_path} not found")
        sys.exit(1)

    text = example_path.read_text()
    lines = text.splitlines()

    mcp_line = find_yaml_section(lines, "mcp_servers")
    if mcp_line is None:
        print("[configure-mcp] WARNING: No 'mcp_servers:' in config.yaml.example")
        return ""

    section_end = find_next_top_key(lines, mcp_line + 1)

    # Get the mcp_servers block lines
    block = lines[mcp_line:section_end]

    # Parse individual servers, keeping only ecosystem ones
    result = ["mcp_servers:"]
    current_server = None
    current_block: list[str] = []

    # We iterate line-by-line within the mcp_servers block (skip the first "mcp_servers:" line)
    for line in block[1:]:
        # Detect top-level server name (2-space indent, ends with colon)
        m = re.match(r"^  (\S+):$", line)
        if m:
            # Save previous server if it's an ecosystem one
            if current_server and current_server in ECOSYSTEM_MCP_SERVERS and current_block:
                result.append("")  # blank line separator
                result.extend(current_block)

            current_server = m.group(1)
            current_block = [line]
        elif current_server:
            current_block.append(line)
        else:
            # Lines before any server definition (comments, etc.)
            result.append(line)

    # Don't forget the last one
    if current_server and current_server in ECOSYSTEM_MCP_SERVERS and current_block:
        result.append("")
        result.extend(current_block)

    if len(result) == 1:
        # Only "mcp_servers:" — no ecosystem servers found
        print("[configure-mcp] WARNING: No ecosystem MCP servers found in config.yaml.example")
        print(f"[configure-mcp]   Expected: {', '.join(sorted(ECOSYSTEM_MCP_SERVERS))}")
        return ""

    return "\n".join(result) + "\n"


def merge_into_config(
    current_config: str,
    ecosystem_block: str,
    force: bool = False,
) -> str:
    """Merge the ecosystem MCP server block into the current config.

    Strategy:
      1) If 'mcp_servers:' doesn't exist — append the block at the end.
      2) If 'mcp_servers:' exists — check which ecosystem servers are already there.
         New ones are added; existing ones are skipped or overwritten (--force).
    """
    if not ecosystem_block:
        return current_config

    lines = current_config.splitlines(keepends=True) if current_config.strip() else []

    mcp_idx = find_yaml_section([l.rstrip("\n") for l in lines], "mcp_servers")

    if mcp_idx is None:
        # No mcp_servers section — append at end
        text = current_config.rstrip("\n") + "\n\n" + ecosystem_block
        return text

    # Parse which ecosystem servers already exist in the current config
    existing_eco_servers: set[str] = set()
    section_end = find_next_top_key([l.rstrip("\n") for l in lines], mcp_idx + 1)
    for line in lines[mcp_idx + 1 : section_end]:
        line_stripped = line.rstrip("\n")
        m = re.match(r"^  (\S+):$", line_stripped)
        if m:
            srv = m.group(1)
            if srv in ECOSYSTEM_MCP_SERVERS:
                existing_eco_servers.add(srv)

    # Parse the ecosystem block into individual servers + body
    eco_lines = ecosystem_block.splitlines()
    eco_servers_to_add: list[list[str]] = []  # list of server blocks (each is a list of lines)
    current_eco_block: list[str] = []
    current_eco_server: str | None = None

    for line in eco_lines[1:]:  # skip "mcp_servers:"
        m = re.match(r"^  (\S+):$", line)
        if m:
            if current_eco_server and current_eco_block:
                eco_servers_to_add.append(current_eco_block)
            current_eco_server = m.group(1)
            current_eco_block = [line]
        elif current_eco_server:
            current_eco_block.append(line)

    if current_eco_server and current_eco_block:
        eco_servers_to_add.append(current_eco_block)

    # Build new config
    result = lines[: mcp_idx + 1]  # include "mcp_servers:"
    eco_servers_seen: set[str] = set()

    # Copy existing non-ecosystem lines and handle ecosystem ones
    for line in lines[mcp_idx + 1 : section_end]:
        line_stripped = line.rstrip("\n")
        m = re.match(r"^  (\S+):$", line_stripped)
        if m:
            srv = m.group(1)
            if srv in ECOSYSTEM_MCP_SERVERS:
                if force:
                    # Replace with new version — skip old block
                    # Track that we've seen this server
                    eco_servers_seen.add(srv)
                    # Skip this and subsequent lines until next top-level server or end
                    continue
                else:
                    # Keep existing, remember not to add new version
                    eco_servers_seen.add(srv)
                    result.append(line)
            else:
                result.append(line)
        elif line_stripped or line_stripped == "":
            # Only add non-ecosystem lines. But in --force mode, we skip all
            # lines that belong to an ecosystem block. We track with a flag.
            if force:
                # Check if this line belongs to an ecosystem server block
                # that we're replacing. Simple heuristic: if the last server
                # seen was an ecosystem one, this line belongs to it.
                pass  # We'll handle this differently below
            result.append(line)

    # With --force, we need a smarter approach. Let me redo this.
    # Actually, let me use a clean-slate approach for the mcp_servers section:
    # 1. Keep all non-ecosystem servers
    # 2. Keep ecosystem servers that the user doesn't want overwritten
    # 3. Add new ecosystem servers
    
    result = lines[: mcp_idx + 1]
    
    i = mcp_idx + 1
    while i < section_end:
        line = lines[i]
        line_stripped = line.rstrip("\n")
        m = re.match(r"^  (\S+):$", line_stripped)
        
        if m:
            srv = m.group(1)
            if srv in ECOSYSTEM_MCP_SERVERS:
                if force:
                    # Skip this entire server block
                    i += 1
                    while i < section_end:
                        l = lines[i].rstrip("\n")
                        if re.match(r"^  (\S+):$", l):
                            break
                        i += 1
                    continue
                else:
                    # Keep existing, add to result and skip adding new version
                    result.append(line)
                    eco_servers_seen.add(srv)
                    i += 1
                    while i < section_end:
                        l = lines[i].rstrip("\n")
                        if re.match(r"^  (\S+):$", l):
                            break
                        result.append(lines[i])
                        i += 1
                    continue
            else:
                # Non-ecosystem server — keep it
                result.append(line)
                i += 1
                while i < section_end:
                    l = lines[i].rstrip("\n")
                    if re.match(r"^  (\S+):$", l):
                        break
                    result.append(lines[i])
                    i += 1
                continue
        
        # Lines before any server (comments, blank lines)
        result.append(line)
        i += 1

    # Now add the ecosystem servers that aren't already present (or all if --force)
    for block in eco_servers_to_add:
        server_name_line = block[0]
        m = re.match(r"^  (\S+):", server_name_line)
        if m:
            srv = m.group(1)
            if srv in eco_servers_seen and not force:
                print(f"  - {srv}: already configured, skipping (use --force to overwrite)")
                continue
            elif force:
                print(f"  ~ {srv}: overwriting (--force)")
            else:
                print(f"  + {srv}: adding")

        result.append("\n")  # blank line separator
        for bline in block:
            result.append(bline + "\n")

    # Append remaining lines after old mcp_servers section
    for j in range(section_end, len(lines)):
        result.append(lines[j])

    # Join, normalizing line endings
    combined = "".join(result)
    return combined


def main():
    parser = argparse.ArgumentParser(
        description="Merge ecosystem MCP server config into Hermes config.yaml"
    )
    parser.add_argument("--dry-run", action="store_true",
                        help="Show what would change without modifying")
    parser.add_argument("--force", action="store_true",
                        help="Overwrite existing ecosystem MCP server definitions")
    args = parser.parse_args()

    config_path = HERMES_HOME / "config.yaml"

    print(f"[configure-mcp] Reading ecosystem MCP definitions from config.yaml.example")
    ecosystem_block = extract_ecosystem_servers()

    if not ecosystem_block:
        sys.exit(1)

    print("")

    if not config_path.parent.exists():
        print(f"[configure-mcp] ERROR: {config_path.parent} does not exist")
        print("[configure-mcp] Run setup-ecosystem.sh first to create Hermes config directory")
        sys.exit(1)

    current_text = config_path.read_text() if config_path.exists() else ""

    if not current_text.strip() and not args.force:
        print(f"[configure-mcp] {config_path} is empty or doesn't exist.")
        print("[configure-mcp] Copy config.yaml.example to get started:")
        print(f"  cp {REPO_ROOT / 'config.yaml.example'} {config_path}")
        print("[configure-mcp] Then run with --force to merge MCP servers.")
        sys.exit(0)

    new_text = merge_into_config(current_text, ecosystem_block, args.force)

    if new_text == current_text:
        print("\n[configure-mcp] No changes needed.")
        sys.exit(0)

    if args.dry_run:
        print("[configure-mcp] DRY-RUN — changes that would be made:")
        diff = unified_diff(
            current_text.splitlines(keepends=True),
            new_text.splitlines(keepends=True),
            fromfile=str(config_path),
            tofile=str(config_path),
        )
        sys.stdout.writelines(diff)
        sys.stdout.flush()
        return

    # Backup
    if config_path.exists():
        backup = config_path.with_suffix(".yaml.bak")
        shutil.copy2(config_path, backup)
        print(f"\n[configure-mcp] Backed up existing config to {backup}")

    config_path.write_text(new_text)
    print(f"\n[configure-mcp] Updated {config_path}")

    print("\n[configure-mcp] Next steps:")
    print("  1. Set required API keys in ~/.hermes/.env or config.yaml")
    print("  2. Verify with: hermes config get mcp_servers")


if __name__ == "__main__":
    main()

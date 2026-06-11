#!/usr/bin/env python3
"""Log ecosystem integration to Notion Hermes Vault."""
import json, urllib.request, subprocess, re, socket

# Read .env and extract NOTION_API_KEY without hardcoding the key pattern
with open("/root/.hermes/.env") as f:
    env_lines = f.readlines()

NOTION_KEY = ""
target = "NOTION_API_KEY"
for line in env_lines:
    line = line.strip()
    if not line or line.startswith("#"):
        continue
    if line.startswith(target) and len(line) > len(target) + 15:
        eq = line.index("=")
        NOTION_KEY = line[eq+1:].strip().strip("'").strip('"')
        break

print(f"Key extracted: {len(NOTION_KEY)} chars" if NOTION_KEY else "KEY NOT FOUND")

if not NOTION_KEY:
    exit(1)

PAGE_ID = "3707b66e-c7e0-80c0-9e1b-eaf7d0ddc697"

chunks = [
    f"PH[DEV] Ecosystem Integration - Alpine Hermes ({socket.gethostname()[:15]}) | 2026-06-11 UTC",
    "Completed full ecosystem integration into Alpine Hermes (aarch64). All integrations from Notion Vault inventory installed and verified.",
    "npm MCP packages: @notionhq/notion-mcp-server (2.2.1), superlocalmemory (3.6.8), context-mode (1.0.162), @colbymchenry/codegraph (0.9.9), deeplx",
    "MCP servers: codegraph (0.9.9), context-mode, firecrawl-mcp, notion (2.2.1), superlocalmemory (3.6.8)",
    "pip: scrapling[fetchers,shell], onex. npm: DeepLX, firecrawl JS SDK, Playwright.",
    "Git repos cloned: freellmapi, CloakBrowser",
    "Repo: install-system-integrations.sh, notion-mcp.sh, slm-mcp.sh, firecrawl-mcp.sh. Verify extended with system checks. Makefile integrate target.",
    "MCP config: firecrawl wrapper script. --force idempotency fix. CodeGraph Alpine node symlink.",
    "Source: https://github.com/PatrickNoFilter/hermes-alpine"
]

body = {
    "children": [
        {
            "object": "block",
            "type": "callout",
            "callout": {
                "rich_text": [{"type": "text", "text": {"content": c[:1900]}}],
                "icon": {"emoji": "🧩"}
            }
        }
        for c in chunks
    ] + [{"object": "block", "type": "divider", "divider": {}}]
}

req = urllib.request.Request(
    f"https://api.notion.com/v1/blocks/{PAGE_ID}/children",
    data=json.dumps(body).encode(),
    headers={
        "Authorization": f"Bearer {NOTION_KEY}",
        "Content-Type": "application/json",
        "Notion-Version": "2022-06-28"
    },
    method="PATCH"
)

try:
    with urllib.request.urlopen(req, timeout=15) as resp:
        result = json.loads(resp.read())
    print(f"Success! {len(result.get('results', []))} blocks created.")
except urllib.error.HTTPError as e:
    err = e.read().decode()
    print(f"HTTP {e.code}: {err[:300]}")
except Exception as e:
    print(f"Error: {e}")

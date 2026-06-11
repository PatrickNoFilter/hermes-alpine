#!/usr/bin/env python3
"""Sync holographic memory facts to Notion Hermes Vault page.

Tracks last synced fact_id in ~/.hermes/state/holographic_notion_sync.json.
Appends new facts as bulleted list items under a 'Holographic Memory' heading.
"""

import json, os, sys, urllib.request, urllib.error
from datetime import datetime, timezone

# --- Config ---
HERMES_HOME = os.environ.get("HERMES_HOME", os.path.expanduser("~/.hermes"))
DB_PATH = os.path.join(HERMES_HOME, "memory_store.db")
STATE_PATH = os.path.join(HERMES_HOME, "state", "holographic_notion_sync.json")
VAULT_PAGE_ID = "3707b66e-c7e0-80c0-9e1b-eaf7d0ddc697"
NOTION_VERSION = "2025-09-03"


def load_env(path):
    env = {}
    if os.path.exists(path):
        for line in open(path):
            line = line.strip()
            if line and not line.startswith("#") and "=" in line:
                k, v = line.split("=", 1)
                env[k.strip()] = v.strip().strip("'\"")
    return env


env = load_env(os.path.join(HERMES_HOME, ".env"))
# Try multiple env var names for Notion API key
NOTION_TOKEN = (
    env.get("NOTION_API_KEY")
    or os.environ.get("NOTION_API_KEY")
    or env.get("NOTION_TOKEN")
    or os.environ.get("NOTION_TOKEN")
)
if not NOTION_TOKEN:
    print("ERROR: NOTION_TOKEN not found")
    sys.exit(1)

HEADERS = {
    "Authorization": f"Bearer {NOTION_TOKEN}",
    "Content-Type": "application/json",
    "Notion-Version": NOTION_VERSION,
}


def notion_get(url):
    try:
        req = urllib.request.Request(url, headers=HEADERS)
        with urllib.request.urlopen(req, timeout=15) as resp:
            return json.loads(resp.read())
    except urllib.error.HTTPError as e:
        print(f"HTTP {e.code}: {e.read().decode()[:200]}")
        return None


def notion_patch(url, data):
    body = json.dumps(data).encode()
    try:
        req = urllib.request.Request(url, data=body, headers=HEADERS, method="PATCH")
        with urllib.request.urlopen(req, timeout=15) as resp:
            return json.loads(resp.read())
    except urllib.error.HTTPError as e:
        print(f"HTTP {e.code} on PATCH {url}")
        return None


# --- Read holographic facts ---
sys.path.insert(0, "/usr/local/lib/hermes-agent")
from plugins.memory.holographic.store import MemoryStore

store = MemoryStore(db_path=DB_PATH)
all_facts = store.list_facts(limit=500)
print(f"OK: {len(all_facts)} facts in holographic store")

# --- Sync state ---
os.makedirs(os.path.dirname(STATE_PATH), exist_ok=True)
state = {}
if os.path.exists(STATE_PATH):
    with open(STATE_PATH) as f:
        state = json.load(f)

last_synced_id = state.get("last_synced_fact_id", 0)
new_facts = sorted(
    [f for f in all_facts if f.get("fact_id", 0) > last_synced_id],
    key=lambda x: x.get("fact_id", 0),
)

if not new_facts:
    print("OK: No new facts to sync")
    sys.exit(0)

print(f"NEW: {len(new_facts)} facts to sync")

# --- Get existing blocks on vault page ---
existing_blocks = []
cursor = None
while True:
    url = f"https://api.notion.com/v1/blocks/{VAULT_PAGE_ID}/children"
    if cursor:
        url += f"?start_cursor={cursor}"
    resp = notion_get(url)
    if not resp:
        break
    existing_blocks.extend(resp.get("results", []))
    if resp.get("has_more"):
        cursor = resp.get("next_cursor")
    else:
        break

print(f"OK: {len(existing_blocks)} blocks on vault page")

existing_texts = set()
for block in existing_blocks:
    btype = block.get("type", "")
    inner = block.get(btype, {})
    for rt in inner.get("rich_text", []):
        existing_texts.add(rt.get("plain_text", ""))

# --- Find or create heading ---
heading_block_id = None
heading_exists = False

for block in existing_blocks:
    btype = block.get("type", "")
    inner = block.get(btype, {})
    text = "".join(rt.get("plain_text", "") for rt in inner.get("rich_text", []))
    if "Holographic Memory" in text:
        heading_block_id = block["id"]
        heading_exists = True
        break

if not heading_exists:
    result = notion_patch(
        f"https://api.notion.com/v1/blocks/{VAULT_PAGE_ID}/children",
        {
            "children": [
                {
                    "type": "heading_2",
                    "heading_2": {
                        "rich_text": [
                            {"type": "text", "text": {"content": "Holographic Memory"}}
                        ]
                    },
                }
            ]
        },
    )
    if result:
        results = result.get("results", [])
        if results:
            heading_block_id = results[0]["id"]
        print("OK: Created 'Holographic Memory' heading")

# --- Build blocks for new facts ---
blocks_to_add = []
for f in new_facts:
    content = f.get("content", "")
    if not content or content in existing_texts:
        continue

    category = f.get("category", "general")
    line = f"[{category}] {content}"

    blocks_to_add.append(
        {
            "type": "bulleted_list_item",
            "bulleted_list_item": {
                "rich_text": [
                    {"type": "text", "text": {"content": line[:2000]}}
                ]
            },
        }
    )

if not blocks_to_add:
    print("OK: All facts already synced (duplicates)")
    max_id = max(f.get("fact_id", 0) for f in new_facts)
    state["last_synced_fact_id"] = max_id
    state["last_synced_at"] = datetime.now(timezone.utc).isoformat()
    with open(STATE_PATH, "w") as f:
        json.dump(state, f, indent=2)
    sys.exit(0)

# --- Append in batches of 10 ---
parent_id = heading_block_id if heading_exists else VAULT_PAGE_ID
for i in range(0, len(blocks_to_add), 10):
    batch = blocks_to_add[i : i + 10]
    result = notion_patch(
        f"https://api.notion.com/v1/blocks/{parent_id}/children",
        {"children": batch},
    )
    if not result:
        # fallback: append to page root
        result = notion_patch(
            f"https://api.notion.com/v1/blocks/{VAULT_PAGE_ID}/children",
            {"children": batch},
        )
    print(f"  synced {len(batch)} facts (batch {i // 10 + 1})")

# --- Save state ---
max_id = max(f.get("fact_id", 0) for f in new_facts)
state["last_synced_fact_id"] = max_id
state["last_synced_at"] = datetime.now(timezone.utc).isoformat()
state["total_synced"] = state.get("total_synced", 0) + len(blocks_to_add)
with open(STATE_PATH, "w") as f:
    json.dump(state, f, indent=2)

print(f"\nDONE. Last fact_id: {max_id}, total synced: {state['total_synced']}")

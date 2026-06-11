# Notion Vault — Inventory Operations

Patterns for managing the Hermes Vault inventory (not task logs, but structured lists: GitHub repos, packages, stats, etc.).

## Three Sources to Sync

| Source | What It Tracks | How to Check |
|--------|---------------|--------------|
| **System** | Actual installed state | `which`, `dpkg`, `ls`, `npm list` |
| **Hermes Config** | What's active | `~/.hermes/config.yaml` (plugins, MCP servers, skills) |
| **Notion Vault** | Documented inventory | `mcp_notion_API_get_block_children` |

**Rule**: Always verify sources #1 and #2 before modifying source #3.

## Common Operations

### Delete (Archive) a Block

```python
# Find block ID first via get_block_children
# Then call the MCP tool:
# mcp_notion_API_delete_a_block(block_id="...")
```

Notion "delete" = archive (in_trash: true). Items can be restored.

### Add a Bulleted List Item

The rich_text format for Notion MCP:

```json
{
  "type": "bulleted_list_item",
  "bulleted_list_item": {
    "rich_text": [
      {"type": "text", "text": {"content": "bold-name", "link": null},
       "annotations": {"bold": true}},
      {"type": "text", "text": {"content": " — "}},
      {"type": "text", "text": {"content": "https://github.com/...",
       "link": {"url": "https://github.com/..."}}},
      {"type": "text", "text": {"content": " — description"}}
    ]
  }
}
```

**Pitfall**: `annotations.bold: true` goes INSIDE the text item, not at top level. The API rejects `"bold": true` at the rich_text item level.

### Append to Page (add items at end)

All items go to the bottom of the page via `mcp_notion_API_patch_block_children`. Use the page ID as `block_id`.

### Batch Appending

Add multiple items in one call — compose the `children` array with all new blocks.

## Stats Updates

When adding/removing inventory items, update the Stats section:
- Change repo count (e.g. "10 GitHub repos" → "11 GitHub repos")
- Change skill count (e.g. "4 Hermes skills" → "5 Hermes skills")
- Update star counts if you know the new totals

## Parallel Operations (Speed Optimization)

**User prefers parallel operations** when checking many items. Never run N sequential commands to check N things.

### Audit Many Items at Once

Use `execute_code` with parallel `terminal()` calls (they're async in Python):

```python
from hermes_tools import terminal
items = []
# Fire all checks concurrently
results = terminal('''\
echo "---pkg1---" && dpkg -l pkg1 | grep '^ii'
echo "---pkg2---" && dpkg -l pkg2 | grep '^ii'
echo "---skill1---" && ls ~/.hermes/skills/*/skill1/SKILL.md
...''')
```

Or delegate independent queries to `delegate_task` with `tasks` array (up to 3 parallel).

For Notion vault operations that are independent (multiple `delete_a_block` calls, multiple `patch_block_children`), fire them all in one response turn — they don't depend on each other and the MCP tools resolve concurrently.

### Finding Block IDs Efficiently

When you need block IDs for vault cleanup:

1. Fetch children with `page_size=100` (max) in a single call
2. **Do not re-read the raw output manually** — use `execute_code` with Python to parse and filter:
   ```python
   import json
   # block_children_output from earlier call (the full JSON)
   data = json.loads(block_children_result_string)
   for block in data.get("results", []):
       btype = block.get("type")
       text = block.get(btype, {}).get("rich_text", [{}])[0].get("plain_text", "")
       if "scrapling" in text.lower():
           print(f"{block['id']} | {btype} | {text}")
   ```
3. This avoids manually scanning through 100+ blocks in raw JSON output.

## System-Wide Cleanup Protocol

When user says "X was deleted / is not useful anymore":

### Step 1: Full Inventory Audit (parallel)

Check ALL vault inventory items against the actual system in one batch:

```python
checks = {
    "tool1": "which tool1 2>/dev/null || dpkg -l tool1 2>/dev/null | grep '^ii'",
    "pkg1": "pip3 list 2>/dev/null | grep -i pkg1",
    "skill1": "ls ~/.hermes/skills/*/skill1/SKILL.md 2>/dev/null",
    "npm-pkg": "npm list -g @scope/package 2>&1 | grep package",
}
```

Run all checks in ONE `terminal()` call using `&&` / `||` / `echo` separators. Parse the output with code to find what's gone.

### Step 2: Report Mismatches

| Vault Entry | System | Action |
|-------------|--------|--------|
| tool1 | ✅ installed | Keep in vault |
| tool2 | ❌ not found | Delete from vault |
| tool3 | ✅ but dead link | Delete from vault + system clean |

### Step 3: Batch Delete from Vault

Delete all confirmed-gone items in ONE parallel call batch (multiple `mcp_notion_API_delete_a_block` calls in the same response turn).

### Step 4: Remove from System (if applicable)

```bash
apt remove -y tool3 tool4
```

### Step 5: Add New Items

Use `mcp_notion_API_patch_block_children` to add replacement/updated items. If adding under a specific heading, append to the page (new items go at the bottom) rather than trying to insert in the middle — Notion sorts display by created_time.

## Example: Full Inventory Add/Remove Cycle

1. User: "X was deleted"
2. Agent: Check `which X`, `dpkg -l X`, `ls ~/.hermes/skills/*/X/`, `grep X ~/.hermes/config.yaml`
3. Report findings: "X is still installed" or "X is confirmed removed from system"
4. If user confirms delete from vault:
   - `mcp_notion_API_get_block_children` to find the block ID
   - `mcp_notion_API_delete_a_block` to archive it
   - If adding replacements, append new items
5. **If user says "same for everything"** → run a full parallel audit of ALL vault entries (steps 1-3 above)

# Batch Logging Example

This reference file documents the batch-logging approach.

## Why Batch?

Instead of N sequential API calls for N entries (slow, rate-limit risk),
compose ALL pending entries into ONE `children` array and send ONE PATCH call.

## Concrete Example

```python
import json, urllib.request

NOTION_KEY = "..."  # see API key extraction pitfall below
VAULT_ID = "3707b66e-c7e0-80c0-9e1b-eaf7d0ddc697"

entries = [
    {
        "emoji": "🔧",
        "title": "[CONFIG] ...",
        "date": "2026-... UTC",
        "summary": "Summary of what was done.",
        "tools": "tool1, tool2",
        "files": "file paths",
        "source": "https://github.com/...",
        "outcome": "What was accomplished."
    },
    # ... more entries
]

children = []
for e in entries:
    text = f"📌 {e['title']}\n🕐 {e['date']}\n\n📝 {e['summary']}\n\n🔧 Tools: {e['tools']}\n📂 Files: {e['files']}\n🔗 Source: {e['source']}\n\n✅ {e['outcome']}"
    children.append({
        "object": "block",
        "type": "callout",
        "callout": {
            "rich_text": [{"type": "text", "text": {"content": text}}],
            "icon": {"emoji": e['emoji']},
            "color": "gray_background"
        }
    })
    children.append({"object": "block", "type": "divider", "divider": {}})

payload = json.dumps({"children": children}).encode()
req = urllib.request.Request(
    f"https://api.notion.com/v1/blocks/{VAULT_ID}/children",
    data=payload,
    headers={
        "Authorization": f"Bearer {NOTION_KEY}",
        "Notion-Version": "2022-06-28",
        "Content-Type": "application/json"
    },
    method="PATCH"
)
resp = urllib.request.urlopen(req)
result = json.loads(resp.read())
```

## Pitfalls Documented

1. **API key extraction**: The MCP tools handle auth automatically — prefer them. For direct API calls, read NOTION_API_KEY from `~/.hermes/.env` using Python's `open()` (the terminal/curl `grep` approach may truncate the key in restricted contexts). Use `python3 -c "import os; key = open('/root/.hermes/.env').read().split('NOTION_API_KEY=')[1].split()[0]"`.
2. **Line breaks in f-strings**: Use `\n` explicitly in the f-string (real newlines), NOT multi-line string literals. This produces the correct `\n` JSON-escaped output for Notion's API.
3. **Source URL**: Every entry MUST include a `🔗 Source:` line with the GitHub URL of the tool/resource being logged.
4. **Verification**: Check `result.get("object") == "list"` after writing.
5. **Emoji in icon**: The `icon.emoji` field MUST be set separately from the text content for proper rendering.
6. **Batch size**: 4-10 entries per call is fine; avoid 1-at-a-time sequential calls.
7. **Updating existing entries**: `mcp_notion_API_update_a_block` may have schema issues. Prefer delete+re-add via `mcp_notion_API_delete_a_block` + `mcp_notion_API_patch_block_children`.

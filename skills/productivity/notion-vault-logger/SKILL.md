---
name: notion-vault-logger
description: Log completed Hermes tasks/work to Notion Hermes Vault as persistent memory. Trigger after completing any non-trivial task (3+ tool calls, bug fix, setup, research, code).
triggers:
  - task completed
  - work finished
  - setup done
  - bug fixed
  - "catat ke notion"
  - "tulis ke vault"
  - "log to vault"
  - notion vault
  - hermes vault
---

# Notion Vault Logger

Log completed work to Notion Hermes Vault for persistent cross-session memory.

## How the Auto-Logging Chain Works

The logging is not a single action — it's a **chain of three layers** that together ensure every completed task lands in Notion:

```
Layer 1: MEMORY (standing instruction)
  └── "Setiap task selesai → log ke Notion Hermes Vault"
      └── Injected into every session automatically
          └── Triggers the agent to log after non-trivial work

Layer 2: SKILL (this file)
  └── Defines the format, categories, and methods
      └── Loaded when triggers match
          └── Guides the agent on HOW to compose and write

Layer 3: TOOLS (execution)
  └── Primary: Notion MCP tools (mcp_notion_API_patch_block_children)
  └── Fallback A: execute_code with Python urllib
  └── Fallback B: ~/.hermes/scripts/hermes_vault_log.py (terminal)
  └── Fallback C: curl via terminal
```

Agent behaviour: after a completed task (3+ tool calls, setup, bugfix, config change, research), compose a structured entry and write it via the tool chain above. Do NOT log trivial lookups or single-command answers.

## Vault Info

- **Hermes Vault Page ID**: `3707b66e-c7e0-80c0-9e1b-eaf7d0ddc697`
- **Hermes Note Page ID**: `3707b66e-c7e0-80e7-a59e-e01f4e584113`
- **Script**: `~/.hermes/scripts/hermes_vault_log.py` (terminal fallback)
- **Notion API Version** (curl/script): `2022-06-28`
- **MCP tools use their own version** (currently `2025-09-03`)

## API Key (for curl/script fallbacks)

```bash
NOTION_KEY=$(grep NOTION_API_KEY /root/.hermes/.env | cut -d= -f2 | tr -d '[:space:]')
```

## Workflow — Log a Completed Task

### Step 1: Compose the entry

Each log entry is a **callout block** with a category emoji and this structure:

```
📌 [CATEGORY] Task Title
🕐 YYYY-MM-DD HH:MM UTC

📝 Summary of what was done (2-5 sentences)

🔧 Tools: tool1, tool2, tool3
📂 Files: path/to/file1, path/to/file2
🔗 Source: https://github.com/...

✅ Outcome: what was accomplished / verified
```

Always append a **divider block** after each entry for visual separation.

**Categories:**

| Category | Emoji | Use When |
|----------|-------|----------|
| SETUP | 🔧 | Installing/configuring tools, services, skills |
| BUGFIX | 🐛 | Fixing broken functionality |
| RESEARCH | 🔍 | Investigating approaches, comparing options |
| DEV | 💻 | Coding, scripting, building features |
| CONFIG | ⚙️ | Config changes, env vars, startup scripts |
| SECURITY | 🔒 | OPSEC, Tor, pentesting tools |
| SYNC | 🔄 | Syncing data, Obsidian vault, git operations |
| OTHER | 📌 | Anything that doesn't fit above |

### Step 2: Write to Vault (Primary — Notion MCP Tools)

The **preferred method** uses `mcp_notion_API_patch_block_children` directly. This avoids shell escaping, temp files, and API key handling.

Use `execute_code` with Python urllib to batch multiple entries:

```python
import json, urllib.request, os

NOTION_KEY = "..."  # read from ~/.hermes/.env
VAULT_ID = "3707b66e-c7e0-80c0-9e1b-eaf7d0ddc697"

entries = [
    {"emoji": "🔧", "title": "[SETUP] ...", "date": "...", 
     "summary": "...", "tools": "...", "files": "...", "source": "...", "outcome": "..."},
]

children = []
for e in entries:
    text = f"📌 {e['title']}\n🕐 {e['date']}\n\n📝 {e['summary']}\n\n🔧 Tools: {e['tools']}\n📂 Files: {e['files']}\n🔗 Source: {e['source']}\n\n✅ {e['outcome']}"
    children.append({
        "object": "block", "type": "callout",
        "callout": {"rich_text": [{"type": "text", "text": {"content": text}}],
                     "icon": {"emoji": e['emoji']}, "color": "gray_background"}
    })
    children.append({"object": "block", "type": "divider", "divider": {}})

payload = json.dumps({"children": children}).encode()
req = urllib.request.Request(
    f"https://api.notion.com/v1/blocks/{VAULT_ID}/children",
    data=payload,
    headers={"Authorization": f"Bearer {NOTION_KEY}",
             "Notion-Version": "2022-06-28",
             "Content-Type": "application/json"},
    method="PATCH"
)
resp = urllib.request.urlopen(req)
result = json.loads(resp.read())
# Verify: result.get("object") == "list"
```

**Batching**: Always batch entries — append ALL pending entries in ONE call (up to ~10 at a time is fine). Never make sequential single-entry calls.

### Step 3: Verify

- **MCP method**: response returns `{"object":"list","results":[...]}` — check for no errors.
- **curl method**: check HTTP 200 and `"object": "list"` in response.
- Open the [Hermes Vault](https://www.notion.so/Hermes-Vault-3707b66ec7e080c09e1beaf7d0ddc697) page in a browser to visually confirm.

## Fallback Methods

### Fallback A: execute_code with Python urllib (above)
Use when MCP tools are unavailable but you can run Python. 
**Pitfall**: When constructing the payload string with f-strings containing `\n`, use raw string or double-backslash. Prefer building the text with explicit `\n` in f-strings rather than multi-line string literals.

**Pitfall: API key extraction from .env** — the `grep NOTION_API_KEY /root/.hermes/.env | cut -d= -f2` approach may return a truncated key in some contexts (e.g. terminal output redaction). Instead, use `python3 -c "import os; key = open('/root/.hermes/.env').read().split('NOTION_API_KEY=')[1].split()[0]"` or read the .env directly with Python and parse it. The MCP tools handle auth automatically and are the preferred path.

### Fallback B: Terminal script
```bash
NOTION_KEY=$(grep NOTION_API_KEY /root/.hermes/.env | cut -d= -f2 | tr -d '[:space:]')
python3 ~/.hermes/scripts/hermes_vault_log.py \
  CATEGORY "Title" "Summary text" "tools" "files" "Outcome"
```

### Fallback C: curl with temp file
Use when shell escaping is an issue (emoji, newlines in payload):
```bash
cat > /tmp/notion_vault_payload.json << 'PAYLOAD'
{"children": [{"object":"block","type":"callout","callout":{"rich_text":[{"type":"text","text":{"content":"..."}}],"icon":{"emoji":"📌"},"color":"gray_background"}}]}
PAYLOAD
NOTION_KEY=$(grep NOTION_API_KEY /root/.hermes/.env | cut -d= -f2 | tr -d '[:space:]')
curl -s "https://api.notion.com/v1/blocks/3707b66e-c7e0-80c0-9e1b-eaf7d0ddc697/children" \
  -H "Authorization: Bearer $NOTION_KEY" \
  -H "Notion-Version: 2022-06-28" \
  -H "Content-Type: application/json" \
  -d @/tmp/notion_vault_payload.json
```

## Before Modifying the Vault — Verify First

**CRITICAL WORKFLOW RULE**: Before you delete, archive, or modify any content in the Notion vault because a user says something "was deleted" or "isn't installed":

1. **Check the SYSTEM first** — verify the actual state (which binary, `dpkg -l`, `ls ~/.hermes/skills/`, etc.)
2. **Check Hermes config** — is it still in `config.yaml` plugins, MCP servers, or skills?
3. **Then update the Vault** — only delete/archive blocks after confirming system state

Report the actual state to the user before making the vault change. If there's a mismatch (e.g. "tors already hapus ketahuan gak check system"), they want to know.

This applies to ALL vault modifications — not just user-requested ones. Before logging a "removed" entry or archiving blocks, verify the external ground truth first.

## Verification Checklist (Before Claiming Something Is Missing)

When user asks whether something is installed or says something should be removed, do NOT answer from memory alone. Run:

```bash
# Binary in PATH
which <tool> 2>/dev/null

# System package (apt)
dpkg -l <package> 2>/dev/null | grep -c '^ii'

# Hermes skill
ls ~/.hermes/skills/*/<tool>/ 2>/dev/null

# Hermes config (plugins, MCP servers)
grep -A2 '<tool>' ~/.hermes/config.yaml 2>/dev/null

# npm global
npm list -g <package> 2>&1 | head -2

# uv/pip venv
hermes -m pip show <package> 2>/dev/null | grep Version
```

Only after checking ALL relevant sources should you conclude something is absent.

## When to Log

- **ALWAYS log**: Completed tasks with 3+ tool calls, bug fixes, system setups, config changes, research findings, importable discovery results
- **OPTIONAL**: Quick lookups, simple file reads, ephemeral one-shot commands
- **SKIP**: Failed/cancelled tasks (unless the failure itself is instructive)
- **LOG separately if user asks**: User requests like "can u list what repo...", "add this to notion" are separate entries

## Tips & Pitfalls

- **MCP `rich_text` array serialization bug**: When calling `mcp_notion_API_patch_block_children` (or any Notion MCP tool that takes a `rich_text` array) with a single-item array, the MCP layer currently wraps the value in `{"item": {...}}` instead of passing the array. The Notion API then returns `400 validation_error: rich_text should be an array, instead was {"item": ...}`. For any non-trivial entry (callout, paragraph, etc.) prefer the Python urllib fallback in this skill (or any of the curl-based paths) — they construct the JSON body directly and bypass the MCP serialization. The MCP path is reliable for tools that take flat string/scalar params (search, retrieve, post_page with a title); it's unreliable for tools where one of the params must be a JSON array.
- **rich_text content 2000-char ceiling**: Notion's `rich_text[].text.content` field has a hard limit of **2000 characters per item**. The Notion API returns `400 validation_error: body.children[0].callout.rich_text[0].text.content.length should be ≤ 2000, instead was <N>`. The fix is to split the long text into multiple `rich_text` items in the SAME callout's array — they render as a single visual block but each item stays under the ceiling. Example pattern (Python urllib):
  ```python
  callout = {
      "object": "block", "type": "callout",
      "callout": {
          "rich_text": [
              {"type": "text", "text": {"content": chunk_1}},  # <2000 chars
              {"type": "text", "text": {"content": chunk_2}},  # <2000 chars
          ],
          "icon": {"emoji": "📌"}, "color": "gray_background",
      },
  }
  ```
  This is different from the MCP serialization bug above (that one is about the ARRAY shape, this is about the CONTENT length). Both can hit on the same call. Verify the chunk sizes with `assert len(chunk) <= 2000` before sending so you fail fast in Python, not with a 400 in the API. Natural split point: between the Source line and the Outcome line, or any other paragraph boundary.
- **Keep summaries concise but informative** — future-you needs to understand quickly without re-reading the whole conversation
- **Include file paths** for traceability
- **Include verification results** (HTTP status, file exists, service running, exit code)
- **Include GitHub source URL** — always add a `🔗 Source:` line with the repo URL for any installed tool or resource
- **Use divider blocks** between entries for readability
- **If the task involved Indonesian language notes**, include them (user is bilingual EN/ID)
- **Batch entries** — do NOT make N sequential API calls for N entries; compose them all into one `children` array
- **MCP tools vs curl**: MCP tools (`mcp_notion_API_patch_block_children`) are preferred for flat-param calls (search, retrieve, post_page with title). For calls that construct JSON arrays (patch_block_children with `rich_text`, children arrays for nested blocks, etc.) the MCP serializer currently wraps single-item arrays in `{"item": ...}` causing 400. Use the Python urllib fallback or curl-with-temp-file path in those cases — they bypass the MCP serialization layer.
- **Response verification**: Always check the response object type before declaring success. A 200 status is not enough — verify `result.object == "list"`.
- **Emoji in titles**: Use the category emoji 📌 prefix in the text AND in the `icon.emoji` field for proper rendering.
- **This skill is loaded by triggers AND by the Memory standing instruction** — the memory says "log completed tasks to Notion", this skill says "how". Both are needed.
- **Reference: `references/inventory-operations.md`** — patterns for adding/removing bullet items, updating stats, and the 3-source verification protocol before vault modifications.
- **Deleting and re-adding a block**: To update an existing Notion entry (e.g. to add a Source URL), delete the old blocks via `mcp_notion_API_delete_a_block` then re-add via `mcp_notion_API_patch_block_children`. The MCP `update_a_block` tool may have schema compatibility issues with the Notion API version — prefer delete+re-add for corrections.
- **API key limitations**: The Notion API key from .env may not work for direct Python/curl calls (returns 401 Unauthorized) even though the MCP tools function fine. When direct API access is needed, prefer MCP tools. If MCP tools are unavailable, test the key extraction method first.

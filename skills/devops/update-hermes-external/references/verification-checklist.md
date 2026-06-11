# Inventory Verification — 3-Source Audit Protocol

When user asks "is X installed?" or "what do we have?", don't answer from memory. Check all three sources.

## The Three Sources

### 1. System (Filesystem/PATH)
```bash
# Binary in PATH
which <tool> 2>/dev/null && <tool> --version

# System package
dpkg -l <package> 2>/dev/null | grep '^ii'

# Hermes skill directory
ls ~/.hermes/skills/*/<name>/ 2>/dev/null

# npm global
npm list -g 2>/dev/null | grep -E 'superlocalmemory|notion|codegraph'

# Standalone binary
ls /root/.local/bin/ 2>/dev/null
```

### 2. Hermes Config
```bash
# MCP servers
grep -A1 'mcp_servers:' ~/.hermes/config.yaml

# Plugins
grep -A5 'plugins:\|enabled:' ~/.hermes/config.yaml | grep -- ' -'

# Memory provider
grep -A5 'memory:' ~/.hermes/config.yaml | head -10
```

### 3. Notion Vault
```bash
# Query via Notion MCP
# mcp_notion_API_get_block_children(block_id="3707b66e-c7e0-80c0-9e1b-eaf7d0ddc697")
```

## Examples From Session

| Claim | System Check | Config Check | Vault Check | Verdict |
|-------|-------------|--------------|-------------|---------|
| "RTK installed?" | `/root/.local/bin/rtk works (v0.42.2)` | No plugin entry (removed) | Listed in inventory | ✅ Installed |
| "tor deleted?" | `/usr/sbin/tor exists (0.4.9.6)` | N/A | Already archived | ❌ Still installed — mismatch |
| "agentmemory deleted?" | npm dir empty, list fails | Not in config | Block archived | ✅ Confirmed removed |

## Protocol

1. When user says "X was deleted" or asks "is X installed?" — **start with System** (#1)
2. Cross-reference with Config (#2) 
3. Only then check or modify the Vault (#3)
4. Report mismatches to user before taking action

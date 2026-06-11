---
name: update-hermes-external
description: "Update all Hermes external integrations (npm globals, MCP SDKs) in one command. Run after adding a new MCP server or periodically."
version: 1.0.0
author: Hermes Agent
platforms: [linux, macos]
---

# Update Hermes External Integrations

Script untuk update semua external dependencies Hermes (npm global packages + MCP Python SDKs) dalam satu perintah.

## Script Location

`~/.hermes/scripts/update-external.sh`

## Usage

```bash
bash ~/.hermes/scripts/update-external.sh
```

Kemudian restart Hermes: `exit` → `hermes`

## What It Updates

| Step | What | How | Why |
|------|------|-----|-----|
| 1 | `npm update -g` | npm | SLM, Notion MCP, CodeGraph |
| 2 | `uv pip install --upgrade mcp` | uv (slm-env venv) | Python MCP SDK untuk SLM |
| 3 | `pip3 install --upgrade mcp` | system pip | Python MCP SDK fallback |
| 4 | GitHub release download | RTK ARM64 binary | CLI proxy untuk hemat token |
| 5 | `npm install -g @colbymchenry/codegraph@latest` | npm | CodeGraph MCP (flow analysis) |
| 6 | npx (auto-latest) | npx | Context Mode — selalu latest |
| 7 | GitHub release download | last30days skill | Hermes skill update |
| 8 | `npm install @notionhq/notion-mcp-server@latest --prefix /tmp` | npm | Notion MCP server — update di /tmp/node_modules/ |
| 9 | GitHub release download (ARM64) | Go binary | DeepLX — translation server (check only) |

## External Tools by Package Manager

Not all tools use npm or pip. Know which manager each uses:

| Manager | Tools Found This Session | Update Command |
|---------|------------------------|----------------|
| **npm** | `superlocalmemory`, `@notionhq/notion-mcp-server`, `@colbymchenry/codegraph` | `npm update -g <pkg>` |
| **npx** (auto-latest) | `context-mode` | Nothing — always latest on each run |
| **cargo** | `rtk` (Rust binary, `~/.local/bin/rtk`) | `cargo install rtk --force` |
| **apt** | `python3-numpy`, `python3-scipy`, `python3-pydantic` | `apt update && apt upgrade` |
| **pip/uv** | `mcp`, `vaderSentiment`, `rank-bm25` | `uv pip install --upgrade` or `pip3 install --upgrade` |
| **pre-built binary** | Some Rust/Go tools | Download latest release from GitHub |

### RTK Update

RTK (`/root/.local/bin/rtk`) adalah Rust binary — beda dari npm/pip tools:

```bash
# Cara 1: via cargo (kalau Rust toolchain terinstall)
cargo install rtk --force

# Cara 2: cek versi
/root/.local/bin/rtk --version
```

## Adding New Integrations

Kalau nanti nambah MCP server atau external tool baru:
1. Tentukan **package manager**-nya (npm, pip, cargo, go, apt, pre-built binary)
2. Tambah baris update di `~/.hermes/scripts/update-external.sh`
3. Update tabel di skill ini

Contoh nambah Go binary:
```bash
echo "=== 4. Go Tools ==="
go install github.com/some/mcp-server@latest 2>&1 | tail -3
echo "   ✓ go tools updated"
```

## Pre-Flight: Inventory Check

Before updating, audit what's installed:

```bash
# MCP servers terdaftar
grep -A1 'mcp_servers:' ~/.hermes/config.yaml | grep -v 'mcp_servers:' | grep command

# Memory provider aktif
grep memory.provider ~/.hermes/config.yaml

# Hermes plugins aktif
grep -A5 'plugins:\|enabled:' ~/.hermes/config.yaml | grep -- '-'

# npm global (Hanya package Hermes-related)
ls /root/.hermes/node/lib/node_modules/ | grep -v '^\.'

# Standalone binaries di PATH
which rtk 2>/dev/null && rtk --version
which codegraph 2>/dev/null && codegraph --version
ls /root/.local/bin/ 2>/dev/null

# Built-in Hermes plugins
ls /usr/local/lib/hermes-agent/plugins/
```

## When to Run

- **Setelah nambah MCP server baru** — pastikan versi terbaru
- **Bulanan** — periodic maintenance
- **Kalau ada bug aneh** — mungkin MCP server butuh update

## Script Content

```bash
#!/bin/bash
set -e

echo "=== 1. NPM Global Packages ==="
npm update -g 2>&1 | grep -v 'hyperframes\|EINVALID\|\.hyperframes\|\.corepack\|corepack-dT' | tail -5 || true
echo "   ✓ npm global updated"

echo ""
echo "=== 2. SLM Venv (Python MCP SDK) ==="
UV_LINK_MODE=copy uv pip install --upgrade mcp --python /root/.hermes/slm-env/bin/python 2>&1 | tail -3
echo "   ✓ slm-env updated"

echo ""
echo "=== 3. System Python MCP SDK ==="
pip3 install --upgrade mcp --no-deps 2>&1 | tail -3
echo "   ✓ system pip mcp updated"

echo ""
echo "=== Versi Sekarang ==="
for pkg in superlocalmemory @notionhq/notion-mcp-server; do
    npm list -g "$pkg" 2>/dev/null | grep "$pkg" | head -1 | sed 's/^/   npm: /'
done
echo "   pip mcp=$(pip3 show mcp 2>/dev/null | grep Version | cut -d' ' -f2)"
/root/.hermes/slm-env/bin/python -c "import mcp; print(f'   venv mcp={mcp.__version__}')" 2>/dev/null || true

echo ""
echo "=== Selesai! Restart Hermes untuk apply ==="
```

## Related References

- **`references/dead-plugin-entries.md`** — identifying and removing zombie plugin entries from Hermes config
- **`references/verification-checklist.md`** — 3-source audit protocol (System → Config → Vault) for answering "is X installed?"

## Pitfalls

- **npm artifact dirs** (`.\*` dirs in node_modules) cause cosmetic errors — they're filtered by `grep -v`
- **PRoot hardlink issue** — `UV_LINK_MODE=copy` diperlukan di environment PRoot/Termux
- **PEP 668** — system Python (3.14) terkunci, makanya SLM pake venv sendiri
- **Restart diperlukan** — MCP tools di-cache di memory Hermes, config baru cuma kebaca pas startup

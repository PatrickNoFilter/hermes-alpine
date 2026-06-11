# External Repo Compatibility Checklist

Use this when asked to evaluate whether an external OSS repo is worth integrating into the Hermes environment.

---

## 1. Quick Metadata (curl GitHub API)

```bash
curl -s https://api.github.com/repos/OWNER/REPO | python3 -c "import json,sys; d=json.load(sys.stdin); [print(f'{k}: {v}') for k,v in {'Name':'full_name','Desc':'description','Stars':lambda d: f\"{d[\"stargazers_count\"]:,}\",'Lang':'language','License':lambda d: d.get('license',{}).get('spdx_id','?'),'Updated':'updated_at','Topics':lambda d: ', '.join(d.get('topics',[]))}.items()]"
```

## 2. README Scan

```bash
curl -s https://raw.githubusercontent.com/OWNER/REPO/main/README.md | head -150
```

Check for: install methods, dependencies, architecture requirements, paid tiers, MCP/integration support.

## 3. Platform Compatibility Matrix

| Criterion | Check | Pass/Fail |
|-----------|-------|-----------|
| **Architecture** | linux-arm64 binary? Source-buildable? Pure Python/JS? RISC? | |
| **RAM** | Peak usage under 4GB (leaves room for Hermes + OS)? | |
| **GPU** | Required? (None available — CPU-only) | |
| **Python** | Python 3.10+? (Current: 3.13.13 / 3.14.4) | |
| **Node** | Node 18+? ARM64 builds available on npm? | |
| **Docker** | Required? (Docker unavailable in Termux PRoot) | |
| **OS** | Linux-specific? macOS-only? Windows? | |
| **Budget** | Completely free + open-source? Free tier that covers need? | |

## 4. Existing Tool Overlap Check

Before committing, check if we already cover this capability:

| Capability | We Have |
|------------|---------|
| Web scraping | `scrapling` skill + CloakBrowser |
| YouTube transcripts | `youtube-content` skill |
| X/Twitter | `xurl` skill |
| GitHub operations | `gh` CLI + `github-*` skills |
| Document to Markdown | `markitdown` (recommended) |
| Web search | Built-in `web_search` tool |
| PDF/OCR | `ocr-and-documents` skill |
| Audio transcription | `text_to_speech` + whisper |
| Video generation | `comfyui` skill (but GPU-limited) |
| RSS/feed monitoring | `blogwatcher` skill |
| Social media scraping | `scrapling` (general), `xurl` (X) |
| MCP integration | Built-in native MCP client |

## 5. Environment-Specific Red Flags

- ❌ **Rust/C++ with no prebuilt arm64 binary** — cross-compilation is unreliable in PRoot
- ❌ **Requires GPU (CUDA, MPS, ROCm)** — none available
- ❌ **Requires Docker** — unavailable
- ❌ **Requires systemd or kernel modules** — PRoot limits syscalls
- ❌ **Paid-only API** (no free tier) — budget-conscious setup
- ⚠️ **Large ML model download** (>2GB) — 8GB RAM + PRoot filesystem overhead
- ⚠️ **Chinese-platform focused** (Bilibili, Xiaohongshu, Douyin) — not useful for Indonesia/Western research
- ✅ **Pure Python pip-installable** — ideal
- ✅ **npm global CLI** — good, try `npx` first
- ✅ **MCP server** — plugs directly into Hermes config

## 6. Verdict Template

```
## Repo: owner/name (★ N)
**Description:** ...
**Language:** ...  **License:** ...
**ARM64:** ✅/❌/⚠️  **RAM:** ...  **GPU:** ❌  **Paid:** ❌/⚠️/✅

**Overlap:** (is this duplicating something we already have?)

**Verdict: Worth it / Skip / Maybe later**
- What it enables that we can't do today
- Key blocker if skipped
```

## 7. Examples from Recent Eval Sessions

| Repo | Stars | Verdict | Key Reason |
|------|-------|---------|------------|
| chopratejas/headroom | 18K | Skip | ML models heavy on ARM64, Hermes already manages context |
| howardpen9/grok-mcp | 2 | Skip | Too new, Grok CLI has no ARM64 binary, paid |
| scrapecreators.com | — | Skip | Paid API, no use case for current workflow |
| microsoft/markitdown | 148K | **Worth it** | Pure Python, ARM64 OK, fills document→markdown gap |
| Panniantong/Agent-Reach | 23K | Skip | Overlaps existing tools (xurl, yt-content, scrapling) |
| harry0703/MoneyPrinterTurbo | 81K | Skip | GPU required, heavy, Chinese-focused |
| MemPalace/mempalace | 54K | Skip | Heavy vector DB (ChromaDB+~300MB model), Hermes fact_store covers memory needs |
| lfnovo/open-notebook | 27K | Skip | Requires Docker + SurrealDB, full web stack — impractical on Termux |
| elder-plinius/OBLITERATUS | 6K | Skip | AGPL, needs GPU (PyTorch), deps ~5-10GB. Skill exists as knowledge reference |
| n8n (external workflow) | — | Skip | Node.js server ~200MB, overkill for research workflow. Hermes cron + webhook suffice |

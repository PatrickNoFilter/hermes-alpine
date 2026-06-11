# Community Memory Plugins (GitHub)

Third-party memory providers and plugins discovered via GitHub search. Not all are Hermes `MemoryProvider` plugins — some are standalone MCP servers, skills, or SDK wrappers.

## Local-first (no API key)

| Plugin | Stars | Stack | Install |
|--------|-------|-------|---------|
| **agent-memory-skill** (xMannixx) | 2★ | Pure Python stdlib, SQLite FTS5 | `hermes plugins install xMannixx/agent-memory-skill` |
| **hermes-mempalace-plugin** (iggut) | 0★ | Verbatim drawers + hybrid search + knowledge graph | `hermes plugins install iggut/hermes-mempalace-plugin` |
| **hermes-mempalace-memory-provider** (rusty4444) | 0★ | Automatic semantic recall | `hermes plugins install rusty4444/hermes-mempalace-memory-provider` |

### Comparison: Holographic vs agent-memory-skill

These are the two local-first options. Holographic (built-in MemoryProvider) and agent-memory-skill (community plugin) can run **alongside each other** — different storage backends, no conflict.

| Aspect | **Holographic** (built-in) | **agent-memory-skill** (plugin) |
|--------|---------------------------|--------------------------------|
| Type | MemoryProvider (core Hermes) | Plugin/skill (community) |
| Install | `hermes memory setup holographic` | `git clone` → manual copy |
| Dependencies | numpy optional (HRR) | **stdlib-only** — zero deps |
| Retrieval | Hybrid: FTS5 (40%) + Jaccard (30%) + HRR vectors (30%) | Pure FTS5 + synonym map + score-ranked |
| Vector/HRR | ✅ 1024-dim phase vectors (SHA-256 deterministic) | ❌ None — pure keyword FTS5 |
| Memory structure | Flat facts + category + tags + trust score | **5 Authority Lanes** with per-lane TTL/confidence/source |
| Entity graph | Simple fact-entity linkage (many-to-many) | ✅ Directed graph `relate(entity1, predicate, entity2)` + 1-hop expansion |
| Conflict detection | ❌ | ✅ Single-valued lane conflicts + resolve |
| Procedural rules | ❌ | ✅ Behavioral rules with human review-gate |
| Audit/provenance | ❌ | ✅ Read-only audit-chain reconstruction |
| Rebound protection | ❌ | ✅ Caps intake after 6h+ idle |
| Token budgeting | ❌ | ✅ Per-lane context injection limits |
| Source trust tiers | ✅ Helpful/unhelpful feedback (binary) | ✅ 5 tiers: observation > conversation > inference > tool > external |
| Recall snippets | ❌ | ✅ Raw conversation turns separate from facts |
| German-aware | ❌ | ✅ FTS5 prefix + synonym map |
| CLI | ❌ (tools only) | ✅ Standalone CLI (`fact.py add/recall/list/stats`) |
| Auto-cleanup | ❌ | ✅ `forget_stale()` + systemd timer |
| Complexity | Low — simple, works out of box | High — many features, manual setup |

**Picking strategy:** Holographic for simple vector-capable fact store with zero setup. agent-memory-skill when you need structured memory with TTL per lane, entity relationships, conflict detection, and audit trail. Both can coexist — holographic as MemoryProvider (auto-index), agent-memory-skill as plugin (authority lanes + graph).

### agent-memory-skill (xMannixx)

**Status:** Skill (not a memory provider plugin). Uses `plugin/` directory with `plugin.yaml`.

**Key features:**
- Authority Lanes: 5 classes (identity, preference, evidence, authorization, procedural) with separate TTL/confidence
- German-aware FTS5 retrieval (stemming + synonym map, no embeddings)
- Entity relations — lightweight directed graph (no embeddings)
- Conflict detection + token budgeting
- Rebound-protection (caps intake after idle phases)
- Procedural lane — self-written behavioral rules with mandatory human review-gate

**Limitation:** It's structured as a skill, not a `MemoryProvider`. Load via `hermes skills install`, not `hermes memory setup`.

## Cloud / API-key based

| Plugin | Stars | Stack | Needs |
|--------|-------|-------|-------|
| **Sibyl-Memory** (Sibyl-Labs) | 10★ | SQLite, no embeddings, account activation | Online browser activation + optional wallet |
| **Exabase Plugin** (futurebrowser) | 4★ | Exabase M-1 engine | Exabase API key |
| **lancedb/hermes-agent-memory** | 2★ | LanceDB + OpenAI embeddings | OPENAI_API_KEY |
| **hy-memory-hermes-plugin** (lijie2333) | 0★ | ChromaDB + Kuzu graph | Embedding API key + LLM API key |
| **Memra** (usememra) | 0★ | Memra platform | Memra API key |

### Sibyl-Memory (10★)

Four PyPI packages: `sibyl-memory-client`, `sibyl-memory-cli`, `sibyl-memory-hermes`, `sibyl-memory-mcp`.

- Ranked #2 on LongMemEval (95.6%) — tied with Chronos, beating Mem0, Hindsight, Supermemory
- SQLite + FTS5, no vector DB, no embeddings
- Five-tier hierarchical schema
- **Catch:** requires `sibyl init` which opens a browser for account activation. Free tier exists but has a local cap.
- MCP server available for non-Hermes agents (Claude Code, Codex, etc.)
- Install: `pip install sibyl-memory-hermes && sibyl-memory-hermes install-plugin`

### LanceDB Plugin (2★)

From LanceDB (the Lance columnar format team). Official Hermes plugin.

- Vector ANN over OpenAI embeddings (default `text-embedding-3-small`)
- Optional hybrid mode (vector + BM25, fused via RRF/linear/cross-encoder)
- Workspace isolation per `agent_workspace` tag
- Auto-compaction + mid-session fact extraction
- Cross-encoder reranker needs `sentence-transformers` (~2 GB torch)

## Not Memory Provider Plugins

These appeared in search results but are NOT `MemoryProvider` plugins:

| Repo | What it actually is |
|------|---------------------|
| botfredthebot/hermes-plugin-honcho-dashboard | Dashboard UI for Honcho memory (not a provider) |
| henqky/hermes-honcho-dashboard | Same — Honcho explorer dashboard |
| venturecrane/hermes-smd-overlay | Plugin overlay (audit, voice, mirroring — not memory) |
| sea-monsters/mem-reflection-hermes | Memory-reflection enhancement loop (not a provider) |
| ryonakae/hermes-self-improvement | DSPy/GEPA self-improvement plugin (not memory) |

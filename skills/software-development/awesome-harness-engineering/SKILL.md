---
name: awesome-harness-engineering
description: "Curated knowledge base on AI agent Harness Engineering — context delivery, tool design, MCP, memory, agent loops, planning artifacts, permissions, verification, and observability. Indexed and searchable via context-mode. Includes templates for PLAN.md, IMPLEMENT.md, AGENTS.md, and HARNESS_CHECKLIST.md."
version: "1.0.0"
---

# Awesome Harness Engineering

**Repo:** <https://github.com/ai-boost/awesome-harness-engineering>
**Local clone:** `/root/workspace/awesome-harness-engineering`
**Indexed in context-mode:** source=`"awesome-harness-engineering"`

This is a curated awesome-list covering every facet of **harness engineering** — the discipline of designing the scaffolding around AI agents: context delivery, tool interfaces, planning artifacts, verification loops, memory systems, and sandboxes.

Hermes Agent is itself an agent harness. This knowledge base helps answer design questions, reference best practices, and apply research-backed patterns.

## When to load this skill

- The user asks about harness engineering concepts (agent loop, context compaction, tool design, MCP, etc.)
- The user asks for references on how to design/improve a harness component
- You need template artifacts for planning (PLAN.md, IMPLEMENT.md, AGENTS.md)
- The user asks about integrating MCP servers, skills, permissions, or verification into an agent
- You're designing or debugging Hermes itself and want reference patterns

## How to use

### 1. Semantic search (context-mode)

The full README is indexed as 48 sections. To find relevant content:

```python
# Search for specific topics
ctx_search(queries=["context compaction", "tool design patterns", "agent loop architecture", "MCP integration", "permissions sandbox"], source="awesome-harness-engineering")
```

### 2. Browse sections locally

```bash
# View the indexed sections
cd /root/workspace/awesome-harness-engineering

# Full README has these major sections:
# - Foundations (canonical essays)
# - Agent Loop
# - Planning & Task Decomposition
# - Context Delivery & Compaction
# - Tool Design
# - Skills & MCP
# - Permissions & Authorization
# - Memory & State
# - Task Runners & Orchestration
# - Verification & CI Integration
# - Observability & Tracing
# - Debugging & Developer Experience
# - Human-in-the-Loop
# - Security, Sandbox & Permissions
# - Evals & Verification

less README.md
```

### 3. Use the templates

The repo provides 4 reusable templates:

| Template | Purpose | Path |
|----------|---------|------|
| `AGENTS.md` | Project-level agent instructions | `templates/AGENTS.md` |
| `PLAN.md` | Task planning artifact with milestones, scope, risks | `templates/PLAN.md` |
| `IMPLEMENT.md` | Implementation log (append-only decisions) | `templates/IMPLEMENT.md` |
| `HARNESS_CHECKLIST.md` | Pre-shipping harness review checklist | `templates/HARNESS_CHECKLIST.md` |

To use a template: `cat /root/workspace/awesome-harness-engineering/templates/<NAME>.md` and adapt.

### 4. Subscribe to updates

The repo is actively maintained (last commit May 30, 2026). To stay current, re-clone periodically:

```bash
cd /root/workspace/awesome-harness-engineering && git pull
```

Then re-index: `ctx_fetch_and_index(url="https://raw.githubusercontent.com/ai-boost/awesome-harness-engineering/main/README.md", source="awesome-harness-engineering", force=true)`

## Key Hermes-relevant sections

For Hermes development specifically, these sections are most relevant:

- **Skills & MCP** — References for the Hermes skills system, MCP client, and skill authoring
- **Context Delivery & Compaction** — How Hermes manages its context window across long sessions
- **Tool Design** — Guidelines for writing effective tools (matches Hermes tool schema patterns)
- **Memory & State** — References for persistent memory, session recall
- **Permissions & Authorization** — Patterns for agent permission systems
- **Agent Loop** — How the observe-plan-act-verify loop works (core Hermes architecture)
- **Verification & CI Integration** — Testing and eval patterns

## References

- `readme` — Full README: `/root/workspace/awesome-harness-engineering/README.md`
- `repo` — GitHub: <https://github.com/ai-boost/awesome-harness-engineering>
- `context-mode` — Search with `ctx_search(source="awesome-harness-engineering")`

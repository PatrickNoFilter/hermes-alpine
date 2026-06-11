---
name: building-ai-from-scratch
category: mlops
description: Implement AI/ML concepts from scratch following a structured curriculum. Build a branded Python package where each lesson adds new capabilities — from vectors to transformers to agents.
---

# Building AI From Scratch

> Every AI model is just matrix math wearing a fancy hat.

## When to Use

- User wants to build AI/ML concepts from the ground up — not just use libraries
- User is following a structured curriculum (e.g., `rohitg00/ai-engineering-from-scratch`)
- User wants to name and brand their own custom AI implementation
- User has PRoot/ARM64/CPU-only hardware and needs feasibility assessment

## Approach

The curriculum follows a **"Build It → Use It → Ship It"** spine:
1. **Build It** — implement every concept from raw Python (no frameworks)
2. **Use It** — show the same operation via production libraries (NumPy, PyTorch)
3. **Ship It** — produce a reusable artifact (prompt, skill, agent, MCP server)

Your project follows the same spine but branded under the user's chosen name.

## Project Structure

```
/path/to/brand/
├── brand/                    # Python package (your AI library)
│   ├── __init__.py
│   ├── linalg.py             # Phase 1: Linear Algebra
│   ├── ml.py                 # Phase 2: ML Fundamentals
│   ├── nn.py                 # Phase 3: Deep Learning Core
│   ├── vision.py             # Phase 4: Computer Vision
│   ├── nlp.py                # Phase 5: NLP
│   ├── transformer.py        # Phase 10: LLMs from Scratch
│   ├── agent.py              # Phase 14: Agent Engineering
│   └── ...
├── tests/
│   └── test_*.py             # 5+ tests per lesson (unittest)
├── notebooks/                # Jupyter exploration
└── demo_*.py                 # Full walkthrough per module
```

## Setup Steps

```bash
# 1. Clone curriculum
git clone https://github.com/rohitg00/ai-engineering-from-scratch.git

# 2. Create branded package
mkdir -p brand/{brand,tests,notebooks}
touch brand/brand/__init__.py
```

Only dependency needed at start: Python 3.10+ stdlib. NumPy/PyTorch arrive in later phases for the "Use It" layer.

## Phase → Module Mapping (for `ai-engineering-from-scratch`)

| Phase | Module | Key Concepts |
|-------|--------|-------------|
| 1 — Math | `linalg.py` | Vectors, matrices, dot product, projection, rank, Gram-Schmidt, SVD |
| 2 — ML | `ml.py` | Regression, trees, SVMs, KNN, K-Means, feature engineering, ensembles |
| 3 — Deep Learning | `nn.py` | Perceptron, backprop, activations, loss, optimizers, regularization |
| 4 — Vision | `vision.py` | Convolutions, CNNs, VLM concepts |
| 5 — NLP | `nlp.py` | Tokenization (BPE/WordPiece), Word2Vec, Seq2Seq, embedding, chunking |
| 7 — Transformers | `transformer.py` | Self-attention, multi-head, RoPE, KV cache, MoE, spec decode |
| 10 — LLMs | `transformer.py` (extend) | Pre-training (124M), SFT, RLHF/DPO, quantization (GGUF/GPTQ) |
| 11 — LLM Engineering | (separate or extend) | RAG, LoRA/QLoRA, function calling, MCP, LangGraph |
| 14 — Agents | `agent.py` | ReWOO, Reflexion, ToT, memory, multi-agent loops |

## Implementation Pattern

Each lesson follows this template:

```python
# === BUILD IT: from scratch ===
class Vector:
    def dot(self, other):
        return sum(a*b for a,b in zip(self.components, other.components))
    # ... no imports except math/random

# === USE IT: framework comparison ===
# import numpy as np
# np.dot(a, b)  # same operation, production-ready
```

Write the from-scratch version before showing the framework version. This ensures the user understands what the framework abstracts.

## Testing Pattern

- 5+ unit tests per lesson minimum
- Use `unittest.TestCase` (no pytest dependency needed early on)
- Test edge cases: zero vectors, perpendicular vectors, rank-deficient matrices
- Run: `python3 -m unittest discover tests -v`

## ARM64 / PRoot Notes

This curriculum runs well on PRoot Ubuntu (Galaxy A33, 8GB RAM) for phases 1-3 and concept learning in phases 4-10. Limitations:
- **No GPU**: CNNs, diffusion, and LLM pre-training are educational only (tiny batch sizes, long runtime)
- **Docker**: not available in PRoot — skip P0 Docker exercises
- **vLLM/SGLang**: GPU-only — learn concepts, deploy to cloud
- **RAM cap (8GB)**: 3B-7B GGUF models fit for inference; 13B+ is impractical

## Pitfalls

- **Don't install all dependencies upfront.** The curriculum is stdlib-first. Only install numpy/torch when a lesson explicitly reaches the "Use It" layer.
- **Don't skip tests.** The "5+ tests per lesson" rule catches implementation bugs that would compound across phases.
- **Don't use frameworks in the "Build It" layer.** The whole point is understanding what the framework does under the hood. A `linalg.py` that imports numpy defeats the purpose.
- **Don't cargo-cult from the repo.** Implement the concepts yourself with the user's branding. The repo is guidance, not copy-paste source.
- **On PRoot, prefer `python3` over `python`** — symlinks may not point where expected.
- **Don't use `execute_code` for filesystem traversal on slow storage.** The `find` command times out at 10s in this environment. Use `terminal()` with explicit `timeout=` instead, or break large traversals into targeted per-file checks.
- **Don't batch >3 `delegate_task` calls at once.** `max_concurrent_children = 3` is the hard limit. Batch large parallel workloads (e.g. 11 Phase 1 lessons) into groups of 3. The subagent context must include ALL required file paths — subagents have no memory of prior calls.

## Verification

After each lesson:
1. Run tests: `python3 -m unittest discover tests/ -v` — all green
2. Run demo: `python3 demo_*.py` — verify output matches expected math
3. Save phase progress in memory so next session picks up correctly

## Session Continuity

Current project state is tracked in `references/anggira-journey.md` — always load it at session start before resuming the build. It records:
- Which lessons are complete / in-progress / pending per phase
- Exact module names and file paths
- Delegation batch size limits (≤3 concurrent subagents)
- Hardware context (Galaxy A33, 8GB, PRoot, ARM64)

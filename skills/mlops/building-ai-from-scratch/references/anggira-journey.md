# Anggira — Project Journal

## Project
- **Name:** Anggira
- **Root:** `/root/anggira/`
- **Curriculum:** `https://github.com/rohitg00/ai-engineering-from-scratch` (cloned to `/root/ai-engineering-from-scratch/`)
- **Package:** `anggira` — Python package implementing AI from scratch

## Progress

### Phase 1 — Math Foundations (L1–L22)
| Lesson | Topic | Status |
|--------|-------|--------|
| L1 | Linear Algebra Intuition | ✅ `linalg.py` — 37 tests green |
| L2–L5 | (intermediate math lessons) | ✅ Done |
| L6–L9 | probability, bayes, optim, information | 🔄 In progress (L6–L9) |
| L10–L14 | reduce, svd, tensors, numeric, norms | 📋 Pending |
| L15–L22 | stats, sampling, linsys, convex, complex, fourier, graph, stochastic | 📋 Pending |

### Phase 2 — ML Fundamentals (L1–L18) | 📋 Pending
### Phase 3 — Deep Learning (L1–L13) | 📋 Pending
### Phase 4 — Vision (L1–L20) | 📋 Pending
### Phase 5 — NLP (L1–L21) | 📋 Pending
### Phase 6–8 — Speech, Transformers, GenAI (L1–L48) | 📋 Pending
### Phase 9–12 — RL, LLMs from scratch, LLM Engineering, Multimodal (L1–L68) | 📋 Pending
### Phase 13–19 — Tools, Agents, Multi-agent, Infra, Ethics, Capstones (L1–L215) | 📋 Pending

## Anggira Package Structure

```
/root/anggira/
├── anggira/              # Python package (build layer)
│   ├── __init__.py
│   ├── linalg.py         # L1 — vectors, matrices, gram-schmidt, dot, cross
│   ├── probability.py    # L6 — combinatorics, distributions, Bayes
│   ├── bayes.py          # L7 — naive bayes, bayesian inference
│   ├── optim.py          # L8 — gradient descent, newton, line search
│   ├── information.py    # L9 — entropy, KL div, mutual information
│   ├── reduce.py         # L10 — PCA, kernel PCA, LDA
│   ├── svd.py            # L11 — SVD
│   ├── tensors.py        # L12 — tensor ops, einsum, broadcasting
│   ├── numeric.py        # L13 — stable softmax, logsumexp, cross-ent
│   ├── norms.py          # L14 — L1/L2/Lp norms, cosine, mahalanobis
│   ├── stats.py          # L15 — mean, median, t-test, bootstrap CI
│   ├── sampling.py       # L16 — inverse CDF, MCMC, metropolis-hastings
│   ├── linsys.py          # L17 — gaussian elim, LU, cholesky, CG
│   ├── convex.py          # L18 — convexity, GD, newton, barrier
│   ├── complex.py         # L19 — complex arithmetic, polar, euler
│   ├── fourier.py         # L20 — DFT, FFT from scratch
│   ├── graph.py           # L21 — BFS, DFS, dijkstra, bellman-ford
│   └── stochastic.py      # L22 — random walk, markov chain, MCMC
└── tests/
    ├── test_linalg.py
    ├── test_probability.py
    └── ...               # one test_*.py per module, 5+ tests each
```

## Conventions

- **From-scratch layer**: pure Python stdlib (`math`, `random`, `statistics`). No numpy in Phase 1–3.
- **Test framework**: `unittest.TestCase` — run with `python3 -m unittest discover tests/ -v`
- **Module name convention**: lesson content, not lesson number (e.g. `reduce.py` not `l10.py`)
- **Test name convention**: `test_<module>.py` (e.g. `test_reduce.py`)
- **Assertion pattern**: `assert abs(value - expected) < 1e-6` for floats
- **Docstring brand**: "anggira" in all module docstrings
- **Batch delegation**: max 3 concurrent subagents. For 11 tasks → 4 delegate_task calls with 3+2+3+3 tasks.
- **Filesystem operations**: use `terminal(timeout=30)` on slow PRoot storage, NOT `execute_code`
- **Test all modules**: `cd /root/anggira && python3 -m unittest discover tests/ -v 2>&1 | tail -50`

## Hardware Context
- Samsung Galaxy A33 (8GB RAM)
- PRoot Ubuntu on Termux, ARM64, no GPU
- Python 3.10+ stdlib primary
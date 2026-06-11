# `_ensure_uv_for_termux` Rust Compile Timeout

## The Problem

`_ensure_uv_for_termux()` in `hermes_cli/main.py` runs `pip install uv` as a fallback when managed uv installation fails on Termux.

**Problem**: On ARM64 (the architecture of most Android phones running Termux), there is **no prebuilt uv wheel** on PyPI. pip falls back to source distribution → `cargo build --release` → compiles uv's entire Rust codebase: jemalloc, OpenSSL, zstd-sys, and ~100K lines of Rust. On a phone with 7-8GB RAM this exhausts swap and freezes the machine.

## Discovery

Reported in upstream issues:
- **#39118**: "_ensure_uv_for_termux triggers Rust source compile — should use prebuilt binary or skip" — explicitly documents the cargo build problem on Pixel 8a
- **#39411**: "[Bug]: fail to build wheel for uv during hermes update in termux" — user reports 100% reproduction rate

Both issues had 0 comments when discovered on 2026-06-06.

## The Fix

Added `timeout=120` to the `subprocess.run(pip_cmd + ["install", "uv"], ...)` call in `_ensure_uv_for_termux()`:

```python
subprocess.run(
    pip_cmd + ["install", "uv"],
    cwd=PROJECT_ROOT,
    check=False,
    timeout=120,
)
except subprocess.TimeoutExpired:
    print("    ↻ uv install timed out (Rust compile on ARM64 is too slow) — falling back to pip")
```

On timeout, the function returns `None`, which causes `_cmd_update_impl()` to fall back to the pip-only dependency install path — slower but reliable.

## Commit

This fix is now one of the four components of **PR [#40377](https://github.com/NousResearch/hermes-agent/pull/40377)** (commits `acd4fa3` and `3a50081` for the timeout specifically). PR #40377 also implements the other three Termux/PRoot fixes from issue #40328: `_is_proot_env` helper, `UV_LINK_MODE=copy` auto-injection, `no_build_isolation` parameter, and `more_itertools` in `build-system.requires`.

## Reproduction

The issue is deterministic on any ARM64 Termux with:
1. No pre-existing `uv` binary
2. `hermes update` invoked (which calls `_ensure_uv_for_termux` before the fallback path)
3. Python 3.x on a phone-class device

## Related

The `UV_NO_BUILD_ISOLATION=1` env var (also in PR #40377) prevents a related build-isolation failure — on PRoot, temporary build directories can cross mount points, breaking the uv build sandbox for *any* pip install.

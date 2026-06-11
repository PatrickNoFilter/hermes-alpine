---
name: update-hermes-termux
description: Update Hermes Agent on Termux/PRoot (ARM64) — bypassing hardlink and build-isolation failures.
---

# Update Hermes Agent on Termux/PRoot

## Problem

`hermes update` fails in Termux/PRoot because:
1. **Hardlinks** fail across PRoot filesystem boundaries → set `UV_LINK_MODE=copy`
2. **Build isolation** fails — setuptools 81+/82+ has missing transitive deps (`more_itertools`, `jaraco-util`) in the uv build sandbox → `UV_NO_BUILD_ISOLATION=1`
3. **Missing build deps** in pyproject.toml `build-system.requires`
4. **Rust compile freeze** — `_ensure_uv_for_termux()` runs `pip install uv`, but on ARM64 no prebuilt wheel exists, triggering `cargo build --release` of uv's entire Rust codebase (jemalloc, OpenSSL, zstd-sys, ~100K lines). On 7-8GB RAM phones this exhausts swap and freezes the machine. Fix: timeout=120 on the pip subprocess so it fails gracefully and falls back to pip.
5. **Forced Electron desktop rebuild** — `hermes update` runs `hermes desktop --build-only` if desktop build artifacts exist (`desktop-build-stamp.json` + `apps/desktop/release/`). On PRoot/ARM64 this is a ~150MB Electron build that takes forever and wastes resources. No config option to skip. Fix: remove desktop artifacts (`rm -f ~/.hermes/desktop-build-stamp.json && rm -rf apps/desktop/release/ apps/desktop/dist/`). See `references/desktop-rebuild-on-update.md`.

## Preferred fix (upstream PRs)

**PR [#40377](https://github.com/NousResearch/hermes-agent/pull/40377)** by @PatrickNoFilter — **more comprehensive approach (preferred)**. After a refactor based on direct reading of issue #40328's spec, it implements all three fixes the issue proposed, in the architecture the issue specified:

- **`_is_proot_env()` helper** detecting `PROOT` env var, `PROOT_TMP_DIR`, and `/proc/self/exe` symlink target
- **Auto-set `UV_LINK_MODE=copy`** when Termux/PRoot is detected and the user hasn't set it — placed inside the shared `_install_python_dependencies_with_optional_fallback()` helper, NOT in `_cmd_update_impl` (so the install path AND pip fallback also benefit)
- **New `no_build_isolation: bool = False` parameter** on `_install_python_dependencies_with_optional_fallback()` that appends `--no-build-isolation` to every install command. Threads through to `_verify_core_dependencies_installed()` for both repair attempts.
- **`more_itertools>=10.0` declared in `pyproject.toml`'s `[build-system] requires`** — the actual root cause of `setuptools>=81` build failures (the transitive is imported at build time by `setup.py` via `jaraco.util` but was missing from the build-system declaration)
- **`timeout=120`** on `subprocess.run(pip_cmd + ["install", "uv"])` in `_ensure_uv_for_termux()` to prevent Rust compile freeze on ARM64 phones
- **7 unit tests** covering `_is_proot_env`, `UV_LINK_MODE` auto-set, user-override preservation, `no_build_isolation` flag

**PR [#40335](https://github.com/NousResearch/hermes-agent/pull/40335)** by @liuhao1024 — **now a strict subset**. It only does the `UV_LINK_MODE=copy` part (A) using env-var hacks in `_cmd_update_impl` only. Once #40377 lands, #40335 is subsumed.

**Related upstream issues**: #39118 (Rust compile), #39411 (wheel build fail)
**Complementary PRs (zip update path, no overlap)**: #39208, #39135

To check if #40377 has been merged:
```bash
git -C /usr/local/lib/hermes-agent merge-base --is-ancestor 42d51c3 HEAD
echo "Upstream fix #40377 merged: $? (0=yes, 1=no)"
```

Until #40377 lands, use the workaround below.

### Workflow lesson: read the issue's "Proposed Fixes" section verbatim

When an issue body enumerates specific fixes (A, B, C…) with their target function names and parameters, **implement all of them in the locations it specifies** — don't reinvent the architecture from the symptom. The first iteration of PR #40377 only implemented fix A in a caller function with env-var hacks; the user had to point out that the issue's spec called for (a) placing the env-var injection in `_install_python_dependencies_with_optional_fallback()`, (b) a `no_build_isolation` PARAMETER (not env var), and (c) a `pyproject.toml` `build-system.requires` change that the first iteration missed entirely. Catching the misalignment early avoids a duplicate-PR situation where another contributor ships a partial fix.

## Workaround (until PR merged)

### Quick fix (run after every `hermes update`)

```bash
bash ~/.hermes/scripts/post-update-termux.sh
```

### Permanent env vars (already applied)

These survive `git pull` because they live in the environment, not the source tree:

```bash
export UV_LINK_MODE=copy
export UV_NO_BUILD_ISOLATION=1
```

Also set in `~/.hermes/.env` for subprocesses.

### Source patches (re-applied by post-update script)

1. **`pyproject.toml`** — `build-system.requires` adds `more_itertools>=10.0`
2. **`hermes_cli/main.py`** — Termux detection path:
   - Adds `_is_proot_env()` helper next to `_is_termux_env()`
   - `_install_python_dependencies_with_optional_fallback()` gets:
     - Auto-injection of `UV_LINK_MODE=copy` when `_is_termux_env(env) or _is_proot_env(env)` and the user hasn't set it
     - New `no_build_isolation: bool = False` parameter that appends `--no-build-isolation` to every install command (including the verify+repair attempts inside `_verify_core_dependencies_installed`)
   - `_cmd_update_impl()` calls the helper with `no_build_isolation=True` when Termux is detected
   - `_ensure_uv_for_termux()` gets `timeout=120` on the `pip install uv` subprocess to prevent Rust compile freeze

### Manual update procedure (if script fails)

```bash
cd /usr/local/lib/hermes-agent

# Fetch latest
git fetch origin
git pull --ff-only origin main || git reset --hard origin/main

# Pin setuptools + install build deps
UV_LINK_MODE=copy VIRTUAL_ENV=venv uv pip install 'setuptools<82' jaraco-util more_itertools

# Reinstall Hermes
UV_LINK_MODE=copy VIRTUAL_ENV=venv uv pip install -e .
```

## References

- `references/verification-and-troubleshooting.md` — Post-update health checks, common PRoot build errors, and full verification commands.
- `references/ensure-uv-rust-compile-timeout.md` — `_ensure_uv_for_termux` Rust compile freeze: root cause, detection, timeout fix, and related upstream issues.
- `references/desktop-rebuild-on-update.md` — Desktop Electron rebuild forced on every update when artifacts exist; workaround and proposed fix.

## Pitfalls

- **Do NOT** run `hermes update` directly without running post-update script afterward (git pull reverts source patches) — unless PR #40377 has already been merged upstream
- **Rust compile freeze**: If uv isn't already installed, `_ensure_uv_for_termux` runs `pip install uv`. On ARM64 Termux this triggers `cargo build --release` — the entire uv Rust codebase compiles from source. On phones, this exhausts swap and freezes the machine. **Pre-condition**: ensure uv is installed before `hermes update`, or set `UV_LINK_MODE=copy` and `UV_NO_BUILD_ISOLATION=1` and use pip-only fallback.
- **Architectural pitfall — fix the SHARED helper, not the caller**: When implementing Termux-style env-var auto-injection or build-isolation flags, place the change inside `_install_python_dependencies_with_optional_fallback()` (or equivalent shared install helper), NOT in the per-caller function (`_cmd_update_impl`, `_update_via_zip`, etc.). Reasoning: (1) the install path is a different entry point that needs the same protection, (2) the pip fallback path (no uv) also needs the same flags, (3) downstream `_verify_core_dependencies_installed()` repair attempts also need them, (4) threading a `no_build_isolation` PARAMETER (not env var) is the cleanest way to cascade the flag through every nested call. The first iteration of the upstream fix put the env vars in `_cmd_update_impl` only — when an issue spec names a specific helper, trust it.
- **Setuptools>=81 build isolation** requires transitives (`more_itertools`, `jaraco.util`) to be declared in `pyproject.toml`'s `[build-system] requires` — the isolated build venv doesn't see the project venv. Setting `--no-build-isolation` works around it but the proper fix is declaring the deps so non-isolated and isolated builds both work.
- Python 3.11 only (venv); Hermes upstream uses 3.11
- uv resolves setuptools from PyPI during build isolation — pinning to <82 avoids the broken 82.x line
- **Desktop Electron rebuild on PRoot**: If `~/.hermes/desktop-build-stamp.json` or `apps/desktop/release/` exist, `hermes update` triggers a full Electron rebuild (`hermes desktop --build-only`) on every update. This is extremely slow on ARM64 PRoot and wastes resources. There is NO config option to skip it. **Remove the artifacts** before updating: `rm -f ~/.hermes/desktop-build-stamp.json && rm -rf apps/desktop/release/ apps/desktop/dist/`. The node-deps step already correctly skips the desktop workspace (`--workspace ui-tui --workspace web`), but the desktop rebuild block at line 10742 only checks `has_desktop_app`. Propose an issue for `updates.skip_desktop_rebuild: true` or auto-detection of headless/PRoot environments.

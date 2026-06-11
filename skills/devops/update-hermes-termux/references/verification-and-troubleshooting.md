# Post-Update Verification & Troubleshooting

## Quick Health Check

```bash
hermes --version
# Expected: "Hermes Agent v0.16.0 (2026.6.5) · upstream <sha> ... Up to date"

hermes config list 2>/dev/null | head -5
# Should show config, not crash

ls /usr/local/lib/hermes-agent/hermes_cli/main.py
# Should exist after reinstall
```

## Verify Env Vars Are Active

```bash
echo "UV_LINK_MODE=$UV_LINK_MODE"
echo "UV_NO_BUILD_ISOLATION=$UV_NO_BUILD_ISOLATION"
# Both should print "copy" / "1"
# If empty: check ~/.bashrc and ~/.hermes/.env
```

## Verify Build Dependencies

```bash
cd /usr/local/lib/hermes-agent
VIRTUAL_ENV=venv uv pip list 2>/dev/null | grep -E "setuptools|more_itertools|jaraco"
# Expected: setuptools <82, more_itertools >=11, jaraco-util >=15
```

## Patch Verification (workaround)

Until PR #40377 is merged, check patches:

```bash
# Check _is_proot_env helper exists
grep -n "def _is_proot_env" /usr/local/lib/hermes-agent/hermes_cli/main.py

# Check UV_LINK_MODE auto-injection in the shared helper (NOT just _cmd_update_impl)
grep -n "UV_LINK_MODE" /usr/local/lib/hermes-agent/hermes_cli/main.py | head -5

# Check no_build_isolation parameter on the shared helper
grep -n "no_build_isolation" /usr/local/lib/hermes-agent/hermes_cli/main.py | head -5

# Check timeout=120 in _ensure_uv_for_termux
grep -n "timeout=120" /usr/local/lib/hermes-agent/hermes_cli/main.py

# Check more_itertools in build-system.requires
grep "more_itertools" /usr/local/lib/hermes-agent/pyproject.toml
```

## Upstream PR Check

Check if PR #40377 (the permanent fix) has been merged:

```bash
git -C /usr/local/lib/hermes-agent merge-base --is-ancestor 42d51c3 HEAD
echo "Upstream fix #40377 merged: $? (0=yes → workaround no longer needed)"
```

Once merged, the `_is_proot_env`, `UV_LINK_MODE` auto-injection, `no_build_isolation` parameter, and `more_itertools` greps above are expected to return matches from the upstream code itself — this confirms the fix is native, not patched.

## If `hermes update` Fails After Git Pull

Symptoms:
- `hermes update` exits with code 1
- Error mentions `OSError: [Errno 18] Invalid cross-device link`
- Error mentions `jaraco.text`, `more_itertools` not found during build

### Recovery

```bash
# 1. Source the env vars (if shell didn't source ~/.bashrc)
export UV_LINK_MODE=copy
export UV_NO_BUILD_ISOLATION=1

# 2. Re-apply source patches (the three from PR #40377):
#    a) Add more_itertools to build-system.requires
sed -i 's|"setuptools>=77.0,<83"|"setuptools>=77.0,<83", "more_itertools>=10.0"|' \
  /usr/local/lib/hermes-agent/pyproject.toml

#    b) Add _is_proot_env helper (full snippet) and the
#       no_build_isolation parameter on _install_python_dependencies_with_optional_fallback
#       (best done via re-running the post-update script, see below)

# Or run the post-update script
bash ~/.hermes/scripts/post-update-termux.sh
```

## Common PRoot Errors During Build

| Error | Cause | Fix |
|-------|-------|-----|
| `Invalid cross-device link` | PRoot can't hardlink across filesystem boundaries | `export UV_LINK_MODE=copy` |
| `ModuleNotFoundError: jaraco.text` | setuptools 82+ missing transitive dep in build isolation | `export UV_NO_BUILD_ISOLATION=1` |
| `No matching distribution found for more_itertools` | Missing from `build-system.requires` | Re-add to pyproject.toml |
| `Building wheel for uv (pyproject.toml) ...  //  cargo build --release ...  //  Killed (9)` | `_ensure_uv_for_termux` triggers Rust compile on ARM64 with no prebuilt wheel; OOM kills cargo | timeout=120 in subprocess.run, or pre-install uv via `pkg install uv` before `hermes update` |

## Verifying the Full Update Cycle

To test that `hermes update` will work on the next real update:

```bash
cd /usr/local/lib/hermes-agent
export UV_LINK_MODE=copy
export UV_NO_BUILD_ISOLATION=1
VIRTUAL_ENV=venv uv pip install -e . 2>&1 | tail -5
echo "Exit code: $?"
```

Exit code 0 with "Successfully installed hermes-agent" = ready for next update.

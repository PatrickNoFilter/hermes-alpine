# Desktop Electron Rebuild During `hermes update` on PRoot

## Root Cause

`_cmd_update_impl()` in `hermes_cli/main.py` (line ~10740) unconditionally
runs `hermes desktop --build-only` when ALL of these are true:

1. `apps/desktop/package.json` exists (always true in git checkout)
2. `npm` is on PATH
3. `has_desktop_app` is True — determined by `_desktop_packaged_executable(desktop_dir) is not None or _desktop_dist_exists(desktop_dir)`

The `has_desktop_app` check looks for:
- `apps/desktop/release/linux-arm64-unpacked/` (or similar platform dir)
- `~/.hermes/desktop-build-stamp.json`

Once built once, every subsequent `hermes update` triggers a full Electron rebuild
because the content hash changes when source files are pulled.

## What Skips Desktop (and What Doesn't)

| Update step | Desktop involved? | Code location |
|---|---|---|
| `npm install` (node deps) | **Skipped** | `_update_node_dependencies()` — uses `--workspace ui-tui --workspace web` |
| Desktop rebuild | **Forced if artifacts exist** | `_cmd_update_impl()` line 10742 |
| Web UI build | **Yes but not desktop** | `_build_web_ui()` — scoped to `--workspace web` |

## Fix (Workaround)

Remove desktop build artifacts before running `hermes update`:

```bash
rm -f ~/.hermes/desktop-build-stamp.json
rm -rf /usr/local/lib/hermes-agent/apps/desktop/release/
rm -rf /usr/local/lib/hermes-agent/apps/desktop/dist/
```

This makes `has_desktop_app = False` → desktop rebuild is skipped.

## Proposed Upstream Fix

Add a config option `updates.skip_desktop_rebuild: true` or auto-detect
headless/PRoot environments. The guard at line 10742 should also check
for `_is_proot_env()` or `_is_termux_env()` (from PR #40377) and skip
the rebuild when detected.

Alternatively, add `--skip-desktop` flag to `hermes update`.

## Related Code

- `_cmd_update_impl()` — main update flow (line 10279)
- `_desktop_build_needed()` — checks content hash (line 7276)
- `_desktop_packaged_executable()` — finds packaged binary
- `_desktop_dist_exists()` — checks dist/ directory
- `_desktop_stamp_path()` → `~/.hermes/desktop-build-stamp.json`
- `_update_node_dependencies()` — correctly skips desktop workspace (line 9578)

## Detection

Check if desktop artifacts exist:
```bash
ls ~/.hermes/desktop-build-stamp.json 2>/dev/null && echo "Desktop rebuild WILL trigger on next update"
ls /usr/local/lib/hermes-agent/apps/desktop/release/ 2>/dev/null && echo "Desktop dist exists"
```

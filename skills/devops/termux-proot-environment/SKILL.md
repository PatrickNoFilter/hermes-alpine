---
name: termux-proot-environment
description: "Know-how for running Linux distributions inside PRoot on Termux for Android — accessing host Android shared storage, system services, and Termux tools from within a PRoot container."
category: devops
triggers:
  - "How do I access Android files from PRoot?"
  - "Can I run Android tools inside PRoot?"
  - "termux-setup-storage"
  - "proot-distro bind mount"
  - "Android APK access from Linux"
  - "numpy scipy networkx install Termux ARM64"
  - "apt Python packages PRoot"
  - "SuperLocalMemory Termux"
  - "cross-version PYTHONPATH bridging"
  - "embedding worker ARM64 constrained"
---

# Termux PRoot Environment

Know-how for running Linux (Ubuntu, Debian, etc.) inside PRoot via Termux on Android, and bridging to the host Android system.

## When to use this skill

- User wants to access Android shared storage (`/sdcard`) from within PRoot
- User asks about running/managing Android apps from PRoot
- User needs Termux binaries (termux-open, termux-notification, etc.) inside PRoot
- Investigating what Android system tools work under PRoot isolation
- Setting up a persistent PRoot environment on a Samsung Galaxy or similar Android device

## Key concepts

### PRoot and Android
PRoot is a user-space chroot — it uses ptrace to translate paths, NOT real kernel namespaces. This means:
- You run as the **Termux app's UID** on Android, not real root (despite `whoami` showing root inside PRoot)
- `/proc/mounts` shows **real Android kernel mounts**, even if PRoot doesn't expose the directories
- SELinux still applies — many Android paths are gated behind permissions the Termux UID doesn't have
- `mount --bind` does NOT work inside PRoot (no `CAP_SYS_ADMIN` at the kernel level)

### PRoot-distro bind mounts
`proot-distro` does NOT expose `/sdcard` by default. You must bind it explicitly.

## Steps

### 1. Grant Android storage permissions (Termux, one time)
```bash
termux-setup-storage
# Creates ~/storage/{shared, downloads, dcim, music, pictures, movies}
```

### 2. Start PRoot with bind mounts
```bash
proot-distro login ubuntu \
  --bind /sdcard:/sdcard \
  --bind /storage:/storage
```

For access to Termux binaries from PRoot:
```bash
proot-distro login ubuntu \
  --bind /sdcard:/sdcard \
  --bind /storage:/storage \
  --bind /data/data/com.termux/files/usr/bin:/termux-bin
```
Then inside PRoot: `/termux-bin/termux-open https://...`

### 3. Make bind mounts permanent
Edit `~/.proot-distro/proot-distro.conf` in Termux:
```ini
PROOT_DISTRO_BINDINGS="/sdcard:/sdcard /storage:/storage"
```

Or per-distro config at `~/.proot-distro/<distro>/<distro>.conf`.

### 4. Create a startup script
Save as `~/start-ubuntu.sh` in Termux:
```bash
#!/data/data/com.termux/files/usr/bin/bash
termux-wake-lock
proot-distro login ubuntu \
  --bind /sdcard:/sdcard \
  --bind /storage:/storage \
  --bind /data/data/com.termux/files/usr/bin:/termux-bin
```

## Android tools inside PRoot

| Tool | Status | Notes |
|------|--------|-------|
| `dumpsys` | ✅ Works | Can query battery, wifi, meminfo, services |
| `service list` | ✅ Works | Lists 300+ Android services |
| `service call` | ✅ Works | But permission-denied for most privileged calls |
| `service check` | ✅ Works | Check if a named service is running |
| `am` (Activity Manager) | ❌ Fails | `SecurityException: INTERACT_ACROSS_USERS_FULL` on non-rooted Android 14+. Previous linker-config failure may no longer be the blocker on newer devices. |
| `pm` (Package Manager) | ✅ Works | `pm list packages`, `pm path <pkg>`, `pm list features` all work. `pm grant` / `pm dump` fail — need GRANT_RUNTIME_PERMISSIONS / DUMP permission (app UID limitation). |
| `content` (Content Provider) | ❌ Fails | Needs `app_process` — Android Java runtime linker not configured |
| `cmd` | ⚠️ Partial | `cmd package` subcommands that use `pm` may work; others fail with `INTERACT_ACROSS_USERS` |
| ADB (TCP) | ❌ Not listening | ADB daemon runs on USB transport, not TCP on device-local connections |
| binder (/dev/binder) | ✅ Accessible | Symlink to /dev/binderfs works, but no Java framework to use it |

### UID context
Inside PRoot on Termux, `id` shows:
```
uid=0(root) gid=0(root) groups=...,21265(aid_u0_a1265_cache),51265(aid_all_a1265)
```
Despite uid=0, you run as the Termux app's UID at the Android kernel level. SELinux and Android permission checks (like `android.permission.DUMP`) still apply with your real app UID (e.g., `uid=11265`). Many `dumpsys` subcommands will fail with `Permission Denial`.

## Verification

```bash
# Check if /sdcard is accessible
ls /sdcard/Download/

# Check if Android tools work
/system/bin/service list | head -5
/system/bin/dumpsys battery | grep "level"

# Check current UID context
id
cat /proc/self/status | grep -E '^Uid|^Gid'

# See real Android mount points (even if PRoot hides them)
cat /proc/mounts | grep -E 'sdcard|emulated|fuse'
```

## Pitfalls

- **`mount --bind` inside PRoot does NOT work.** PRoot intercepts syscalls but doesn't implement mount. All bind mounts must be set when launching proot-distro.
- **Restarting PRoot is required** to add or change bind mounts. No way to hot-add them.
- **`am`, `content` will NEVER work inside PRoot** without the Android Java runtime linker config (`/linkerconfig/ld.config.txt`), which PRoot doesn't provide. `pm` may work on newer Android versions (list packages, path) but `pm grant` and `pm dump` require elevated permissions the Termux app UID doesn't have.
- **Termux API apps must be installed** from F-Droid/Play Store for `termux-open`, `termux-notification`, etc. to work.
- **UID number varies** — the Termux app's UID depends on installation order and Android version. Never hardcode UIDs.
- **Android FUSE filesystem silently ignores `chmod`** — `/sdcard` files stay `660` (`-rw-rw----`) and dirs `2770` (`drwxrws---`) regardless of `chmod`. This is a VFAT/exFAT-backed FUSE limitation; you cannot make files world-writable (777) on Android shared storage.
- **`pm` works but with limitations** — `pm list packages` (641+ apps), `pm path` (APK location), `pm list features` all work. `pm grant`, `pm dump` fail with permission errors due to the Termux app UID. This may vary across Android versions and devices. Always test first.
- **`crond` dies silently in PRoot** — the system cron daemon can be killed by the container/runtime without leaving anything in the logs. Symptom: cron jobs stop firing silently, including any watchdog that depends on them. First diagnostic: `pgrep -x cron` (empty = dead). Recovery: `service cron start`. Defensive pattern: have cron watch itself in user crontab — `*/15 * * * * pgrep -x cron >/dev/null || service cron start`. This converts a multi-hour silent outage into a self-healing 15-min blip.

- **`cpuset:/top-app` lmkd kill window — new process in top-app cgroup dies if spawned too soon after old process exit** — confirmed for python3, but likely affects any non-trivial process. Symptom: any new process that joins `cpuset:/top-app` (Android's top-app/foreground cgroup) within ~10 seconds of the previous process's exit in the same cgroup gets SIGKILLed before reaching first user code. **Manifests as silent post-restart death with no shim marker, no traceback, no log line, no dmesg entry.** Affects: in-place `os.execv()` (cgroup reclassification), `subprocess.Popen(start_new_session=True)` (new session, same cgroup), `os.fork()` + immediate `os.execvp()` (forked child inherits cgroup). **The cron watchdog at 5-min intervals naturally waits long enough to avoid this** — which is why watchdog-recovered processes always survive and self-restart attempts die. **Workaround** (verified 2026-06-02, 2 consecutive real-update tests on Termux+PRoot/aarch64): if a process must self-restart in-place, use `os.fork()` + `os.setsid()` in the child + `time.sleep(15)` in the child + `os.execvp(target)`, then `os._exit(0)` in the parent. The 15s sleep outlasts the cgroup kill window; the new process is then in a brand-new cgroup context (post-exec) and survives. **Diagnostic tell**: the new process dies, has no markers/logs, BUT a process started by the same code via cron (or any 5+ min-later restart) survives with the same code. The cgroup of the dying and surviving processes is the same string (`cat /proc/PID/cgroup` → `cpuset:/top-app`) — so cgroup membership is not the differentiator, timing is. **Why this is broader than `os.execv()`**: any new python3 process in `cpuset:/top-app` is at risk, not just in-place execv. The strace-through-execv diagnostic is useless here — strace's first write happens after the kill (log is 0 bytes). Use 3-state lifecycle markers (pre-spawn + first-line + first-instrumented-call) to localize the kill to execve/loader/Py_Initialize/post-startup windows.

- **Discovery sequence when fixing a silent restart death** (verified 2026-06-02 on hermes-webui, 4 stages, 11 commits). When a self-restart silently kills the new process, iterate through 4 spawn mechanisms in this order — each one is one POSIX abstraction closer to the working primitive: (1) **in-place `os.execv`** — kills the new process in the execve window, marker pattern: pre-execv marker only, no first-line/install from new PID. (2) **`subprocess.Popen(start_new_session=True)` + `os._exit`** — Popen survives on most kernels but on Termux+PRoot the child dies with the parent (start_new_session doesn't survive `_exit` on this kernel), marker pattern: pre only, watchdog recovers. (3) **`os.fork()` + `os.setsid()` in child + `os.execvp(target)`** (no delay) — primitive POSIX spawn, child DOES start, but the new process is also killed in the cgroup window (same `cpuset:/top-app`, ~10s after old exit), marker pattern: pre only, no new PID markers. (4) **(3) + `time.sleep(15)` in child before `os.execvp`** — sleep outlasts the cgroup kill window, new process survives, marker pattern: pre + new first-line + new install. The 4-stage iteration is what proves the kill is cgroup-WINDOW-based (not execv-specific, not Popen-specific): only stage 4 survives, and it does so with the same `os.fork+os.setsid+os.execvp` mechanism that stage 3 used (which died). The 15s number is empirical — the cgroup kill window is empirically ~10s, so 15s gives a 50% margin. **Verification discipline**: do NOT trust a single successful restart — the first test could be lucky. Always do **2 consecutive real-update tests** before claiming the fix works. The first test confirms the new process starts; the second test confirms the mechanism isn't dependent on some state set up by the first test. For hermes-webui this means `POST /api/updates/apply` twice in a row, each with a `for i in 1..30; do curl /health; done` loop tracking the new PID's first-line + install markers and the absence of cron watchdog recovery lines. If 2/2 tests show new PID alive 30+ seconds after spawn, the fix is real.

## Running web services inside PRoot (accessible from Android host)

Web servers inside PRoot bound to `127.0.0.1` are only reachable within PRoot — not from the Android host's browser. Bind to `0.0.0.0` instead:

```bash
# Find device LAN IP
ifconfig | grep "inet " | grep -v 127.0.0.1

# Generic web server
python3 -m http.server 8000 --bind 0.0.0.0

# Hermes Web UI (nesquena/hermes-webui at /root/hermes-webui)
cd /root/hermes-webui
HERMES_WEBUI_AGENT_DIR=/usr/local/lib/hermes-agent \
  HERMES_WEBUI_HOST=0.0.0.0 \
  python3 server.py
# → Access at http://<device-lan-ip>:8787
```

**Security note:** Binding to `0.0.0.0` without auth exposes the service to anyone on the same network. Set `HERMES_WEBUI_PASSWORD` or use SSH tunneling for sensitive tools.

### Hermes Web UI vs built-in dashboard

Two separate services, easy to confuse:

| Service | Port | Purpose | Start command |
|---------|------|---------|---------------|
| Built-in dashboard | 9119 | Config/session management (shipped with Hermes) | `hermes dashboard` |
| nesquena/hermes-webui | 8787 | Full web UI with CLI parity, workspace browser | `python3 server.py` in `/root/hermes-webui/` |

## Package management with apt in PRoot

PRoot containers run a full Ubuntu/Debian userspace with `apt-get`.
However, interrupted operations from previous sessions leave dpkg in a
locked state. Always run this before any `apt-get install`:

```bash
dpkg --configure -a 2>/dev/null
apt-get update -qq
apt-get install -y -qq <package>
```

### Installing `gh` CLI (GitHub CLI)

```bash
dpkg --configure -a 2>/dev/null
apt-get update -qq && apt-get install -y -qq gh
gh --version
```

After install, authenticate via `gh auth login --with-token` (see
`github-auth` skill for token handling in sandboxed environments).

### Common package installation recovery

| Symptom | Cause | Fix |
|---------|-------|-----|
| `E: dpkg was interrupted` | Previous session killed mid-install | `dpkg --configure -a` |
| `E: Could not get lock /var/lib/dpkg/lock` | Another apt process running or stale lock | `rm /var/lib/dpkg/lock-frontend 2>/dev/null; rm /var/lib/apt/lists/lock 2>/dev/null; dpkg --configure -a` |
| Package not found | Outdated package lists | `apt-get update` before install |
| Architecture mismatch (`armhf` vs `arm64`) | PRoot may detect wrong arch first | `dpkg --print-architecture; dpkg --add-architecture arm64` |

## Python package management on ARM64 PRoot

Standard `pip install` / `uv pip install` often fails because the platform
tag detected by Python is `android_24_arm64_v8a`, which doesn't match
`manylinux_2_17_aarch64` wheels. Workaround: use `--python-platform linux`
to force linux-platform wheel resolution.

**Caveat:** Wheels installed this way may extract without `__init__.py`,
causing `ImportError: cannot import name 'X' from 'package' (unknown location)`.
Fix: create minimal `__init__.py` files for each affected package.

See `references/python-packaging-termux-arm64.md` for the full technique,
package-specific workarounds, and diagnostic commands.

## See also

- `references/android-tools-inventory.md` — Detailed findings from session exploring which Android tools work from PRoot.
- `references/hermes-webui-setup.md` — Steps to start the Hermes Web UI with proper env vars in PRoot.
- `references/python-packaging-termux-arm64.md` — Installing Python packages on ARM64 PRoot with platform-tag overrides and missing `__init__.py` fixes.
- `references/slm-mcp-arm64.md` — Connecting SuperLocalMemory as an MCP server in Hermes on ARM64 PRoot: venv setup, UV_LINK_MODE=copy workaround, embedding worker disable, PYTHONPATH dual bridge.

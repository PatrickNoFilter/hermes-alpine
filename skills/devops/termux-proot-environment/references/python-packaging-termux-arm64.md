# Python package management on ARM64 Termux + PRoot

## Problem

Python on Termux `proot-distro` (Ubuntu 26.04 aarch64) reports platform
`android_24_arm64_v8a` via `sysconfig.get_platform()`. Most manylinux wheels
don't match this tag, so `pip install` / `uv pip install` fails with
`ERROR: Could not find a matching version`.

## Solution 1: `--python-platform` / `--python-version` override

Force pip/uv to accept linux-platform wheels:

```sh
# pip
pip install --platform manylinux_2_17_aarch64 --only-binary :all: modal

# uv
uv pip install --python-platform linux --python-version 3.13 modal
```

**Caveat — missing `__init__.py`:** Wheels installed this way may extract
incomplete packages (no `__init__.py`). This manifests as mysterious
`ImportError: cannot import name 'X' from package Y (unknown location)`
or `ModuleNotFoundError` for submodules that clearly exist on disk.

**Fix:** For each affected package, create a minimal `__init__.py`:

```sh
# Identify packages missing __init__.py
python -c "
import os
site = '.../site-packages'
for item in sorted(os.listdir(site)):
    p = os.path.join(site, item, '__init__.py')
    if os.path.isdir(os.path.join(site, item)) and not os.path.exists(p):
        py = [f for f in os.listdir(os.path.join(site, item)) if f.endswith('.py')]
        if py: print(f'MISSING: {item}')
"
```

Then create the `__init__.py` with the exports that other packages need.

**Package-specific workarounds (Modal 1.4.3 on Python 3.13 arm64):**

| Package | Fix |
|---------|-----|
| `grpclib` | Need `Status`, `GRPCError`, `StreamTerminatedError` exports |
| `yarl` | Need `URL`, `Query` exports |
| `aiohttp` | Need `ClientSession`, `web.Application`, etc. |
| `propcache` | Need `under_cached_property` |
| `watchfiles` | Need `awatch`, `Change`, `DefaultFilter` |
| `cbor2` | Need `dumps`, `loads` |
| `aiohappyeyeballs` | Need `AddrInfoType`, `SocketFactoryType` |
| `h2` | Empty `__init__.py` suffices (submodules self-contained) |
| `modal` | Need `App`, `Image`, `Volume`, `Secret`, `Cls`, `method`, etc. |

**cbor2 version-meta bug:** Version 6.x reports version `0.0.0` on this
platform, which causes uv to try building from source (fails). Install v5.9.0
instead which has working manylinux wheels.

## Complete recipe: Modal on Termux/PRoot ARM64

Installing [Modal](https://modal.com) on Termux/PRoot hits every ARM64 packaging
quirk at once. Here's the full end-to-end.

### Version matrix

| Component | Working version | Reason |
|-----------|----------------|--------|
| Python | **3.13** (not 3.14) | 3.14 has broken `__init__.py` in wheels; 3.13 works |
| modal | **>=1.4.4.dev17** | 1.4.3 has `modal.config` ↔ `modal._utils.logger` circular import at import time |
| grpclib | 0.4.9 | Needs `__init__.py` patch (see below) |
| watchfiles | any with `manylinux_2_17_aarch64` wheel | Python API installs; **native `_rust_notify` is incompatible with Android Bionic** so the `modal` CLI crashes |

### Install

```sh
# 1. Create venv with Python 3.13
uv venv --python 3.13 .venv-modal
source .venv-modal/bin/activate

# 2. Install Modal (override Android platform tag)
UV_LINK_MODE=copy uv pip install --python-platform linux modal==1.4.4.dev17

# 3. Fix grpclib circular import
# grpclib/metadata.py tries `from . import __version__`, but __version__ was
# defined AFTER submodule imports. Move it before.
cat > "$(python -c 'import grpclib; print(grpclib.__file__)')" << 'EOF'
__version__ = "0.4.9"

from .const import Status
from .exceptions import GRPCError, StreamTerminatedError
from . import events, protocol, client, server

__all__ = (
    "Status", "GRPCError", "StreamTerminatedError",
    "events", "protocol", "client", "server",
)
EOF
```

### What works vs doesn't on Termux

| Operation | Status | Notes |
|-----------|--------|-------|
| `import modal` | ✅ | Library imports fine |
| `modal.App()`, `@app.function()` | ✅ | All Python API works |
| `modal run`, `modal deploy` | ❌ | CLI crashes — `watchfiles._rust_notify` native .so compiled for glibc, Android uses Bionic |
| `modal setup` | ❌ | Same CLI crash |
| Auth via `MODAL_TOKEN_ID`/`MODAL_TOKEN_SECRET` env vars | ✅ | Set env vars, use Python API directly |

### Auth (no CLI available)

1. Sign up at **https://modal.com** from any browser device
2. **Settings → Tokens → Create token**
3. Export env vars:

```sh
export MODAL_TOKEN_ID="your-token-id"
export MODAL_TOKEN_SECRET="your-token-secret"
```

Then use Modal via Python:

```sh
python -c "
import os
os.environ['MODAL_TOKEN_ID'] = 'your-token-id'
os.environ['MODAL_TOKEN_SECRET'] = 'your-token-secret'
import modal
print('Modal OK:', modal.__version__)
"
```

### Verification

```sh
python -c "import modal; print('Modal OK:', modal.__version__)"
# → Modal OK: 1.4.4.dev17
```

## Solution 2: Manual wheel download

When `--python-platform` causes too many breakages, download matching-arm
wheels directly from PyPI and force-install:

```sh
pip install \
  --only-binary :all: \
  --platform manylinux_2_17_aarch64 \
  --target /path/to/venv/lib/python3.13/site-packages/ \
  /path/to/downloaded.whl
```

## Solution 3: System-level (apt) for ML stack

When you need numpy, scipy, networkx, or other C-extension-heavy packages
on ARM64 PRoot, **use `apt` instead of pip** — it provides pre-compiled
`aarch64` packages that install instantly:

```sh
# Core ML stack
apt install -y python3-numpy python3-scipy python3-networkx python3-httpx
# Pure Python packages that happen to be in apt
apt install -y python3-dateutil python3-einops python3-pyyaml
```

This avoids the ~30+ minute compile time of `pip install numpy scipy` on
ARM64. The apt versions run on system Python (`python3`, typically 3.14+).

## PYTHONPATH cross-version bridging

When your system Python (e.g. 3.14) has numpy/scipy via apt, but a separate
Python (e.g. Termux's 3.13) was used to `pip install` pure-Python packages
(vaderSentiment, rank-bm25, etc.), bridge them via `PYTHONPATH`:

```sh
# Find the other Python's site-packages
python3.13 -c "import site; print(site.getsitepackages()[0])"
# → /data/data/com.termux/files/usr/lib/python3.13/site-packages

# Use it with system python3:
PYTHONPATH=/data/data/com.termux/files/usr/lib/python3.13/site-packages \
  python3 -c "import vaderSentiment; import rank_bm25"
```

**Limitations:** Only pure-Python packages (no native code) can be bridged
this way. Packages with C extensions (numpy, orjson) are version-specific
and must match the Python version.

### Embed this into npm-wrapped Python tools

If a tool uses a Node wrapper to launch Python (e.g. SuperLocalMemory's
`slm` CLI), patch the wrapper to prioritise the right Python and inject
the cross-version PYTHONPATH:

```diff
# In the wrapper's findPython() candidates list:
 const candidates = [
+    'python3',
     'python3.13',
-    'python3',
     'python',
 ];

# In the PYTHONPATH env passed to the subprocess:
 env: {
     ...process.env,
-    PYTHONPATH: SRC_DIR + ...,
+    PYTHONPATH: SRC_DIR + ':' +
+      '/data/data/com.termux/files/usr/lib/python3.13/site-packages' + ':...',
 },
```

### When to use each install method

| Method | When | Dependencies | Speed |
|--------|------|-------------|-------|
| `apt install` | C-ext packages (numpy, scipy) | Ubuntu/Debian repos | Instant |
| `pip install` (native Python) | Pure-Python packages | pip available | Fast |
| `uv pip --python-platform linux` | Wheels with native code (Modal, grpclib) | See Solution 1 | Medium |
| PYTHONPATH bridge | Cross-version pure-Python packages | Both Pythons installed | Config only |

## Environment variables

| Var | When needed | Why |
|-----|-------------|-----|
| `UV_LINK_MODE=copy` | Any PRoot env | Hardlinks fail with `Operation not permitted` under ptrace |
| `PIP_NO_BUILD_ISOLATION=0` | Rarely | Only if a dep needs to compile C extensions |
| `SLM_MIN_AVAILABLE_MEMORY_GB` | Avoid embedding worker spawn on constrained devices | Set high (e.g. 999) to prevent worker launch |
| `SLM_EMBED_RESPONSE_TIMEOUT` | Fast fail when embedding unavailable | Set low (e.g. 2) to avoid 180s timeout on each call |

## Diagnostic commands

```sh
# What platform does Python detect?
python -c "import sysconfig; print(sysconfig.get_platform())"

# What wheels does a package have?
pip download --no-binary :all: --no-deps modal 2>&1 | head -5
pip download --only-binary :all: --platform manylinux_2_17_aarch64 modal 2>&1

# Check if imports work end-to-end
python -c "
import modal
app = modal.App('test')
print('App:', type(app))
print('Image:', type(modal.Image))
"

# Verify apt-installed ML stack
python -c "import numpy, scipy, networkx; print('numpy:', numpy.__version__); print('scipy:', scipy.__version__)"

# Cross-version check (bridge test)
PYTHONPATH=$(python3.13 -c "import site; print(site.getsitepackages()[0])") \
  python3 -c "import vaderSentiment; import rank_bm25; print('bridge OK')"

# Check for PRoot hardlink issues
uv pip install --dry-run requests 2>&1 | grep -i hardlink
# If "failed to hardlink" appears, export UV_LINK_MODE=copy
```


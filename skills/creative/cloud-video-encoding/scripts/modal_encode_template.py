#!/usr/bin/env python3
"""
Modal cloud ffmpeg transcoder — copy-paste starter.
Fill in LOCAL_IN, LOCAL_OUT, and adjust crf/preset as needed.

CRITICAL: import toml INSIDE a function, not at module top level.
Modal's cloud-side introspection imports all top-level modules.
toml is not on the cloud image → ModuleNotFoundError.
"""
import os, time

# ---- Auth (assumes /root/.modal.toml exists) ----
# toml must NOT be imported at top level — see docstring above.
def _load_modal_auth():
    import toml
    cfg = toml.load('/root/.modal.toml')
    os.environ['MODAL_TOKEN_ID']     = cfg['default']['token_id']
    os.environ['MODAL_TOKEN_SECRET'] = cfg['default']['token_secret']

import modal

# ---- Config ----
LOCAL_IN   = "/path/to/input.webm"          # EDIT
LOCAL_OUT  = "/path/to/output.mp4"          # EDIT
REMOTE_IN  = "input.webm"
REMOTE_OUT = "output.mp4"
CRF        = 20                             # 18=high, 23=medium, 28=low
PRESET     = "medium"                       # ultrafast → veryslow

# ---- Modal app ----
image  = modal.Image.debian_slim(python_version="3.11").apt_install("ffmpeg")
volume = modal.Volume.from_name("video-jobs", create_if_missing=True)
app    = modal.App("video-encode", image=image)

@app.function(volumes={"/data": volume}, timeout=1800)
def encode(in_name: str, out_name: str, crf: int, preset: str):
    import subprocess
    cmd = [
        "ffmpeg", "-y", "-i", f"/data/{in_name}",
        "-c:v", "libx264", "-preset", preset, "-crf", str(crf),
        "-pix_fmt", "yuv420p",
        "-c:a", "aac", "-b:a", "192k",
        "-movflags", "+faststart",
        "-threads", "0",
        f"/data/{out_name}",
    ]
    p = subprocess.run(cmd, capture_output=True, text=True)
    if p.returncode != 0:
        raise RuntimeError(f"ffmpeg failed:\n{p.stderr[-1500:]}")
    volume.commit()
    return {"out": out_name, "bytes": os.path.getsize(f"/data/{out_name}")}

@app.local_entrypoint()
def main():
    _load_modal_auth()  # must run before any .remote() call
    # Upload
    with open(LOCAL_IN, "rb") as f: data = f.read()
    print(f"[1/3] Uploading {len(data)/1024/1024:.2f} MB ...")

    @app.function(volumes={"/data": volume}, timeout=120)
    def upload(name: str, content: bytes):
        with open(f"/data/{name}", "wb") as g: g.write(content)
        volume.commit()
    upload.remote(REMOTE_IN, data)

    # Encode
    print(f"[2/3] Encoding (crf={CRF}, preset={PRESET}) ...")
    t0 = time.time()
    res = encode.remote(REMOTE_IN, REMOTE_OUT, CRF, PRESET)
    print(f"  done in {time.time()-t0:.1f}s → {res}")

    # Download
    print(f"[3/3] Downloading to {LOCAL_OUT} ...")
    @app.function(volumes={"/data": volume}, timeout=120)
    def download(name: str) -> bytes:
        with open(f"/data/{name}", "rb") as g: return g.read()
    with open(LOCAL_OUT, "wb") as f:
        f.write(download.remote(REMOTE_OUT))
    print(f"  saved → {LOCAL_OUT}")

if __name__ == "__main__":
    main()

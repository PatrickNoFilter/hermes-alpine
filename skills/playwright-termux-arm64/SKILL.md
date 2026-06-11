---
name: playwright-termux-arm64
description: "Run Playwright on Termux/PRoot ARM64. The full Chromium binary is in ~/.cache/ms-playwright/chromium-XXXX/chrome-linux/chrome, but Playwright's default launch() looks for the slim chromium_headless_shell which is NOT downloaded. Workaround: pass executablePath to the full chrome binary. Works without re-downloading anything."
---

# Playwright on Termux/PRoot ARM64

## The trap

`npx playwright install chromium` (or the html-video pipeline setup) downloads the **full Chromium** build:
`~/.cache/ms-playwright/chromium-1223/chrome-linux/chrome`

But `chromium.launch()` defaults to the **slim headless_shell**:
`~/.cache/ms-playwright/chromium_headless_shell-1223/chrome-linux/headless_shell`

If the headless_shell is missing (it usually is on this device), you get:
```
browserType.launch: Executable doesn't exist at
/root/.cache/ms-playwright/chromium_headless_shell-1223/chrome-linux/headless_shell
```

## The fix (no network needed)

Point `executablePath` at the full Chromium that's already on disk:

```js
import { chromium } from 'playwright';
const browser = await chromium.launch({
  headless: true,
  executablePath: '/root/.cache/ms-playwright/chromium-1223/chrome-linux/chrome',
  args: ['--no-sandbox', '--disable-dev-shm-usage', '--disable-gpu'],
});
```

Verified working: launch ~1.6s, `https://example.com` loads, screenshot saves as valid PNG (18 KB for example.com, magic bytes `89 50 4e 47`).

## Required launch args for this environment

- `--no-sandbox` — running as root in PRoot, sandbox will fail
- `--disable-dev-shm-usage` — /dev/shm is tiny in Termux
- `--disable-gpu` — no GPU, software rendering only

## Install pattern

Playwright is **not** installed globally. Create a project dir and install locally:
```bash
mkdir -p ~/pw-project && cd ~/pw-project
npm init -y
npm install playwright    # finds the cached Chromium automatically
```

The npm package itself is small (~6s install). The Chromium binary download is the heavy part and is already cached.

## Alternative: download the headless_shell

If you want the default behavior to work:
```bash
npx playwright install chromium
```
This downloads both `chromium-XXXX` and `chromium_headless_shell-XXXX` to the cache. But the executablePath approach is faster and reuses what's already there.

## Known working versions (as of June 2026)

- Node 22.22.3, npm 10.9.8
- Playwright npm package (latest as of install)
- Chromium 1223 -> /root/.cache/ms-playwright/chromium-1223/
- ffmpeg 1011 (bundled, for video pipeline)

## HTML → MP4 render pattern (Playwright recordVideo + ffmpeg)

Use Playwright's built-in `recordVideo` to capture an HTML page as webm, then convert with ffmpeg.
The key: **run the script from a directory that has playwright in its local node_modules** (e.g. `/root/pw-test`), not from `/root` directly — `require('playwright')` will fail if run from a dir without it.

```js
const { chromium } = require('playwright'); // must run from /root/pw-test or similar

const context = await browser.newContext({
  viewport: { width: 1920, height: 1080 },
  recordVideo: { dir: '/tmp/record-out', size: { width: 1920, height: 1080 } }
});
const page = await context.newPage();
await page.goto('file:///path/to/file.html', { waitUntil: 'domcontentloaded' });
await page.evaluate(() => document.fonts.ready);

// iterate slides / animate as needed, e.g. page.evaluate() + waitForTimeout()

await context.close(); // MUST close context (not just browser) to flush the webm

// convert webm → mp4
const webmFile = fs.readdirSync('/tmp/record-out').find(f => f.endsWith('.webm'));
// ffmpeg -y -i <webm> -r 30 -c:v libx264 -pix_fmt yuv420p -crf 20 output.mp4
```

**Pitfalls:**
- Close `context`, not just `browser`, to flush the webm — closing browser before context loses frames.
- `recordVideo` produces a single webm per page covering the entire session duration.
- Output webm lands as a UUID-named file in the `dir` you specified — use `readdirSync` to find it.
- Copy output to `/sdcard/Movies/` to access from Android gallery: `cp output.mp4 /sdcard/Movies/`

Working render: `/root/pw-test/render-ihsg.js` — 16-slide HTML, 1920×1080, 80s, 1.4 MB MP4.

## Controlling animations via `window.__activate(n)` (for HTML→video pipelines)

When recording a **multi-state HTML page** (slide deck, animated explainer), expose a JS function on `window` that Playwright can call to switch states. The recording script then waits for the new state's natural duration before calling the next.

```js
// Inside the HTML being recorded
function activate(n) {
  document.querySelectorAll('.slide').forEach(s => s.classList.remove('active'));
  document.getElementById('slide-' + n)?.classList.add('active');
  // … trigger CSS animations, count-up timers, etc.
}
window.__activate = activate;  // exposed for Playwright
```

```js
// Playwright recording script
const MANIFEST = JSON.parse(fs.readFileSync('audio/manifest.json', 'utf-8'));
for (let i = 0; i < MANIFEST.length; i++) {
  const slide = MANIFEST[i];
  if (i > 0) {
    await page.evaluate(n => window.__activate(n), slide.num);
    await page.waitForTimeout(300);  // let CSS animation kick in
  }
  await page.waitForTimeout(slide.dur * 1000 - (i > 0 ? 300 : 0));
}
await ctx.close();  // close context to flush webm
```

**Why this pattern works:** the animations are pure CSS/JS inside the HTML, so the recorded video captures them as they happen. Playwright's `recordVideo` is just a screen capture — anything Chromium renders will be in the webm. This is how the pocket-director pipeline produces animated bar charts, number counters, and text reveals for free, with zero per-frame ffmpeg work.

See the `animated-infographic-video-generation-node` skill for the full pipeline context.

## The encoding-speed wall (long recordings)

**Symptom:** For webm recordings >~5 min at 1080p, `ffmpeg -c:v libx264` runs at **~0.2–0.5x realtime** on this device. A 11-min 1080p VP8 webm takes ~25 min to re-encode locally. Worse: if the process is killed mid-encode (e.g. by `kill -9` during cleanup), the resulting MP4 is **corrupt at the NAL-unit level** — `ffprobe` returns `Invalid NAL unit size` errors and the file is unusable. Always wait for ffmpeg to fully complete (including the `[mp4 @ ...] Starting second pass: moving the moov atom` post-processing step) before assuming output is valid.

**The fix — encode in the cloud**, not locally. Three viable options (full decision matrix and code in the `cloud-video-encoding` skill):

1. **Modal cloud ffmpeg** (~3 min for 10-min video) — preferred, fast, uses existing `/root/.modal.toml` auth. See `cloud-video-encoding` skill for the working `modal_encode.py` pattern.
2. **YouTube unlisted upload + yt-dlp download** (~30 min) — free, no account billing, but slower and needs Google OAuth.
3. **Local `-preset ultrafast -threads 0`** (~5–10 min, 1–2x realtime) — last resort, drains the device. Use only if Modal is unavailable.

After cloud encoding returns an H.264 MP4, mux with the audio locally (this is fast — minutes, not the bottleneck):
```bash
ffmpeg -y -i video_h264.mp4 -i audio_mixed.mp3 \
  -c:v copy -c:a aac -b:a 192k -shortest -movflags +faststart \
  final.mp4
```

## Verification script

`~/pw-test/test.mjs` -- full working example: launches browser, navigates to example.com, prints title + UA, saves screenshot.

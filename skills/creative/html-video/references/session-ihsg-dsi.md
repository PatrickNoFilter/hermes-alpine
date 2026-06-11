# Session IHSG‑DSI HTML‑to‑Video

- Used `nexu‑io/html-video` to render a 16‑slide documentary.
- Chosen template: **frame‑ihsg‑dsi** (multi‑frame, 80‑90 s, 1920×1080, 30 fps).
- Added HTML prototype (`/root/ihsg-dsi-prototype.html`) as an asset.
- Rendering produced a 3.6 s video because the template used a single‑frame design for the prototype; for full slide sequence the template must contain separate frames or a content‑graph.
- Lesson: When converting slide‑based HTML to video, ensure the template supports multi‑frame rendering (e.g., `frame‑ihsg‑dsi` with proper `?slide=N` navigation) and provide each slide as a separate HTML file or a content‑graph JSON.
- Workaround for ARM64 PRoot: Playwright’s standalone Chromium works out‑of‑the‑box; no snap needed.
- Verify output with `ffprobe`.

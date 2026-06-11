# HTML template architecture — pocket-director slide deck

The HTML slide deck (`templates/slide_deck.html` in the repo) is
**one self-contained file** with embedded CSS and JS. The
`pipeline/02_build_slides.py` script injects slide data as
inline HTML sections. This reference documents how the template
works so you can customize it.

## High-level structure

```html
<!DOCTYPE html>
<html>
<head>
  <style>/* CSS — animations, layout, watermark */</style>
</head>
<body>
  <section class="slide" id="slide-1">…</section>
  <section class="slide" id="slide-2">…</section>
  …
  <div class="watermark">● PatrickNoFilter</div>
  <script>
    // manifest = [{num, dur}, ...]  (injected from build script)
    // window.__activate(n) — switches to slide N, triggers animations
  </script>
</body>
</html>
```

## CSS animation system

The template defines these keyframes (used throughout):

| Keyframe | Effect | Used by |
|----------|--------|---------|
| `fadeIn` | opacity 0 → 1 | slide activation |
| `growUp` | height 0 → target | bar charts (set `data-target-h`) |
| `scaleIn` | scale 0 → 1 | timeline dots, pop cards |
| `slideRight` | translateX(-40px) opacity 0 → 0 1 | text reveal, quote blocks |
| `countUp` | translateY(20px) opacity 0 → 0 1 | data cards, body text |

All animations triggered by adding `.active` class. Stagger via
`animation-delay` on child elements.

## Slide layouts

The build script picks one of these per slide:

### `title` (slides 1, 16 typically)
- H1 title, optional body
- Title animates `slideRight`, body animates `countUp`

### `chart` (bar charts)
- Title + horizontal bar groups
- Each bar has inline `data-target-h` and `.val` for the label
- Bars `growUp` on activation
- Use `red` / `green` / `yellow` / `blue` / `gray` color classes

```html
<div class="chart-bars">
  <div class="bar-group">
    <div class="bar red" style="height: 0;" data-target-h="180">
      <div class="val">-38%</div>
    </div>
    <div class="bar-label">IHSG</div>
  </div>
  ...
</div>
```

### `data` (key metrics cards)
- Title + body + row of `.data-card` divs
- Each card has `<div data-counter="908" data-suffix="B">$908B</div>`
- JS in the template animates the counter via `requestAnimationFrame`

```html
<div class="data-card">
  <div class="label">Total outflow</div>
  <div class="value red" data-counter="908" data-suffix="B">$908B</div>
  <div class="source">Bloomberg, Q1 2025</div>
</div>
```

### `timeline` (events over time)
- Title + horizontal timeline
- Each event has `.tl-node` with `.tl-dot`, `.tl-date`, `.tl-event`, `.tl-detail`
- Dots `scaleIn` sequentially via staggered `animation-delay`

### `quote` (highlight quote)
- Title + large quote block
- `.quote-block` has `border-left: 4px solid #ef4444` and slides in
- `.quote-source` for attribution

### `list` (bulleted list)
- Title + `<ul class="bullet-list">`
- Each `<li>` slides in sequentially via staggered `animation-delay`

## JS runtime (the `__activate(n)` pattern)

This is the critical piece that makes Playwright control possible:

```js
const MANIFEST = __MANIFEST__;  // injected from build script
let currentSlide = 1;

function activate(n) {
  document.querySelectorAll('.slide').forEach(s => s.classList.remove('active'));
  const el = document.getElementById('slide-' + n);
  if (!el) return;
  el.classList.add('active');

  // Stagger animation for child elements (80ms per element)
  const children = el.querySelectorAll('.slide-title, .slide-body, .data-card, .bar, .tl-dot, .quote-block, .bullet-list li');
  children.forEach((c, i) => {
    c.classList.remove('active');
    setTimeout(() => c.classList.add('active'), 50 + i * 80);
  });

  // Number counter animation
  el.querySelectorAll('[data-counter]').forEach(el => {
    const target = parseFloat(el.dataset.counter);
    const dur = 1200;
    const start = performance.now();
    const step = (now) => {
      const t = Math.min(1, (now - start) / dur);
      const v = target * (1 - Math.pow(1 - t, 3));
      el.textContent = (target >= 1000 ? Math.round(v).toLocaleString() : v.toFixed(0)) + (el.dataset.suffix || '');
      if (t < 1) requestAnimationFrame(step);
    };
    requestAnimationFrame(step);
  });

  // Bar grow — read data-target-h, set height with transition
  el.querySelectorAll('.bar[data-target-h]').forEach(bar => {
    bar.style.height = '0';
    setTimeout(() => bar.style.height = bar.dataset.targetH + 'px', 50);
  });
}

window.__activate = activate;  // exposed for Playwright
window.addEventListener('load', () => setTimeout(() => activate(1), 200));
```

**Why this matters for Playwright:** the recording script can call
`page.evaluate(n => window.__activate(n), slideNum)` to switch
slides, and then `waitForTimeout(dur_ms)` for the slide's TTS
duration. The animations are pure CSS/JS, so the recorded video
catches them as they happen.

## Watermark

Fixed position, always renders:
```css
.watermark {
  position: fixed; bottom: 24px; right: 32px;
  font-size: 13px; color: rgba(255,255,255,0.5);
  padding: 8px 14px; border: 1px solid rgba(255,255,255,0.15);
  border-radius: 6px; background: rgba(0,0,0,0.3);
}
```

The build script substitutes the text — pass `--watermark "● YourBrand"`.

## Customization tips

- **Vertical (TikTok) format**: change `body` width to `1080px` and rotate slide layout. Or use a different template entirely.
- **Add a new layout type**: define a new `<style>` block + a new branch in `render_slide_html()`.
- **Smoother animations**: bump `cubic-bezier(0.34, 1.56, 0.64, 1)` to a more elastic curve.
- **Background images**: add `body { background: url(...); background-size: cover; }` — Ken Burns effect via keyframes.

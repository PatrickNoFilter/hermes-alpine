# HTML Slide Prototype Template

For quick visual review of slide decks, build a single-file HTML prototype with:

- **Dark theme** (#0a0a0f background, #e8e8ed text) for documentary tone
- **One HTML file** with all CSS + JS embedded — no dependencies
- **Slide navigation**: Previous/Next buttons + keyboard arrow keys
- **Progress bar** at bottom showing position
- **No direct photos of officials** — use silhouettes, data cards, chart bars, icons
- **Responsive** — works on mobile via media queries

## Data Visualization Components

- **Data cards**: `.data-card` with label, value (color-coded), source
- **Chart bars**: `.bar` with gradient fills, `.bar.red` for negative, `.green` for positive
- **Timeline**: `.timeline` with dot nodes, dates, events, details
- **Quote block**: `.quote-block` with left red border, italic text, attribution
- **Step list**: `.step-list` with numbered circles for recommendations
- **Target table**: `.target-table` with period + goal cards
- **Big number**: `.big-number` for emphasis (e.g. "$908B")

### Slide Structure Pattern

```html
<div id="slideN" class="slide-container hidden">
  <span class="slide-number">NN / 16</span>
  <span class="slide-section">BAGIAN X — NAME</span>
  <div class="slide-title">Slide Title</div>
  <div class="slide-body">Narasi/description</div>
  <div class="data-row">...data cards...</div>
  <div class="nav-buttons">
    <button class="nav-btn" onclick="go(N-1)">← Sebelum</button>
    <button class="nav-btn primary" onclick="go(N+1)">Selanjutnya →</button>
  </div>
  <div class="progress-bar" style="width:XX%"></div>
</div>
```

### URL Query Parameter Navigation

Support `?slide=N` in the URL so individual slides can be targeted (for screenshots, linking, or testing):

```javascript
function getSlideFromUrl() {
  const params = new URLSearchParams(window.location.search);
  const n = parseInt(params.get('slide'));
  if (n && n >= 1 && n <= totalSlides) return n;
  return 1;
}
```

Call this on page load instead of always starting at slide 1:
```javascript
let current = getSlideFromUrl();
go(current);  // show the target slide
```

Also update the URL as the user navigates (for shareability):
```javascript
function go(n) {
  document.getElementById('slide'+current).classList.add('hidden');
  document.getElementById('slide'+n).classList.remove('hidden');
  current = n;
  // Update URL without reloading page
  const url = new URL(window.location);
  url.searchParams.set('slide', n);
  window.history.replaceState({}, '', url);
}
```

### Keyboard Navigation

```javascript
let current = 1;
function go(n) {
  document.getElementById('slide'+current).classList.add('hidden');
  document.getElementById('slide'+n).classList.remove('hidden');
  current = n;
  // Optional: update URL param
  const url = new URL(window.location);
  url.searchParams.set('slide', n);
  window.history.replaceState({}, '', url);
}
document.addEventListener('keydown', function(e) {
  if (e.key === 'ArrowRight' || e.key === ' ' || e.key === 'ArrowDown') {
    e.preventDefault();
    // trigger primary (next) button
  }
  if (e.key === 'ArrowLeft' || e.key === 'ArrowUp') {
    e.preventDefault();
    // trigger secondary (prev) button
  }
});
```

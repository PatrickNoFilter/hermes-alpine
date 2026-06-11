# Multi-frame HTML Video Example

This is a minimal template structure for slide-based documentaries.

## Content Graph (content-graph.json)
```json
{
  "nodes": [
    {"id": "slide1", "kind": "slide", "data": {"title": "Slide 1", "content": "..."}},
    {"id": "slide2", "kind": "slide", "data": {"title": "Slide 2", "content": "..."}},
    {"id": "slide3", "kind": "slide", "data": {"title": "Slide 3", "content": "..."}}
  ],
  "edges": [
    {"from": "slide1", "to": "slide2", "type": "sequence"},
    {"from": "slide2", "to": "slide3", "type": "sequence"}
  ],
  "totalDurationSec": 30
}
```

## HTML Template (slide.html)
```html
<!DOCTYPE html>
<html>
<head>
  <style>
    .slide { width: 100vw; height: 100vh; display: flex; flex-direction: column; justify-content: center; align-items: center; }
    .slide.hidden { display: none; }
  </style>
</head>
<body>
  <div id="slide1" class="slide">Slide 1 content</div>
  <div id="slide2" class="slide hidden">Slide 2 content</div>
  <div id="slide3" class="slide hidden">Slide 3 content</div>
  <script>
    // Auto-advance based on content-graph timing
  </script>
</body>
</html>
```

## CLI Usage
```bash
# Create project with multi-frame template
node packages/cli/dist/bin.js project-create --name "documentary"
node packages/cli/dist/bin.js project-set-template <id> --template frame-ihsg-dsi
node packages/cli/dist/bin.js project-add-asset <id> --file content-graph.json
node packages/cli/dist/bin.js project-render <id>
```

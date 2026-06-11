#!/usr/bin/env python3
"""
Template: Generate 1920x1080 dark-theme slide images for documentary video.

Customize the SLIDES list with your content — each entry produces one PNG.
Usage:  uv run python scripts/generate-slides.py
Output: slide01.png .. slideNN.png in current directory
"""

from PIL import Image, ImageDraw, ImageFont
import os, textwrap

W, H = 1920, 1080
BG = (10, 10, 15)
FG = (232, 232, 237)
ACCENT_RED = (220, 50, 50)
ACCENT_GREEN = (50, 200, 100)
ACCENT_BLUE = (70, 130, 220)
ACCENT_GOLD = (255, 200, 50)
DARK_CARD = (25, 25, 35)
SECTION_FG = (150, 150, 160)

# --- SLIDE CONTENT ---
# Each entry: (section, title, lines, layout_hint)
# layout_hint: "body" | "data-cards" | "quotes" | "list" | "big-number"
SLIDES = [
    # Slide 1 — Title / Hook
    ("", "Judul Dokumenter", [
        "Subtitle / hook line",
        "Narasi pembuka singkat",
    ], "body"),

    # Slide 2 — Data
    ("BAGIAN 1 — FAKTA", "Judul Slide Data", [
        "Poin data utama pertama dengan angka besar",
        "Poin data kedua dengan perbandingan",
        "Sumber: Nama Sumber",
    ], "data-cards"),

    # Add more slides following the same pattern...
]

# ---- RENDERING FUNCTIONS ----

def load_font(size, bold=False):
    """Load a font with fallback to default."""
    try:
        return ImageFont.truetype("/usr/share/fonts/truetype/dejavu/DejaVuSans-Bold.ttf" if bold else "/usr/share/fonts/truetype/dejavu/DejaVuSans.ttf", size)
    except (IOError, OSError):
        return ImageFont.load_default()

def draw_bg(draw):
    draw.rectangle([(0, 0), (W, H)], fill=BG)
    # Subtle gradient at top
    for i in range(4):
        draw.rectangle([(0, i), (W, i+1)], fill=(15, 15, 22 + i*3))

def draw_slide_number(draw, num, total):
    text = f"{num:02d} / {total:02d}"
    _, _, tw, th = draw.textbbox((0, 0), text, font=load_font(14))
    draw.text((W - tw - 40, 30), text, fill=SECTION_FG, font=load_font(14))

def draw_section(draw, section):
    if section:
        draw.text((60, 30), section, fill=SECTION_FG, font=load_font(14))

def draw_title(draw, title, y_start=80):
    draw.text((60, y_start), title, fill=FG, font=load_font(36, bold=True))

def draw_body_text(draw, lines, y_start=160):
    y = y_start
    font = load_font(22)
    line_h = 38
    for line in lines:
        # Word wrap for long lines
        wrapped = textwrap.wrap(line, width=70)
        for wl in wrapped:
            draw.text((60, y), wl, fill=FG, font=font)
            y += line_h
        y += 8

def draw_data_cards(draw, lines, y_start=160):
    """Draw data cards in a 2-column grid."""
    y = y_start
    font_val = load_font(28, bold=True)
    font_label = load_font(16)
    card_w = 400
    card_h = 100
    gap = 30
    for i, line in enumerate(lines):
        col = i % 2
        row = i // 2
        x = 60 + col * (card_w + gap)
        cy = y + row * (card_h + gap)
        # Card background
        draw.rounded_rectangle([(x, cy), (x + card_w, cy + card_h)], radius=8, fill=DARK_CARD)
        # Check if line has a colon for value:label split
        if ":" in line:
            val, label = line.split(":", 1)
            draw.text((x + 20, cy + 15), val.strip(), fill=ACCENT_GOLD, font=font_val)
            draw.text((x + 20, cy + 55), label.strip(), fill=SECTION_FG, font=font_label)
        else:
            draw.text((x + 20, cy + 25), line, fill=FG, font=font_label)

def draw_big_number(draw, lines, y_start=160):
    """Draw a large central number with supporting text."""
    font_big = load_font(72, bold=True)
    font_sub = load_font(24)
    if lines:
        draw.text((W//2, y_start + 40), lines[0], fill=ACCENT_RED, font=font_big, anchor="mt")
    for i, line in enumerate(lines[1:], 1):
        draw.text((W//2, y_start + 130 + i*40), line, fill=FG, font=font_sub, anchor="mt")

def render_slide(num, total, section, title, lines, layout):
    img = Image.new("RGB", (W, H))
    draw = ImageDraw.Draw(img)

    draw_bg(draw)
    draw_slide_number(draw, num, total)
    draw_section(draw, section)
    draw_title(draw, title)

    if layout == "data-cards":
        draw_data_cards(draw, lines)
    elif layout == "big-number":
        draw_big_number(draw, lines)
    else:
        draw_body_text(draw, lines)

    # Progress bar at bottom
    prog_w = int((W - 120) * (num / total))
    draw.rectangle([(60, H - 25), (W - 60, H - 20)], fill=(40, 40, 50))
    draw.rectangle([(60, H - 25), (60 + prog_w, H - 20)], fill=ACCENT_BLUE)

    path = f"slide{num:02d}.png"
    img.save(path)
    print(f"  ✓ {path}")
    return path

def main():
    total = len(SLIDES)
    print(f"Rendering {total} slides...")
    os.makedirs("slides", exist_ok=True)
    orig_cwd = os.getcwd()
    os.chdir("slides")
    for i, (section, title, lines, layout) in enumerate(SLIDES, 1):
        render_slide(i, total, section, title, lines, layout)
    os.chdir(orig_cwd)
    print(f"\nDone! Output in slides/")
    print(f"To render FFmpeg segments:")
    print(f"  cd slides && for i in $(seq -w 1 {total}); do ffmpeg -y -loop 1 -i slide$i.png -i slide$i.mp3 -c:v libx264 -c:a aac -pix_fmt yuv420p -shortest segment$i.mp4; done")
    print(f"To concat: create segments.txt and run ffmpeg -f concat -safe 0 -i segments.txt -c copy final.mp4")

if __name__ == "__main__":
    main()

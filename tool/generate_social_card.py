#!/usr/bin/env python3
"""Generate the landing page's Open Graph card and Apple touch icon.

    python3 tool/generate_social_card.py

Writes:
  site/social-card.png      1200x630 — og:image / twitter:image
  site/apple-touch-icon.png 180x180  — iOS home-screen icon

Reproducible: re-run to regenerate. Both outputs are committed, so this only
needs running when the wordmark, headline or palette changes.

Platform logos are rasterised straight out of the <symbol> sprite in
site/index.html via cairosvg, so the card can never drift from the page.
Text uses the page's own typefaces, downloaded to a temp directory and loaded
by path — nothing is installed system-wide.

Requires: pillow, cairosvg (`pip install pillow cairosvg`) and network access
for the one-time font fetch.
"""

import io
import re
import subprocess
import tempfile
import urllib.request
from pathlib import Path

from PIL import Image, ImageDraw, ImageFont

ROOT = Path(__file__).resolve().parent.parent
SITE = ROOT / "site"

FONT_URLS = {
    "archivo.ttf": "https://github.com/google/fonts/raw/main/ofl/archivo/Archivo%5Bwdth%2Cwght%5D.ttf",
    "plexsans.ttf": "https://github.com/google/fonts/raw/main/ofl/ibmplexsans/IBMPlexSans%5Bwdth%2Cwght%5D.ttf",
    "plexmono.ttf": "https://github.com/google/fonts/raw/main/ofl/ibmplexmono/IBMPlexMono-Regular.ttf",
}

# Dark-mode tokens from site/styles.css — social cards read better dark.
INK = (232, 237, 241)
INK2 = (162, 176, 187)
BG = (12, 17, 22)
TEAL = (62, 202, 214)
AMBER = (233, 166, 72)
RULE = (37, 48, 57)


def fetch_fonts(into: Path) -> None:
    for name, url in FONT_URLS.items():
        target = into / name
        if not target.exists():
            urllib.request.urlretrieve(url, target)


def svg_to_image(svg: str, width: int, height: int) -> Image.Image:
    out = subprocess.run(
        ["cairosvg", "-", "-f", "png", "-o", "-",
         "--output-width", str(width), "--output-height", str(height)],
        input=svg.encode(), capture_output=True, check=True,
    )
    return Image.open(io.BytesIO(out.stdout)).convert("RGBA")


def logo(symbol_id: str, height: int, currentcolor: str = "#e8edf1") -> Image.Image:
    """Rasterise one <symbol> from the page's inline sprite."""
    html = (SITE / "index.html").read_text()
    match = re.search(
        r'<symbol id="%s" viewBox="([^"]+)">(.*?)</symbol>' % re.escape(symbol_id),
        html, re.S,
    )
    if not match:
        raise SystemExit(f"symbol #{symbol_id} not found in site/index.html")
    viewbox, body = match.group(1), match.group(2).replace("currentColor", currentcolor)
    _, _, vw, vh = (float(v) for v in viewbox.split())
    width = round(height * vw / vh)
    return svg_to_image(
        f'<svg xmlns="http://www.w3.org/2000/svg" viewBox="{viewbox}" '
        f'width="{width}" height="{height}">{body}</svg>',
        width, height,
    )


def font(fonts: Path, name: str, size: int, axes=None) -> ImageFont.FreeTypeFont:
    # Variable-font axes are ordered [Weight, Width] in both families.
    loaded = ImageFont.truetype(str(fonts / name), size)
    if axes:
        loaded.set_variation_by_axes(axes)
    return loaded


def social_card(fonts: Path) -> None:
    W, H, PAD = 1200, 630, 76
    img = Image.new("RGB", (W, H), BG)
    draw = ImageDraw.Draw(img)

    # Hairline frame, echoing the page's contained rules.
    draw.rectangle([PAD // 2, PAD // 2, W - PAD // 2, H - PAD // 2], outline=RULE, width=1)

    mono = font(fonts, "plexmono.ttf", 25)
    sans = font(fonts, "plexsans.ttf", 25, [400, 100])
    sans_bold = font(fonts, "plexsans.ttf", 22, [600, 100])
    display = font(fonts, "archivo.ttf", 80, [800, 118])

    # Wordmark: the amber dot + teal bar used as the page glyph and favicon.
    draw.ellipse([PAD, PAD + 6, PAD + 18, PAD + 24], fill=AMBER)
    draw.rounded_rectangle([PAD + 25, PAD + 9, PAD + 45, PAD + 21], radius=3, fill=TEAL)
    draw.text((PAD + 58, PAD + 1), "native_datastore", font=mono, fill=INK)

    y = 176
    for line, colour in (("Store a value.", INK),
                         ("Close the app.", INK),
                         ("It's still there.", TEAL)):
        draw.text((PAD, y), line, font=display, fill=colour)
        y += 84

    draw.text((PAD, y + 22), "Persistent key-value storage for Flutter", font=sans, fill=INK2)

    x, row_y = PAD, H - PAD - 30
    for symbol_id, label in (("logo-flutter", "Flutter 3.3+"),
                             ("logo-android", "Android · Jetpack DataStore"),
                             ("logo-apple", "iOS · UserDefaults")):
        mark = logo(symbol_id, 28)
        img.paste(mark, (x, row_y - 4), mark)
        x += mark.width + 12
        draw.text((x, row_y + 3), label, font=sans_bold, fill=INK2)
        x += round(draw.textlength(label, font=sans_bold)) + 44

    img.save(SITE / "social-card.png", optimize=True)
    print(f"wrote {SITE / 'social-card.png'} {img.size}")


def touch_icon() -> None:
    # Full-bleed square: iOS applies its own corner mask.
    icon = svg_to_image(
        '<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 180 180">'
        '<rect width="180" height="180" fill="#101820"/>'
        '<circle cx="62" cy="90" r="23" fill="#e9a648"/>'
        '<rect x="100" y="67" width="46" height="46" rx="11" fill="#2fb9c6"/>'
        '</svg>', 180, 180).convert("RGB")
    icon.save(SITE / "apple-touch-icon.png", optimize=True)
    print(f"wrote {SITE / 'apple-touch-icon.png'} {icon.size}")


if __name__ == "__main__":
    with tempfile.TemporaryDirectory() as tmp:
        fonts = Path(tmp)
        fetch_fonts(fonts)
        social_card(fonts)
    touch_icon()

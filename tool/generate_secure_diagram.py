#!/usr/bin/env python3
"""Generate doc/assets/secure-storage.gif — an animated diagram of how
SecureDatastore encrypts values at rest and shares them across processes.

Reproducible: re-run to regenerate the asset. Pure Pillow, no network.

    python3 tool/generate_secure_diagram.py

The animation loops through four phases:
  1. A plaintext secret leaves your Dart code.
  2. It is encrypted with an AES-256-GCM key held in the AndroidKeyStore /
     iOS Keychain (hardware-backed where available).
  3. Only ciphertext lands on disk — unreadable without the key.
  4. With configure(multiProcess/appGroupId), a second process reads the same
     encrypted store.
"""

import os
import shutil
import subprocess
import tempfile
from PIL import Image, ImageDraw, ImageFont

W, H = 1000, 500
FRAMES = 84
FRAME_MS = 45

# ---- palette (legible on light & dark README backgrounds) -------------------
BG = (255, 255, 255)
INK = (31, 35, 40)
MUTED = (101, 109, 118)
BORDER = (208, 215, 222)
CARD = (246, 248, 250)
BLUE = (21, 101, 192)
BLUE_SOFT = (219, 234, 254)
GREEN = (26, 127, 55)
GREEN_SOFT = (218, 244, 226)
RED = (207, 34, 46)
RED_SOFT = (255, 227, 228)
AMBER = (154, 103, 0)
AMBER_SOFT = (255, 240, 200)

FONT_DIR = "/System/Library/Fonts/Supplemental"
SANS = os.path.join(FONT_DIR, "Arial.ttf")
SANS_B = os.path.join(FONT_DIR, "Arial Bold.ttf")
MONO = "/System/Library/Fonts/Menlo.ttc"


def font(path, size):
    return ImageFont.truetype(path, size)


F_TITLE = font(SANS_B, 26)
F_H = font(SANS_B, 17)
F_B = font(SANS, 14)
F_S = font(SANS, 12)
F_MONO = font(MONO, 14)
F_MONO_S = font(MONO, 12)


def ease(t):
    """Smoothstep easing on [0,1]."""
    t = max(0.0, min(1.0, t))
    return t * t * (3 - 2 * t)


def lerp(a, b, t):
    return a + (b - a) * t


def mix(c1, c2, t):
    return tuple(round(lerp(c1[i], c2[i], t)) for i in range(3))


def rrect(d, box, radius, fill=None, outline=None, width=1):
    d.rounded_rectangle(box, radius=radius, fill=fill, outline=outline, width=width)


def center_text(d, cx, cy, text, fnt, fill):
    l, t, r, b = d.textbbox((0, 0), text, font=fnt)
    d.text((cx - (r - l) / 2, cy - (b - t) / 2), text, font=fnt, fill=fill)


def arrow(d, x1, y1, x2, y2, color, width=3, head=9):
    d.line([(x1, y1), (x2, y2)], fill=color, width=width)
    # horizontal head only (all arrows here are left-to-right / vertical)
    if abs(y2 - y1) < abs(x2 - x1):
        d.polygon(
            [(x2, y2), (x2 - head, y2 - head * 0.7), (x2 - head, y2 + head * 0.7)],
            fill=color,
        )
    else:
        diry = 1 if y2 > y1 else -1
        d.polygon(
            [(x2, y2), (x2 - head * 0.7, y2 - head * diry),
             (x2 + head * 0.7, y2 - head * diry)],
            fill=color,
        )


# Box geometry for the top row.
AX0, AX1 = 40, 300
BX0, BX1 = 372, 628
CX0, CX1 = 700, 960
ROW_Y0, ROW_Y1 = 92, 232
BCX = (BX0 + BX1) / 2  # encrypt box centre-x
TRAVEL_Y = (ROW_Y0 + ROW_Y1) / 2


def draw_static(d):
    # Title
    center_text(d, W / 2, 34, "SecureDatastore — encrypted at rest", F_TITLE, INK)

    # Box A: Dart code
    rrect(d, [AX0, ROW_Y0, AX1, ROW_Y1], 12, fill=CARD, outline=BORDER, width=2)
    center_text(d, (AX0 + AX1) / 2, ROW_Y0 + 22, "Your Dart code", F_H, INK)
    d.text((AX0 + 18, ROW_Y0 + 50), "secure.setString(", font=F_MONO_S, fill=INK)
    d.text((AX0 + 30, ROW_Y0 + 70), "'token',", font=F_MONO_S, fill=INK)
    d.text((AX0 + 30, ROW_Y0 + 90), "'jwt.header…',", font=F_MONO_S, fill=GREEN)
    d.text((AX0 + 18, ROW_Y0 + 110), ")", font=F_MONO_S, fill=INK)

    # Box B: encrypt
    rrect(d, [BX0, ROW_Y0, BX1, ROW_Y1], 12, fill=BLUE_SOFT, outline=BLUE, width=2)
    center_text(d, BCX, ROW_Y0 + 22, "Encrypt", F_H, BLUE)
    center_text(d, BCX, ROW_Y0 + 58, "AES-256-GCM", F_B, INK)
    center_text(d, BCX, ROW_Y0 + 82, "key in AndroidKeyStore /", F_S, MUTED)
    center_text(d, BCX, ROW_Y0 + 100, "iOS Keychain", F_S, MUTED)
    center_text(d, BCX, ROW_Y0 + 120, "hardware-backed", F_S, MUTED)

    # Box C: storage
    rrect(d, [CX0, ROW_Y0, CX1, ROW_Y1], 12, fill=CARD, outline=BORDER, width=2)
    center_text(d, (CX0 + CX1) / 2, ROW_Y0 + 22, "On-device storage", F_H, INK)
    d.text((CX0 + 20, ROW_Y0 + 52), "9f 3a c1 07 e2", font=F_MONO_S, fill=RED)
    d.text((CX0 + 20, ROW_Y0 + 72), "b8 44 6d 2a f0", font=F_MONO_S, fill=RED)
    d.text((CX0 + 20, ROW_Y0 + 92), "1c 9e 55 …", font=F_MONO_S, fill=RED)
    center_text(d, (CX0 + CX1) / 2, ROW_Y1 - 18,
                "unreadable without the key", F_S, MUTED)

    # Arrows between boxes
    arrow(d, AX1 + 6, TRAVEL_Y, BX0 - 6, TRAVEL_Y, BORDER, width=3)
    arrow(d, BX1 + 6, TRAVEL_Y, CX0 - 6, TRAVEL_Y, BORDER, width=3)


# Bottom: multi-process sharing.
PILL_Y0, PILL_Y1 = 320, 372
P1X0, P1X1 = 90, 360
P2X0, P2X1 = 640, 910
STORE_CX, STORE_CY = W / 2, 452
STORE_W, STORE_H = 210, 46


def draw_multiprocess(d, hi):
    """hi in [0,1] highlights the shared-store data flow."""
    # Section label
    center_text(d, W / 2, 292,
                "configure(multiProcess: true) · Android    "
                "configure(appGroupId: …) · iOS Keychain group",
                F_S, MUTED)

    p1c = mix(BORDER, BLUE, hi)
    p2c = mix(BORDER, BLUE, hi)
    rrect(d, [P1X0, PILL_Y0, P1X1, PILL_Y1], 24, fill=CARD, outline=p1c, width=2)
    center_text(d, (P1X0 + P1X1) / 2, (PILL_Y0 + PILL_Y1) / 2,
                "Main app process", F_B, INK)
    rrect(d, [P2X0, PILL_Y0, P2X1, PILL_Y1], 24, fill=CARD, outline=p2c, width=2)
    center_text(d, (P2X0 + P2X1) / 2, (PILL_Y0 + PILL_Y1) / 2,
                "Background service · App extension", F_B, INK)

    # Shared encrypted store (rounded "cylinder")
    sx0, sx1 = STORE_CX - STORE_W / 2, STORE_CX + STORE_W / 2
    sy0, sy1 = STORE_CY - STORE_H / 2, STORE_CY + STORE_H / 2
    rrect(d, [sx0, sy0, sx1, sy1], 14, fill=GREEN_SOFT, outline=GREEN, width=2)
    center_text(d, STORE_CX, STORE_CY - 8, "Shared encrypted store", F_B, GREEN)
    center_text(d, STORE_CX, STORE_CY + 10, "one AES key · one file/group", F_S, MUTED)

    fc = mix(BORDER, GREEN, hi)
    arrow(d, (P1X0 + P1X1) / 2, PILL_Y1 + 4, STORE_CX - 70, sy0 - 4, fc, width=3)
    arrow(d, (P2X0 + P2X1) / 2, PILL_Y1 + 4, STORE_CX + 70, sy0 - 4, fc, width=3)


def draw_packet(d, p):
    """The travelling secret. p in [0,1] across the whole top-row journey."""
    # Journey: A->B (0..0.4), dwell/encrypt at B (0.4..0.58), B->C (0.58..1)
    if p < 0.40:
        t = ease(p / 0.40)
        x = lerp(AX1 + 6, BCX, t)
        label, fill, outline = "token", GREEN_SOFT, GREEN
        txtc = GREEN
    elif p < 0.58:
        # pulsing lock at the encrypt box
        x = BCX
        label, fill, outline = "🔒", AMBER_SOFT, AMBER
        txtc = AMBER
    else:
        t = ease((p - 0.58) / 0.42)
        x = lerp(BCX, CX0 - 6, t)
        label, fill, outline = "9f3a…", RED_SOFT, RED
        txtc = RED

    r = 26
    # keep packet clear of the boxes vertically (ride the arrow line)
    y = TRAVEL_Y
    d.ellipse([x - r, y - r, x + r, y + r], fill=fill, outline=outline, width=2)
    center_text(d, x, y, label, F_S if label != "🔒" else F_H, txtc)


def render_frame(i):
    img = Image.new("RGB", (W, H), BG)
    d = ImageDraw.Draw(img)
    draw_static(d)

    p = i / FRAMES  # global loop progress 0..1

    # Top-row packet runs during the first ~70% of the loop; then it rests at C
    # while the multi-process flow highlights.
    if p < 0.72:
        draw_packet(d, p / 0.72)
    # multi-process highlight ramps up in the back third, pulsing.
    hi = 0.0
    if p >= 0.60:
        hi = ease((p - 0.60) / 0.40)
    draw_multiprocess(d, hi)

    return img


def main():
    out_dir = os.path.abspath(
        os.path.join(os.path.dirname(__file__), "..", "doc", "assets"))
    os.makedirs(out_dir, exist_ok=True)
    out = os.path.join(out_dir, "secure-storage.gif")

    if not shutil.which("ffmpeg"):
        raise SystemExit("ffmpeg is required (brew install ffmpeg)")

    tmp = tempfile.mkdtemp(prefix="secgif_")
    try:
        for i in range(FRAMES):
            render_frame(i).save(os.path.join(tmp, f"f{i:03d}.png"))
        fps = round(1000 / FRAME_MS)
        palette = os.path.join(tmp, "palette.png")
        # Two-pass palette pipeline: far smaller, cleaner flat-colour GIFs than
        # PIL's built-in quantiser. 64 colours is plenty for this flat design.
        subprocess.run(
            ["ffmpeg", "-y", "-framerate", str(fps), "-i",
             os.path.join(tmp, "f%03d.png"),
             "-vf", "palettegen=max_colors=64:stats_mode=diff", palette],
            check=True, capture_output=True)
        subprocess.run(
            ["ffmpeg", "-y", "-framerate", str(fps), "-i",
             os.path.join(tmp, "f%03d.png"), "-i", palette,
             "-lavfi", "paletteuse=dither=bayer:bayer_scale=3", "-loop", "0",
             out],
            check=True, capture_output=True)
    finally:
        shutil.rmtree(tmp, ignore_errors=True)

    print(f"wrote {out} ({os.path.getsize(out) // 1024} KiB, {FRAMES} frames)")


if __name__ == "__main__":
    main()

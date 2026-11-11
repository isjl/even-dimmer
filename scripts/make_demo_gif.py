"""Builds the README demo GIF.

Screen recordings can't capture Even Dimmer's darkest levels (they're applied after
the frame buffer), so this simulates them: a mock desktop with real popup screenshots,
darkened at each step by the light ratio the app measures (same numbers as its
"about N% of Apple's lowest" label). Darkening is done in linear light, which is
conservative.
"""
import sys
from pathlib import Path
from PIL import Image, ImageDraw, ImageFont, ImageFilter

FRAMES = Path(sys.argv[1])
OUT = Path(sys.argv[2])

W, H = 960, 600          # the "laptop screen"
CAP = 64                 # undimmed caption strip under it
SF_REG = "/Library/Fonts/SF-Pro-Text-Regular.otf"
SF_MED = "/Library/Fonts/SF-Pro-Text-Medium.otf"
SF_SEMI = "/Library/Fonts/SF-Pro-Display-Semibold.otf"
NY = "/System/Library/Fonts/NewYork.ttf"

def font(path, size, weight=None):
    if path == "SF":
        path = SF_SEMI if (weight or 400) >= 600 else SF_MED if (weight or 400) >= 500 else SF_REG
    return ImageFont.truetype(path, size)

# Slider position -> share of Apple's lowest light (as reported by the app).
STEPS = [
    (0.35, 1.00), (0.30, 0.78), (0.25, 0.61), (0.20, 0.38),
    (0.15, 0.24), (0.10, 0.15), (0.05, 0.10), (0.0, 0.06),
]

def desktop() -> Image.Image:
    img = Image.new("RGB", (W, H))
    d = ImageDraw.Draw(img)
    # Night-ish wallpaper gradient.
    for y in range(H):
        t = y / H
        d.line([(0, y), (W, y)], fill=(int(40 + 30 * t), int(48 + 20 * t), int(92 - 30 * t)))
    # Menu bar.
    d.rectangle([0, 0, W, 24], fill=(232, 232, 236))
    mf = font("SF", 13, 600)
    x = 16
    for i, word in enumerate(["", "Reader", "File", "Edit", "View", "Window"]):
        if i == 0:
            d.ellipse([x, 7, x + 10, 17], fill=(30, 30, 30)); x += 28; continue
        d.text((x, 5), word, font=mf if i == 1 else font("SF", 13, 400), fill=(25, 25, 25)); x += d.textlength(word, font=mf) + 18
    d.text((W - 80, 5), "11:42 PM", font=font("SF", 13, 500), fill=(25, 25, 25))
    # Even Dimmer's menu bar icon, highlighted (the popup is open).
    d.rounded_rectangle([W - 128, 3, W - 102, 21], 5, fill=(205, 205, 212))
    d.ellipse([W - 120, 7, W - 110, 17], outline=(25, 25, 25), width=2)

    # A reading window (bright page: the thing that's too bright at night).
    wx, wy, ww, wh = 40, 52, 560, 520
    shadow = Image.new("L", (W, H), 0)
    ImageDraw.Draw(shadow).rounded_rectangle([wx, wy + 8, wx + ww, wy + wh + 8], 12, fill=120)
    img.paste((0, 0, 0), mask=shadow.filter(ImageFilter.GaussianBlur(14)))
    d.rounded_rectangle([wx, wy, wx + ww, wy + wh], 12, fill=(250, 248, 243))
    d.rounded_rectangle([wx, wy, wx + ww, wy + 30], 12, fill=(236, 234, 229))
    d.rectangle([wx, wy + 18, wx + ww, wy + 30], fill=(236, 234, 229))
    for i, c in enumerate([(255, 95, 87), (254, 188, 46), (40, 200, 64)]):
        d.ellipse([wx + 12 + i * 20, wy + 9, wx + 24 + i * 20, wy + 21], fill=c)
    tf, bf = font(NY, 24), font(NY, 15)
    d.text((wx + 44, wy + 62), "Chapter Three", font=tf, fill=(30, 30, 30))
    text = ("The house was quiet except for the rain. She read by the light of the "
            "screen, turned down as far as it would go, and still it glowed like a "
            "lamp in the dark room. Somewhere down the hall a door clicked shut. "
            "She lowered it further, and the page settled into the night, soft "
            "enough to read without waking anyone.")
    words, line, y = text.split(), "", wy + 112
    for w in words:
        trial = (line + " " + w).strip()
        if d.textlength(trial, font=bf) > ww - 88:
            d.text((wx + 44, y), line, font=bf, fill=(55, 55, 55)); y += 26; line = w
        else:
            line = trial
    d.text((wx + 44, y), line, font=bf, fill=(55, 55, 55))
    for k in range(6):  # more "text" as soft lines
        y2 = y + 48 + k * 26
        d.rounded_rectangle([wx + 44, y2 + 6, wx + ww - 44 - (k % 3) * 60, y2 + 14], 4, fill=(225, 222, 215))
    return img

def with_popup(base: Image.Image, pos: float) -> Image.Image:
    img = base.copy()
    pop = Image.open(FRAMES / f"pop_{pos:.2f}.png" if pos else FRAMES / "pop_0.0.png").convert("RGBA")
    # Keep the useful top part of the popup (brightness + Night Shift).
    pop = pop.crop((0, 0, pop.width, 700))
    # Fade the cut edge so it doesn't look clipped.
    fade = Image.new("L", pop.size, 255)
    fd = ImageDraw.Draw(fade)
    for i in range(60):
        fd.line([(0, pop.height - 60 + i), (pop.width, pop.height - 60 + i)], fill=int(255 * (1 - i / 60)))
    alpha = Image.composite(pop.getchannel("A"), Image.new("L", pop.size, 0), fade)
    pop.putalpha(alpha)
    scale = 0.5
    pop = pop.resize((int(pop.width * scale), int(pop.height * scale)), Image.LANCZOS)
    img.paste(pop, (W - pop.width + 8, 14), pop)
    return img

def dim(img: Image.Image, ratio: float) -> Image.Image:
    # Scale light in linear space, then re-encode as sRGB.
    lut = []
    for v in range(256):
        c = v / 255
        lin = c / 12.92 if c <= 0.04045 else ((c + 0.055) / 1.055) ** 2.4
        lin *= ratio
        out = lin * 12.92 if lin <= 0.0031308 else 1.055 * lin ** (1 / 2.4) - 0.055
        lut.append(round(out * 255))
    return img.point(lut * 3)

def frame(pos: float, ratio: float, title: str, sub: str) -> Image.Image:
    screen = dim(with_popup(desktop_img, pos), ratio)
    out = Image.new("RGB", (W, H + CAP), (16, 16, 18))
    out.paste(screen, (0, 0))
    d = ImageDraw.Draw(out)
    d.text((24, H + 12), title, font=font("SF", 20, 650), fill=(245, 245, 245))
    d.text((24, H + 38), sub, font=font("SF", 13, 400), fill=(160, 160, 165))
    # Level bar on the right of the caption.
    bx, by, bw = W - 284, H + 27, 260
    d.rounded_rectangle([bx, by, bx + bw, by + 10], 5, fill=(60, 60, 64))
    d.rounded_rectangle([bx, by, bx + max(10, int(bw * ratio)), by + 10], 5, fill=(255, 200, 80))
    return out

desktop_img = desktop()
frames, durations = [], []

def add(img, ms):
    frames.append(img); durations.append(ms)

add(frame(0.35, 1.0, "Apple's lowest brightness", "As dark as macOS lets you go. Still glaring in a dark room."), 1800)
for pos, ratio in STEPS[1:]:
    add(frame(pos, ratio, f"Even Dimmer: {round(ratio * 100)}% of Apple's lowest",
              "Press brightness-down again, or drag the slider past Apple's lowest."), 520)
add(frame(0.0, 0.06, "Even Dimmer: 6% of Apple's lowest",
          "Comfortable for reading at night. Press brightness-up to go back."), 2200)
for pos, ratio in reversed(STEPS[:-1]):
    add(frame(pos, ratio, f"Even Dimmer: {round(ratio * 100)}% of Apple's lowest",
              "Press brightness-up to go back."), 160)

OUT.mkdir(parents=True, exist_ok=True)
with open(OUT / "concat.txt", "w") as c:
    for i, (img, ms) in enumerate(zip(frames, durations)):
        img.save(OUT / f"f{i:02d}.png")
        c.write(f"file 'f{i:02d}.png'\nduration {ms / 1000:.3f}\n")
    c.write(f"file 'f{len(frames) - 1:02d}.png'\n")
print("frames", len(frames), "->", OUT)

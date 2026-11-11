"""Draws Even Dimmer's app icon as an Icon Composer package (Resources/AppIcon.icon).

The idea: a sun turning into a moon. A warm sun on a night-blue background, its rays
fading and shrinking around the circle like a dimmer dial, its core becoming a crescent.

The package has a gradient background fill and two transparent layers (sun, stars).
scripts/build-app.sh compiles it with `actool`: macOS 26 and later get a native icon
(the system adds its glass and lighting effects), and older macOS gets a classic .icns.

Usage: python3 scripts/make_icon.py   (needs Pillow)
"""
import json
import math
import shutil
import subprocess
import tempfile
from pathlib import Path

from PIL import Image, ImageChops, ImageDraw, ImageFilter

ROOT = Path(__file__).resolve().parent.parent
PACKAGE = ROOT / "Resources" / "AppIcon.icon"

SS = 2048          # draw at 2x, then downsample for clean edges
S = SS / 1024      # scale from the 1024 design grid
# Icon Composer canvases are full-bleed; the system masks them to the rounded tile.
# The artwork was designed for the classic 824 px tile, so enlarge it to match.
ZOOM = 1.18

BACKGROUND_TOP = (52, 58, 128)       # indigo
BACKGROUND_BOTTOM = (10, 12, 34)     # near-black navy


def px(v):
    return int(round(v * S))


def zoom(img):
    """Enlarges a layer around its centre, keeping the canvas size."""
    size = img.width
    big = img.resize((int(size * ZOOM), int(size * ZOOM)), Image.LANCZOS)
    off = (big.width - size) // 2
    return big.crop((off, off, off + size, off + size))


def radial_gradient(size, inner, outer, center, radius):
    img = Image.new("RGB", (size, size), outer)
    d = ImageDraw.Draw(img)
    steps = 120
    for i in range(steps, 0, -1):
        t = i / steps
        r = radius * t
        c = tuple(int(inner[k] + (outer[k] - inner[k]) * t) for k in range(3))
        d.ellipse([center[0] - r, center[1] - r, center[0] + r, center[1] + r], fill=c)
    return img


def draw_sun():
    canvas = Image.new("RGBA", (SS, SS), (0, 0, 0, 0))
    cx, cy = SS / 2, px(512)

    # Rays: 12 rounded strokes, fading and shortening clockwise from the top,
    # like a dial being turned down.
    rays = Image.new("RGBA", (SS, SS), (0, 0, 0, 0))
    rd = ImageDraw.Draw(rays)
    count = 12
    for i in range(count):
        t = i / (count - 1)                      # 0 = brightest, 1 = dimmest
        angle = -math.pi / 2 + 2 * math.pi * i / count
        inner = px(235)
        outer = px(345 - 75 * t)
        width = px(46 - 14 * t)
        alpha = int(255 * (1 - 0.82 * t))
        color = (255, int(206 - 40 * t), int(110 - 30 * t), alpha)
        x1, y1 = cx + inner * math.cos(angle), cy + inner * math.sin(angle)
        x2, y2 = cx + outer * math.cos(angle), cy + outer * math.sin(angle)
        rd.line([(x1, y1), (x2, y2)], fill=color, width=width)
        for (x, y) in [(x1, y1), (x2, y2)]:      # round caps
            rd.ellipse([x - width / 2, y - width / 2, x + width / 2, y + width / 2], fill=color)
    canvas = Image.alpha_composite(canvas, rays)

    # Core: a warm disc turning into a crescent, as a night-coloured disc slides over it.
    r = px(165)
    core = radial_gradient(SS, (255, 226, 150), (255, 150, 60), (cx - px(50), cy - px(60)), px(260)).convert("RGBA")
    core_mask = Image.new("L", (SS, SS), 0)
    ImageDraw.Draw(core_mask).ellipse([cx - r, cy - r, cx + r, cy + r], fill=255)
    bite_r = px(150)
    bx, by = cx + px(78), cy + px(46)
    bite = Image.new("L", (SS, SS), 0)
    ImageDraw.Draw(bite).ellipse([bx - bite_r, by - bite_r, bx + bite_r, by + bite_r], fill=255)
    crescent = ImageChops.subtract(core_mask, bite)
    core.putalpha(crescent)

    halo = Image.new("RGBA", (SS, SS), (255, 190, 90, 0))
    halo.putalpha(crescent.filter(ImageFilter.GaussianBlur(px(30))).point(lambda v: int(v * 0.55)))
    canvas = Image.alpha_composite(canvas, halo)
    canvas = Image.alpha_composite(canvas, core)

    # The dimmed part of the disc stays faintly visible, like an unlit moon.
    ghost = Image.new("RGBA", (SS, SS), (255, 220, 170, 0))
    ghost.putalpha(ImageChops.multiply(core_mask, bite).point(lambda v: int(v * 0.12)))
    canvas = Image.alpha_composite(canvas, ghost)
    return zoom(canvas).resize((1024, 1024), Image.LANCZOS)


def draw_stars():
    canvas = Image.new("RGBA", (SS, SS), (0, 0, 0, 0))
    d = ImageDraw.Draw(canvas)
    for x, y, r, a in [(258, 250, 7, 210), (330, 175, 4, 160), (205, 380, 4, 130),
                       (770, 805, 5, 120), (700, 870, 3, 100), (300, 820, 4, 130)]:
        d.ellipse([px(x - r), px(y - r), px(x + r), px(y + r)], fill=(255, 255, 255, a))
    return zoom(canvas).resize((1024, 1024), Image.LANCZOS)


def srgb(c):
    return "srgb:" + ",".join(f"{v / 255:.5f}" for v in c) + ",1.00000"


def write_package():
    if PACKAGE.exists():
        shutil.rmtree(PACKAGE)
    (PACKAGE / "Assets").mkdir(parents=True)
    draw_sun().save(PACKAGE / "Assets" / "sun.png")
    draw_stars().save(PACKAGE / "Assets" / "stars.png")
    icon = {
        "fill": {"linear-gradient": [srgb(BACKGROUND_TOP), srgb(BACKGROUND_BOTTOM)]},
        "groups": [
            {
                "layers": [{"image-name": "sun.png", "name": "sun"}],
                "shadow": {"kind": "layer-color", "opacity": 0.5},
                "translucency": {"enabled": False, "value": 0.5},
            },
            {
                "layers": [{"image-name": "stars.png", "name": "stars", "glass": False}],
                "shadow": {"kind": "none", "opacity": 0.5},
                "translucency": {"enabled": False, "value": 0.5},
            },
        ],
        "supported-platforms": {"squares": ["macOS"]},
    }
    (PACKAGE / "icon.json").write_text(json.dumps(icon, indent=2) + "\n")


def compile_icon(out_dir: Path):
    """Compiles the package the same way build-app.sh does. Returns the .icns path."""
    out_dir.mkdir(parents=True, exist_ok=True)
    subprocess.run(
        ["xcrun", "actool", str(PACKAGE), "--compile", str(out_dir),
         "--platform", "macosx", "--minimum-deployment-target", "13.0",
         "--app-icon", "AppIcon", "--output-partial-info-plist", str(out_dir / "partial.plist"),
         "--output-format", "human-readable-text", "--notices", "--warnings", "--errors"],
        check=True,
    )
    return out_dir / "AppIcon.icns"


def main():
    write_package()
    # Also refresh the README image from the compiled (classic) icon.
    with tempfile.TemporaryDirectory() as tmp:
        icns = compile_icon(Path(tmp))
        iconset = Path(tmp) / "AppIcon.iconset"
        subprocess.run(["iconutil", "-c", "iconset", str(icns), "-o", str(iconset)], check=True)
        Image.open(iconset / "icon_128x128@2x.png").save(ROOT / "docs" / "images" / "icon.png")
    print("wrote", PACKAGE.relative_to(ROOT), "and docs/images/icon.png")


if __name__ == "__main__":
    main()

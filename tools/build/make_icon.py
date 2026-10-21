#!/usr/bin/env python3
"""Builds the SmartOnion icons from the owner's artwork with Pillow (no other dependency).

    python3 tools/build/make_icon.py [--preview SHEET.png]

Reads   tools/build/icon/smartonion_icon_source.png   (1254 px, an armoured onion in a gold ring on black)
Writes  tools/build/icon/smartonion_icon_512.png      the art cut out of its black background, 512 px (master)
        assets/icon/smartonion_icon_256.png           the game's window / taskbar icon (application/config/icon)
        tools/build/SmartOnion.ico                    the Windows executable icon (export_presets.cfg)

The cut-out: the near-black background that touches the image border becomes transparent, so the ring's outer
edge, the tip of the sword, the cape and the leaves keep their shape (a plain circle would chop them off).
Sizes 48 px and up show the whole art; 16 / 24 / 32 px show a tighter, rounded-square crop of the onion's face,
because the full art is mush at that size. The .ico holds 16, 24, 32, 48, 64, 128 and 256 px frames.

The committed outputs only change when the source art changes (export.sh does not run this). --preview writes
a contact sheet of every .ico frame, as stored in the .ico, on a dark and a light background.
"""

import argparse
import io
import sys
from pathlib import Path

from PIL import Image, ImageChops, ImageDraw, ImageFilter

ROOT = Path(__file__).resolve().parents[2]
SOURCE = ROOT / "tools/build/icon/smartonion_icon_source.png"
MASTER = ROOT / "tools/build/icon/smartonion_icon_512.png"
GAME_ICON = ROOT / "assets/icon/smartonion_icon_256.png"
ICO = ROOT / "tools/build/SmartOnion.ico"

ICO_SIZES = [16, 24, 32, 48, 64, 128, 256]
# Frames up to this size use the face crop, bigger ones the whole art.
SMALL_MAX = 32
# Pixels whose brightest channel is below this are "black background" when they connect to the image border.
# (The ring's dark-amber halo is ~60-90, the gold ring starts at ~130.)
BACKGROUND_MAX = 100
# The gold ring (source pixels): centre and the radii of its middle. Inside this ellipse everything is artwork,
# whatever its brightness (dark armour and sky must not count as background); the cut-out only works outside it.
RING_CENTRE = (619.5, 604.5)
RING_MIDDLE_RADII = (583.0, 575.0)
# The face crop in source pixels (left, top, right, bottom): the eyes in the lower middle, the top of the
# bulb and the base of the leaves above them, the red scarf at the bottom.
FACE_BOX = (360, 180, 920, 740)
FACE_CORNER = 0.16
# Margin around the art's bounding box, in source pixels.
PAD = 4
SUPERSAMPLE = 4


def cut_out(src: Image.Image) -> Image.Image:
    """The source as RGBA with the border-connected black background transparent (anti-aliased)."""
    rgb = src.convert("RGB")
    r, g, b = rgb.split()
    brightest = ImageChops.lighter(ImageChops.lighter(r, g), b)
    dark = brightest.point(lambda v: 255 if v < BACKGROUND_MAX else 0)
    w, h = rgb.size
    cx, cy = RING_CENTRE
    rx, ry = RING_MIDDLE_RADII
    ImageDraw.Draw(dark).ellipse((cx - rx, cy - ry, cx + rx, cy + ry), fill=0)
    seeds = [(0, 0), (w - 1, 0), (0, h - 1), (w - 1, h - 1), (w // 2, 0), (w // 2, h - 1), (0, h // 2), (w - 1, h // 2)]
    for seed in seeds:
        if dark.getpixel(seed) == 255:
            ImageDraw.floodfill(dark, seed, 128)
    foreground = dark.point(lambda v: 0 if v == 128 else 255)
    # One pixel of erosion drops the dark fringe of the edge, the blur anti-aliases it.
    mask = foreground.filter(ImageFilter.MinFilter(3)).filter(ImageFilter.GaussianBlur(0.9))
    out = rgb.convert("RGBA")
    out.putalpha(mask)
    return out


def square_crop(art: Image.Image) -> Image.Image:
    """The art cropped square around its (alpha) bounding box, padded with transparency."""
    box = art.getchannel("A").point(lambda v: 255 if v > 8 else 0).getbbox()
    if box is None:
        raise SystemExit("make_icon: the cut-out is empty")
    side = max(box[2] - box[0], box[3] - box[1]) + 2 * PAD
    cx, cy = (box[0] + box[2]) / 2, (box[1] + box[3]) / 2
    left, top = round(cx - side / 2), round(cy - side / 2)
    canvas = Image.new("RGBA", (side, side), (0, 0, 0, 0))
    canvas.paste(art, (-left, -top))
    return canvas


def rounded_square(img: Image.Image, corner: float) -> Image.Image:
    """[param img] with its corners rounded (radius = corner * edge), anti-aliased by supersampling."""
    size = img.width
    big = size * SUPERSAMPLE
    mask = Image.new("L", (big, big), 0)
    ImageDraw.Draw(mask).rounded_rectangle((0, 0, big - 1, big - 1), radius=corner * big, fill=255)
    mask = mask.resize((size, size), Image.Resampling.LANCZOS)
    out = img.convert("RGBA")
    out.putalpha(ImageChops.multiply(out.getchannel("A"), mask))
    return out


def resized(img: Image.Image, size: int) -> Image.Image:
    # Pillow resizes RGBA premultiplied, so transparent pixels do not bleed into the edge.
    return img.resize((size, size), Image.Resampling.LANCZOS)


def build() -> dict:
    """Every output as an RGBA image (the .ico frames by size)."""
    with Image.open(SOURCE) as opened:
        src = opened.convert("RGB")
    art = cut_out(src)
    full = square_crop(art)
    face = rounded_square(src.convert("RGBA").crop(FACE_BOX), FACE_CORNER)
    frames = {}
    for size in ICO_SIZES:
        frame = resized(face if size <= SMALL_MAX else full, size)
        if size <= SMALL_MAX:
            # A touch of sharpening keeps the eyes readable once the face is shrunk to 16-32 px.
            frame = frame.filter(ImageFilter.UnsharpMask(radius=0.7, percent=70, threshold=0))
        frames[size] = frame
    return {"master": resized(full, 512), "game": resized(full, 256), "frames": frames}


def png_bytes(img: Image.Image) -> bytes:
    buf = io.BytesIO()
    img.save(buf, format="PNG", optimize=True)
    return buf.getvalue()


def ico_bytes(frames: dict) -> bytes:
    base = frames[256]
    others = [frames[s] for s in ICO_SIZES if s != 256]
    buf = io.BytesIO()
    base.save(buf, format="ICO", sizes=[(s, s) for s in ICO_SIZES], append_images=others)
    return buf.getvalue()


def preview(frames: dict, path: Path) -> None:
    """A contact sheet: every frame as stored (read back from the .ico) at 1x, and the small ones at 4x, on a
    dark and a light background (the Windows taskbar and Explorer use both)."""
    with Image.open(io.BytesIO(ico_bytes(frames))) as ico:
        stored = sorted(s[0] for s in ico.info["sizes"])
        read = {}
        for size in stored:
            ico.size = (size, size)
            read[size] = ico.convert("RGBA")
    gap, zoom, zoomed_max = 20, 4, 64
    row1_w = gap + sum(read[s].width + gap for s in stored)
    row2_w = gap + sum(read[s].width * zoom + gap for s in stored if s <= zoomed_max)
    width = max(row1_w, row2_w)
    band_h = 256 + zoomed_max * zoom + 3 * gap
    sheet = Image.new("RGBA", (width, band_h * 2), (0, 0, 0, 255))
    for band, bg in enumerate([(32, 34, 42, 255), (236, 236, 232, 255)]):
        top = band * band_h
        ImageDraw.Draw(sheet).rectangle((0, top, width, top + band_h), fill=bg)
        x = gap
        for size in stored:
            sheet.alpha_composite(read[size], (x, top + gap + 256 - size))
            x += size + gap
        x = gap
        for size in [s for s in stored if s <= zoomed_max]:
            big = read[size].resize((size * zoom, size * zoom), Image.Resampling.NEAREST)
            sheet.alpha_composite(big, (x, top + 2 * gap + 256))
            x += big.width + gap
    sheet.convert("RGB").save(path)
    print("make_icon: preview %s (%s)" % (path, ", ".join(str(s) for s in stored)))


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__.split("\n")[0])
    parser.add_argument("--preview", metavar="SHEET.png", help="also write a contact sheet of the .ico frames")
    args = parser.parse_args()
    if not SOURCE.is_file():
        print("make_icon: the source art is missing: %s" % SOURCE, file=sys.stderr)
        return 1
    out = build()
    files = {MASTER: png_bytes(out["master"]), GAME_ICON: png_bytes(out["game"]), ICO: ico_bytes(out["frames"])}
    for path, data in files.items():
        path.parent.mkdir(parents=True, exist_ok=True)
        path.write_bytes(data)
        print("make_icon: wrote %s (%d bytes)" % (path.relative_to(ROOT), len(data)))
    if args.preview:
        preview(out["frames"], Path(args.preview))
    return 0


if __name__ == "__main__":
    sys.exit(main())

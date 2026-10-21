#!/usr/bin/env python3
"""Renders the 3 s "rotate your device" card that opens the trailer (for phones held upright).

A gold phone outline turns from portrait to landscape over the dark end-card backdrop, with
"ROTATE YOUR DEVICE" in Cinzel under it. Writes PNG frames; make_trailer.sh / the README show how
they are encoded and put in front of the cut.

Usage: rotate_card.py <out_dir> [--fps 30] [--seconds 3] [--font <Cinzel ttf>]
"""
import argparse
import math
import os

from PIL import Image, ImageDraw, ImageFilter, ImageFont

W, H = 1920, 1080
GOLD = (232, 184, 74)
GOLD_DIM = (176, 132, 52)
TEXT_SOFT = (214, 196, 160)
BG_CENTRE = (44, 24, 14)
BG_EDGE = (10, 6, 4)
PHONE_W, PHONE_H = 150, 270


def backdrop() -> Image.Image:
	"""Radial warm-dark gradient, like the trailer's end card."""
	small = Image.new("RGB", (W // 8, H // 8))
	px = small.load()
	cx, cy = small.width / 2, small.height / 2
	max_d = math.hypot(cx, cy)
	for y in range(small.height):
		for x in range(small.width):
			t = min(1.0, math.hypot(x - cx, y - cy) / max_d)
			t = t * t
			px[x, y] = tuple(int(BG_CENTRE[i] + (BG_EDGE[i] - BG_CENTRE[i]) * t) for i in range(3))
	return small.resize((W, H), Image.BICUBIC)


def phone_layer() -> Image.Image:
	"""The phone outline (portrait), with a little screen and home dot, on a transparent layer."""
	pad = 40
	layer = Image.new("RGBA", (PHONE_W + pad * 2, PHONE_H + pad * 2), (0, 0, 0, 0))
	d = ImageDraw.Draw(layer)
	box = (pad, pad, pad + PHONE_W, pad + PHONE_H)
	d.rounded_rectangle(box, radius=26, outline=GOLD + (255,), width=9)
	inner = (pad + 18, pad + 34, pad + PHONE_W - 18, pad + PHONE_H - 44)
	d.rounded_rectangle(inner, radius=6, fill=GOLD + (46,))
	cx = pad + PHONE_W / 2
	d.ellipse((cx - 8, pad + PHONE_H - 32, cx + 8, pad + PHONE_H - 16), outline=GOLD + (255,), width=4)
	glow = layer.filter(ImageFilter.GaussianBlur(10))
	return Image.alpha_composite(glow, layer)


def arrow_layer(alpha: int) -> Image.Image:
	"""A curved arrow around the phone, showing the turn direction (clockwise)."""
	layer = Image.new("RGBA", (W, H), (0, 0, 0, 0))
	d = ImageDraw.Draw(layer)
	cx, cy, r = W / 2, H / 2 - 70, 230
	d.arc((cx - r, cy - r, cx + r, cy + r), start=-150, end=-40, fill=GOLD_DIM + (alpha,), width=8)
	tip = math.radians(-40)
	tx, ty = cx + r * math.cos(tip), cy + r * math.sin(tip)
	head = [(tx + 26, ty - 6), (tx - 20, ty - 26), (tx - 6, ty + 22)]
	d.polygon(head, fill=GOLD_DIM + (alpha,))
	return layer


def ease(t: float) -> float:
	t = max(0.0, min(1.0, t))
	return t * t * (3.0 - 2.0 * t)


def main() -> None:
	here = os.path.dirname(os.path.abspath(__file__))
	ap = argparse.ArgumentParser()
	ap.add_argument("out_dir")
	ap.add_argument("--fps", type=int, default=30)
	ap.add_argument("--seconds", type=float, default=3.0)
	ap.add_argument("--font", default=os.path.join(here, "..", "..", "assets", "fonts", "Cinzel-VariableFont_wght.ttf"))
	args = ap.parse_args()
	os.makedirs(args.out_dir, exist_ok=True)

	title = ImageFont.truetype(args.font, 72)
	sub = ImageFont.truetype(args.font, 34)
	for f, w in ((title, 800), (sub, 600)):
		try:
			f.set_variation_by_axes([w])
		except Exception:
			pass  # a static font: use as is

	bg = backdrop()
	phone = phone_layer()
	frames = int(round(args.fps * args.seconds))
	for i in range(frames):
		t = i / args.fps
		# 0.0-0.4 s fade in; 0.5-1.4 s turn 0 -> 90 degrees (clockwise); hold; last 0.35 s fade out.
		fade = ease(t / 0.4) * (1.0 - ease((t - (args.seconds - 0.35)) / 0.35))
		angle = -90.0 * ease((t - 0.5) / 0.9)
		frame = bg.copy().convert("RGBA")
		turned = phone.rotate(angle, resample=Image.BICUBIC, expand=True)
		frame.alpha_composite(turned, (int(W / 2 - turned.width / 2), int(H / 2 - 70 - turned.height / 2)))
		frame = Image.alpha_composite(frame, arrow_layer(int(200 * (1.0 - ease((t - 1.2) / 0.4)))))
		d = ImageDraw.Draw(frame)
		d.text((W / 2, H / 2 + 230), "ROTATE YOUR DEVICE", font=title, fill=GOLD + (255,), anchor="mm")
		d.text((W / 2, H / 2 + 305), "for the best view", font=sub, fill=TEXT_SOFT + (255,), anchor="mm")
		black = Image.new("RGBA", (W, H), (0, 0, 0, int(255 * (1.0 - fade))))
		frame = Image.alpha_composite(frame, black).convert("RGB")
		frame.save(os.path.join(args.out_dir, "rotate_%03d.png" % i))


if __name__ == "__main__":
	main()

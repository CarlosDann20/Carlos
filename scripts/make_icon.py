#!/usr/bin/env python3
"""Generate Memora's 1024x1024 app icon: a dark blue-black gradient with a
stacked-cards motif in the accent colour. Uses Pillow."""
import os, math
from PIL import Image, ImageDraw

S = 1024
out = os.path.join(os.path.dirname(__file__), "..", "Memora", "Resources",
                   "Assets.xcassets", "AppIcon.appiconset", "AppIcon-1024.png")

img = Image.new("RGB", (S, S), (14, 17, 23))
px = img.load()
# Vertical gradient from #0E1117 to #1B2436
top = (14, 17, 23); bot = (27, 36, 54)
for y in range(S):
    t = y / (S - 1)
    r = int(top[0] + (bot[0]-top[0]) * t)
    g = int(top[1] + (bot[1]-top[1]) * t)
    b = int(top[2] + (bot[2]-top[2]) * t)
    for x in range(S):
        px[x, y] = (r, g, b)

draw = ImageDraw.Draw(img, "RGBA")

def rounded(cx, cy, w, h, radius, fill):
    draw.rounded_rectangle([cx - w//2, cy - h//2, cx + w//2, cy + h//2], radius=radius, fill=fill)

# Three stacked cards (back to front), accent gradient-ish.
accent = (124, 136, 255)
rounded(512, 470, 520, 360, 56, (124, 136, 255, 70))
rounded(512, 520, 520, 360, 56, (124, 136, 255, 130))
rounded(512, 575, 540, 380, 60, (124, 136, 255, 255))

# "M" on the front card.
draw.line([(360, 700), (360, 470), (512, 610), (664, 470), (664, 700)],
          fill=(14, 17, 23), width=46, joint="curve")

img.save(out, "PNG")
print("wrote", os.path.abspath(out), os.path.getsize(out), "bytes")

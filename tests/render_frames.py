"""Render recorded editor frames (tests/lua/ui_harness.lua dump) to PNG, for reviewing the layout offline.

The overlay's rectangles and text are drawn in layer order over a neutral game-like backdrop. Text uses Bahnschrift
as a stand-in for FS Sinclair (the game's font is not on disk); widths come from the Runtime's real FS Sinclair
metrics, so clipping and alignment match the game closely.
"""
import json
import sys
from pathlib import Path

from PIL import Image, ImageDraw, ImageFont

FONT = r'C:\Windows\Fonts\bahnschrift.ttf'


def render(frame, path, backdrop=(46, 52, 58)):
    w, h = frame['width'], frame['height']
    base = Image.new('RGBA', (w, h), backdrop + (255,))
    # a soft gradient so translucency reads
    grad = ImageDraw.Draw(base)
    for y in range(h):
        t = y / h
        grad.line([(0, y), (w, y)], fill=(int(40 + 30 * t), int(48 + 22 * t), int(56 + 10 * t), 255))
    items = sorted(enumerate(frame['items']), key=lambda p: (p[1]['z'], p[0]))
    fonts = {}
    for _, it in items:
        layer = Image.new('RGBA', (w, h), (0, 0, 0, 0))
        d = ImageDraw.Draw(layer)
        r, g, b, a = it['c']
        if it['k'] == 'i':
            # an icon mask (images/<id>.png): R in the accent colour, G white, as the game's icon material draws it
            icon = Path(__file__).resolve().parents[1] / 'images' / (it['image'] + '.png')
            if icon.is_file():
                mask = Image.open(icon).convert('RGB').resize((int(it['w']), int(it['h'])))
                rr, gg, _ = mask.split()
                accent = Image.new('RGBA', mask.size, (r, g, b, 255))
                white = Image.new('RGBA', mask.size, (255, 255, 238, 255))
                tile = Image.new('RGBA', mask.size, (0, 0, 0, 0))
                tile = Image.composite(accent, tile, rr)
                tile = Image.composite(white, tile, gg)
                layer.paste(tile, (int(it['x']), int(it['y'])), tile)
            base = Image.alpha_composite(base, layer)
            continue
        if it['k'] == 'r':
            d.rectangle([it['x'], it['y'], it['x'] + it['w'] - 1, it['y'] + it['h'] - 1], fill=(r, g, b, a))
        else:
            size = int(round(it['size'] * 0.86))
            key = (size, it['font'])
            if key not in fonts:
                f = ImageFont.truetype(FONT, size)
                try:
                    f.set_variation_by_name('SemiBold' if it['font'] == 'title' else 'Regular')
                except Exception:
                    pass
                fonts[key] = f
            # overlay text: (x, y) is the top of the line; FS Sinclair ascent 49.25/56 em to the baseline
            baseline = it['y'] + it['size'] * 49.25 / 56
            d.text((it['x'], baseline), it['s'], font=fonts[key], fill=(r, g, b, a), anchor='ls')
        base = Image.alpha_composite(base, layer)
    base.convert('RGB').save(path)


if __name__ == '__main__':
    for src in sys.argv[1:]:
        frame = json.loads(Path(src).read_text(encoding='utf-8'))
        out = Path(src).with_suffix('.png')
        render(frame, out)
        print(out)

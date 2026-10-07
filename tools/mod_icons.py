"""The installed mods' own icons as the editor's images (a local, opt-in build step, like tools/game_icons.py).

    py tools/mod_icons.py            # from the deployed mods of Echelon or HD2 Arsenal, then build normally
    py tools/mod_icons.py --clean    # remove them again

The overlay draws a mod image as three colour masks (R, G and B, each painted one colour: HD2Runtime d:image), so a
picture is reduced to its own most common colours and drawn as stacked mask layers: LAYERS layers of 3 colours each.
Every pixel belongs to exactly one colour, its coverage is the picture's own alpha, and the colours are the
picture's own (median cut over its pixels): nothing is drawn, only re-coloured into the palette.

Reads (read-only) %APPDATA%\\Echelon\\state.json or %LOCALAPPDATA%\\hd2arsenal\\hd2a_data.json, whichever deployed
last, and each deployed mod's icon file. Writes images/mi_<id>_<layer>.png and src/editor/generated/mod_icons.lua:
key -> layers ({image, colours = {r, g, b}}), keyed by 'echelon:<id>' / 'arsenal:<uuid>', 'guid:<guid>' and
'resource:<lua addon id>'.

The icons are the mod authors' artwork: they are git-ignored and end up only in builds you make yourself.
"""
import argparse
import json
import os
import re
import sys
from datetime import datetime
from pathlib import Path

PROJECT = Path(__file__).resolve().parents[1]
IMAGES = PROJECT / 'images'
GENERATED = PROJECT / 'src' / 'editor' / 'generated' / 'mod_icons.lua'
PREFIX = 'mi_'
LAYERS = 3
SIZE = 256


def echelon():
    folder = Path(os.environ.get('APPDATA', '')) / 'Echelon'
    path = folder / 'state.json'
    if not path.is_file():
        return None
    state = json.loads(path.read_text(encoding='utf-8'))
    mods = []
    for mid in state.get('slots', {}):
        e = state.get('library', {}).get(mid)
        if not e:
            continue
        addons = [a for s in (e.get('scan') or {}).get('sets', []) for a in s.get('addons', [])]
        image = folder / 'images' / e['image'] if e.get('image') else None
        mods.append({'keys': ['echelon:' + mid] + (['guid:' + e['guid']] if e.get('guid') else [])
                     + ['resource:' + a for a in addons], 'name': e.get('name', mid), 'image': image, 'id': mid})
    at = state.get('deployed_at') or ''
    try:
        stamp = datetime.strptime(at, '%Y-%m-%d %H:%M').timestamp()
    except ValueError:
        stamp = 0
    return stamp, 'Echelon', mods


def arsenal():
    folder = Path(os.environ.get('LOCALAPPDATA', '')) / 'hd2arsenal'
    path = folder / 'hd2a_data.json'
    if not path.is_file():
        return None
    state = json.loads(path.read_text(encoding='utf-8'))
    library = {e.get('uuid'): e for e in state.get('modsLibrary', [])}
    profile = (state.get('modsList') or {}).get(state.get('deployedProfile') or '') or {}
    mods = []
    for m in profile.get('mods', []):
        e = library.get(m.get('uuid'))
        if not e or m.get('deployed') is False or m.get('enabled') is False:
            continue
        image = Path(e['iconPath']) if e.get('iconPath') else None
        mods.append({'keys': ['arsenal:' + m['uuid'], 'guid:' + m['uuid']], 'name': e.get('label'), 'image': image,
                     'id': m['uuid']})
    stamp = 0
    snap = folder / 'deployment_snapshot.json'
    if snap.is_file():
        try:
            t = json.loads(snap.read_text(encoding='utf-8')).get('timestamp')
            stamp = t / 1000 if isinstance(t, (int, float)) and t > 1e11 else (t or 0)
            if isinstance(stamp, str):
                stamp = datetime.fromisoformat(stamp.replace('Z', '+00:00')).timestamp()
        except (ValueError, TypeError):
            stamp = 0
    return stamp, 'HD2 Arsenal', mods


def layers_of(path):
    """The picture as LAYERS RGB mask images and their colours, or None."""
    from PIL import Image
    try:
        img = Image.open(path)
        img.load()
    except OSError:
        return None
    img = img.convert('RGBA')
    # square, centred, 256 x 256
    side = max(img.size)
    canvas = Image.new('RGBA', (side, side), (0, 0, 0, 0))
    canvas.paste(img, ((side - img.width) // 2, (side - img.height) // 2))
    img = canvas.resize((SIZE, SIZE), Image.LANCZOS)
    alpha = img.getchannel('A')
    rgb = Image.new('RGB', img.size, (0, 0, 0))
    rgb.paste(img.convert('RGB'), mask=alpha)
    colours = LAYERS * 3
    pal = rgb.quantize(colors=colours, method=Image.Quantize.MEDIANCUT, dither=Image.Dither.NONE)
    palette = pal.getpalette()[:colours * 3]
    index = pal.load()
    a = alpha.load()
    masks = [[Image.new('L', img.size, 0) for _ in range(3)] for _ in range(LAYERS)]
    pixels = [[m.load() for m in layer] for layer in masks]
    used = set()
    for y in range(SIZE):
        for x in range(SIZE):
            cover = a[x, y]
            if cover == 0:
                continue
            i = index[x, y]
            used.add(i)
            pixels[i // 3][i % 3][x, y] = cover
    out = []
    for layer in range(LAYERS):
        cols = []
        for ch in range(3):
            i = layer * 3 + ch
            cols.append(tuple(palette[i * 3:i * 3 + 3]) + ((255,) if i in used else (0,)))
        if not any(layer * 3 + ch in used for ch in range(3)):
            continue
        out.append((Image.merge('RGB', masks[layer]), cols))
    return out


def lua_string(text):
    return '"' + text.replace('\\', '\\\\').replace('"', '\\"') + '"'


def clean(quiet=False):
    n = 0
    for p in IMAGES.glob(PREFIX + '*.png'):
        p.unlink()
        n += 1
    if not quiet:
        if GENERATED.is_file():
            GENERATED.unlink()
        print('removed %d mod icon images' % n)


def main():
    parser = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    parser.add_argument('--clean', action='store_true')
    args = parser.parse_args()
    if args.clean:
        clean()
        return 0
    sources = [s for s in (echelon(), arsenal()) if s]
    if not sources:
        sys.exit('no Echelon or HD2 Arsenal state found')
    stamp, source, mods = max(sources, key=lambda s: s[0])
    clean(quiet=True)
    IMAGES.mkdir(exist_ok=True)
    entries = []
    for m in mods:
        if not m['image'] or not Path(m['image']).is_file():
            continue
        layers = layers_of(m['image'])
        if not layers:
            continue
        slug = re.sub(r'[^a-z0-9]+', '', m['id'].lower())[:16]
        items = []
        for n, (image, cols) in enumerate(layers, 1):
            iid = '%s%s_%d' % (PREFIX, slug, n)
            image.save(IMAGES / (iid + '.png'), optimize=True)
            items.append((iid, cols))
        entries.append((m, items))
    lines = ['-- Generated by tools/mod_icons.py from the deployed mods (%s); do not edit. Not committed.' % source,
             'return {source=%s,icons={' % lua_string(source)]
    for m, items in entries:
        layer_text = ','.join('{image=%s,colours={r={%d,%d,%d,%d},g={%d,%d,%d,%d},b={%d,%d,%d,%d}}}' % (
            lua_string(iid), *cols[0], *cols[1], *cols[2]) for iid, cols in items)
        for key in m['keys']:
            lines.append('  [%s]={%s},' % (lua_string(key), layer_text))
    lines.append('}}')
    GENERATED.parent.mkdir(parents=True, exist_ok=True)
    GENERATED.write_text('\n'.join(lines) + '\n', encoding='utf-8', newline='\n')
    print('%d of %d deployed mods have an icon (%s) -> images/%s*.png, %s' % (
        len(entries), len(mods), source, PREFIX, GENERATED.relative_to(PROJECT)))
    return 0


if __name__ == '__main__':
    sys.exit(main())

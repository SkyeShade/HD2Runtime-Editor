"""The game's own stratagem and booster icons as the editor's images (a local, opt-in build step).

    py tools/game_icons.py                        # from the installed game (read-only), then build normally
    py tools/game_icons.py --game "D:\\SteamLibrary\\steamapps\\common\\Helldivers 2\\data"
    py tools/game_icons.py --clean                # remove the generated icons again

What it does:
1. Reads the game's vector icon libraries (content/ui/shared/resources/generated_icons/stratagem_icons and
   booster_icons, Noesis XAML) from your Helldivers 2 data folder through the HD2Runtime SDK's read-only game data
   reader. Nothing is written to the game folder.
2. Converts each icon to SVG as HD2Runtime ModBuilder does (Viewbox/Canvas/Path; unknown content is skipped).
3. Recolours it into the game's icon masks: the category accent colour becomes the R mask, white and light grey the G
   mask, the dark plate nothing. In game the overlay colours R with the icon's own accent and G white
   (HD2Runtime d:image), so the icon looks as it does on the loadout screen.
4. Rasterises every icon at 256 x 256 in one headless Microsoft Edge pass and writes images/si_<key>.png (stratagems)
   and images/bi_<key>.png (boosters), only for icons the HD2Runtime catalogues bind to a stratagem or booster
   (StratagemAuthoringCapabilities uiIcon, BoosterAuthoringCapabilities identity.uiIcon).
5. Writes src/editor/generated/game_icons.lua: stratagem and booster name -> {image id, accent colour}.

The images are derived from Arrowhead's artwork. They are git-ignored and are packed only into builds you make
yourself; publish a build with them only if you are allowed to redistribute them.
"""
import argparse
import hashlib
import json
import os
import re
import shutil
import subprocess
import sys
import tempfile
import xml.etree.ElementTree as ET
from pathlib import Path

PROJECT = Path(__file__).resolve().parents[1]
IMAGES = PROJECT / 'images'
GENERATED = PROJECT / 'src' / 'editor' / 'generated' / 'game_icons.lua'
LIBRARIES = {
    'stratagem': 'content/ui/shared/resources/generated_icons/stratagem_icons',
    'booster': 'content/ui/shared/resources/generated_icons/booster_icons',
}
PREFIX = {'stratagem': 'si_', 'booster': 'bi_'}
# Reviewed by hand: the library icon of a stratagem whose type binding is missing (uiIcon state 'unbound').
UNBOUND = {'AC-8 Autocannon': 'StratagemWeaponAutocannon'}
NS = '{http://schemas.microsoft.com/winfx/2006/xaml/presentation}'
X = '{http://schemas.microsoft.com/winfx/2006/xaml}'
KEY = re.compile(r'\A[A-Za-z][A-Za-z0-9]{0,63}\Z')
PATH_DATA = re.compile(r'\A[MmLlHhVvCcSsQqTtAaZz0-9eE+\-.,\s]{1,200000}\Z')
COLOUR = re.compile(r'\A#([0-9A-Fa-f]{2})?([0-9A-Fa-f]{6})\Z')
BROWSERS = [os.environ.get('HD2_ART_BROWSER', ''), r'C:\Program Files (x86)\Microsoft\Edge\Application\msedge.exe',
            r'C:\Program Files\Microsoft\Edge\Application\msedge.exe',
            r'C:\Program Files\Google\Chrome\Application\chrome.exe']


# ------------------------------------------------------------------------------------------------ inputs --
def find_sdk(explicit=None):
    spec = json.loads((PROJECT / 'hd2runtime.json').read_text(encoding='utf-8'))
    for path in [explicit, os.environ.get('HD2RUNTIME_SDK'), spec.get('sdk') and str(PROJECT / spec['sdk'])]:
        if path and (Path(path) / 'tools' / 'hd2_game_data.py').is_file():
            return Path(path).resolve()
    sys.exit('HD2Runtime SDK not found: pass --sdk or set HD2RUNTIME_SDK (the folder holding hd2.py and tools/).')


def read_libraries(sdk, game):
    sys.path.insert(0, str(sdk / 'tools'))
    import hd2_game_data
    data = hd2_game_data.Data(game) if game else hd2_game_data.Data()
    xaml_type = hd2_game_data.murmur64(b'xaml')
    wanted = {kind: (hd2_game_data.murmur64(name.encode()), xaml_type) for kind, name in LIBRARIES.items()}
    found = data.find(set(wanted.values()))
    out = {}
    for kind, key in wanted.items():
        if key not in found:
            sys.exit('the game data has no ' + LIBRARIES[kind] + ' (is this a Helldivers 2 data folder?)')
        archive, main, _stream, _gpu = found[key]
        raw = data.read(archive, main)
        size = int.from_bytes(raw[0:4], 'little')
        if size > len(raw) - 16:
            sys.exit('unexpected XAML resource layout for ' + LIBRARIES[kind])
        out[kind] = (raw[16:16 + size].decode('utf-8'), hashlib.sha256(raw).hexdigest())
    return out


def bindings(sdk):
    """{'stratagem': {name: icon key}, 'booster': {name: icon key}} from the SDK catalogues."""
    strat = json.loads((sdk / 'StratagemAuthoringCapabilities.json').read_text(encoding='utf-8'))
    boost = json.loads((sdk / 'BoosterAuthoringCapabilities.json').read_text(encoding='utf-8'))
    out = {'stratagem': {}, 'booster': {}}
    for s in strat.get('stratagems', []):
        icon = s.get('uiIcon') or {}
        if icon.get('state') == 'resolved' and icon.get('iconKey'):
            out['stratagem'][s['name']] = icon['iconKey']
    # Stratagems whose native type the game's icon template leaves unbound, but whose icon the library has.
    for name, key in UNBOUND.items():
        out['stratagem'].setdefault(name, key)
    for b in boost.get('boosters', []):
        key = (b.get('identity') or {}).get('uiIcon')
        if key:
            out['booster'][b['name']] = key
    return out


# --------------------------------------------------------------------------------------------- XAML -> SVG --
def number(value):
    try:
        v = float(value)
        return v if v == v and abs(v) != float('inf') else None
    except (TypeError, ValueError):
        return None


def fmt(v):
    return ('%.4f' % v).rstrip('0').rstrip('.')


def classify(colour):
    """A Noesis colour -> (mask colour, accent rgb or None, opacity)."""
    m = COLOUR.match((colour or '').strip())
    if not m:
        return None, None, 1.0
    alpha = int(m.group(1), 16) / 255 if m.group(1) else 1.0
    rgb = tuple(int(m.group(2)[i:i + 2], 16) for i in (0, 2, 4))
    hi, lo = max(rgb), min(rgb)
    lum = (0.299 * rgb[0] + 0.587 * rgb[1] + 0.114 * rgb[2]) / 255
    if hi - lo > 56:
        return '#FF0000', rgb, alpha
    if lum > 0.5:
        return '#00%02X00' % round(lum * 255), None, alpha
    return '#000000', None, alpha


def to_svgs(xaml):
    """{key: (mask svg, accent rgb)} for every vector DataTemplate (ModBuilder's XamlIcons.ToSvgs, recoloured)."""
    root = ET.fromstring(xaml)
    out = {}
    for template in root.findall(NS + 'DataTemplate'):
        key = template.get(X + 'Key')
        if not key or not KEY.match(key):
            continue
        viewbox = template.find(NS + 'Viewbox')
        canvas = (viewbox.find(NS + 'Canvas') if viewbox is not None else None)
        if canvas is None:
            canvas = template.find(NS + 'Canvas')
        paths = (canvas if canvas is not None else template).findall(NS + 'Path')
        if not paths:
            continue
        width = number(canvas.get('Width')) if canvas is not None else None
        height = number(canvas.get('Height')) if canvas is not None else None
        if not width or not height or width > 4096 or height > 4096:
            width = height = 256
        parts = ['<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 %s %s" width="256" height="256" '
                 'preserveAspectRatio="xMidYMid meet">' % (fmt(width), fmt(height))]
        accents = {}
        ok = True
        for p in paths:
            data = (p.get('Data') or '').strip()
            rule = 'evenodd'
            if data.startswith('F0'):
                data = data[2:]
            elif data.startswith('F1'):
                rule, data = 'nonzero', data[2:]
            if not PATH_DATA.match(data):
                ok = False
                break
            fill = p.get('Fill')
            if fill is None:
                brush = p.find(NS + 'Path.Fill/' + NS + 'SolidColorBrush')
                fill = brush.get('Color') if brush is not None else None
            attrs = ['d="%s"' % data, 'fill-rule="%s"' % rule]
            mask, accent, alpha = classify(fill)
            attrs.append('fill="%s"' % (mask or 'none'))
            if alpha < 1:
                attrs.append('fill-opacity="%s"' % fmt(alpha))
            if accent:
                accents[accent] = accents.get(accent, 0) + 1
            stroke = p.get('Stroke')
            if stroke:
                smask, saccent, salpha = classify(stroke)
                attrs.append('stroke="%s"' % (smask or 'none'))
                if saccent:
                    accents[saccent] = accents.get(saccent, 0) + 1
                thickness = number(p.get('StrokeThickness'))
                if thickness is not None:
                    attrs.append('stroke-width="%s"' % fmt(thickness))
            left, top = number(p.get('Canvas.Left')) or 0, number(p.get('Canvas.Top')) or 0
            matrix = p.find(NS + 'Path.RenderTransform/' + NS + 'MatrixTransform')
            if matrix is not None and matrix.get('Matrix'):
                m = [number(v) for v in matrix.get('Matrix').split(',')]
                if len(m) != 6 or any(v is None for v in m):
                    ok = False
                    break
                attrs.append('transform="matrix(%s %s %s %s %s %s)"' % (fmt(m[0]), fmt(m[1]), fmt(m[2]), fmt(m[3]),
                                                                       fmt(left), fmt(top)))
            elif left or top:
                attrs.append('transform="translate(%s %s)"' % (fmt(left), fmt(top)))
            parts.append('<path ' + ' '.join(attrs) + '/>')
        if ok:
            accent = max(accents.items(), key=lambda kv: kv[1])[0] if accents else (255, 255, 255)
            out[key] = (''.join(parts) + '</svg>', accent)
    return out


# ---------------------------------------------------------------------------------------------- raster --
def browser():
    for path in BROWSERS:
        if path and Path(path).is_file():
            return path
    for name in ('msedge', 'chrome', 'chromium'):
        if shutil.which(name):
            return shutil.which(name)
    sys.exit('No Edge or Chrome found; set HD2_ART_BROWSER to a Chromium browser executable.')


def rasterise(items):
    """{image id: svg} -> {image id: PIL image 256 x 256 RGB}, through one headless browser screenshot."""
    from PIL import Image
    ids = sorted(items)
    columns = 10
    rows = (len(ids) + columns - 1) // columns
    cells = ''.join('<div>%s</div>' % items[i] for i in ids)
    html = ('<!doctype html><html><head><style>html,body{margin:0;background:#000;overflow:hidden}'
            'body{display:grid;grid-template-columns:repeat(%d,256px);grid-auto-rows:256px}'
            'div{width:256px;height:256px}svg{display:block;width:256px;height:256px}</style></head><body>%s</body></html>'
            % (columns, cells))
    with tempfile.TemporaryDirectory() as tmp:
        page = Path(tmp) / 'sheet.html'
        page.write_text(html, encoding='utf-8')
        shot = Path(tmp) / 'sheet.png'
        subprocess.run([browser(), '--headless=new', '--disable-gpu', '--hide-scrollbars', '--no-first-run',
                        '--user-data-dir=' + str(Path(tmp) / 'profile'), '--force-device-scale-factor=1',
                        '--window-size=%d,%d' % (columns * 256, rows * 256), '--screenshot=' + str(shot), page.as_uri()],
                       check=True, stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL, timeout=120)
        sheet = Image.open(shot).convert('RGB')
        sheet.load()
    out = {}
    for index, image_id in enumerate(ids):
        x, y = (index % columns) * 256, (index // columns) * 256
        tile = sheet.crop((x, y, x + 256, y + 256))
        # masks: B must stay empty (the SDK then uses the picture as given)
        r, g, _b = tile.split()
        out[image_id] = Image.merge('RGB', (r, g, Image.new('L', tile.size, 0)))
    return out


def lua_string(text):
    return '"' + text.replace('\\', '\\\\').replace('"', '\\"') + '"'


def clean():
    removed = 0
    for path in IMAGES.glob('*.png'):
        if path.name.startswith(tuple(PREFIX.values())):
            path.unlink()
            removed += 1
    if GENERATED.is_file():
        GENERATED.unlink()
    print('removed %d generated icons' % removed)


def main():
    parser = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    parser.add_argument('--game', help='the Helldivers 2 data folder (default: the Steam install)')
    parser.add_argument('--sdk', help='the HD2Runtime SDK folder (default: HD2RUNTIME_SDK or hd2runtime.json "sdk")')
    parser.add_argument('--clean', action='store_true', help='remove the generated icons and mapping')
    args = parser.parse_args()
    if args.clean:
        clean()
        return 0
    sdk = find_sdk(args.sdk)
    libraries = read_libraries(sdk, args.game)
    names = bindings(sdk)
    svgs, mapping, sources = {}, {'stratagem': {}, 'booster': {}}, {}
    for kind, (xaml, digest) in libraries.items():
        icons = to_svgs(xaml)
        sources[kind] = {'resource': LIBRARIES[kind], 'sha256': digest, 'icons': len(icons)}
        for name, key in names[kind].items():
            if key not in icons:
                continue
            image_id = PREFIX[kind] + key.lower()
            svgs[image_id] = icons[key][0]
            mapping[kind][name] = (image_id, icons[key][1])
    images = rasterise(svgs)
    clean_quiet = [p for p in IMAGES.glob('*.png') if p.name.startswith(tuple(PREFIX.values()))]
    for path in clean_quiet:
        path.unlink()
    IMAGES.mkdir(exist_ok=True)
    for image_id, image in images.items():
        image.save(IMAGES / (image_id + '.png'), optimize=True)
    GENERATED.parent.mkdir(parents=True, exist_ok=True)
    lines = ['-- Generated by tools/game_icons.py from the installed game; do not edit. Not committed (derived artwork).',
             'return {format=1,sources={']
    for kind in ('stratagem', 'booster'):
        s = sources[kind]
        lines.append('  %s={resource=%s,sha256=%s,icons=%d},' % (kind, lua_string(s['resource']), lua_string(s['sha256']),
                                                                 s['icons']))
    lines.append('},')
    for kind, field in (('stratagem', 'stratagems'), ('booster', 'boosters')):
        lines.append(field + '={')
        for name in sorted(mapping[kind]):
            image_id, accent = mapping[kind][name]
            lines.append('  [%s]={image=%s,accent={%d,%d,%d}},' % (lua_string(name), lua_string(image_id), *accent))
        lines.append('},')
    lines.append('}')
    GENERATED.write_text('\n'.join(lines) + '\n', encoding='utf-8', newline='\n')
    print('%d stratagem and %d booster icons -> images/ (%s)' % (len(mapping['stratagem']), len(mapping['booster']),
                                                                  GENERATED.relative_to(PROJECT)))
    return 0


if __name__ == '__main__':
    sys.exit(main())

"""The game's own stratagem and booster icons as the editor's images (a local, opt-in build step).

    py tools/game_icons.py                        # from the installed game (read-only), then build normally
    py tools/game_icons.py --game "D:\\SteamLibrary\\steamapps\\common\\Helldivers 2\\data"
    py tools/game_icons.py --clean                # remove the generated icons again

Every icon is the game's own pixels: nothing is drawn, traced or converted from vectors.
1. The HD2Runtime SDK (r51) names each stratagem's and booster's HUD sprite (sdk/HudIconSprites.json: StratagemInfo
   +0xB0, the native Booster table +0x20) and extracts it from the installed game's texture atlases, read-only
   (sdk/tools/hd2_hud_icons.py). Nothing is written to the game folder.
2. A stratagem sprite is already the game's icon masks (R the category colour layer, G the white layer); it is
   written as it is, 256 x 256.
3. A booster sprite is a colour picture (a yellow plate with a dark glyph). Its pixels are split onto the masks: the
   plate's coverage on R, the glyph's on B, anything light and unsaturated on G, with the plate and glyph colours
   measured from the sprite itself, so the overlay draws the same picture (HD2Runtime d:image colours R, G and B).
4. The accent colour of a stratagem (what the overlay paints R with) is the colour the game's own loadout icon
   library gives that stratagem's icon; a stratagem that library leaves out takes its family's colour from the same
   library.
5. Writes images/si_<id>.png and images/bi_<id>.png, and src/editor/generated/game_icons.lua: name -> {image,
   accent, dark}. An item without a sprite (SG-88 and CQC-72 have no call-in stratagem) gets no icon; the editor
   then draws a plain colour square.

The images are derived from Arrowhead's artwork. They are git-ignored and are packed only into builds you make
yourself; publish a build with them only if you are allowed to redistribute them.
"""
import argparse
import hashlib
import json
import os
import re
import sys
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
COLOUR = re.compile(r'\A#([0-9A-Fa-f]{2})?([0-9A-Fa-f]{6})\Z')


# ------------------------------------------------------------------------------------------------ inputs --
def find_sdk(explicit=None):
    spec = json.loads((PROJECT / 'hd2runtime.json').read_text(encoding='utf-8'))
    for path in [explicit, os.environ.get('HD2RUNTIME_SDK'), spec.get('sdk') and str(PROJECT / spec['sdk'])]:
        if path and (Path(path) / 'tools' / 'hd2_game_data.py').is_file():
            return Path(path).resolve()
    sys.exit('HD2Runtime SDK not found: pass --sdk or set HD2RUNTIME_SDK (the folder holding hd2.py and tools/).')


def game_data(sdk, game):
    sys.path.insert(0, str(sdk / 'tools'))
    import hd2_game_data
    return hd2_game_data.Data(game) if game else hd2_game_data.Data()


def read_libraries(data):
    """{kind: (xaml text, sha256)} of the loadout icon libraries (used for accent colours only)."""
    import hd2_game_data
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


def accents(xaml):
    """{template key: accent rgb}: the most used saturated fill or stroke colour of each icon template."""
    root = ET.fromstring(xaml)
    out = {}
    for template in root.findall(NS + 'DataTemplate'):
        key = template.get(X + 'Key')
        if not key:
            continue
        counts = {}
        for element in template.iter():
            colours = [element.get('Fill'), element.get('Stroke'), element.get('Color')]
            for colour in colours:
                m = COLOUR.match((colour or '').strip())
                if not m:
                    continue
                rgb = tuple(int(m.group(2)[i:i + 2], 16) for i in (0, 2, 4))
                if max(rgb) - min(rgb) > 56:
                    counts[rgb] = counts.get(rgb, 0) + 1
        if counts:
            out[key] = max(counts.items(), key=lambda kv: kv[1])[0]
    return out


def catalogue(sdk):
    strat = json.loads((sdk / 'StratagemAuthoringCapabilities.json').read_text(encoding='utf-8'))['stratagems']
    boost = json.loads((sdk / 'BoosterAuthoringCapabilities.json').read_text(encoding='utf-8'))['boosters']
    return strat, boost


# ---------------------------------------------------------------------------------------------- pixels --
def stratagem_mask(image):
    """A HUD stratagem sprite (already masks) as 256 x 256 RGB: R and G as the game has them, B empty."""
    from PIL import Image
    if image.size != (256, 256):
        image = image.resize((256, 256), Image.LANCZOS)
    r, g, _b, a = image.split()
    black = Image.new('L', image.size, 0)
    return Image.merge('RGB', (Image.composite(r, black, a), Image.composite(g, black, a), black))


def booster_mask(image):
    """A colour booster sprite split onto the masks. Returns (RGB mask image, plate rgb, glyph rgb)."""
    from PIL import Image
    if image.size != (256, 256):
        image = image.resize((256, 256), Image.LANCZOS)
    px = image.load()
    w, h = image.size
    plate, glyph = [0, 0, 0, 0], [0, 0, 0, 0]
    for y in range(h):
        for x in range(w):
            r, g, b, a = px[x, y]
            if a < 250:
                continue
            sat, lum = max(r, g, b) - min(r, g, b), (r * 299 + g * 587 + b * 114) // 1000
            if sat > 150:
                plate[0] += r; plate[1] += g; plate[2] += b; plate[3] += 1
            elif sat < 24 and lum < 96:
                glyph[0] += r; glyph[1] += g; glyph[2] += b; glyph[3] += 1
    plate_rgb = tuple(round(c / plate[3]) for c in plate[:3]) if plate[3] else (255, 255, 255)
    glyph_rgb = tuple(round(c / glyph[3]) for c in glyph[:3]) if glyph[3] else (0, 0, 0)
    plate_sat = max(1, max(plate_rgb) - min(plate_rgb))
    mask = Image.new('RGB', image.size, (0, 0, 0))
    out = mask.load()
    for y in range(h):
        for x in range(w):
            r, g, b, a = px[x, y]
            if a == 0:
                continue
            share = min(1.0, (max(r, g, b) - min(r, g, b)) / plate_sat)
            red = round(a * share)
            rest = a - red
            lum = (r * 299 + g * 587 + b * 114) // 1000
            if lum < 128:
                out[x, y] = (red, 0, rest)
            else:
                out[x, y] = (red, rest, 0)
    return mask, plate_rgb, glyph_rgb


# ------------------------------------------------------------------------------------------------ output --
def image_id(kind, name):
    return PREFIX[kind] + re.sub(r'[^a-z0-9]+', '_', name.lower()).strip('_')[:60]


def lua_string(text):
    return '"' + text.replace('\\', '\\\\').replace('"', '\\"') + '"'


def clean(quiet=False):
    removed = 0
    for path in IMAGES.glob('*.png'):
        if path.name.startswith(tuple(PREFIX.values())):
            path.unlink()
            removed += 1
    if GENERATED.is_file() and not quiet:
        GENERATED.unlink()
    if not quiet:
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
    from PIL import Image
    sdk = find_sdk(args.sdk)
    if not (sdk / 'tools' / 'hd2_hud_icons.py').is_file() or not (sdk / 'HudIconSprites.json').is_file():
        sys.exit('this HD2Runtime SDK has no tools/hd2_hud_icons.py: HD2Runtime 0.30.0-dev r51 or later is needed')
    data = game_data(sdk, args.game)
    import hd2_hud_icons
    hud = hd2_hud_icons.HudIcons(data)
    libraries = read_libraries(data)
    library_accents = {kind: accents(xaml) for kind, (xaml, _digest) in libraries.items()}
    stratagems, boosters = catalogue(sdk)

    # accents: the stratagem's own library icon colour, else the most common colour of its family's library icons
    own, by_family = {}, {}
    for s in stratagems:
        key = ((s.get('uiIcon') or {}).get('iconKey') if (s.get('uiIcon') or {}).get('state') == 'resolved'
               else UNBOUND.get(s['name']))
        rgb = library_accents['stratagem'].get(key) if key else None
        if rgb:
            own[s['name']] = rgb
            counts = by_family.setdefault(s.get('family'), {})
            counts[rgb] = counts.get(rgb, 0) + 1

    def accent(s):
        if s['name'] in own:
            return own[s['name']]
        counts = by_family.get(s.get('family')) or by_family.get('support') or {(255, 255, 255): 1}
        return max(counts.items(), key=lambda kv: kv[1])[0]

    images, mapping, missing = {}, {'stratagem': {}, 'booster': {}}, []
    for s in stratagems:
        got = hud.icon('stratagem', s['name'])
        if got is None:
            missing.append(s['name'])
            continue
        w, h, rgba = got
        iid = image_id('stratagem', s['name'])
        images[iid] = stratagem_mask(Image.frombytes('RGBA', (w, h), rgba))
        mapping['stratagem'][s['name']] = {'image': iid, 'accent': accent(s)}
    for b in boosters:
        got = hud.icon('booster', b['name'])
        if got is None:
            missing.append(b['name'])
            continue
        w, h, rgba = got
        iid = image_id('booster', b['name'])
        mask, plate, glyph = booster_mask(Image.frombytes('RGBA', (w, h), rgba))
        images[iid] = mask
        mapping['booster'][b['name']] = {'image': iid, 'accent': plate, 'dark': glyph}

    clean(quiet=True)
    IMAGES.mkdir(exist_ok=True)
    for iid, image in images.items():
        image.save(IMAGES / (iid + '.png'), optimize=True)
    GENERATED.parent.mkdir(parents=True, exist_ok=True)
    lines = ['-- Generated by tools/game_icons.py from the installed game; do not edit. Not committed (derived artwork).',
             '-- Every image is the game\'s own HUD sprite (HD2Runtime SDK tools/hd2_hud_icons.py, build %s).'
             % hud.names.get('build', '?'),
             'return {format=2,source=%s,' % lua_string('hud_atlas'),
             'missing={%s},' % ','.join(lua_string(n) for n in sorted(missing))]
    for kind, field in (('stratagem', 'stratagems'), ('booster', 'boosters')):
        lines.append(field + '={')
        for name in sorted(mapping[kind]):
            e = mapping[kind][name]
            extra = (',dark={%d,%d,%d}' % e['dark']) if 'dark' in e else ''
            lines.append('  [%s]={image=%s,accent={%d,%d,%d}%s},' % (lua_string(name), lua_string(e['image']),
                                                                     *e['accent'], extra))
        lines.append('},')
    lines.append('}')
    GENERATED.write_text('\n'.join(lines) + '\n', encoding='utf-8', newline='\n')
    print('%d stratagem and %d booster icons from the game\'s HUD atlases -> images/ (%s)%s' % (
        len(mapping['stratagem']), len(mapping['booster']), GENERATED.relative_to(PROJECT),
        ('; no sprite in the game: ' + ', '.join(sorted(missing))) if missing else ''))
    return 0


if __name__ == '__main__':
    sys.exit(main())

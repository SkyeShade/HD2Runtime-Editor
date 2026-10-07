"""Export tools/ui-art/art.html artboards to PNG with headless Microsoft Edge (or Chrome).

    py tools/ui-art/export.py                 # every artboard, @1x and @2x, into assets/ui/
    py tools/ui-art/export.py btn-apply       # only these artboards
    py tools/ui-art/export.py --game          # also write data-game="raw" artboards to images/<name>.png (256 x 256)

Each artboard is rendered alone on a transparent page (art.html?only=<name>) at its data-w x data-h size.
Images written to images/ become the mod's own icon families at build time; declare them raw in hd2runtime.json
("images": {"<name>": "raw"}) so the SDK keeps their colours instead of converting them to the game's icon masks.
"""
import argparse
import os
import re
import shutil
import subprocess
import sys
import tempfile
from pathlib import Path

HERE = Path(__file__).resolve().parent
PROJECT = HERE.parents[1]
ART = HERE / 'art.html'
BROWSERS = [
    os.environ.get('HD2_ART_BROWSER', ''),
    r'C:\Program Files (x86)\Microsoft\Edge\Application\msedge.exe',
    r'C:\Program Files\Microsoft\Edge\Application\msedge.exe',
    r'C:\Program Files\Google\Chrome\Application\chrome.exe',
]


def browser():
    for path in BROWSERS:
        if path and Path(path).is_file():
            return path
    for name in ('msedge', 'chrome', 'chromium'):
        found = shutil.which(name)
        if found:
            return found
    sys.exit('No Edge or Chrome found; set HD2_ART_BROWSER to a Chromium browser executable.')


def artboards():
    html = ART.read_text(encoding='utf-8')
    boards = []
    for tag in re.findall(r'<div[^>]*class="[^"]*\bartboard\b[^"]*"[^>]*>', html):
        attrs = dict(re.findall(r'data-([\w-]+)="([^"]*)"', tag))
        if 'name' in attrs:
            boards.append({'name': attrs['name'], 'w': int(attrs['w']), 'h': int(attrs['h']), 'game': attrs.get('game')})
    return boards


def render(exe, board, scale, out):
    out.parent.mkdir(parents=True, exist_ok=True)
    url = ART.as_uri() + '?only=' + board['name']
    with tempfile.TemporaryDirectory() as profile:
        cmd = [exe, '--headless=new', '--disable-gpu', '--hide-scrollbars', '--no-first-run',
               '--user-data-dir=' + profile, '--default-background-color=00000000',
               '--force-device-scale-factor=' + str(scale), '--window-size=%d,%d' % (board['w'], board['h']),
               '--screenshot=' + str(out), url]
        subprocess.run(cmd, check=True, stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL, timeout=60)
    if not out.is_file():
        raise RuntimeError('the browser wrote no screenshot for ' + board['name'])
    # Exact size: crop away anything past the artboard (window chrome rounding).
    try:
        from PIL import Image
        with Image.open(out) as im:
            want = (board['w'] * scale, board['h'] * scale)
            if im.size != want:
                im.crop((0, 0) + want).save(out)
    except ImportError:
        pass


def main():
    parser = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    parser.add_argument('names', nargs='*', help='artboards to export (default: all)')
    parser.add_argument('--game', action='store_true', help='also write data-game="raw" artboards to images/ at 256 x 256')
    parser.add_argument('--out', default=str(PROJECT / 'assets' / 'ui'), help='output folder (default assets/ui)')
    args = parser.parse_args()
    exe = browser()
    boards = [b for b in artboards() if not args.names or b['name'] in args.names]
    if not boards:
        sys.exit('no artboard matches ' + ', '.join(args.names))
    out = Path(args.out)
    for board in boards:
        render(exe, board, 1, out / (board['name'] + '.png'))
        render(exe, board, 2, out / (board['name'] + '@2x.png'))
        line = board['name'] + ': ' + str(out / (board['name'] + '.png'))
        if args.game and board['game'] == 'raw':
            if (board['w'], board['h']) != (256, 256):
                print(board['name'] + ': data-game needs a 256 x 256 artboard; skipped for images/', file=sys.stderr)
            else:
                game = PROJECT / 'images' / (board['name'] + '.png')
                render(exe, board, 1, game)
                line += '  + ' + str(game.relative_to(PROJECT))
        print(line)
    return 0


if __name__ == '__main__':
    sys.exit(main())

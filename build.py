"""Build the HD2R Editor mod ZIP with the HD2Runtime SDK, then give it its HD2 Arsenal description.

The SDK (the folder holding hd2.py and metadata.json) is found in this order: the HD2RUNTIME_SDK environment variable;
the "sdk" path in hd2runtime.json; then this folder and every folder above it, each one itself or a subfolder named
sdk or ending in -sdk. `hd2.py build` packs every src/**/*.lua, the thumbnail (assets/editor-icon.png, shipped as
thumbnail.png and the manifest's IconPath) and the README. This script then writes the mod-manager description into
manifest.json (the description, then "// " and the SDK's dependency line, as ModBuilder exports it) and refreshes
build/build-report.json's artifact digest.

Usage: py build.py   (or build.cmd)
"""
import hashlib
import json
import os
import subprocess
import sys
import zipfile
from pathlib import Path

ROOT = Path(__file__).resolve().parent
ARTIFACT = 'HD2REditor'
DESCRIPTION = (
    'An in-game editor for every value HD2Runtime exposes. See which installed HD2Runtime mods change what, edit any '
    'field live (also the ones a mod sets), apply only what changed, and reset to the mods\' and game values at any '
    'time. Calldown codes, mission uses, projectile swaps and payloads too. Presets included. Press F8 in game.'
)


def is_sdk(path):
    return (path / 'hd2.py').is_file() and (path / 'metadata.json').is_file()


def find_sdk():
    configured = json.loads((ROOT / 'hd2runtime.json').read_text(encoding='utf-8')).get('sdk')
    named = [Path(os.environ['HD2RUNTIME_SDK'])] if os.environ.get('HD2RUNTIME_SDK') else []
    for path in named + ([ROOT / configured] if configured else []):
        if is_sdk(path):
            return path.resolve()
    for folder in (ROOT, *ROOT.parents):
        if is_sdk(folder):
            return folder
        try:
            children = sorted(p for p in folder.iterdir() if p.is_dir() and (p.name.lower() == 'sdk'
                              or p.name.lower().endswith('-sdk')))
        except OSError:
            continue
        for child in children:
            if is_sdk(child):
                return child
    return None


def describe(path):
    """Rewrite manifest.json inside the built ZIP with the editor's description and add LICENSE and THIRD_PARTY.md
    (every other entry unchanged)."""
    with zipfile.ZipFile(path) as source:
        entries = [(info, source.read(info.filename)) for info in source.infolist()]
    temporary = path.with_suffix('.tmp')
    with zipfile.ZipFile(temporary, 'w', zipfile.ZIP_DEFLATED) as target:
        for info, data in entries:
            if info.filename == 'manifest.json':
                manifest = json.loads(data)
                dependency = manifest.get('Description', '')
                text = DESCRIPTION + ('\n\n// ' + dependency if dependency else '')
                assert len(text) <= 4000 and '<' not in text, 'the Arsenal description must stay plain text'
                manifest['Description'] = text
                for option in manifest.get('Options', []):
                    option['Description'] = text
                data = json.dumps(manifest, indent=2).encode()
            target.writestr(info, data)
        # the license and third-party notices travel with every release
        names = {info.filename for info, _ in entries}
        for extra in ('LICENSE', 'THIRD_PARTY.md'):
            if extra not in names and (ROOT / extra).is_file():
                target.write(ROOT / extra, extra)
    os.replace(temporary, path)
    report = ROOT / 'build' / 'build-report.json'
    if report.is_file():
        data = json.loads(report.read_text(encoding='utf-8'))
        data['artifact_sha256'] = hashlib.sha256(path.read_bytes()).hexdigest()
        report.write_text(json.dumps(data, indent=2) + '\n', encoding='utf-8')


def main():
    sdk = find_sdk()
    if sdk is None:
        print('HD2Runtime SDK not found. Set HD2RUNTIME_SDK to the SDK folder (the one holding hd2.py and '
              'metadata.json), or point "sdk" in hd2runtime.json at it.', file=sys.stderr)
        return 1
    print('HD2Runtime SDK: ' + str(sdk), flush=True)
    status = subprocess.run([sys.executable, '-B', str(sdk / 'hd2.py'), 'build', str(ROOT)]).returncode
    if status != 0:
        return status
    version = (ROOT / 'VERSION').read_text().strip()
    built = ROOT / 'build' / (ROOT.name + '-' + version + '.zip')
    if not built.is_file():
        print('build finished but ' + built.name + ' is missing', file=sys.stderr)
        return 1
    # released as HD2R Editor (not to be confused with HD2Runtime itself)
    artifact = ROOT / 'build' / (ARTIFACT + '-' + version + '.zip')
    os.replace(built, artifact)
    describe(artifact)
    print('Arsenal description written: ' + str(artifact))
    return 0


if __name__ == '__main__':
    sys.exit(main())

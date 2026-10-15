"""Audit every enumerable catalogue display text; never read a game text dump.

Uses the same offline LuaJIT/Runtime configuration as tests/lua_host.py. Reports
can include native resource names, so save them under build/, not in the pack.
"""
import argparse
import collections
import hashlib
import json
from pathlib import Path
import re
import sys

ROOT = Path(__file__).resolve().parents[1]
SUMMARY = ROOT / 'localization/catalog-coverage.json'


def inventory():
    sys.path.insert(0, str(ROOT / 'tests'))
    import lua_host
    if not lua_host.available():
        raise RuntimeError('Configure HD2_GAME_ROOT and HD2RUNTIME_ROOT for the offline catalogue audit.')
    source = ROOT / 'tests/lua/catalog_localization_inventory.lua'
    return json.loads(lua_host.run(source.read_text(encoding='utf8')))


def classification(row):
    text = row['text']
    if row['display'] != text:
        return 'translated_exact' if row['exact'] else 'translated_composed'
    if row.get('native_model'):
        return 'retained_model_name_or_id'
    if re.fullmatch(r'content/\S+', text):
        return 'retained_resource_path'
    if re.fullmatch(r'[A-Za-z]+(?:_[A-Za-z0-9]+)+', text):
        return 'retained_native_identifier'
    if re.fullmatch(r'Mec [FM] \d+|AX/ARC-3 K-9', text):
        return 'retained_designation'
    if text == 'ID':
        return 'retained_acronym'
    return 'uncovered'


def summarize(rows):
    counts = collections.Counter(classification(row) for row in rows)
    counts.setdefault('uncovered', 0)
    texts = '\n'.join(sorted(row['text'] for row in rows)).encode('utf8')
    return {'catalogue_texts': len(rows), 'keys_sha256': hashlib.sha256(texts).hexdigest(),
            'counts': dict(sorted(counts.items()))}


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--check', action='store_true', help='Compare with the reviewed coverage summary.')
    parser.add_argument('--report', type=Path, help='Save a local, complete coverage and retained-identifier list.')
    args = parser.parse_args()
    rows = inventory()
    summary = summarize(rows)
    print(json.dumps(summary, indent=2))
    if args.report:
        args.report.parent.mkdir(parents=True, exist_ok=True)
        args.report.write_text(json.dumps({'summary': summary, 'texts': [
            dict(row, classification=classification(row)) for row in rows]},
            ensure_ascii=False, indent=2) + '\n', encoding='utf8')
    if summary['counts']['uncovered']:
        for row in rows:
            if classification(row) == 'uncovered':
                print('Uncovered:', row['text'])
        return 1
    if args.check:
        expected = json.loads(SUMMARY.read_text(encoding='utf8'))['coverage']
        if expected != summary:
            print('Catalogue changed: review the new texts before updating catalog-coverage.json.')
            return 1
    return 0


if __name__ == '__main__':
    raise SystemExit(main())

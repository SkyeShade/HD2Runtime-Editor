"""Collect every interface text of the editor into src/editor/strings.lua (the localisation template's list).

    py tools/locale_strings.py                      # rewrite src/editor/strings.lua
    py tools/locale_strings.py --check              # exit 1 when it is out of date (the tests run this)
    py tools/locale_strings.py --template FILE      # write a complete template: the interface texts, then every
                                                    # name, section and field the catalogue shows

Texts are the literal arguments of L('...') and Lf('...', ...) in src/, plus the labels the code passes to L() through
variables: tab, category and weapon-group labels, preset actions, custom stratagem fields, and the catalogue's own
section, group, subtitle, note and value-label literals (catalog.lua: 'Fire Mode', 'Health & Armor', 'Damage Zones',
'Hellpod' ...).

--template builds the catalogue on the game's own LuaJIT against an HD2Runtime checkout (tests/lua_host.py:
HD2_GAME_ROOT, HD2RUNTIME_ROOT) and adds every object name, subtitle, section, group, field label, value label, note
and reason it shows (editor/catalog.lua Catalog:texts), the same list Settings > WRITE TEMPLATE writes in game. The
format is the one the editor reads: "English = " per line, # comments.
"""
import re
import sys
from pathlib import Path

PROJECT = Path(__file__).resolve().parents[1]
SRC = PROJECT / 'src' / 'editor'
OUTPUT = SRC / 'strings.lua'
LITERAL = r"'((?:[^'\\]|\\.)*)'"
# keys whose literal values the window shows through L() (catalogue rows and objects, tables of labels)
SHOWN_KEYS = ('label', 'section', 'group', 'subtitle', 'detail', 'note', 'own_label', 'sub')
# tables of the catalogue whose values are labels or notes (key -> text)
LABEL_TABLES = ('PRESET_ACTIONS', 'FILE_ACTIONS', 'MB_ACTIONS', 'IMPORT_ACTIONS', 'WEAPON_GROUPS', 'GROUP_LABELS',
                'DOMAIN_LABELS', 'UI_GROUPS',
                'PATH_LABELS', 'HOVER_LABELS', 'TEAM_RELOAD_NOTES', 'DERIVED_HEAT', 'MOUNT_LABELS', 'STATUS_SLOT_NOTE',
                'SAME_HIT_LABELS', 'VW_NOTES', 'VW_NO_RELOAD_NOTES', 'CHAIN_LABELS', 'HELLBOMB_NOTE', 'TITLES',
                'SUB_TITLES', 'FIRES_TEXTS', 'FIELD_NOTES', 'PAYLOAD_TEXTS', 'PAYLOAD_LABELS', 'PAYLOAD_GROUPS', 'PAYLOAD_WARNINGS')


def unescape(text):
    return re.sub(r"\\(.)", lambda m: {'n': '\n', 't': '\t'}.get(m.group(1), m.group(1)), text)


def block(text, start):
    """The text of the balanced {...} that opens at text[start]."""
    depth = 0
    for i in range(start, len(text)):
        if text[i] == '{':
            depth += 1
        elif text[i] == '}':
            depth -= 1
            if depth == 0:
                return text[start:i + 1]
    return text[start:]


def collect():
    import json
    found = list(json.loads((PROJECT / 'localization/builtin.json').read_text(encoding='utf8'))['de'])
    for path in sorted(SRC.rglob('*.lua')):
        if 'generated' in path.parts or path == OUTPUT:
            continue
        text = path.read_text(encoding='utf-8')
        # one text split over lines as 'first part '..'second part' is one literal
        while True:
            joined = re.sub(LITERAL + r"\s*\.\.\s*" + LITERAL, r"'\1\2'", text)
            if joined == text:
                break
            text = joined
        found += re.findall(r"\bLf?\(" + LITERAL + r"\s*[,)]", text)
        if path.parent.name == 'ui' or path.name == 'catalog.lua':
            # labels of tables and rows the code localises at draw time
            for key in SHOWN_KEYS:
                # (not a fragment the code joins with other text: 'Slot '..i)
                found += re.findall(r"\b" + key + r"=" + LITERAL + r"(?!\s*\.\.)", text)
        if path.name == 'catalog.lua':
            # the catalogue's composite labels: join('Explosion', ...) and its parts
            for args in re.findall(r"\bjoin\(([^()]*(?:\([^()]*\))?[^()]*)\)", text):
                found += [x for x in re.findall(LITERAL, args) if x[:1].isupper()]
        for name in LABEL_TABLES:
            for m in re.finditer(r'\b' + name + r'=\{', text):
                body = block(text, m.end() - 1)
                found += re.findall(r"=\s*" + LITERAL, body)
                if name in ('PRESET_ACTIONS', 'FILE_ACTIONS', 'MB_ACTIONS', 'IMPORT_ACTIONS', 'WEAPON_GROUPS'):
                    found += re.findall(LITERAL, body)
            for m in re.finditer(r'\b' + name + r'=' + LITERAL, text):
                found.append(m.group(1))
    out, seen = [], set()
    for s in (unescape(x) for x in found):
        # (an identifier such as 'acid_splash' is no text the window shows)
        if s and s not in seen and not s.isspace() and re.search(r'[A-Za-z]', s) and '\n' not in s \
                and not re.fullmatch(r'[a-z0-9]+(_[a-z0-9]+)+', s):
            seen.add(s)
            out.append(s)
    return sorted(out, key=str.lower)


def render(strings):
    def lua(s):
        return "'" + s.replace('\\', '\\\\').replace("'", "\\'").replace('\n', '\\n') + "'"
    lines = ['-- Generated by tools/locale_strings.py: every interface text of the editor (the localisation template).',
             '-- Do not edit; run the tool after changing texts.', 'return {']
    lines += ['    ' + lua(s) + ',' for s in strings]
    lines.append('}')
    return '\n'.join(lines) + '\n'


def catalogue_texts():
    """Every text the catalogue shows (Catalog:texts), built against the HD2Runtime checkout."""
    sys.path.insert(0, str(PROJECT / 'tests'))
    import lua_host
    if not lua_host.available():
        raise SystemExit('--template needs Helldivers 2 bin/lua51.dll and an HD2Runtime checkout (see tests/lua_host.py)')
    body = '''
        local hd2=require('hd2runtime/api/hd2')
        local catalog=require('mods/skyeshade/hd2runtime_editor/editor/catalog')
        return table.concat(catalog.new(hd2):texts(),'\\n')..'\\n@version '..tostring(hd2.version_label or hd2.version)
    '''
    result = lua_host.run(body)
    lines = result.split('\n')
    version = lines[-1].replace('@version ', '') if lines and lines[-1].startswith('@version ') else '?'
    return [x for x in lines[:-1] if x], version


def write_template(path):
    strings = collect()
    texts, version = catalogue_texts()
    seen = set(strings)
    more = [t for t in texts if t not in seen and not seen.add(t)]
    out = ['# HD2R Editor localisation template. Copy this file (any name ending in .txt), set the language',
           '# name below and write each translation after " = ". Lines without a translation are ignored.',
           '@language My language', '']
    out += [s + ' = ' for s in strings]
    if more:
        out += ['', '# Names, sections and fields of the catalogue (HD2Runtime %s) (%d texts). A section such as' % (
            version, len(more)),
                '# "Explosion · Primary impact" is also translated part by part: "Explosion", "Primary impact".']
        out += [s + ' = ' for s in more]
    Path(path).write_text('\n'.join(out) + '\n', encoding='utf-8', newline='\n')
    print('%d interface texts + %d catalogue texts -> %s' % (len(strings), len(more), path))


def main():
    if '--template' in sys.argv:
        at = sys.argv.index('--template')
        if at + 1 >= len(sys.argv):
            print('--template needs a file name')
            return 2
        write_template(sys.argv[at + 1])
        return 0
    body = render(collect())
    current = OUTPUT.read_text(encoding='utf-8') if OUTPUT.is_file() else ''
    if '--check' in sys.argv:
        if current != body:
            print('src/editor/strings.lua is out of date: run py tools/locale_strings.py')
            return 1
        return 0
    OUTPUT.write_text(body, encoding='utf-8', newline='\n')
    print('%d texts -> %s' % (body.count('\n') - 4, OUTPUT.relative_to(PROJECT)))
    return 0


if __name__ == '__main__':
    sys.exit(main())

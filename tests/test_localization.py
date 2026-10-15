"""Bundled translation checks. Static checks need only Python, no game or Runtime."""
import collections
import importlib.util
import json
from pathlib import Path
import re
import unittest

import lua_host

ROOT = Path(__file__).resolve().parents[1]


def tool(name):
    spec = importlib.util.spec_from_file_location(name, ROOT / 'tools' / (name + '.py'))
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    return module


def unique_object(pairs):
    result = {}
    for key, value in pairs:
        if key in result:
            raise ValueError('Duplicate translation key: ' + key)
        result[key] = value
    return result


def chinese():
    return json.loads((ROOT / 'localization/zh-cn.json').read_text(encoding='utf8'),
                      object_pairs_hook=unique_object)


class LocalizationDataTests(unittest.TestCase):
    def test_complete_interface_and_generated_resources(self):
        data = chinese()
        strings = tool('locale_strings')
        self.assertFalse(set(strings.collect()) - data.keys())
        self.assertEqual(strings.render(strings.collect()),
                         (ROOT / 'src/editor/strings.lua').read_text(encoding='utf8'))
        self.assertEqual(tool('locale_builtin').build(),
                         (ROOT / 'src/editor/locale.lua').read_text(encoding='utf8'))
        self.assertEqual(data['APPLY  %d'], '应用  %d')

    def test_formats_numbers_and_identifiers(self):
        formats = re.compile(r'%(?:[-+ #0]*\d*(?:\.\d+)?[cdiouxXeEfgGqs%])')
        numbers = re.compile(r'0x[0-9A-Fa-f]+|\d+(?:[.,]\d+)?')
        identifiers = re.compile(r'\b[a-z]+(?:_[a-z0-9]+)+\b|\b[A-Z]+(?:_[A-Z0-9]+)+\b')
        for key, value in chinese().items():
            with self.subTest(key=key):
                self.assertIsInstance(value, str)
                self.assertTrue(value.strip())
                self.assertNotRegex(value, r'[\x00-\x1f\ufffd]')
                self.assertEqual(formats.findall(key), formats.findall(value))
                self.assertEqual(re.findall(r'#[A-Z]+',key), re.findall(r'#[A-Z]+',value))
                self.assertEqual(collections.Counter(numbers.findall(key)),
                                 collections.Counter(numbers.findall(value)))
                for token in identifiers.findall(key):
                    self.assertIn(token, value)

    def test_pack_has_translations_not_native_catalogue_tables(self):
        # Authored name fallbacks are allowed; a name key alone cannot establish provenance.
        # Opaque paths, component lists and observed bone names are handled by templates.
        for key in chinese():
            self.assertFalse(key.startswith('content/'),key)
            self.assertFalse(' (observed)'in key and key!='%s (observed)',key)
            self.assertFalse(' (candidate)'in key and key!='%s (candidate)',key)
            if key.endswith('. Authored type values; existing instances may retain private copies.'):
                self.assertTrue(key.startswith('%s.'),key)


@unittest.skipUnless(lua_host.available(), 'needs game LuaJIT and a Runtime checkout')
class LocalizationRuntimeTests(unittest.TestCase):
    def test_enumerated_catalogue_coverage(self):
        audit = tool('locale_catalog')
        rows = audit.inventory()
        self.assertFalse([row['text'] for row in rows if audit.classification(row)=='uncovered'])
        expected = json.loads((ROOT/'localization/catalog-coverage.json').read_text(encoding='utf8'))
        self.assertEqual(audit.summarize(rows), expected['coverage'])

    def test_bundled_chinese_in_the_window(self):
        paths = {key: (ROOT / 'tests/lua' / name).as_posix() for key, name in
                 [('harness', 'ui_harness.lua'), ('sim', 'sim.lua')]}
        args = '{' + ','.join(key + '=' + lua_host._lua_string(path) for key, path in paths.items()) + '}'
        script = lua_host._lua_string((ROOT / 'tests/lua/test_localization_ui.lua').as_posix())
        self.assertEqual(lua_host.run('return assert(loadfile(%s))(%s)' % (script, args)), 'ok')

    def test_fonts_and_other_language_supplements(self):
        available = set()
        for path in (lua_host.RUNTIME / 'domains').glob('ui_fonts*.lua'):
            available.update(map(int, re.findall(r'\[(\d+)\]=', path.read_text(encoding='utf8'))))
        # Runtime 0.31+ falls back across its game font atlases, rather than requiring every glyph in zh_hans.
        missing = {ch for text in chinese().values() for ch in text if ord(ch) not in available}
        self.assertFalse(missing)
        self.assertEqual(lua_host.run(r'''
local data=require('mods/skyeshade/hd2runtime_editor/editor/locale')
local json=require('mods/skyeshade/hd2runtime_editor/editor/json')
local f=assert(io.open(SOURCE,'rb'));local base=assert(json.decode(f:read('*a')));f:close()
for code,rows in pairs(base)do
    if code~='cn'then
        for key,value in pairs(rows)do assert(data[code][key]==value)end
        for key in pairs(data[code])do assert(rows[key])end
    end
end
return 'ok'
'''.replace('SOURCE', lua_host._lua_string((ROOT / 'localization/builtin.json').as_posix()))), 'ok')

    def test_official_names_keep_precedence_and_identity(self):
        self.assertEqual(lua_host.run(r'''
local root='mods/skyeshade/hd2runtime_editor/editor/'
local i=require(root..'i18n')
assert(i.use('简体中文',{}))
local util=require(root..'util')
local names=require(root..'game_names')
local key='AR-23 Liberator'
local object={key='pw|'..key,name=key}
local api={text={available=function()return true,'cn'end,language=function()return'cn'end,
    name=function(kind,id)assert(kind=='weapon'and id==key);return'游戏名称'end}}
local instance=names.new(api):install()
assert(util.display_name(object)=='游戏名称')
assert(object.key=='pw|'..key and object.name==key)
api.text.name=function()return nil,'UNAVAILABLE'end
api.text.language=function()return'us'end
instance:refresh()
assert(util.display_name(object)==i.L(key) and i.L(key)=='AR-23 解放者')
assert(i.L('Damage')=='伤害')
i.use('English')
assert(util.display_name(object)==key and object.key=='pw|'..key)
return 'ok'
'''), 'ok')

    def test_language_loading_and_display(self):
        source = (ROOT / 'tests/lua/test_localization.lua').as_posix()
        self.assertEqual(lua_host.run('return assert(loadfile(%s))()' % lua_host._lua_string(source)), 'ok')


if __name__ == '__main__':
    unittest.main()

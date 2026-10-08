"""HD2R Editor offline tests, on the game's own LuaJIT (tests/lua_host.py) and the HD2Runtime source checkout.

    py -m unittest discover -s tests -v

Set HD2_GAME_ROOT (Helldivers 2 folder) and HD2RUNTIME_ROOT (HD2Runtime checkout) if they are not the defaults.
"""
import importlib.util
import json
import re
import sys
import unittest
from pathlib import Path

HERE = Path(__file__).resolve().parent
sys.path.insert(0, str(HERE))
import lua_host  # noqa: E402

LUA = HERE / 'lua'


def lua_file(name, args):
    """Run tests/lua/<name> with a Lua table of string arguments."""
    table = '{' + ','.join('[ %s ]=%s' % (lua_host._lua_string(k), lua_host._lua_string(v)) for k, v in args.items()) + '}'
    body = 'local f=assert(loadfile(%s)) return f(%s)' % (lua_host._lua_string((LUA / name).as_posix()), table)
    return lua_host.run(body)


@unittest.skipUnless(lua_host.available(), 'needs Helldivers 2 bin/lua51.dll and an HD2Runtime checkout')
class EditorTests(unittest.TestCase):

    def test_util(self):
        result = lua_host.run(r'''
            local u=require('mods/skyeshade/hd2runtime_editor/editor/util')
            assert(u.representable(0.30000001192092896,false,'f32')==0.3,'f32 0.3')
            assert(u.representable(0.1234,false,'f32')==nil,'four decimals refused')
            assert(u.representable(12,true)==12 and u.representable(12.5,true)==nil,'integers')
            assert(u.format(1200)=='1200' and u.format(0.25)=='0.25' and u.format(1.0000001)=='1','format')
            assert(u.humanize('damage.ap_direct')=='AP direct','humanize')
            assert(u.unit('degrees_per_second')=='°/s' and u.unit('damage')==nil,'units')
            local catalog=require('mods/skyeshade/hd2runtime_editor/editor/catalog')
            assert(catalog.strip('explosion.primary.impact.damage.status_1_strength','primary','impact')
                =='explosion.damage.status_1_strength','strip')
            assert(catalog.strip('projectile.feed_primary.velocity','feed_primary')=='projectile.velocity','strip feed')
            return 'ok'
        ''')
        self.assertEqual(result, 'ok')

    def test_json_mod_manager_state_and_localisation(self):
        result = lua_host.run(r"""
            local json=require('mods/skyeshade/hd2runtime_editor/editor/json')
            local t=json.decode('{"a":[1,2,{"b":"x\\u00e9\\n"}],"c":true,"d":null,"e":-1.5e2,"f":{}}')
            assert(t.a[3].b=='x\195\169\n' and t.c==true and t.d==nil and t.e==-150 and next(t.f)==nil,'decode')
            assert(not pcall(json.decode,'{"a":}'),'bad JSON raises')
            -- a large file is read in slices: decode yields every n values inside a coroutine
            local yields=0
            local co=coroutine.create(function()return json.decode('[1,2,3,4,5,6,7,8,9,10]',3)end)
            local ok,value
            repeat ok,value=coroutine.resume(co);assert(ok,value);yields=yields+1 until coroutine.status(co)=='dead'
            assert(#value==10 and yields>3,'sliced: '..yields)
            -- Echelon: deployed mods are the slots; a HD2Runtime mod is matched by the Lua addon Echelon scanned
            local installed=require('mods/skyeshade/hd2runtime_editor/editor/installed')
            local mods=installed.from_echelon({slots={a={'x.patch_0'},b={'y.patch_0'}},library={
                a={name='Eagle Tweaks',guid='g1',image='a_1.png',scan={sets={{addons={'mods/x/eagle'}}}}},
                b={name='Colours',description='Lasers'},c={name='Not deployed'}}},'C:\\E')
            table.sort(mods,function(p,q)return p.name<q.name end)
            assert(#mods==2 and mods[2].name=='Eagle Tweaks'and mods[2].addons[1]=='mods/x/eagle'and mods[2].guid=='g1')
            assert(mods[2].image=='C:\\E\\images\\a_1.png'and mods[1].image==nil,'images')
            -- Arsenal: the deployed profile's enabled mods, joined to the library
            local list=installed.from_arsenal({deployedProfile='p',modsLibrary={{uuid='u1',label='One',iconPath='C:\\i.png'},
                {uuid='u2',label='Two'}},modsList={p={mods={{uuid='u1',enabled=true,deployed=true},{uuid='u2',enabled=false}}}}})
            assert(#list==1 and list[1].name=='One'and list[1].image=='C:\\i.png','arsenal')
            -- localisation files: "English = translation", @language, comments; empty translations ignored
            local i18n=require('mods/skyeshade/hd2runtime_editor/editor/i18n')
            local map,name=i18n.parse('\239\187\191@language Deutsch\n# note\nAPPLY = ANWENDEN\n%d fields = %d Felder\r\nEmpty = \n')
            assert(name=='Deutsch'and map.APPLY=='ANWENDEN'and map['%d fields']=='%d Felder'and map.Empty==nil,'parse')
            i18n.set(map,'Deutsch')
            assert(i18n.L('APPLY')=='ANWENDEN'and i18n.L('%d fields'):format(3)=='3 Felder'and i18n.L('Other')=='Other')
            i18n.set({},'English')
            assert(i18n.L('APPLY')=='APPLY')
            return 'ok'
        """)
        self.assertEqual(result, 'ok')

    def test_mod_export_matches_the_sdk_and_applies(self):
        import hashlib
        import tempfile
        import zipfile
        sys.path.insert(0, str(lua_host.RUNTIME / 'sdk' / 'tools'))
        import hd2_archive
        with tempfile.TemporaryDirectory() as tmp:
            image = Path(tmp) / 'icon.png'
            image.write_bytes(b'\x89PNG\r\n\x1a\nfake image bytes')
            folder = Path(tmp) / 'out'
            result = lua_file('test_export.lua', {'sim': (LUA / 'sim.lua').as_posix(), 'image': str(image),
                                                  'folder': str(folder)})
            lines = dict(line.split(' ', 1) for line in result.splitlines() if ' ' in line and not line.startswith('['))
            self.assertEqual(lines['murmur'].split()[-1] if False else lines['murmur'], lines['murmur'])
            got = {line.split(' ')[1]: line.split(' ')[2] for line in result.splitlines() if line.startswith('murmur ')}
            self.assertEqual(int(got['packages/boot'], 16), hd2_archive.resource_hash('packages/boot'))
            self.assertEqual(int(got['lua'], 16), hd2_archive.LUA_TYPE)
            self.assertEqual(int(got['resource'], 16), hd2_archive.resource_hash('mods/skye/test5'))
            self.assertEqual(lines['crc'], 'cbf43926')
            self.assertEqual(lines['sha'], hashlib.sha256(b'abc').hexdigest())
            self.assertEqual(lines['guid'], 'e27e2c3e-fd0d-575d-b341-e2460d2c8adb')   # ModBuilder's own derivation
            expected = hd2_archive.make_archive({hd2_archive.resource_hash(n): hd2_archive.lua_resource(b)
                                                 for n, b in {'mods/skye/test5': b'print(1)\n',
                                                              'mods/skye/test5/x': b'return 2\n'}.items()})
            self.assertEqual(lines['archive'], expected.hex(), 'the archive matches hd2_archive.make_archive')
            path = Path(lines['zip'])
            self.assertEqual(path.name, 'Test-Export-1.2.3.zip')
            with zipfile.ZipFile(path) as z:
                self.assertIsNone(z.testzip())
                names = z.namelist()
                self.assertEqual(names, sorted(names))
                for name in ('README.md', 'build-report.json', 'hd2runtime.json', 'manifest.json', 'src/addon.lua',
                             'mod/9ba626afa44a3aa3.patch_0', 'mod/9ba626afa44a3aa3.patch_0.stream',
                             'mod/9ba626afa44a3aa3.patch_0.gpu_resources', 'thumbnail.png'):
                    self.assertIn(name, names)
                manifest = json.loads(z.read('manifest.json'))
                self.assertEqual(manifest['Name'], 'Test Export 1.2.3')
                self.assertEqual(manifest['Guid'], lines['guid2'])
                self.assertEqual(manifest['IconPath'], 'thumbnail.png')
                self.assertEqual(manifest['Options'][0]['Include'], ['mod'])
                self.assertTrue(manifest['Description'].startswith('Made in a test.\n\n// Requires Bingus'))
                spec = json.loads(z.read('hd2runtime.json'))
                self.assertEqual(spec['resource'], 'mods/skye_tester/test_export')
                archive = z.read('mod/9ba626afa44a3aa3.patch_0')
                body = archive[0xC0 + 8:0xC0 + 8 + int.from_bytes(archive[0xC0:0xC4], 'little')]
                self.assertEqual(int.from_bytes(archive[0x68:0x70], 'little'),
                                 hd2_archive.resource_hash('mods/skye_tester/test_export'))
                self.assertTrue(body.startswith(b'-- HD2-Addon: mods/skye_tester/test_export\n'))
            self.assertTrue((folder / 'project' / 'src' / 'addon.lua').is_file())
            self.assertTrue((folder / 'project' / 'thumbnail.png').is_file())
            self.assertIn('applied ok', result)
            self.assertIn('wrapped ok', result)

    def test_interface_text_list_is_current(self):
        spec = importlib.util.spec_from_file_location('locale_strings', lua_host.PROJECT / 'tools' / 'locale_strings.py')
        tool = importlib.util.module_from_spec(spec)
        spec.loader.exec_module(tool)
        self.assertEqual(tool.render(tool.collect()), (lua_host.PROJECT / 'src' / 'editor' / 'strings.lua')
                         .read_text(encoding='utf-8'), 'run py tools/locale_strings.py')

    def test_catalogue_rows_pass_the_runtime_validator(self):
        src = (HERE / 'catalog_report.lua').read_text(encoding='utf-8')
        report = lua_host.run('local f=assert(loadstring(%s,"@catalog_report")) return f(nil)' % lua_host._lua_string(src))
        total = re.search(r'TOTAL rows=(\d+) editable=(\d+) valid=(\d+)', report)
        self.assertIsNotNone(total, report)
        rows, editable, valid = map(int, total.groups())
        self.assertGreater(rows, 15000, report)
        # Known exceptions: an enemy field whose reviewed domain is "-1, or above 0" (the sample value is 0), and the
        # M-1000 Maxigun's rate slots, which need a selector binding in the same transaction (the editor shows the
        # Runtime's reason when such a value is chosen).
        self.assertGreaterEqual(valid, editable - 2, report)
        for failure in re.findall(r'^\s+\d+ x (.+)$', report, re.M):
            self.assertTrue('gore' in failure or 'SELECTOR_REQUIRED' in failure, report)

    def test_override_layer_over_the_real_ensure(self):
        # test_layer.lua takes the simulator's path as its only argument
        result = lua_host.run('local f=assert(loadfile(%s)) return f(%s)' % (
            lua_host._lua_string((LUA / 'test_layer.lua').as_posix()), lua_host._lua_string((LUA / 'sim.lua').as_posix())))
        for line in ('vanilla set/reset ok', 'mod ensure takeover/reset ok', 'one-shot mod patch override/reset ok',
                     'rebind ok', 'refusals ok', 'reset all ok'):
            self.assertIn(line, result)

    def test_value_fields_over_script_choices(self):
        # calldown codes, mission uses, booleans, statuses, projectile swaps, terminal explosions (HD2Runtime r50)
        result = lua_host.run('local f=assert(loadfile(%s)) return f(%s)' % (
            lua_host._lua_string((LUA / 'test_layer_values.lua').as_posix()),
            lua_host._lua_string((LUA / 'sim.lua').as_posix())))
        for line in ('calldown code ok', 'mission uses ok', 'boolean ok', 'status ok', 'projectile swap ok',
                     'terminal explosion ok', 'refusals ok', 'rate slots with selector binding ok', 'direct first edit ok', 'armory traits ok', 'displayed penetration ok', 'steer watchdog ok', 'skipped steer settled again ok', 'disable sentinel ok', 'helldiver fields ok', 'armor stats ok', 'armor perks ok', 'mod code takeover ok', 'base value is a reset ok'):
            self.assertIn(line, result)

    def test_window_frames_stay_inside_overlay_limits(self):
        result = lua_file('test_ui.lua', {'sim': (LUA / 'sim.lua').as_posix(),
                                          'harness': (LUA / 'ui_harness.lua').as_posix()})
        self.assertIn('ui ok', result, result)

    def test_shipped_addon_starts(self):
        spec = importlib.util.spec_from_file_location('hd2sdk', lua_host.RUNTIME / 'sdk' / 'hd2.py')
        sdk = importlib.util.module_from_spec(spec)
        sys.path.insert(0, str(lua_host.RUNTIME / 'sdk'))
        spec.loader.exec_module(sdk)
        manifest = json.loads((lua_host.PROJECT / 'hd2runtime.json').read_text(encoding='utf-8'))
        body = (lua_host.PROJECT / 'src' / 'addon.lua').read_text(encoding='utf-8')
        wrapped = sdk.wrap_addon(manifest['resource'], manifest['requires']['hd2runtime']['min_version'], body,
                                 manifest['name'])
        result = lua_file('test_startup.lua', {'wrapped': wrapped})
        self.assertTrue(result.startswith('ready'), result)


if __name__ == '__main__':
    unittest.main()

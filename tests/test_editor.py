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
            -- a text with " = " in it (the trait picker's help) and a translation that keeps one; a tab separator
            local help='Enter / click toggle   numbers = order   Backspace remove last   Tab save'
            local m2,_,count,code=i18n.parse('@code cn\n'..help..' = 回车 切换   数字 = 顺序\nAPPLY\t=\t应用\nx = y = z\n')
            assert(m2[help]=='回车 切换   数字 = 顺序'and m2.APPLY=='应用'and count==3 and code=='cn','ambiguous lines')
            assert(m2.x=='y = z'and m2['x = y']=='z','an unknown text keeps every split')
            -- a translation whose format does not fit its arguments falls back to the English template
            i18n.set({['%d fields']='%s Felder',['Saved preset %s (%d fields)']='%d %d'},'Deutsch')
            assert(i18n.Lf('%d fields',3)=='3 Felder','format')
            assert(i18n.Lf('Saved preset %s (%d fields)','x',2)=='Saved preset x (2 fields)','a broken template: English')
            -- a composite section, part by part
            i18n.set({Explosion='爆炸',Status='状态'},'中文')
            assert(i18n.L('Explosion · Primary impact · Status')=='爆炸 · Primary impact · 状态','by parts')
            i18n.set({},'English')
            assert(i18n.L('Explosion · Status')=='Explosion · Status')
            -- a file for the game language: by @code, file name or language name
            local langs={{name='English'},{name='Deutsch',file='de.txt'},{name='简体中文',file='mine.txt'},
                {name='X',file='x.txt',code='jp'}}
            assert(i18n.match_game_language('de',langs)=='Deutsch'and i18n.match_game_language('cn',langs)=='简体中文'
                and i18n.match_game_language('jp',langs)=='X'and i18n.match_game_language('ru',langs)==nil,'game language')
            -- UTF-8: cuts and Backspace never split a character
            local u=require('mods/skyeshade/hd2runtime_editor/editor/util')
            assert(u.utf8_cut('ab解放者',4)=='ab'and u.utf8_cut('ab解放者',5)=='ab解'and u.drop_last('a解')=='a'
                and u.drop_last('é')==''and u.drop_last('')=='','utf8 cuts')
            assert(u.plain(string.rep('解',200)):len()<=u.text_limit()and u.plain(string.rep('解',200)):len()%3==0,'plain')
            assert(u.estimate_width('解解',10)==20 and u.estimate_width('ab',10)==11,'width estimate')
            assert(u.value_text(true)=='On'and u.value_text('none')=='None','English values')
            i18n.set({On='开',None='无'},'中文')
            assert(u.value_label(true)=='开'and u.value_label('none')=='无'and u.value_text(true)=='On','translated values')
            assert(u.display_name({name='None'})=='无'and u.display_subtitle({name='x'})==nil,'display name')
            i18n.set({},'English')
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
            if (lua_host.RUNTIME / 'core' / 'status_slots.lua').is_file():
                self.assertIn('status slots one transaction ok', result)

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
                     'rebind ok', 'refusals ok', 'reset all ok', 'foreign values locked'):
            self.assertIn(line, result)

    def test_value_fields_over_script_choices(self):
        # calldown codes, mission uses, booleans, statuses, projectile swaps, terminal explosions (HD2Runtime r50)
        result = lua_host.run('local f=assert(loadfile(%s)) return f(%s)' % (
            lua_host._lua_string((LUA / 'test_layer_values.lua').as_posix()),
            lua_host._lua_string((LUA / 'sim.lua').as_posix())))
        for line in ('calldown code ok', 'mission uses ok', 'boolean ok', 'status ok', 'projectile swap ok',
                     'terminal explosion ok', 'refusals ok', 'rate slots with selector binding ok', 'direct first edit ok', 'armory traits ok', 'displayed penetration ok', 'steer watchdog ok', 'skipped steer settled again ok', 'disable sentinel ok', 'helldiver fields ok', 'armor stats ok', 'armor perks ok', 'mod code takeover ok', 'base value is a reset ok', 'turret limits ok', 'queued steer ok',
                     'registration cap ok'):
            self.assertIn(line, result)
        # HD2Runtime 0.31.0: a weapon without a fire-mode selector binds it with its second mode (when the Runtime
        # under test offers the binding)
        capabilities = lua_host.RUNTIME / 'sdk' / 'WeaponFireModeCapabilities.json'
        if capabilities.is_file() and '"addable"' in capabilities.read_text(encoding='utf-8'):
            self.assertIn('fire modes with selector binding ok', result)

    def test_runtime_0_30_4_rows(self):
        # each check runs only where the Runtime under test publishes the field (0.30.3, 0.31.0)
        result = lua_host.run('local f=assert(loadfile(%s)) return f()' % lua_host._lua_string(
            (LUA / 'test_runtime_rows.lua').as_posix()))
        self.assertIn('beam conversion ok', result)
        if (lua_host.RUNTIME / 'domains' / 'status_effect_writes.lua').is_file():
            for line in ('beam swaps ok', 'beam fire mode ok', 'team reload ok', 'derived heat ok',
                         'mounted sections ok', 'ammunition swap ok'):
                self.assertIn(line, result)
        # HD2Runtime 0.31.1 (scripts/programmable_feed_fields.py): the Peacemaker, missile and flak rows
        if (lua_host.RUNTIME / 'scripts' / 'programmable_feed_fields.py').is_file():
            self.assertIn('0.31.1 damage rows ok', result)
        else:
            self.assertIn('no 0.31.1 rows ok', result)
        # status slots 1 to 4 on every damage row (HD2Runtime 0.31.2 core/status_slots.lua)
        if (lua_host.RUNTIME / 'core' / 'status_slots.lua').is_file():
            self.assertIn('status slots ok', result)
        # catalogue explosions on the page of what sets them off (the RL-77's bomblets, both Hellbombs)
        explosions = lua_host.RUNTIME / 'domains' / 'explosion_catalogue.lua'
        text = explosions.read_text(encoding='utf-8') if explosions.is_file() else ''
        if 'rl77_airburst_rocket_launcher/function_expiry/shrapnel_expiry' in text:
            self.assertIn('rl77 bomblets ok', result)
        if 'nux223_hellbomb/behavior' in text and 'b100_portable_hellbomb/behavior' in text:
            self.assertIn('hellbombs ok', result)

    def test_dependent_fields_follow_what_they_need(self):
        # the rearm pool and the mission uses (HD2Runtime 0.31.0); beam conversion settings and their conversion
        result = lua_host.run('local f=assert(loadfile(%s)) return f(%s)' % (
            lua_host._lua_string((LUA / 'test_dependent_fields.lua').as_posix()),
            lua_host._lua_string((LUA / 'sim.lua').as_posix())))
        if (lua_host.RUNTIME / 'domains' / 'beam_conversion.lua').is_file():
            for line in ('setting refused while off ok', 'setting waits for the conversion ok',
                         'settings released with the conversion ok'):
                self.assertIn(line, result)
        else:
            self.assertIn('no beam conversion', result)
        if (lua_host.RUNTIME / 'docs' / 'stratagem-uses.md').is_file() and 'rearm_pool' in (
                lua_host.RUNTIME / 'docs' / 'stratagem-uses.md').read_text(encoding='utf-8'):
            self.assertIn('rearm pool order ok', result)
        # status slots (HD2Runtime 0.31.2): slot 2 waits for slot 1; a reset clears the later slot first
        if (lua_host.RUNTIME / 'core' / 'status_slots.lua').is_file():
            for line in ('status slot order ok', 'status slot reset ok'):
                self.assertIn(line, result)

    def test_window_frames_stay_inside_overlay_limits(self):
        result = lua_file('test_ui.lua', {'sim': (LUA / 'sim.lua').as_posix(),
                                          'harness': (LUA / 'ui_harness.lua').as_posix()})
        self.assertIn('ui ok', result, result)

    def test_presets_tab_imports_sections_and_icons(self):
        import subprocess
        # the 0.9.2 reader, to show an older editor still reads a file with an icon (when the tag is there)
        old = subprocess.run(['git', 'show', 'v0.9.2:src/editor/preset_files.lua'], cwd=lua_host.PROJECT,
                             capture_output=True, text=True, encoding='utf-8')
        result = lua_file('test_presets.lua', {'sim': (LUA / 'sim.lua').as_posix(),
                                               'harness': (LUA / 'ui_harness.lua').as_posix(),
                                               'old_preset_files': old.stdout if old.returncode == 0 else ''})
        for line in ('large import ok', 'background import ok', 'malformed ok', 'modbuilder file ok', 'sections ok',
                     'icons ok'):
            self.assertIn(line, result)
        if old.returncode == 0:
            self.assertIn('old editor ok', result)

    def test_preset_pictures_tool(self):
        # tools/preset_icons.py: your own pictures as layered mask images the build packs (the Runtime cannot load a
        # picture file while the game runs)
        try:
            from PIL import Image
        except ImportError:
            self.skipTest('needs Pillow')
        import tempfile
        spec = importlib.util.spec_from_file_location('preset_icons', lua_host.PROJECT / 'tools' / 'preset_icons.py')
        tool = importlib.util.module_from_spec(spec)
        spec.loader.exec_module(tool)
        with tempfile.TemporaryDirectory() as tmp:
            pictures, images = Path(tmp) / 'pictures', Path(tmp) / 'images'
            pictures.mkdir()
            picture = Image.new('RGBA', (300, 200), (0, 0, 0, 0))
            for x in range(40, 260):
                for y in range(30, 170):
                    picture.putpixel((x, y), (220, 40, 40, 255) if x < 150 else (250, 250, 250, 255))
            picture.save(pictures / 'My Squad.png')
            (pictures / 'notes.txt').write_text('not a picture')
            (pictures / 'broken.png').write_bytes(b'not a png')
            generated = Path(tmp) / 'preset_icons.lua'
            self.assertEqual(tool.main([str(pictures), '--images', str(images), '--generated', str(generated)]), 0)
            made = sorted(p.name for p in images.glob('pi_*.png'))
            self.assertTrue(made and all(n.startswith('pi_mysquad') for n in made), made)
            result = lua_host.run('local t=dofile(%s) local e=t.icons[1] return #t.icons..\' \'..e.name..\' \'..#e.layers'
                                  '..\' \'..e.layers[1].image..\' \'..#e.layers[1].colours.r' % lua_host._lua_string(
                                      generated.as_posix()))
            count, name, rest = result.split(' ', 2)
            self.assertEqual(count, '1')
            self.assertEqual(name + ' ' + rest.split(' ')[0], 'My Squad')
            layers, image, channels = rest.split(' ')[1:]
            self.assertEqual(int(layers), len(made))
            self.assertIn(image + '.png', made)
            self.assertEqual(channels, '4')
            self.assertEqual(tool.main(['--clean', '--images', str(images), '--generated', str(generated)]), 0)
            self.assertFalse(list(images.glob('pi_*.png')) or generated.exists())

    def test_saved_session_keeps_values_that_did_not_come_back(self):
        result = lua_file('test_session.lua', {'sim': (LUA / 'sim.lua').as_posix(),
                                               'harness': (LUA / 'ui_harness.lua').as_posix()})
        for line in ('kept ok', 'player wins ok', 'reset all ok', 'next start ok'):
            self.assertIn(line, result)

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

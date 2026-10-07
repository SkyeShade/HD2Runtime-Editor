"""HD2Runtime Editor offline tests, on the game's own LuaJIT (tests/lua_host.py) and the HD2Runtime source checkout.

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

    def test_catalogue_rows_pass_the_runtime_validator(self):
        src = (HERE / 'catalog_report.lua').read_text(encoding='utf-8')
        report = lua_host.run('local f=assert(loadstring(%s,"@catalog_report")) return f(nil)' % lua_host._lua_string(src))
        total = re.search(r'TOTAL rows=(\d+) editable=(\d+) valid=(\d+)', report)
        self.assertIsNotNone(total, report)
        rows, editable, valid = map(int, total.groups())
        self.assertGreater(rows, 15000, report)
        # The one known exception: an enemy field whose reviewed domain is "-1, or above 0" (the sample value is 0).
        self.assertGreaterEqual(valid, editable - 1, report)
        for failure in re.findall(r'^\s+\d+ x (.+)$', report, re.M):
            self.assertIn('gore', failure, report)

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
                     'terminal explosion ok', 'refusals ok', 'mod code takeover ok'):
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

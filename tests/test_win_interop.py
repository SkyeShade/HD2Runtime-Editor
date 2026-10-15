import tempfile
import unittest
from pathlib import Path
import lua_host


@unittest.skipUnless(lua_host.available(), 'game LuaJIT required')
class WinInteropTests(unittest.TestCase):
    def test_localization_in_a_native_codepage_profile_without_an_index(self):
        # Lua's CRT getenv/io.open paths are native-codepage bytes, not UTF-8.
        # Use only private fixtures, and declare win.lua's distinct FIND_DATA first.
        try:
            '测试路径/简中.txt'.encode('mbcs')
        except (UnicodeEncodeError, LookupError):
            self.skipTest('Chinese paths are not representable in this Windows code page')
        with tempfile.TemporaryDirectory() as directory:
            profile = Path(directory) / '测试路径'
            folder = profile / 'HD2REditor/localization'
            folder.mkdir(parents=True)
            (folder / '简中.txt').write_text('@language 路径测试\n@code cn\nBROWSE = 路径覆盖\n', encoding='utf8')
            native = '"' + ''.join('\\%03d' % byte for byte in str(profile).encode('mbcs')) + '"'
            body = r'''
local win=require('mods/skyeshade/hd2runtime_editor/editor/win')
assert(#assert(win.list(FOLDER))==1)
os.getenv=function(name)if name=='LOCALAPPDATA'then return PROFILE end end
local i=require('mods/skyeshade/hd2runtime_editor/editor/i18n')
local languages=i.languages()
assert(#languages==3,'English, external file and bundled Chinese; no index required')
assert(languages[2].display_file=='简中.txt','display filenames remain UTF-8')
assert(i.match_game_language('cn',languages)=='路径测试')
assert(i.use('路径测试',languages)and i.L('BROWSE')=='路径覆盖')
assert(i.L('APPLY')=='应用','external file inherits built-in translations')
return 'ok'
'''.replace('FOLDER', lua_host._lua_string(str(folder))).replace('PROFILE', native)
            self.assertEqual(lua_host.run(body), 'ok')

    def test_folder_listing_after_another_modules_find_data_declaration(self):
        with tempfile.TemporaryDirectory() as directory:
            root=Path(directory)
            (root/'preset.json').write_text('{}')
            (root/'second.json').write_text('{}')
            (root/'folder').mkdir()
            body=r'''
local ffi=require('ffi')
ffi.cdef[[
typedef struct { uint32_t flags; uint32_t times[6]; uint32_t sizeHigh,sizeLow;
 uint32_t reserved[2]; uint16_t filename[260],shortname[14]; } AnotherModFindData;
void *FindFirstFileW(const uint16_t *, AnotherModFindData *);
int FindNextFileW(void *, AnotherModFindData *);
]]
local win=require('mods/skyeshade/hd2runtime_editor/editor/win')
local rows,why=win.list(PATH)
assert(rows,why)
local found={};for _,r in ipairs(rows)do found[r.name]=r end
assert(#rows==3 and found['folder'].folder and found['preset.json'].size==2)
assert(not found['second.json'].folder)
return 'ok'
'''.replace('PATH',lua_host._lua_string(str(root)))
            self.assertEqual(lua_host.run(body),'ok')

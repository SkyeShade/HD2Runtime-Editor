import tempfile
import unittest
from pathlib import Path
import lua_host


@unittest.skipUnless(lua_host.available(), 'game LuaJIT required')
class WinInteropTests(unittest.TestCase):
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

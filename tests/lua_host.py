"""Run Lua offline in Helldivers 2's own LuaJIT (bin/lua51.dll), the VM the editor runs on in game.

Only lua51.dll is loaded into this process: never the game executable or game.dll. Modules resolve from disk:

* ``hd2runtime/<folder>/<name>``  -> ``<HD2Runtime checkout>/<folder>/<name>.lua`` (read only; for contract tests
  against the real Runtime catalogues and validators);
* ``mods/skyeshade/hd2runtime_editor[/<path>]`` -> ``src/addon.lua`` / ``src/<path>.lua`` of this project.

Environment: ``HD2_GAME_ROOT`` (default: the Steam install) and ``HD2RUNTIME_ROOT`` (default: ``../HD2Runtime``).
"""
import ctypes
import os
from pathlib import Path

PROJECT = Path(__file__).resolve().parents[1]
RUNTIME = Path(os.environ.get('HD2RUNTIME_ROOT', PROJECT.parent / 'HD2Runtime')).resolve()
GAME = Path(os.environ.get('HD2_GAME_ROOT', r'C:\Program Files (x86)\Steam\steamapps\common\Helldivers 2'))
RESOURCE = 'mods/skyeshade/hd2runtime_editor'

_library = None


def library():
    global _library
    if _library is None:
        lib = ctypes.CDLL(str(GAME / 'bin/lua51.dll'))
        lib.luaL_newstate.restype = ctypes.c_void_p
        lib.luaL_openlibs.argtypes = [ctypes.c_void_p]
        lib.luaL_loadbuffer.argtypes = [ctypes.c_void_p, ctypes.c_char_p, ctypes.c_size_t, ctypes.c_char_p]
        lib.lua_pcall.argtypes = [ctypes.c_void_p, ctypes.c_int, ctypes.c_int, ctypes.c_int]
        lib.lua_tolstring.argtypes = [ctypes.c_void_p, ctypes.c_int, ctypes.POINTER(ctypes.c_size_t)]
        lib.lua_tolstring.restype = ctypes.c_void_p
        lib.lua_close.argtypes = [ctypes.c_void_p]
        _library = lib
    return _library


def _lua_string(text):
    """A Lua long-bracket string literal whose level never collides with the text."""
    level = 2
    while (']' + '=' * level + ']') in text:
        level += 1
    eq = '=' * level
    # a long bracket drops a newline right after it: keep a leading newline of the text
    return '[' + eq + '[' + ('\n' if text.startswith('\n') else '') + text + ']' + eq + ']'


def prelude():
    """A package searcher for the Runtime checkout and this project's src/ (plain files, loaded on demand)."""
    return '''
local RUNTIME=%s
local SRC=%s
local RESOURCE=%s
local function read(path)
    local f=io.open(path,'rb')
    if not f then return nil end
    local s=f:read('*a');f:close();return s
end
local function search(name)
    local path
    local inner=name:match('^hd2runtime/(.+)$')
    if inner then path=RUNTIME..'/'..inner..'.lua'
    elseif name==RESOURCE then path=SRC..'/addon.lua'
    else
        local rest=name:sub(1,#RESOURCE+1)==RESOURCE..'/'and name:sub(#RESOURCE+2)
        if rest then path=SRC..'/'..rest..'.lua'end
    end
    if not path then return nil end
    local source=read(path)
    if not source then return '\\n\\tno file '..path end
    local chunk,err=loadstring(source,'@'..name)
    if not chunk then error(err,0)end
    return chunk
end
table.insert(package.loaders,2,search)
''' % (_lua_string(RUNTIME.as_posix()), _lua_string((PROJECT / 'src').as_posix()), _lua_string(RESOURCE))


def run(body: str, name: str = '@editor-test') -> str:
    """Run ``prelude() + body`` in a fresh state; returns the chunk's first result as a string. Lua errors raise
    RuntimeError with the Lua message (and traceback)."""
    lib = library()
    script = (prelude() + '\nlocal function __main()\n' + body + '\nend\n'
              'local ok,result=xpcall(__main,function(e)return tostring(e)..\'\\n\'..debug.traceback()end)\n'
              'if not ok then error(result,0)end\nreturn result==nil and\'\'or tostring(result)\n').encode()
    state = lib.luaL_newstate()
    if not state:
        raise RuntimeError('luaL_newstate failed')
    try:
        lib.luaL_openlibs(state)
        status = lib.luaL_loadbuffer(state, script, len(script), name.encode())
        if status == 0:
            status = lib.lua_pcall(state, 0, 1, 0)
        length = ctypes.c_size_t()
        pointer = lib.lua_tolstring(state, -1, ctypes.byref(length))
        result = ctypes.string_at(pointer, length.value).decode('utf-8', 'replace') if pointer else ''
        if status:
            raise RuntimeError(result)
        return result
    finally:
        lib.lua_close(state)


def available():
    return (GAME / 'bin/lua51.dll').is_file() and RUNTIME.is_dir()

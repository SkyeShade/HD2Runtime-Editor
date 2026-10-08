-- HD2R Editor (c) 2026 SkyeShade. All rights reserved except as granted in LICENSE
-- (https://github.com/SkyeShade/HD2Runtime-Editor). Do not redistribute or reuse without the credit it requires.
-- The few Windows calls the editor makes itself, through LuaJIT's FFI (declared once, each call guarded): open a file
-- or folder with its default program (ShellExecuteW), list a folder (FindFirstFileW), create folders, and the user's
-- folders. Every function returns nil and why when the FFI or the call is unavailable.
local M={}

local ffi,kernel,shell
local function load()
    if ffi~=nil then return ffi~=false end
    local ok=pcall(function()
        ffi=require('ffi')
        if not rawget(_G,'HD2REditorWinV1')then
            ffi.cdef[[
                typedef struct { uint32_t attributes; uint32_t c1,c2,a1,a2,w1,w2; uint32_t size_hi,size_lo;
                    uint32_t r0,r1; uint16_t name[260]; uint16_t alt[14]; uint32_t t,c,f; } HD2REditorFindW;
                void *FindFirstFileW(const uint16_t *pattern, HD2REditorFindW *data);
                int FindNextFileW(void *handle, HD2REditorFindW *data);
                int FindClose(void *handle);
                int CreateDirectoryW(const uint16_t *path, void *security);
                int MultiByteToWideChar(uint32_t cp, uint32_t flags, const char *s, int n, uint16_t *w, int wn);
                int WideCharToMultiByte(uint32_t cp, uint32_t flags, const uint16_t *w, int wn, char *s, int n,
                    const char *d, int *u);
                void *ShellExecuteW(void *hwnd, const uint16_t *op, const uint16_t *file, const uint16_t *params,
                    const uint16_t *dir, int show);
            ]]
            rawset(_G,'HD2REditorWinV1',true)
        end
        kernel=ffi.load('kernel32')
        shell=ffi.load('shell32')
    end)
    if not ok then ffi=false end
    return ok
end

function M.wide(text)
    if not load()then return nil end
    local n=#text*2+2
    local w=ffi.new('uint16_t[?]',n)
    kernel.MultiByteToWideChar(65001,0,text,-1,w,n)
    return w
end
local function narrow(w)
    local buffer=ffi.new('char[1024]')
    local n=kernel.WideCharToMultiByte(65001,0,w,-1,buffer,1024,nil,nil)
    return n>1 and ffi.string(buffer,n-1)or''
end

-- Opens a file or folder with its default program (Explorer for a folder). True, or nil and why.
function M.open(path)
    if not load()then return nil,'no FFI'end
    local ok,result=pcall(function()return shell.ShellExecuteW(nil,M.wide('open'),M.wide(path),nil,nil,1)end)
    if not ok then return nil,tostring(result)end
    local code=tonumber(ffi.cast('intptr_t',result))
    if code<=32 then return nil,'ShellExecute failed ('..code..')'end
    return true
end
-- Opens Explorer with a file selected.
function M.reveal(path)
    if not load()then return nil,'no FFI'end
    local ok,result=pcall(function()
        return shell.ShellExecuteW(nil,M.wide('open'),M.wide('explorer.exe'),M.wide('/select,"'..path..'"'),nil,1)
    end)
    if not ok then return nil,tostring(result)end
    return tonumber(ffi.cast('intptr_t',result))>32 or nil
end

-- {{name, folder = true|false, size}} of a folder's entries matching pattern ('*' by default), '.' and '..' left out.
function M.list(folder,pattern)
    if not load()then return nil,'no FFI'end
    local out={}
    local ok,why=pcall(function()
        local data=ffi.new('HD2REditorFindW')
        local handle=kernel.FindFirstFileW(M.wide(folder..'\\'..(pattern or'*')),data)
        if handle==nil or tonumber(ffi.cast('intptr_t',handle))==-1 then return end
        repeat
            local name=narrow(data.name)
            if name~='.'and name~='..'and name~=''then
                local dir=bit.band(data.attributes,0x10)~=0
                local hidden=bit.band(data.attributes,0x2)~=0
                if not hidden then
                    out[#out+1]={name=name,folder=dir,size=tonumber(data.size_lo)+tonumber(data.size_hi)*4294967296}
                end
            end
        until kernel.FindNextFileW(handle,data)==0
        kernel.FindClose(handle)
    end)
    if not ok then return nil,tostring(why)end
    table.sort(out,function(a,b)
        if a.folder~=b.folder then return a.folder end
        return a.name:lower()<b.name:lower()
    end)
    return out
end

-- Creates a folder and every missing parent. True, or nil and why.
function M.mkdir(path)
    if not load()then return nil,'no FFI'end
    local built=''
    for part in path:gmatch('[^\\/]+')do
        built=built==''and part or(built..'\\'..part)
        if not built:match('^%a:$')then pcall(kernel.CreateDirectoryW,M.wide(built),nil)end
    end
    return true
end

function M.env(name)local ok,v=pcall(os.getenv,name);return ok and v or nil end
-- The user's own folders, for the image picker.
function M.places()
    local home=M.env('USERPROFILE')
    local out={}
    if home then
        for _,name in ipairs({'Pictures','Desktop','Downloads','Documents'})do out[#out+1]={label=name,path=home..'\\'..name}end
    end
    return out
end

return M

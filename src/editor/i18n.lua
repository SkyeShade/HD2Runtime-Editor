-- HD2Runtime Editor (c) 2026 SkyeShade. All rights reserved except as granted in LICENSE
-- (https://github.com/SkyeShade/HD2Runtime-Editor). Do not redistribute or reuse without the credit it requires.
-- Localisation: every text the editor shows goes through L(text). English is built in (the text itself); other
-- languages are plain UTF-8 text files in a folder the editor reads at startup and on Reload:
--     %LOCALAPPDATA%\HD2RuntimeEditor\localization\<anything>.txt
-- One line per text, the English original, then " = ", then the translation; # starts a comment. A line
-- "@language Deutsch" names the language (else the file name does). Formats such as "%d fields" keep their %d / %s.
-- Settings → Write template puts template.txt (every text of the editor's interface) in that folder to translate.
-- Field names come from the Runtime's catalogues; add lines for them too if you like (L() looks every one up).
local M={}

local current={}          -- English -> translation
local language='English'

function M.L(text)
    if text==nil then return''end
    local t=current[text]
    if t then return t end
    return text
end
function M.language()return language end

-- Parse a localisation file: returns map, language name (or nil).
function M.parse(text)
    local map,name={},nil
    for line in(tostring(text or'')..'\n'):gmatch('([^\n]*)\n')do
        line=line:gsub('\r$','')
        if line:sub(1,3)=='\239\187\191'then line=line:sub(4)end     -- UTF-8 byte order mark
        local lang=line:match('^%s*@language%s+(.-)%s*$')
        if lang and lang~=''then name=lang
        elseif not line:match('^%s*#')and not line:match('^%s*$')then
            local original,translated=line:match('^(.-)%s=%s(.*)$')
            if original and original~=''and translated and translated~=''then
                -- \n in a file stands for nothing special: the editor's texts are single lines
                map[original]=translated
            end
        end
    end
    return map,name
end

local function env(name)local ok,v=pcall(os.getenv,name);return ok and v or nil end
function M.folder()
    local base=env('LOCALAPPDATA')
    return base and(base..'\\HD2RuntimeEditor\\localization')or nil
end
local function read(path)
    if type(io)~='table'or type(io.open)~='function'then return nil end
    local ok,f=pcall(io.open,path,'rb')
    if not ok or not f then return nil end
    local text=f:read('*a');f:close()
    return text
end

-- The .txt files in the folder: FindFirstFileW through LuaJIT's FFI when available, else the names listed in the
-- folder's index.txt (one per line).
local function list_files(folder)
    local names={}
    local ok=pcall(function()
        local ffi=require('ffi')
        local kernel=ffi.load('kernel32')
        local key='HD2EditorFindDataW'
        if not rawget(_G,key)then
            ffi.cdef[[
                typedef struct { uint32_t attributes; uint32_t c1,c2,a1,a2,w1,w2; uint32_t size_hi,size_lo;
                    uint32_t r0,r1; uint16_t name[260]; uint16_t alt[14]; uint32_t t,c,f; } HD2EditorFindDataW;
                void *FindFirstFileW(const uint16_t *pattern, HD2EditorFindDataW *data);
                int FindNextFileW(void *handle, HD2EditorFindDataW *data);
                int FindClose(void *handle);
                int MultiByteToWideChar(uint32_t cp, uint32_t flags, const char *s, int n, uint16_t *w, int wn);
                int WideCharToMultiByte(uint32_t cp, uint32_t flags, const uint16_t *w, int wn, char *s, int n,
                    const char *d, int *u);
            ]]
            rawset(_G,key,true)
        end
        local pattern=folder..'\\*.txt'
        local wide=ffi.new('uint16_t[?]',#pattern*2+2)
        kernel.MultiByteToWideChar(65001,0,pattern,-1,wide,#pattern*2+2)
        local data=ffi.new('HD2EditorFindDataW')
        local handle=kernel.FindFirstFileW(wide,data)
        if handle==nil or tonumber(ffi.cast('intptr_t',handle))==-1 then return end
        local buffer=ffi.new('char[1024]')
        repeat
            local n=kernel.WideCharToMultiByte(65001,0,data.name,-1,buffer,1024,nil,nil)
            if n>1 then names[#names+1]=ffi.string(buffer,n-1)end
        until kernel.FindNextFileW(handle,data)==0
        kernel.FindClose(handle)
    end)
    if not ok or#names==0 then
        local index=read(folder..'\\index.txt')
        for line in tostring(index or''):gmatch('[^\r\n]+')do
            if line:match('%.txt$')then names[#names+1]=line end
        end
    end
    local out={}
    for _,n in ipairs(names)do
        if n:lower()~='template.txt'and n:lower()~='index.txt'then out[#out+1]=n end
    end
    table.sort(out)
    return out
end

-- Every language: {{name, file (nil for English), count}}.
function M.languages()
    local out={{name='English',count=0}}
    local folder=M.folder()
    if not folder then return out end
    for _,file in ipairs(list_files(folder))do
        local text=read(folder..'\\'..file)
        if text then
            local map,name=M.parse(text)
            local n=0
            for _ in pairs(map)do n=n+1 end
            out[#out+1]={name=name or file:gsub('%.txt$',''),file=file,count=n}
        end
    end
    return out
end
-- Switch to a language by name ('English' or a file's language); false and why when it is not found.
function M.use(name)
    if name==nil or name=='English'then current,language={},'English';return true end
    for _,l in ipairs(M.languages())do
        if l.name==name and l.file then
            local text=read(M.folder()..'\\'..l.file)
            if text then current,language=(M.parse(text)),l.name;return true end
        end
    end
    current,language={},'English'
    return false,'no localisation file for '..tostring(name)
end
-- For tests: use a map directly.
function M.set(map,name)current,language=map or{},name or'Custom'end

-- Write template.txt (every interface text, untranslated) into the folder. Returns the path, or nil and why.
function M.write_template(strings)
    local folder=M.folder()
    if not folder then return nil,'%LOCALAPPDATA% is not set'end
    pcall(function()
        local ffi=require('ffi')
        local kernel=ffi.load('kernel32')
        if not rawget(_G,'HD2EditorCreateDirectoryA')then
            ffi.cdef'int CreateDirectoryA(const char *path, void *security);'
            rawset(_G,'HD2EditorCreateDirectoryA',true)
        end
        kernel.CreateDirectoryA(folder:match('^(.*)\\[^\\]+$'),nil)
        kernel.CreateDirectoryA(folder,nil)
    end)
    local path=folder..'\\template.txt'
    local ok,f=pcall(io.open,path,'wb')
    if not ok or not f then return nil,'cannot write '..path end
    f:write('# HD2Runtime Editor localisation template. Copy this file (any name ending in .txt), set the language\n')
    f:write('# name below and write each translation after " = ". Lines without a translation are ignored.\n')
    f:write('@language My language\n\n')
    for _,s in ipairs(strings or{})do f:write(s,' = \n')end
    f:close()
    return path
end

return M

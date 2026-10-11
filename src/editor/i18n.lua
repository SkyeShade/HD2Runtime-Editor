-- HD2R Editor (c) 2026 SkyeShade. All rights reserved except as granted in LICENSE
-- (https://github.com/SkyeShade/HD2Runtime-Editor). Do not redistribute or reuse without the credit it requires.
-- Localisation: every text the editor shows goes through L(text). English is built in (the text itself); other
-- languages are plain UTF-8 text files in a folder the editor reads at startup and on Reload:
--     %LOCALAPPDATA%\HD2REditor\localization\<anything>.txt
-- One line per text, the English original, then " = ", then the translation; # starts a comment. A line
-- "@language Deutsch" names the language (else the file name does); an optional "@code cn" names the game language it
-- is for (else the file name or language name tells, M.GAME_LANGUAGES). Formats such as "%d fields" keep their %d /
-- %s (a translation that breaks them shows the English text, M.Lf). With no language picked in Settings, the file for
-- the game's language is used when there is one.
-- Settings → Write template puts template.txt in that folder to translate: every text of the editor's interface,
-- then every name, section and field the catalogue shows (weapons, stratagems, enemies ...). L() looks every one up.
local M={}

local current={}          -- English -> translation
local language='English'
local parts_cache={}      -- composite labels ('Damage · Flak') translated part by part, per language

-- A composite label the catalogue builds from parts ('Explosion · Primary impact · Status'): the whole text when the
-- file translates it, else each part that it translates (the rest stays English).
local SEPARATOR=' · '
local function by_parts(text)
    local cached=parts_cache[text]
    if cached then return cached end
    local out,changed,start={},false,1
    while true do
        local a,b=text:find(SEPARATOR,start,true)
        local part=text:sub(start,(a or 0)-1)
        local t=current[part]
        if t then changed=true;part=t end
        out[#out+1]=part
        if not a then break end
        start=b+1
    end
    local result=changed and table.concat(out,SEPARATOR)or text
    parts_cache[text]=result
    return result
end
function M.L(text)
    if text==nil then return''end
    local t=current[text]
    if t then return t end
    if type(text)=='string'and next(current)~=nil and text:find(SEPARATOR,1,true)then return by_parts(text)end
    return text
end
-- L(template):format(...), safe: a translation whose format specifiers do not fit the arguments (a missing %s, a %d
-- given text) shows the English template instead of failing, like HD2Runtime's own i18n.translate.
function M.Lf(template,...)
    local ok,text=pcall(string.format,M.L(template),...)
    if ok then return text end
    local okx,english=pcall(string.format,template,...)
    if okx then return english end
    return tostring(template)
end
function M.language()return language end

-- Parse a localisation file: returns map, language name (or nil), the number of translated lines and the language
-- code the file names (@code, or nil). A line is "English = translation" (a space or tab either side of the "=").
-- When a line has " = " more than once (an English text such as "numbers = order", or a translation that keeps one),
-- the split whose English part is an interface text the editor knows wins; with none known, every split is kept for
-- lookups (never over a line with one " = " only).
local known_texts
local function known()
    if known_texts==nil then
        known_texts={}
        local ok,list=pcall(require,'mods/skyeshade/hd2runtime_editor/editor/strings')
        for _,s in ipairs(ok and type(list)=='table'and list or{})do known_texts[s]=true end
    end
    return known_texts
end
function M.parse(text)
    local map,name,code,count={},nil,nil,0
    local ambiguous={}
    for line in(tostring(text or'')..'\n'):gmatch('([^\n]*)\n')do
        line=line:gsub('\r$','')
        if line:sub(1,3)=='\239\187\191'then line=line:sub(4)end     -- UTF-8 byte order mark
        local lang=line:match('^%s*@language%s+(.-)%s*$')
        local lcode=line:match('^%s*@code%s+(.-)%s*$')
        if lang and lang~=''then name=lang
        elseif lcode and lcode~=''then code=lcode:lower()
        elseif not line:match('^%s*#')and not line:match('^%s*$')then
            -- every " = " of the line: the possible splits
            local splits,start={},1
            while true do
                local a,b=line:find('%s=%s',start)
                if not a then break end
                local original,translated=line:sub(1,a-1),line:sub(b+1)
                if original~=''and translated~=''and not translated:match('^%s*$')then
                    splits[#splits+1]={original,translated}
                end
                start=a+1
            end
            if#splits==1 then map[splits[1][1]]=splits[1][2];count=count+1
            elseif#splits>1 then ambiguous[#ambiguous+1]=splits;count=count+1 end
        end
    end
    for _,splits in ipairs(ambiguous)do
        local chosen
        for _,s in ipairs(splits)do if known()[s[1]]then chosen=s;break end end
        if chosen then map[chosen[1]]=chosen[2]
        else
            for _,s in ipairs(splits)do if map[s[1]]==nil then map[s[1]]=s[2]end end
        end
    end
    return map,name,count,code
end

local function env(name)local ok,v=pcall(os.getenv,name);return ok and v or nil end
function M.folder()
    local base=env('LOCALAPPDATA')
    return base and(base..'\\HD2REditor\\localization')or nil
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

-- The characters of a translation map the overlay can never draw (the game then shows '?'). HD2Runtime 0.31.0+ draws
-- Chinese, Japanese, Korean and Russian in the game's own language fonts, in any game language, loading the font a
-- text needs (hd2.ui.unsupported: only characters no game font has, Greek for one, count). An older HD2Runtime draws
-- with FS Sinclair only (ASCII, Latin-1, the call-in arrows, a few punctuation marks). Returns how many distinct
-- characters, and up to three of them.
local glyphs
-- 'game_fonts' (HD2Runtime 0.31.0+: hd2.ui.unsupported) or 'latin' (FS Sinclair only).
function M.drawing()
    local ok,hd2=pcall(require,'mods/skyeshade/hd2runtime')
    if ok and type(hd2)=='table'and type(hd2.ui)=='table'and type(hd2.ui.unsupported)=='function'then
        return 'game_fonts',hd2
    end
    return 'latin'
end
function M.undrawable(map)
    local mode,hd2=M.drawing()
    if mode=='game_fonts'then
        local texts={}
        for _,text in pairs(map or{})do texts[#texts+1]=tostring(text)end
        table.sort(texts)
        local ok,n,sample=pcall(hd2.ui.unsupported,table.concat(texts,' '))
        if ok and type(n)=='number'then return n,type(sample)=='table'and sample or{}end
    end
    if glyphs==nil then
        local ok,data=pcall(require,'hd2runtime/domains/ui_fonts')
        local body=ok and type(data)=='table'and type(data.fonts)=='table'and data.fonts.body
        glyphs=body and type(body.advances)=='table'and body.advances or false
    end
    if not glyphs then return 0,{}end
    local seen,n,sample={},0,{}
    for _,text in pairs(map or{})do
        for ch in tostring(text):gmatch('[%z\1-\127\194-\244][\128-\191]*')do
            local b1=ch:byte(1)
            local cp=b1
            if b1>=0xF0 then cp=((b1%8)*262144)+((ch:byte(2)or 128)%64)*4096+((ch:byte(3)or 128)%64)*64+((ch:byte(4)or 128)%64)
            elseif b1>=0xE0 then cp=((b1%16)*4096)+((ch:byte(2)or 128)%64)*64+((ch:byte(3)or 128)%64)
            elseif b1>=0xC0 then cp=((b1%32)*64)+((ch:byte(2)or 128)%64)end
            if cp>=32 and not glyphs[cp]and not seen[cp]then
                seen[cp]=true;n=n+1
                if#sample<3 then sample[#sample+1]=ch end
            end
        end
    end
    return n,sample
end
-- Every language: {{name, file (nil for English), count, undrawable, sample}}.
function M.languages()
    local out={{name='English',count=0}}
    local folder=M.folder()
    if not folder then return out end
    for _,file in ipairs(list_files(folder))do
        local text=read(folder..'\\'..file)
        if text then
            local map,name,n,code=M.parse(text)
            local missing,sample=M.undrawable(map)
            out[#out+1]={name=name or(file:gsub('%.txt$','')),file=file,count=n,undrawable=missing,sample=sample,
                code=code}
        end
    end
    return out
end
local function switch(map,name)current,language,parts_cache=map or{},name,{}end
-- Switch to a language by name ('English' or a file's language); false and why when it is not found.
function M.use(name,languages)
    if name==nil or name=='English'then switch({},'English');return true end
    for _,l in ipairs(languages or M.languages())do
        if l.name==name and l.file then
            local text=read(M.folder()..'\\'..l.file)
            if text then switch((M.parse(text)),l.name);return true end
        end
    end
    switch({},'English')
    return false,'no localisation file for '..tostring(name)
end
-- For tests: use a map directly.
function M.set(map,name)switch(map,name or'Custom')end

-- The names a localisation file for a game language can have (HD2Runtime's language codes, hd2.ui.language): the
-- code, the usual ISO codes, the language's English name and its own. A file matches by its "@code" line, its file
-- name or its "@language" name (case does not matter).
M.GAME_LANGUAGES={
    us={'us','en','en-us','english','english (us)'},gb={'gb','en-gb','english (uk)'},
    de={'de','de-de','german','deutsch'},fr={'fr','fr-fr','french','français'},
    es={'es','es-es','spanish','español','español (españa)'},
    ms={'ms','es-419','es-mx','español (latinoamérica)'},it={'it','it-it','italian','italiano'},
    pl={'pl','pl-pl','polish','polski'},bp={'bp','pt-br','português (brasil)'},
    pt={'pt','pt-pt','portuguese','português','português (portugal)'},ru={'ru','ru-ru','russian','русский'},
    jp={'jp','ja','ja-jp','japanese','日本語'},ko={'ko','kr','ko-kr','korean','한국어'},
    cn={'cn','zh','zh-cn','zh-hans','zh_cn','chinese','simplified chinese','简体中文','中文','简中'},
    tc={'tc','zh-tw','zh-hk','zh-hant','zh_tw','traditional chinese','繁體中文','繁体中文','繁中'}}
-- The language (a file's language name, as M.use takes it) for a game language code, or nil.
function M.match_game_language(code,languages)
    local names=M.GAME_LANGUAGES[tostring(code or''):lower()]
    if not names then return nil end
    local wanted={}
    for _,n in ipairs(names)do wanted[n]=true end
    for _,l in ipairs(languages or M.languages())do
        if l.file then
            local stem=l.file:gsub('%.txt$',''):lower()
            if(l.code and wanted[l.code])or wanted[stem]or wanted[tostring(l.name):lower()]then return l.name end
        end
    end
    return nil
end
-- No language picked in Settings: the language the game (or HD2Runtime's F10 Language setting) shows, when a
-- localisation file for it is there (hd2.ui.language, HD2Runtime 0.31.1). Returns the language now used, or nil.
function M.use_game_language(hd2)
    local ui=type(hd2)=='table'and type(hd2.ui)=='table'and hd2.ui
    if not(ui and type(ui.language)=='function')then return nil end
    local ok,code=pcall(ui.language)
    if not ok or type(code)~='string'then return nil end
    local languages=M.languages()
    local name=M.match_game_language(code,languages)
    if name and M.use(name,languages)then return name end
    return nil
end

-- Write template.txt (every interface text, untranslated) into the folder, then `extra` (the names, sections and field
-- labels the window shows from the catalogue: editor/catalog.lua Catalog:texts) under their own heading. Returns the
-- path, or nil and why.
function M.write_template(strings,extra,extra_heading)
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
    f:write('# HD2R Editor localisation template. Copy this file (any name ending in .txt), set the language\n')
    f:write('# name below and write each translation after " = ". Lines without a translation are ignored.\n')
    f:write('@language My language\n\n')
    local seen={}
    for _,s in ipairs(strings or{})do seen[s]=true;f:write(s,' = \n')end
    local more={}
    for _,s in ipairs(extra or{})do
        if type(s)=='string'and s~=''and not seen[s]and not s:find('[\r\n]')then seen[s]=true;more[#more+1]=s end
    end
    if#more>0 then
        f:write('\n# ',extra_heading or'Names, sections and fields',' (',#more,' texts). A section such as\n')
        f:write('# "Explosion · Primary impact" is also translated part by part: "Explosion", "Primary impact".\n')
        for _,s in ipairs(more)do f:write(s,' = \n')end
    end
    f:close()
    return path
end

return M

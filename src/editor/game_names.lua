-- HD2R Editor (c) 2026 SkyeShade. All rights reserved except as granted in LICENSE
-- (https://github.com/SkyeShade/HD2Runtime-Editor). Do not redistribute or reuse without the credit it requires.
-- The game's own names of the catalogue's objects, in the game's language, through HD2Runtime's game text API when the
-- installed Runtime has one (HD2Runtime 0.31.2 docs/game-text.md): hd2.text.name(kind, key) -> the display name, or
-- nil, code and reason; hd2.text.available() -> true and the language, or false, code and reason; hd2.text.language().
-- Feature-detected and called under pcall: without the API, while the game's texts are not available, or when a call
-- fails or has no name, the window shows the editor's own name (a localisation file's translation, else English).
-- Names are cached per game language and looked up again when the window opens (refresh). The English name stays the
-- identity everywhere: keys, presets, exports and search. Settings → "Use the game's names" (setting game_names,
-- default on) turns it off.
local util=require('mods/skyeshade/hd2runtime_editor/editor/util')
local M={}

-- The Runtime's kind of an object, by the family of its key ('pw|AR-23 Liberator'); the key is the object's English
-- name. A support weapon, backpack or vehicle without a name of its kind is asked for as its stratagem.
M.KINDS={pw='weapon',sp='support_weapon',th='throwable',sb='backpack',ve='vehicle',bo='booster',
    st='stratagem',rs='stratagem',ex='stratagem'}
local STRATAGEM_FALLBACK={sp=true,sb=true,ve=true}
-- (the game is registering its texts or switching language: asked again when the window opens next)
local TRANSIENT={UNAVAILABLE=true}

local function field(t,key)
    local ok,value=pcall(function()return t[key]end)
    if ok then return value end
    return nil
end
-- The Runtime's game text API, or nil.
local function api(hd2)
    local text=type(hd2)=='table'and field(hd2,'text')
    if type(text)=='table'and type(field(text,'name'))=='function'then return text end
    return nil
end
function M.available(hd2)return api(hd2)~=nil end

-- A name the window can show: a non-empty string without control characters, trimmed.
local function clean(name)
    if type(name)~='string'then return nil end
    name=name:gsub('[%z\1-\31\127]',''):gsub('^%s+',''):gsub('%s+$','')
    if name==''then return nil end
    return util.plain(name,120)
end

local Names={};Names.__index=Names
-- enabled() -> whether the setting is on.
function M.new(hd2,enabled)
    local self=setmetatable({hd2=hd2,enabled=enabled or function()return true end,cache={},current=nil,
        language=nil,ready=false,version=0},Names)
    self:refresh()
    return self
end
-- The game's text language now: the text API's own (hd2.text.language; not hd2.ui.language, the language HD2Runtime's
-- panels use), the one available() names, else 'default'.
function Names:game_language(named)
    local text=api(self.hd2)
    local fn=text and field(text,'language')
    if type(fn)=='function'then
        local ok,code=pcall(fn)
        if ok and type(code)=='string'and code~=''then return code end
    end
    if type(named)=='string'and named~=''then return named end
    return 'default'
end
-- Reads whether the game's texts can be read now, and their language. True when what the window shows changes.
function Names:refresh()
    local text=api(self.hd2)
    local ready=text~=nil and self.enabled()==true
    local named
    if ready and type(field(text,'available'))=='function'then
        local ok,value,language=pcall(text.available)
        ready=ok and value~=false and value~=nil
        named=language
    end
    local language=ready and self:game_language(named)or nil
    if ready==self.ready and language==self.language then return false end
    self.ready,self.language=ready,language
    if language then
        self.cache[language]=self.cache[language]or{}
        self.current=self.cache[language]
    else self.current=nil end
    self.version=self.version+1
    return true
end
-- The name, or nil and whether the answer may change (the texts are not available now).
local function ask(text,kind,key)
    local ok,name,code=pcall(text.name,kind,key)
    if ok then
        local shown=clean(name)
        if shown then return shown end
        return nil,TRANSIENT[code]==true
    end
    return nil,false
end
-- The game's name of a catalogue object (editor/util.lua display_name), or nil.
function Names:name(object)
    local current=self.current
    if not current or type(object)~='table'or type(object.key)~='string'then return nil end
    local cached=current[object.key]
    if cached~=nil then return cached or nil end
    local name,transient
    local text=api(self.hd2)
    local family=object.key:match('^(%a+)|')
    local kind=M.KINDS[family or'']
    if text and kind and type(object.name)=='string'then
        name,transient=ask(text,kind,object.name)
        if not name and not transient and STRATAGEM_FALLBACK[family]and type(object.stratagem)=='string'then
            name,transient=ask(text,'stratagem',object.stratagem)
        end
    end
    if transient then
        -- not now: the editor's own names until the window opens again (refresh), and nothing cached
        self.ready,self.language,self.current=false,nil,nil
        self.version=self.version+1
        return nil
    end
    current[object.key]=name or false
    return name
end
-- Installs the lookup as the window's name hook (util.game_name) and its version (util.names_version).
function Names:install()
    util.game_name=function(object)return self:name(object)end
    util.names_version=function()return self.version end
    return self
end
return M

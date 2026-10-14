-- HD2R Editor (c) 2026 SkyeShade. All rights reserved except as granted in LICENSE
-- (https://github.com/SkyeShade/HD2Runtime-Editor). Do not redistribute or reuse without the credit it requires.
-- Presets, the saved session and settings, in the editor's own saved data (hd2.store: one JSON file per mod in
-- %LOCALAPPDATA%\HD2Runtime\mod_data). Values are stored by row key ('pw|AR-23 Liberator|weapon.fire_rate'), never
-- by address, so a preset survives game and Runtime updates; a key the catalogue no longer has is reported, not
-- guessed. A preset may carry an icon ({kind, name}: editor/preset_files.lua icon).
--
-- HD2Runtime keeps at most 1 MiB of saved data per mod (runtime/mod_store.lua MAX_BYTES): past it every later save
-- fails (the presets, the session and the settings alike). A preset that would not fit, with room left for the saved
-- session, is refused here with its size, instead of being kept only until the game closes.
local util=require('mods/skyeshade/hd2runtime_editor/editor/util')
local M={}
local FORMAT=1
local MAX_PRESETS=64
local MAX_NAME=40
M.STORE_LIMIT=1048576     -- bytes: HD2Runtime's saved data limit per mod
M.HEADROOM=64*1024        -- bytes kept free beyond the saved session and settings

local Presets={};Presets.__index=Presets

-- Stored forms: numbers, booleans, strings and plain tables of those (codes, encoded references), by row key.
local function storable(v,depth)
    local t=type(v)
    if t=='number'then return v==v and v>-math.huge and v<math.huge end
    if t=='boolean'or t=='string'then return true end
    if t~='table'or getmetatable(v)~=nil or(depth or 0)>4 then return false end
    for k,x in pairs(v)do
        if type(k)~='string'and type(k)~='number'then return false end
        if not storable(x,(depth or 0)+1)then return false end
    end
    return true
end
local function pairs_of(map)
    local list={}
    for key,value in pairs(map or{})do
        if type(key)=='string'and storable(value)then list[#list+1]={k=key,v=value}end
    end
    table.sort(list,function(a,b)return a.k<b.k end)
    return list
end
local function map_of(list)
    local map={}
    for _,item in ipairs(type(list)=='table'and list or{})do
        if type(item)=='table'and type(item.k)=='string'and item.v~=nil then map[item.k]=item.v end
    end
    return map
end
-- The bytes a value takes as compact JSON (as hd2.store writes it), near enough to keep under the store's limit.
local function json_size(v,depth)
    local t=type(v)
    if t=='boolean'then return v and 4 or 5 end
    if t=='number'then
        if v%1==0 and math.abs(v)<2^53 then return#string.format('%d',v)end
        return#string.format('%.17g',v)
    end
    if t=='string'then
        local _,special=v:gsub('[%c"\\]','')
        return#v+2+special*5
    end
    if t~='table'or(depth or 0)>16 then return 4 end
    local n,size=0,2
    for k,x in pairs(v)do
        n=n+1
        size=size+json_size(x,(depth or 0)+1)
        if type(k)=='string'then size=size+#k+3 end
    end
    return size+math.max(0,n-1)
end
M.json_size=json_size
local function clean_name(name)
    name=tostring(name or''):gsub('[%z\1-\31\127]',''):gsub('^%s+',''):gsub('%s+$','')
    if#name>MAX_NAME then name=util.utf8_cut(name,MAX_NAME)end     -- (whole characters: a name can be Chinese)
    return name
end
M.clean_name=clean_name

function M.new(store)
    local self=setmetatable({store=store,version=0},Presets)
    if store and store:get('format',nil)==nil then pcall(store.set,store,'format',FORMAT)end
    return self
end
function Presets:available()return self.store~=nil end
-- The presets {name, count, created, fields, icon}, read once per change (hd2.store copies a whole value on every
-- get: a preset of thousands of fields read every frame took tens of milliseconds). Not to be changed by callers.
function Presets:list()
    if self.cache and self.cache_version==self.version then return self.cache end
    local list=self.store and self.store:get('presets',{})or{}
    local out={}
    for _,p in ipairs(list)do
        if type(p)=='table'and type(p.name)=='string'then
            out[#out+1]={name=p.name,count=#(p.fields or{}),created=p.created,fields=p.fields,
                icon=type(p.icon)=='table'and p.icon or nil}
        end
    end
    self.cache,self.cache_version=out,self.version
    return out
end
-- Stores the presets list: true, or false and why (the store's limit; a value it refuses).
function Presets:put(list)
    local size=json_size(list)
    for _,key in ipairs({'session','settings'})do size=size+json_size(self.store:get(key,{}))+#key+4 end
    if size>M.STORE_LIMIT-M.HEADROOM then
        return false,('saved presets would take %d KB (limit %d KB). Keep this as a shared file (SHARE), '
            ..'or delete saved presets.'):format(math.ceil(size/1024),
            math.floor((M.STORE_LIMIT-M.HEADROOM)/1024))
    end
    local ok,why=pcall(self.store.set,self.store,'presets',list)
    self.version=self.version+1
    if not ok then return false,tostring(why)end
    return true
end
function Presets:find(name)
    for index,p in ipairs(self:list())do if p.name==name then return p,index end end
    return nil
end
function Presets:unique_name(base)
    base=clean_name(base or'Preset')
    if base==''then base='Preset'end
    if not self:find(base)then return base end
    for i=2,999 do
        local candidate=clean_name(base..' '..i)
        if not self:find(candidate)then return candidate end
    end
    return base
end
-- Saves (or replaces) a preset; icon: its icon (a replaced preset keeps its own when none is given). True, or false
-- and why.
function Presets:save(name,values,icon)
    if not self.store then return false,'saved data is not available on this Runtime'end
    name=clean_name(name)
    if name==''then return false,'a preset needs a name'end
    local list=self.store:get('presets',{})
    local entry={name=name,created=os.time and os.time()or 0,fields=pairs_of(values),icon=icon or nil}
    local replaced=false
    for index,p in ipairs(list)do
        if p.name==name then
            if entry.icon==nil and type(p.icon)=='table'then entry.icon=p.icon end
            list[index]=entry;replaced=true
        end
    end
    if not replaced then
        if#list>=MAX_PRESETS then return false,'at most '..MAX_PRESETS..' presets'end
        list[#list+1]=entry
    end
    return self:put(list)
end
-- Sets a preset's icon ({kind, name}; nil removes it). True, or false and why.
function Presets:set_icon(name,icon)
    if not self.store then return false,'saved data is not available'end
    local list=self.store:get('presets',{})
    local found=false
    for _,p in ipairs(list)do if p.name==name then p.icon=icon or nil;found=true end end
    if not found then return false,'no preset named '..tostring(name)end
    return self:put(list)
end
function Presets:load(name)
    local p=self:find(name)
    return p and map_of(p.fields)or nil
end
function Presets:delete(name)
    if not self.store then return false end
    local list=self.store:get('presets',{})
    for index=#list,1,-1 do if list[index].name==name then table.remove(list,index)end end
    self.version=self.version+1
    return pcall(self.store.set,self.store,'presets',list)
end
function Presets:rename(old,new)
    if not self.store then return false,'saved data is not available'end
    new=clean_name(new)
    if new==''then return false,'a preset needs a name'end
    if new~=old and self:find(new)then return false,'a preset with that name exists'end
    local list=self.store:get('presets',{})
    for _,p in ipairs(list)do if p.name==old then p.name=new end end
    self.version=self.version+1
    return pcall(self.store.set,self.store,'presets',list)
end

-- The values applied when the game was last left (restored at startup when the setting is on).
function Presets:session()return self.store and map_of(self.store:get('session',{}))or{}end
-- A durable checkpoint before any application starts. Deferred store:set alone is not a crash barrier.
function Presets:application()return self.store and self.store:get('application',nil)or nil end
function Presets:checkpoint(values,application)
    if not self.store or type(self.store.save)~='function'then return false,'saved data cannot be flushed'end
    local ok,done,why=pcall(function()
        if values then self.store:set('session',pairs_of(values))end
        self.store:set('application',application)
        return self.store:save()
    end)
    return ok and done==true,ok and why or tostring(done)
end
function Presets:set_session(values)
    if not self.store then return end
    pcall(self.store.set,self.store,'session',pairs_of(values))
end
function Presets:setting(key,default)
    if not self.store then return default end
    local settings=self.store:get('settings',{})
    local value=type(settings)=='table'and settings[key]
    if value==nil then return default end
    return value
end
function Presets:set_setting(key,value)
    if not self.store then return end
    local settings=self.store:get('settings',{})
    if type(settings)~='table'then settings={}end
    settings[key]=value
    pcall(self.store.set,self.store,'settings',settings)
end

return M

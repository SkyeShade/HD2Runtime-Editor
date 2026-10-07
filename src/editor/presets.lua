-- Presets, the saved session and settings, in the editor's own saved data (hd2.store: one JSON file per mod in
-- %LOCALAPPDATA%\HD2Runtime\mod_data). Values are stored by row key ('pw|AR-23 Liberator|weapon.fire_rate'), never
-- by address, so a preset survives game and Runtime updates; a key the catalogue no longer has is reported, not
-- guessed.
local M={}
local FORMAT=1
local MAX_PRESETS=64
local MAX_NAME=40

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
local function clean_name(name)
    name=tostring(name or''):gsub('[%z\1-\31\127]',''):gsub('^%s+',''):gsub('%s+$','')
    if#name>MAX_NAME then name=name:sub(1,MAX_NAME)end
    return name
end
M.clean_name=clean_name

function M.new(store)
    local self=setmetatable({store=store},Presets)
    if store and store:get('format',nil)==nil then pcall(store.set,store,'format',FORMAT)end
    return self
end
function Presets:available()return self.store~=nil end
function Presets:list()
    local list=self.store and self.store:get('presets',{})or{}
    local out={}
    for _,p in ipairs(list)do
        if type(p)=='table'and type(p.name)=='string'then
            out[#out+1]={name=p.name,count=#(p.fields or{}),created=p.created,fields=p.fields}
        end
    end
    return out
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
-- Saves (or replaces) a preset. True, or false and why.
function Presets:save(name,values)
    if not self.store then return false,'saved data is not available on this Runtime'end
    name=clean_name(name)
    if name==''then return false,'a preset needs a name'end
    local list=self.store:get('presets',{})
    local entry={name=name,created=os.time and os.time()or 0,fields=pairs_of(values)}
    local replaced=false
    for index,p in ipairs(list)do
        if p.name==name then list[index]=entry;replaced=true end
    end
    if not replaced then
        if#list>=MAX_PRESETS then return false,'at most '..MAX_PRESETS..' presets'end
        list[#list+1]=entry
    end
    local ok,why=pcall(self.store.set,self.store,'presets',list)
    if not ok then return false,tostring(why)end
    return true
end
function Presets:load(name)
    local p=self:find(name)
    return p and map_of(p.fields)or nil
end
function Presets:delete(name)
    if not self.store then return false end
    local list=self.store:get('presets',{})
    for index=#list,1,-1 do if list[index].name==name then table.remove(list,index)end end
    return pcall(self.store.set,self.store,'presets',list)
end
function Presets:rename(old,new)
    if not self.store then return false,'saved data is not available'end
    new=clean_name(new)
    if new==''then return false,'a preset needs a name'end
    if new~=old and self:find(new)then return false,'a preset with that name exists'end
    local list=self.store:get('presets',{})
    for _,p in ipairs(list)do if p.name==old then p.name=new end end
    return pcall(self.store.set,self.store,'presets',list)
end

-- The values applied when the game was last left (restored at startup when the setting is on).
function Presets:session()return self.store and map_of(self.store:get('session',{}))or{}end
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

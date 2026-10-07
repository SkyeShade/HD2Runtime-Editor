-- What the installed HD2Runtime mods write, and through which operations.
--
-- * Applied values: the Runtime records every APPLIED / ALREADY_DESIRED change in core/shared_records (claim); the
--   editor observes those records (it wraps claim and always calls the original first), so it knows, for every
--   native field, which mod applied which value with which target, field and acknowledgements. Load order does not
--   matter: no write happens before the first update tick, after every mod has loaded.
-- * Operations: hd2.diagnostics.operations() lists every registration (refused ones included); the Runtime's own
--   registry behind it holds each operation's handle, which the editor needs to hand a mod's ensure over to itself
--   (layer.lua). Read-only access to that registry is through the debug library; without it the editor still works,
--   it only cannot stop a mod's ensure before taking a field over.
-- Nothing here writes game memory or changes another mod's operation.
local catalog=require('mods/skyeshade/hd2runtime_editor/editor/catalog')
local util=require('mods/skyeshade/hd2runtime_editor/editor/util')
local M={}
local GLOBAL='HD2RuntimeEditorLedgerV1'

local Ledger={};Ledger.__index=Ledger

local function changes_of(spec)
    local list={}
    if type(spec)~='table'then return list end
    if type(spec.operations)=='table'then
        for _,operation in ipairs(spec.operations)do
            local inner=operation.spec or{}
            for _,change in ipairs(inner.changes or{})do
                list[#list+1]={change=change,id=tostring(spec.id)..'/'..tostring(operation.id),spec=inner}
            end
        end
    else
        for _,change in ipairs(spec.changes or{})do list[#list+1]={change=change,id=spec.id,spec=spec}end
    end
    return list
end
-- The editor catalogue object a validated spec writes (its kind and the target name the validator keeps).
local function object_key(spec)
    local kind=spec.kind
    if kind=='player_weapon'and spec.weapon then return 'pw|'..spec.weapon end
    if kind=='support_weapon'and spec.weapon then return 'sw|'..spec.weapon end
    if kind=='stratagem'and spec.stratagem then return 'st|'..spec.stratagem end
    if kind=='entity'and spec.entity then return(spec.family=='backpack'and'bp|'or'vh|')..spec.entity end
    if kind=='vehicle_weapon'and spec.weapon then return 'vw|'..spec.weapon end
    if kind=='throwable'and spec.throwable then return 'th|'..spec.throwable end
    if kind=='booster'and spec.booster then return 'bo|'..spec.booster end
    if kind=='enemy'and spec.enemy then return 'en|'..spec.enemy end
    if kind=='attachment'and spec.attachment then return 'mg|'..spec.attachment end
    return nil
end
M.object_key=object_key
local function flags_of(spec,outer)
    local f={}
    for _,key in ipairs({'allow_shared','allow_unverified_effect','allow_unverified_reference'})do
        if spec[key]==true or(outer and outer[key]==true)then f[key]=true end
    end
    return f
end

function Ledger:record(spec,kind,mod)
    if type(spec)~='table'then return end
    mod=mod or spec.mod or'unknown'
    if mod==self.editor then return end
    if spec.ensured then kind='ensure'end
    local op_id=tostring(spec.id)
    local op_key=mod..'#'..op_id
    local op={mod=mod,kind=kind,id=op_id,changes={},time=self.clock}
    for _,item in ipairs(changes_of(spec))do
        local change=item.change
        local descriptor=change.descriptor
        local loc=catalog.location(descriptor,nil)
        if loc then
            local text
            if self.shared_records then
                local ok,value=pcall(self.shared_records.describe,descriptor)
                text=ok and value or nil
            end
            local claim={mod=mod,kind=kind,op=op_id,id=item.id,loc=loc,field=change.field,value=change.value,
                expect=change.expect,descriptor=descriptor,object=object_key(item.spec)or object_key(spec),
                flags=flags_of(item.spec,spec),text=util.plain(text or tostring(change.field),140),time=self.clock}
            local list=self.by_loc[loc]or{}
            for i=#list,1,-1 do
                if list[i].mod==mod and list[i].op==op_id then table.remove(list,i)end
            end
            table.insert(list,1,claim)
            while#list>8 do table.remove(list)end
            self.by_loc[loc]=list
            op.changes[#op.changes+1]=claim
        end
    end
    if#op.changes>0 then self.ops[op_key]=op end
    self.version=self.version+1
end

-- The claims on these native bytes by other mods, newest first (empty when no mod applied a value).
function Ledger:holders(loc)return self.by_loc[loc]or{}end
function Ledger:holder(loc)local list=self.by_loc[loc];return list and list[1]or nil end
-- Every change one operation applied (for handing all of a mod ensure's fields over at once).
function Ledger:operation(mod,op_id)return self.ops[mod..'#'..tostring(op_id)]end

-- The live handle of a registered operation (newest registration with this mod and id), or nil.
function Ledger:handle(mod,op_id)
    local registry=self:registry()
    if not registry then return nil end
    for i=#registry,1,-1 do
        local item=registry[i]
        local origin=item.origin or{}
        if origin.mod==mod and tostring(item.id)==tostring(op_id)and type(item.handle)=='table'then
            return item.handle,item.kind
        end
    end
    return nil
end
function Ledger:registry()
    if self.registry_table~=nil then return self.registry_table or nil end
    self.registry_table=false
    local operations=self.hd2.diagnostics and self.hd2.diagnostics.operations
    if type(operations)=='function'and type(debug)=='table'and type(debug.getupvalue)=='function'then
        for i=1,64 do
            local ok,name,value=pcall(debug.getupvalue,operations,i)
            if not ok or name==nil then break end
            if name=='registry'and type(value)=='table'then self.registry_table=value;break end
        end
    end
    return self.registry_table or nil
end

-- Every mod the editor can see: its registered operations (status), the values it applied, and whether it runs.
-- {{id, operations = {...}, writes = {...}, refused = n, applied = n}} sorted by id.
function Ledger:mods()
    local by_id={}
    local function entry(id)
        local e=by_id[id]
        if not e then e={id=id,operations={},writes={},refused=0,applied=0};by_id[id]=e end
        return e
    end
    local ok,list=pcall(function()return self.hd2.diagnostics.operations()end)
    if ok and type(list)=='table'then
        for _,op in ipairs(list)do
            local mod=op.mod or'unknown'
            if mod~=self.editor then
                local e=entry(mod)
                e.operations[#e.operations+1]=op
                if op.status=='rejected'or op.status=='blocked'then e.refused=e.refused+1 end
            end
        end
    end
    for _,claims in pairs(self.by_loc)do
        for _,claim in ipairs(claims)do
            local e=entry(claim.mod)
            e.writes[#e.writes+1]=claim
            e.applied=e.applied+1
        end
    end
    for key in pairs(_G)do
        local id=type(key)=='string'and key:match('^HD2RuntimeMod:(.+)$')
        if id and id~=self.editor then entry(id).loaded=true end
    end
    local out={}
    for _,e in pairs(by_id)do
        table.sort(e.writes,function(a,b)return util.natural_less(a.text,b.text)end)
        out[#out+1]=e
    end
    table.sort(out,function(a,b)return a.id<b.id end)
    return out
end

-- Observes core/shared_records.claim (once per Lua state; a reload reuses the installed ledger).
function M.install(hd2,editor_id)
    local existing=rawget(_G,GLOBAL)
    if existing then existing.hd2=hd2;return existing end
    local self=setmetatable({hd2=hd2,editor=editor_id,by_loc={},ops={},version=0,clock=0},Ledger)
    local ok,shared=pcall(require,'hd2runtime/core/shared_records')
    if ok and type(shared)=='table'and type(shared.claim)=='function'then
        self.shared_records=shared
        local original=shared.claim
        shared.claim=function(spec,kind,mod,...)
            local results={original(spec,kind,mod,...)}
            local recorded,why=pcall(self.record,self,spec,kind,mod)
            if not recorded and not self.warned then
                self.warned=true
                self.error=tostring(why)
            end
            return unpack(results,1,table.maxn(results))
        end
        self.observing=true
    else
        self.error='the Runtime claim records are not available: '..tostring(shared)
    end
    rawset(_G,GLOBAL,self)
    return self
end

return M

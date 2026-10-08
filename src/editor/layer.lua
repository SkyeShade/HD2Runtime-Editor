-- HD2R Editor (c) 2026 SkyeShade. All rights reserved except as granted in LICENSE
-- (https://github.com/SkyeShade/HD2Runtime-Editor). Do not redistribute or reuse without the credit it requires.
-- The editor's override layer: live values over what the game and the installed mods set, applied through the
-- Runtime's own guarded ensures, and taken back exactly.
--
-- How a field is changed (the Runtime refuses a second writer by design, so the editor never writes over a value):
--   1. Adopt. The editor registers an ensure for the field whose value is a live handle (a script value) set to the
--      value the game holds now: vanilla, or what a mod applied (the Runtime's claim records say which). Its first
--      resolution finds those bytes already desired, and from then on the ensure owns them.
--   2. Hand-over. If a mod's ensure holds these bytes, every field of that operation is adopted the same way, and only
--      then is the mod's ensure stopped, so nothing it maintained is left unmaintained. A mod's one-shot patch,
--      transaction or plan has nothing to stop.
--   3. Steer. The handle is set to the user's value; the ensure re-applies it as an owned transition (guards,
--      fingerprints and rollback unchanged). Only fields whose value changed are touched.
--   4. Reset. The handle is set back to the base value (the mod's, or vanilla). A field whose base is vanilla or a
--      one-shot mod write is then released (the ensure stops; the bytes stay at the base). A field taken over from a
--      mod's ensure stays held at the mod's value for the session, standing in for that ensure.
-- A value outside a handle's range is reached by adopting again with a wider handle (step 1 with the editor's own
-- ensure handed over). Every failure stops at the guards and is shown on the field; nothing is retried blindly.
--
-- Armor perks (rows with controller 'passives') are not ensures: the Runtime holds one hd2.player_passives.set
-- override per game (the local player's own record, solo only). Both perk rows are applied together as one set();
-- a change stops the previous handle and sets again; resetting both stops it (the armor's own passives return).
local util=require('mods/skyeshade/hd2runtime_editor/editor/util')
local catalog_module=require('mods/skyeshade/hd2runtime_editor/editor/catalog')
local M={}

-- The form the editor holds a value in for a row, or nil: numbers with three decimals (or whole), other kinds as given
-- after a shape check (a code of the row's directions and length; uses a whole count in range or 'unlimited').
local function hold(row,value)
    if value==nil then return nil end
    if not row.kind then return util.representable(value,row.integer,row.storage)end
    if row.kind=='uses'then
        if value=='unlimited'then return value end
        if type(value)=='number'and value%1==0 then return value end
        return nil
    end
    if row.kind=='code'then
        if type(value)~='table'then return nil end
        local allowed={}
        for _,d in ipairs(row.directions or{'up','right','down','left'})do allowed[d]=true end
        for _,d in ipairs(value)do if not allowed[d]then return nil end end
        return value
    end
    return value
end
M.hold=hold

local FAILED={rejected=true,blocked=true,cancelled=true,unavailable=true}
-- A steer the Runtime has not even started to apply after STALL seconds (its ensure never settled on the new value:
-- live r52 log) is taken over by a fresh ensure: the field is adopted again at the value it holds and steered from
-- there, at most READOPTS times. A steer that started but has not confirmed after GIVE_UP seconds is shown as an error
-- with the ensure's state. Every editor ensure's status changes, and these decisions, are written to HD2Runtime.log.
local STALL,GIVE_UP,READOPTS=4,20,2
local function watch_state(w)
    if type(w)~='table'then return 'no operation'end
    local text='status='..tostring(w.status)..' runs='..tostring(w.runs)..' rebinds='..tostring(w.rebinds)
        ..' recoveries='..tostring(w.recoveries)..(w.retry_in and(' retry_in='..tostring(w.retry_in))or'')
        ..(w.error and(' error='..tostring(w.error))or'')
    if type(w.debug)=='function'then
        local ok,d=pcall(w.debug)
        if ok and type(d)=='table'then
            local parts={}
            for _,k in ipairs({'dirty','debounce','elapsed','next_at','child','applied','ticks','last_dt','listeners'})do
                parts[#parts+1]=k..'='..tostring(d[k])
            end
            text=text..' ['..table.concat(parts,' ')..']'
        end
    end
    return text
end
local Layer={};Layer.__index=Layer

function M.new(opts)
    return setmetatable({hd2=opts.hd2,id=opts.id,ledger=opts.ledger,catalog=opts.catalog,
        log=opts.log or function()end,slots={},groups={},released={},counter=0,version=0,history={}},Layer)
end

local function note(self,text)
    self.history[#self.history+1]=text
    if#self.history>40 then table.remove(self.history,1)end
    pcall(self.log,text)
end
function Layer:changed()self.version=self.version+1 end

-- The editor row for a field another mod's operation wrote (found through the catalogue), with that mod's own
-- acknowledgements added; nil when the editor has no row for it.
local function mirror_row(self,claim)
    if not self.catalog then return nil end
    local ok,row=pcall(self.catalog.find,self.catalog,claim.object,claim.loc,claim.descriptor)
    if not ok or not row or not row.editable then return nil end
    local copy={}
    for k,v in pairs(row)do copy[k]=v end
    copy.acks={}
    for k,v in pairs(row.acks or{})do copy.acks[k]=v end
    for k,v in pairs(claim.flags or{})do if v then copy.acks[k]=true end end
    copy.mirror=true
    return copy
end

----------------------------------------------------------------------------------------------- reading --
-- The value the field returns to on reset, and the claim of the mod that set it (nil: vanilla).
function Layer:base(row)
    local holder=self.ledger:holder(row.loc)
    if holder and holder.value~=nil and(row.kind or type(holder.value)=='number')then return holder.value,holder end
    return row.vanilla,nil
end
-- What the field is (or is being set to): value, source ('editor' | 'mod' | 'vanilla'), holder claim, slot.
function Layer:value(row)
    local slot=self.slots[row.loc]
    local base,holder=self:base(row)
    if slot and slot.user and slot.target~=nil then return slot.target,'editor',holder,slot end
    return base,holder and'mod'or'vanilla',holder,slot
end
-- 'idle' | 'applying' | 'active' | 'held' (maintained at a mod's value) | 'error', and the error text.
function Layer:state(row)
    local slot=self.slots[row.loc]
    if not slot then return 'idle'end
    if slot.error then return 'error',slot.error end
    if slot.phase=='adopt'or slot.phase=='steer'or slot.dirty then return 'applying'end
    if slot.user then return 'active'end
    if slot.watch then return 'held'end
    return 'idle'
end
function Layer:counts()
    local active,applying,errors=0,0,0
    for _,slot in pairs(self.slots)do
        if slot.error then errors=errors+1
        elseif slot.phase=='adopt'or slot.phase=='steer'or slot.dirty then applying=applying+1
        elseif slot.user then active=active+1 end
    end
    return active,applying,errors
end
function Layer:busy()local _,applying=self:counts();return applying>0 end
-- The user's applied values, {row key = value} (for the saved session and presets).
function Layer:overrides()
    local out={}
    for _,slot in pairs(self.slots)do
        if slot.user and slot.target~=nil and slot.row and slot.row.key then out[slot.row.key]=slot.target end
    end
    return out
end
function Layer:slot_of(row)return self.slots[row.loc]end

----------------------------------------------------------------------------------------------- changing --
local function slot_for(self,row)
    local slot=self.slots[row.loc]
    if not slot then
        slot={loc=row.loc,row=row,phase='idle',passive=row.controller=='passives'or nil}
        self.slots[row.loc]=slot
    elseif row.key and(not slot.row or slot.row.mirror)then
        slot.row=row
    end
    return slot
end
-- Ask for the user's value on a field. False and why when the value cannot be held exactly.
function Layer:set(row,value)
    local held=hold(row,value)
    if held==nil then
        if row.kind then return false,'not a value this field takes'end
        return false,'use at most 3 decimals'..(row.integer and' (whole numbers only)'or'')
    end
    if type(held)=='number'and(row.min and held<row.min or row.max and held>row.max)then
        return false,'outside the field range '..util.format(row.min)..' to '..util.format(row.max)
    end
    if row.kind=='code'and(#held<(row.min_length or 1)or#held>(row.max_length or 9))then
        return false,'a code has '..(row.min_length or 1)..' to '..(row.max_length or 9)..' directions'
    end
    if held=='unlimited'and row.kind=='uses'and not row.unlimited then
        return false,'this stratagem cannot be made unlimited'
    end
    -- two fields on the same bytes (an armory's displayed traits and displayed penetration share five label slots):
    -- one at a time
    local existing=self.slots[row.loc]
    if existing and existing.row and not existing.row.mirror and existing.row.key~=row.key
        and(existing.user or existing.watch)then
        return false,'this field shares its game data with "'..tostring(existing.row.label)
            ..'", which the editor holds: reset that field first'
    end
    local slot=slot_for(self,row)
    slot.user,slot.target,slot.error,slot.dirty=true,held,nil,true
    self:changed()
    return true
end
-- Back to the base value (the mod's, or vanilla).
function Layer:reset(row)
    local slot=self.slots[row.loc]
    if not slot then return false end
    local base=self:base(slot.row)
    slot.user,slot.error=false,nil
    slot.target=hold(slot.row,base)
    slot.dirty=true
    self:changed()
    return true
end
function Layer:reset_all()
    local n=0
    for _,slot in pairs(self.slots)do
        if slot.user or slot.error then self:reset(slot.row);n=n+1 end
    end
    return n
end

-- A live handle for a field: integer steps, or 0.001; its range holds `values`, the field's range and storage.
function Layer:handle(row,current,values)
    if row.kind then
        -- a script choice over the values this change needs: the one held now first, then the target and the base
        local list={current}
        for _,v in ipairs(values)do
            local known=false
            for _,x in ipairs(list)do if util.same(x,v)then known=true end end
            if v~=nil and not known then list[#list+1]=v end
        end
        local mod=self.hd2.mod(self.id)
        if type(mod.choice)~='function'then return nil,'editing this field needs HD2Runtime r50 (script choices)'end
        self.counter=self.counter+1
        local spec={id='c'..self.counter,values=list,default=1}
        local ok,handle=pcall(function()return mod:choice(spec)end)
        if not ok then return nil,tostring(handle)end
        return handle
    end
    local step=row.integer and 1 or util.STEP
    local lo,hi=current,current
    for _,v in ipairs(values)do
        if type(v)=='number'then lo,hi=math.min(lo,v),math.max(hi,v)end
    end
    local span=math.max(hi-lo,math.abs(lo),math.abs(hi),row.integer and 10 or 1)
    local a,b=lo-span,hi+2*span
    if row.min then a=math.max(a,row.min)elseif lo>=0 then a=math.max(a,0)end
    if row.max then b=math.min(b,row.max)end
    local function down(x)return util.round(math.floor(x/step+1e-9)*step)end
    local function up(x)return util.round(math.ceil(x/step-1e-9)*step)end
    a=down(a)
    if row.min and a<row.min then a=up(row.min)end
    b=up(b)
    if row.max and b>row.max then b=down(row.max)end
    a,b=math.min(a,lo),math.max(b,hi)
    if b-a<step then
        if not row.max or a+step<=row.max then b=util.round(a+step)else a=util.round(b-step)end
    end
    if b-a<step then return nil,'the field has no range to hold a value in'end
    self.counter=self.counter+1
    local spec={id='v'..self.counter,min=a,max=b,step=step,default=current}
    local ok,handle=pcall(function()return self.hd2.mod(self.id):value(spec)end)
    if not ok then return nil,tostring(handle)end
    return handle
end
-- Registers the editor's ensure for a field bound to a handle. Returns the watch (a rejected one on failure).
function Layer:register(row,handle)
    self.counter=self.counter+1
    local id='hd2editor-'..self.counter..'-'..util.slug(row.field or'field',28)
    local patch={id=id,field=row.field,expect=row.vanilla,value=handle}
    for key,on in pairs(row.acks or{})do if on then patch[key]=true end end
    if row.kind then
        -- every value of the choice passes the bind-time proof: ask the validator which acknowledgements they need
        local acks={}
        for key,on in pairs(row.acks or{})do if on then acks[key]=true end end
        for _,value in ipairs(handle.values or{})do
            local ok,result=catalog_module.probe(row,value,acks)
            if not ok then return {status='rejected',error=catalog_module.text(row,value)..': '..tostring(result)}end
            acks=result
        end
        for key in pairs(acks)do patch[key]=true end
    end
    -- rates that fill an empty slot of a weapon without a rate selector: one transaction with the selector binding,
    -- which follows the rates choice (HD2Runtime r51 mod:choice{follow}): bound for every value with two or more rates,
    -- unbound for the others
    local binding
    if row.kind=='rates'then
        for _,value in ipairs(handle.values or{})do binding=binding or catalog_module.rate_binding(row,value)end
    end
    local follower
    if binding then
        local values={}
        for i,value in ipairs(handle.values)do
            values[i]=catalog_module.filled(value)>=2 and binding.value or binding.expect
        end
        self.counter=self.counter+1
        local okf,f=pcall(function()
            return self.hd2.mod(self.id):choice({id='b'..self.counter,values=values,follow=handle})
        end)
        if not okf then
            return {status='rejected',error='filling an empty rate slot binds the rate selector with it, which needs '
                ..'HD2Runtime r51 (linked choices): '..tostring(f)}
        end
        follower=f
    end
    local ok,watch=pcall(function()
        patch.expect=catalog_module.expect(row)
        patch.target=row.target()
        local body={patch=patch}
        if follower then
            local t={id=patch.id,target=patch.target,changes={
                {field=row.field,expect=patch.expect,value=handle},
                {field=binding.field,expect=binding.expect,value=follower}}}
            for key,on in pairs(patch)do if key:match('^allow_')and on then t[key]=true end end
            body={transaction=t}
        end
        local request={patch=body.patch,transaction=body.transaction,startup_delay=0,interval=30,recover=true,
            on_status=function(status,info)
                note(self,'ensure '..id..' '..tostring(info and info.previous)..' -> '..tostring(status)
                    ..(info and info.error and(': '..tostring(info.error))or''))
            end}
        return self.hd2.events.run_as(self.id,function()return self.hd2.ensure(request)end)
    end)
    if not ok then return {status='rejected',error=tostring(watch)}end
    if type(watch)~='table'then return {status='rejected',error='the Runtime returned no operation'}end
    return watch
end

local function fail(self,slot,why)
    slot.error=util.plain(why or'the operation was refused',300)
    slot.dirty=false
    if slot.watch then
        slot.phase='hold'
        slot.target=slot.held
        local base=self:base(slot.row)
        slot.user=slot.held~=nil and not util.same(slot.held,hold(slot.row,base))
    else
        slot.phase,slot.user,slot.target='idle',false,nil
    end
    note(self,'field '..tostring(slot.row.label)..': '..slot.error)
    self:changed()
end

-- Starts adopting `slot` at the value the game holds now; with a mod's ensure on these bytes, its whole operation.
function Layer:adopt(slot)
    local row=slot.row
    local current
    if slot.watch then current=slot.held
    else
        local base=self:base(row)
        current=base
    end
    local held=hold(row,current)
    if held==nil then return fail(self,slot,'the value in the game now ('..util.value_text(current)..') cannot be held')end
    local group={slots={},cancel={},started=self.clock}
    local function begin(s,value,values)
        local handle,why=self:handle(s.row,value,values)
        if not handle then return nil,why end
        local watch=self:register(s.row,handle)
        if FAILED[watch.status]then return nil,watch.error or watch.status end
        s.next_watch,s.next_handle,s.adopt_value,s.phase,s.group=watch,handle,value,'adopt',group
        group.slots[#group.slots+1]=s
        return true
    end
    local base,holder=self:base(row)
    -- Direct: the game data still holds the field's original value and nobody else claims it, so the Runtime accepts
    -- the user's value as the first write (expect = the original value): no adopt-then-steer. A steer that followed
    -- an adopt was seen to be skipped live (r53: the ensure settled without writing), so a first edit never steers.
    local target=slot.target~=nil and hold(row,slot.target)or nil
    local direct=target~=nil and holder==nil and util.same(held,hold(row,row.vanilla))
        and(slot.direct or(not slot.watch and#self.ledger:holders(slot.loc)==0))
    slot.direct=nil
    local ok,why
    if direct then ok,why=begin(slot,target,{held,base})
    else ok,why=begin(slot,held,{slot.target,base})end
    if not ok then return fail(self,slot,why)end
    if slot.watch then
        group.cancel[#group.cancel+1]={handle=slot.watch}
    else
        for _,claim in ipairs(self.ledger:holders(slot.loc))do
            local key=claim.mod..'#'..claim.op
            if claim.kind=='ensure'and not self.released[key]then
                local handle=self.ledger:handle(claim.mod,claim.op)
                if handle and not FAILED[handle.status]then
                    local op=self.ledger:operation(claim.mod,claim.op)
                    local whole=true
                    for _,change in ipairs(op and op.changes or{})do
                        local other=self.slots[change.loc]
                        if change.loc~=slot.loc and not(other and(other.watch or other.phase=='adopt'))then
                            local mrow=mirror_row(self,change)
                            local value=mrow and hold(mrow,change.value)
                            if not value then whole=false
                            else
                                local m=slot_for(self,mrow)
                                m.target,m.base_kind=value,'ensure'
                                local started=begin(m,value,{value})
                                if not started then whole=false end
                            end
                        end
                    end
                    if whole then group.cancel[#group.cancel+1]={handle=handle,mod=claim.mod,op=claim.op,key=key}
                    else note(self,claim.mod..' '..claim.op..': not every field can be held by the editor; its ensure '
                        ..'keeps running (it stops itself on its next check once the editor changes these bytes)')end
                    slot.base_kind='ensure'
                end
            end
        end
    end
    self.groups[#self.groups+1]=group
    self:changed()
end

-- Whether a handle can take `value` without adopting again (a slider's range, or one of a choice's values).
function Layer:covers(handle,value)
    if handle.kind=='choice'then
        for _,v in ipairs(handle.values or{})do if util.same(v,value)then return true end end
        return false
    end
    return type(value)=='number'and value>=handle.min and value<=handle.max
end
-- Steers a held slot to its target through its handle.
function Layer:steer(slot)
    slot.mark=slot.watch.runs or 0
    slot.steering=slot.target
    slot.phase='steer'
    slot.steer_started,slot.stalled=self.clock or 0,false
    slot.rebinds_at=slot.watch.rebinds
    local changed=slot.handle:set(slot.target)
    note(self,'steer '..tostring(slot.row.key)..' -> '..util.value_text(slot.target)..' (handle '
        ..(changed and'changed'or'unchanged')..'; '..watch_state(slot.watch)..')')
    if not changed then slot.held,slot.phase=slot.target,'hold'end
    self:changed()
end

local function release_if_done(self,slot)
    if slot.phase~='hold'or slot.user or slot.dirty or not util.same(slot.target,slot.held)then return end
    if slot.base_kind=='ensure'then return end
    if slot.watch then pcall(slot.watch.cancel)end
    self.slots[slot.loc]=nil
    self:changed()
end

local function step_group(self,group)
    local done,failed=true,nil
    for _,s in ipairs(group.slots)do
        local w=s.next_watch
        if FAILED[w.status]then failed=failed or(w.error or w.status)
        elseif not(w.status=='waiting'and(w.runs or 0)>=1)then done=false end
    end
    if failed then
        for _,s in ipairs(group.slots)do
            pcall(s.next_watch.cancel)
            s.next_watch,s.next_handle,s.group=nil,nil,nil
            s.phase=s.watch and'hold'or'idle'
        end
        local first=group.slots[1]
        if first then fail(self,first,failed)end
        for i=2,#group.slots do
            local s=group.slots[i]
            if not s.watch and s.row.mirror then self.slots[s.loc]=nil end
        end
        return true
    end
    if not done then return false end
    for _,c in ipairs(group.cancel)do
        pcall(c.handle.cancel)
        if c.key then
            self.released[c.key]=true
            note(self,'took over '..c.mod..' '..c.op..' (its values are now held by the editor)')
        end
    end
    for _,s in ipairs(group.slots)do
        s.watch,s.handle=s.next_watch,s.next_handle
        s.next_watch,s.next_handle,s.group=nil,nil,nil
        s.held,s.phase=s.adopt_value,'hold'
        s.dirty=s.target~=nil and not util.same(s.target,s.held)
    end
    self:changed()
    return true
end

-- Armor perks: one hd2.player_passives.set for both perk rows ('kit' / 'none' leave a slot to the armor).
local BAD_PERK={refused=true,lost=true,replaced=true}
local function perk_error(handle)
    return tostring(handle.code or handle.status)..(handle.reason and(': '..tostring(handle.reason))or'')
end
local function step_perks(self)
    local dirty,any=false,false
    for _,slot in pairs(self.slots)do
        if slot.passive then
            any=true
            if slot.dirty then dirty=true end
        end
    end
    local perks=self.perks
    if not dirty then
        -- follow the held override: a refused, lost or replaced one shows on the edited perk rows
        if perks and perks.handle then
            local status=perks.handle.status
            if status~=perks.status then
                perks.status=status
                note(self,'armor perks '..tostring(status)..(BAD_PERK[status]and(': '..perk_error(perks.handle))or''))
                for _,slot in pairs(self.slots)do
                    if slot.passive and slot.user then slot.error=BAD_PERK[status]and perk_error(perks.handle)or nil end
                end
                self:changed()
            end
        end
        return
    end
    if not any then return end
    local want={}
    for loc,slot in pairs(self.slots)do
        if slot.passive then
            slot.dirty,slot.error=false,nil
            local key=tostring(slot.row.field):match('([%w_]+)$')
            local value=slot.user and slot.target or nil
            if value~=nil and value~='kit'and value~='none'then want[key]=value end
            if not slot.user then self.slots[loc]=nil end
        end
    end
    if perks and perks.handle then pcall(perks.handle.stop,perks.handle)end
    self.perks=nil
    if next(want)==nil then
        if perks then note(self,'armor perks: back to the armor\'s own')end
        self:changed()
        return
    end
    local spec={armor=want.armor,second=want.second,allow_unverified_effect=true}
    local ok,handle=pcall(function()
        return self.hd2.events.run_as(self.id,function()return self.hd2.player_passives.set(spec)end)
    end)
    local why
    if not ok then why=tostring(handle)
    elseif type(handle)~='table'then why='the Runtime returned no perk handle'
    elseif BAD_PERK[handle.status]then why=perk_error(handle)end
    if why then
        note(self,'armor perks refused: '..why)
        if ok and type(handle)=='table'then pcall(handle.stop,handle)end
        for _,slot in pairs(self.slots)do if slot.passive and slot.user then slot.error=why end end
    else
        self.perks={handle=handle,status=handle.status}
        note(self,'armor perks '..tostring(handle.status)..': armor '..tostring(want.armor or'own')..', second '
            ..tostring(want.second or'none'))
    end
    self:changed()
end

-- Drives every field one update further. Cheap when nothing changes.
function Layer:tick(dt)
    self.clock=(self.clock or 0)+(dt or 0)
    step_perks(self)
    for i=#self.groups,1,-1 do
        if step_group(self,self.groups[i])then table.remove(self.groups,i)end
    end
    -- A snapshot: adopting a field can add the slots of a mod operation's other fields.
    local list={}
    for _,slot in pairs(self.slots)do list[#list+1]=slot end
    for _,slot in ipairs(list)do
        if self.slots[slot.loc]~=slot or slot.passive then
            -- removed earlier in this pass, or an armor perk (step_perks)
        elseif slot.phase=='steer'then
            local w=slot.watch
            if FAILED[w.status]then
                slot.watch=nil
                fail(self,slot,w.error or w.status)
            elseif w.status=='waiting'and(w.runs or 0)>slot.mark then
                slot.readopts=nil
                slot.held,slot.phase=slot.steering,'hold'
                slot.dirty=not util.same(slot.target,slot.held)
                self:changed()
            else
                local waited=(self.clock or 0)-(slot.steer_started or 0)
                local settled=w.rebinds~=nil and w.rebinds~=slot.rebinds_at
                if waited>=STALL and not settled and not slot.stalled then
                    slot.stalled=true
                    slot.readopts=(slot.readopts or 0)+1
                    if slot.readopts>READOPTS then
                        note(self,'steer '..tostring(slot.row.key)..' never settled after '..READOPTS..' fresh ensures: '
                            ..watch_state(w))
                        fail(self,slot,'the Runtime did not apply this change ('..watch_state(w)..')')
                    elseif util.same(slot.held,hold(slot.row,slot.row.vanilla))and not select(2,self:base(slot.row))then
                        -- the field holds its original value: stop the stuck ensure and write the value directly
                        note(self,'steer '..tostring(slot.row.key)..' did not settle after '..STALL..' s ('..watch_state(w)
                            ..'); the field holds its original value: applying directly with a fresh ensure')
                        pcall(w.cancel)
                        slot.watch,slot.handle,slot.phase,slot.direct=nil,nil,'idle',true
                        slot.target=slot.steering
                        self:adopt(slot)
                    else
                        note(self,'steer '..tostring(slot.row.key)..' did not settle after '..STALL..' s ('..watch_state(w)
                            ..'); taking the field over with a fresh ensure')
                        -- the bytes still hold the held value: adopt again there, then steer from the new ensure
                        slot.phase='hold'
                        slot.target=slot.steering
                        self:adopt(slot)
                    end
                elseif waited>=GIVE_UP then
                    note(self,'steer '..tostring(slot.row.key)..' not confirmed after '..GIVE_UP..' s: '..watch_state(w))
                    fail(self,slot,'the Runtime did not confirm this change within '..GIVE_UP..' s ('..watch_state(w)..')')
                end
            end
        elseif slot.phase=='hold'or slot.phase=='idle'then
            if slot.dirty then
                slot.dirty=false
                local target=slot.target
                if target==nil then
                    if not slot.watch then self.slots[slot.loc]=nil end
                elseif slot.phase=='hold'and util.same(slot.held,target)then
                    release_if_done(self,slot)
                elseif slot.phase=='idle'and not slot.user and util.same(target,hold(slot.row,self:base(slot.row)))then
                    self.slots[slot.loc]=nil
                elseif slot.watch and slot.handle and self:covers(slot.handle,target)then
                    self:steer(slot)
                else
                    self:adopt(slot)
                end
            elseif slot.phase=='hold'then
                if slot.watch and FAILED[slot.watch.status]then
                    local w=slot.watch
                    slot.watch=nil
                    fail(self,slot,'the editor ensure stopped: '..tostring(w.error or w.status))
                else
                    release_if_done(self,slot)
                end
            end
        end
    end
end

return M

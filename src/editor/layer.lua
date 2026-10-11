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
--      mod's ensure stays held at the mod's value for the session, standing in for that ensure. A field reset while
--      its value is still on its way (its ensure not yet run, or its steer still queued) never gets that value first:
--      the unrun ensure is stopped (nothing was written) or the queued steer is turned to the base. Until the base is
--      back in the game the field is "removing" (slot.removing); a reset that fails keeps its error and is never
--      saved again (slot.reset_failed).
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
-- HD2Runtime runs one guarded operation at a time (runtime/exclusive.lua); the others report 'queued'. Time an ensure's
-- operation spends queued behind them is not the steer's: a preset re-applied over 300 held fields queued its steers
-- for more than GIVE_UP seconds, and 15 were shown failed that the Runtime applied afterwards.
local function queued(w)
    if type(w)~='table'or type(w.debug)~='function'then return false end
    local ok,d=pcall(w.debug)
    return ok and type(d)=='table'and d.child=='queued'
end
-- At most this many fields start an ensure in one update: registering 300 at once (each with its bind-time proof) cost
-- one 53-64 ms frame. The Runtime resolves them one at a time anyway (3-6 updates each), so the cap costs no time.
local ADOPTS_PER_TICK=16
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
-- A steer must never be skipped. Live (r52, r53, r55) a bound ensure settled after a steer without applying it: its
-- settle found the rebuilt signature equal to the one it last applied (`rebinds` unchanged, no write), which no offline
-- run reproduces. So the editor clears the ensure's record of what it last applied whenever it steers (what the
-- Runtime's listener could do itself): the settle then always resolves again, and a value already in place is simply
-- ALREADY_DESIRED. The record is an upvalue of watch.debug (r53), reached through LuaJIT's debug library; without
-- either, nothing changes. When a steer still stalls, `inspect` logs whether the rebuilt signature equals the applied
-- one (the handle's value did not reach the ensure) or not (the settle should have applied it).
local function upvalue(fn,name)
    if type(fn)~='function'or type(debug)~='table'or type(debug.getupvalue)~='function'then return nil end
    for i=1,255 do
        local n,v=debug.getupvalue(fn,i)
        if n==nil then return nil end
        if n==name then return i,v end
    end
    return nil
end
-- A function's upvalue by name, searched through the closures it holds (watch.tick -> tick -> settle -> build).
local function deep_upvalue(fn,name,depth,seen)
    seen=seen or{}
    if type(fn)~='function'or seen[fn]or(depth or 0)>4 then return nil end
    seen[fn]=true
    local i,v=upvalue(fn,name)
    if i then return v,true end
    for k=1,255 do
        local n,inner=debug.getupvalue(fn,k)
        if n==nil then break end
        if type(inner)=='function'then
            local found,ok=deep_upvalue(inner,name,(depth or 0)+1,seen)
            if ok then return found,true end
        end
    end
    return nil
end
local function readable(signature)
    if type(signature)~='string'then return tostring(signature)end
    local text=signature:gsub('\n',' '):gsub('[%z\1-\31\127-\255]',function(c)return('%02X'):format(c:byte())end)
    return #text>80 and(text:sub(1,80)..'...')or text
end
-- Forget what the ensure last applied (and optionally settle again now). True when done.
local function forget_applied(w,settle_now)
    if type(w)~='table'or type(debug)~='table'or type(debug.setupvalue)~='function'then return false end
    local ia=upvalue(w.debug,'applied_signature')
    if not ia then return false end
    debug.setupvalue(w.debug,ia,nil)
    if settle_now then
        local id_,ib=upvalue(w.debug,'dirty'),upvalue(w.debug,'debounce')
        if id_ and ib then debug.setupvalue(w.debug,id_,true);debug.setupvalue(w.debug,ib,0)end
    end
    return true
end
-- What the stalled ensure would resolve to now against what it last applied.
local function inspect(w,handle)
    if type(w)~='table'or type(w.debug)~='function'or type(debug)~='table'then return 'no ensure internals'end
    local _,applied=upvalue(w.debug,'applied_signature')
    local parts={'handle '..tostring(handle and handle.id)..' = '..util.value_text(handle and handle:get()),
        'applied '..readable(applied)}
    local build=deep_upvalue(w.tick,'build')
    local signature=deep_upvalue(w.tick,'signature')
    local kind=deep_upvalue(w.tick,'kind')
    if type(build)=='function'and type(signature)=='function'then
        local ok,spec=pcall(build)
        if ok then
            local now=signature(kind,spec,true)
            parts[#parts+1]='rebuilt '..readable(now)
            parts[#parts+1]=now==applied and'SAME: the value did not reach the ensure'
                or'DIFFERENT: the settle should have applied it'
        else parts[#parts+1]='rebuild failed: '..tostring(spec)end
    end
    return table.concat(parts,'; ')
end

local Layer={};Layer.__index=Layer

function M.new(opts)
    return setmetatable({hd2=opts.hd2,id=opts.id,ledger=opts.ledger,catalog=opts.catalog,
        log=opts.log or function()end,slots={},groups={},released={},counter=0,version=0,history={},touched={}},Layer)
end

local function note(self,text)
    self.history[#self.history+1]=text
    if#self.history>40 then table.remove(self.history,1)end
    pcall(self.log,text)
end
function Layer:changed()self.version=self.version+1 end
-- Fields the player changed or reset, by row key (editor/session.lua: a carried saved value gives way to them).
function Layer:touch(key)if key~=nil then self.touched[key]=true end end

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
-- active, applying, errors, and removing (those of the applying fields being reset: slot.removing).
function Layer:counts()
    local active,applying,errors,removing=0,0,0,0
    for _,slot in pairs(self.slots)do
        if slot.error then errors=errors+1
        elseif slot.phase=='adopt'or slot.phase=='steer'or slot.dirty then
            applying=applying+1
            if slot.removing then removing=removing+1 end
        elseif slot.user then active=active+1 end
    end
    return active,applying,errors,removing
end
-- Whether a field is being reset (its base value not yet back in the game).
function Layer:removing(row)
    local slot=self.slots[row.loc]
    return slot~=nil and slot.removing==true and not slot.error
end
-- The resets under way: how many of them are done, and how many were asked for since none was under way.
function Layer:removal()
    local _,_,_,removing=self:counts()
    local total=math.max(self.removal_total or 0,removing)
    return total-removing,total
end
-- How many fields a reset of everything takes back: those with a value of yours or a failed one (being applied or
-- not), apart from those already being reset.
function Layer:resettable()
    local n=0
    for _,slot in pairs(self.slots)do
        if slot.row and not slot.removing and(slot.user or slot.error)then n=n+1 end
    end
    return n
end
function Layer:busy()local _,applying=self:counts();return applying>0 end
-- Every field whose value was refused or failed: {{row, slot, value (asked for), reason, code, origin, time}}.
function Layer:errors()
    local out={}
    for _,slot in pairs(self.slots)do
        if slot.error and slot.row then
            out[#out+1]={row=slot.row,slot=slot,value=slot.failed_value,reason=slot.error,code=slot.failed_code,
                origin=slot.origin,time=slot.failed_at}
        end
    end
    return out
end
-- The user's applied values, {row key = value} (for the saved session and presets). A value a reset was asked to take
-- away (the reset failed) is not one of them.
function Layer:overrides()
    local out={}
    for _,slot in pairs(self.slots)do
        if slot.user and not slot.reset_failed and slot.target~=nil and slot.row and slot.row.key then
            out[slot.row.key]=slot.target
        end
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
-- Whether a payload slot's value sets off another explosion than the weapon's own (editor/catalog.lua "What a payload
-- slot sets off"): HD2Runtime then refuses the weapon's own explosion rows, their reset included.
local function payload_other(self,slot_row,value)
    if not catalog_module.payload_identity(value)then return false end
    if self.catalog and self.catalog.payload_view then
        local ok,view=pcall(self.catalog.payload_view,self.catalog,slot_row,value)
        if ok and view then return view.other==true end
    end
    return catalog_module.payload_other(slot_row,value)
end
-- Turning a beam conversion off (or back to the weapon as shipped) takes its settings back too: they apply to a
-- converted weapon only (editor/catalog.lua conversion_rows). Mission uses back to unlimited (their reset) take the
-- stratagem out of the Eagle Rearm pool the editor put it in (REARM_POOL_UNLIMITED).
local function release_dependents(self,row,value,from_reset)
    -- a status slot back to its base takes its own strength and the editor's later slots of the same damage row with
    -- it (they cannot stay behind an empty slot: STATUS_SLOT_GAP); status_wait clears them first
    local s=row.status_slot
    if from_reset and s and s.kind=='type'and(value==nil or value=='none')then
        local rows={s.strength}
        for _,r in ipairs(s.later or{})do rows[#rows+1]=r end
        for _,r in ipairs(rows)do
            local other=self.slots[r.loc]
            if other and(other.user or other.error)then self:reset(r)end
        end
    end
    -- a projectile swap to a donor takes the editor's values of the weapon's own projectile rows back first: HD2Runtime
    -- refuses those rows once the weapon fires another projectile (COMPOSITION_TARGET_CHANGED), its reset included, so
    -- they go back while they still can (swap_wait holds the swap until they are back)
    if row.swap_scope and catalog_module.donor_of(row,value)then
        for _,r in ipairs(row.fires_rows or{})do
            local other=self.slots[r.loc]
            if other and(other.user or other.error)and not other.removing then self:reset(r)end
        end
    end
    -- the same for a payload slot setting off another explosion: the weapon's own explosion rows go back first
    if row.payload_rows and payload_other(self,row,value)then
        for _,r in ipairs(row.payload_rows)do
            local other=self.slots[r.loc]
            if other and(other.user or other.error)and not other.removing then self:reset(r)end
        end
    end
    if from_reset and row.pool_row and value=='unlimited'then
        local s=self.slots[row.pool_row.loc]
        if s and s.user and(s.target==catalog_module.EAGLE_REARM or s.target=='eagle_rearm')then
            self:reset(row.pool_row)
        end
    end
    if not row.conversion_rows or value==true then return end
    for _,r in ipairs(row.conversion_rows)do
        local s=self.slots[r.loc]
        if s and(s.user or s.error)then self:reset(r)end
    end
end
-- Ask for the user's value on a field. False and why when the value cannot be held exactly. origin: where the value
-- came from, for the errors list ({kind = 'edit' | 'preset' | 'session' | 'mod', name}); a personal edit by default.
function Layer:set(row,value,origin)
    local held=hold(row,value)
    if held==nil then
        if row.kind then return false,'not a value this field takes'end
        return false,'use at most 3 decimals'..(row.integer and' (whole numbers only)'or'')
    end
    if type(held)=='number'and(row.min and held<row.min or row.max and held>row.max)then
        return false,'outside the field range '..util.format(row.min)..' to '..util.format(row.max)
    end
    if row.disabled_value~=nil and held~=row.disabled_value and held<=0 then
        return false,util.format(row.disabled_value)..' disables it; otherwise use a value above 0'
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
    -- the base value itself (the mod's, or the game's when no mod set it) is a reset, never an editor value
    if util.same(held,hold(row,(self:base(row))))then
        local slot=self.slots[row.loc]
        if slot and(slot.user or slot.error)then self:reset(row)end
        release_dependents(self,row,held)
        self:touch(row.key)
        return true
    end
    local slot=slot_for(self,row)
    slot.user,slot.target,slot.error,slot.dirty=true,held,nil,true
    if slot.removing then self.removal_total=math.max(0,(self.removal_total or 1)-1)end
    slot.removing,slot.reset_failed=nil,nil
    slot.origin=origin or{kind='edit'}
    release_dependents(self,row,held)
    self:touch(row.key)
    self:changed()
    return true
end
-- A field reset before its adoption ran: the ensure that would write its value is stopped, with those of the mod
-- fields adopted with it (that mod's ensure keeps running: nothing was handed over). An ensure counts its run in the
-- update that writes, so while none of the group has run, nothing was written. True when stopped.
local function abort_adopt(self,slot)
    local group=slot.phase=='adopt'and slot.group
    if not group then return false end
    for _,s in ipairs(group.slots)do
        local w=s.next_watch
        if type(w)~='table'or(w.runs or 0)>0 or FAILED[w.status]then return false end
        if s~=slot and s.user then return false end
    end
    for _,s in ipairs(group.slots)do
        pcall(s.next_watch.cancel)
        s.next_watch,s.next_handle,s.group,s.adopt_value=nil,nil,nil,nil
        s.phase=s.watch and'hold'or'idle'
        if s~=slot and not s.watch and s.row.mirror then self.slots[s.loc]=nil end
    end
    for i=#self.groups,1,-1 do if self.groups[i]==group then table.remove(self.groups,i)end end
    note(self,'reset '..tostring(slot.row.key)..' before its ensure ran: stopped, nothing was written')
    return true
end
-- Back to the base value (the mod's, or vanilla). The field is removing until the base is back in the game.
function Layer:reset(row)
    local slot=self.slots[row.loc]
    if not slot then return false end
    local base=self:base(slot.row)
    if not slot.removing then
        self.removal_total=(self.removal_total or 0)+1
        -- (the value being taken away, shown until it is gone)
        slot.removed_value=slot.user and slot.target or slot.held
        if slot.removed_value==nil then slot.removed_value=slot.failed_value end
    end
    slot.user,slot.error,slot.reset_failed=false,nil,nil
    slot.removing=true
    slot.target=hold(slot.row,base)
    slot.dirty=true
    abort_adopt(self,slot)
    release_dependents(self,slot.row,slot.target,true)
    self:touch(slot.row.key)
    self:changed()
    return true
end
-- Every field back to its base: those with a value of yours or a failed one, whether applied or still being applied.
-- A field already being reset is left to finish. Returns the number of fields reset.
function Layer:reset_all()
    local list={}
    for _,slot in pairs(self.slots)do
        if slot.row and not slot.removing and(slot.user or slot.error)then list[#list+1]=slot end
    end
    local n=0
    -- (a status slot's reset takes its later slots with it: each field once)
    for _,slot in ipairs(list)do
        if self.slots[slot.loc]==slot and not slot.removing then self:reset(slot.row);n=n+1 end
    end
    return n
end

-- A live handle for a field: integer steps, or 0.001; its range holds `values`, the field's range and storage.
function Layer:handle(row,current,values)
    -- a field with a disable sentinel (-1, or above 0), or one ordered against another (a turret's minimum below its
    -- maximum): no continuous range can span the gap (the bind-time proof checks the range's ends and one step, and a
    -- range end past the other limit is refused, TURRET_LIMIT_ORDER), so its handle holds exactly the values this
    -- change needs
    if row.kind or row.disabled_value~=nil or row.exact then
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
    -- (0.31.0: likewise two or three fire modes on a weapon without a fire-mode selector bind the fire-mode selector)
    local binding
    if row.kind=='rates'or row.kind=='modes'then
        for _,value in ipairs(handle.values or{})do binding=binding or catalog_module.rate_binding(row,value)end
    end
    local follower
    if binding then
        local values={}
        for i,value in ipairs(handle.values)do
            values[i]=catalog_module.rate_binding(row,value)and binding.value or binding.expect
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
                note(self,'ensure '..id..' ('..tostring(row.object and row.object.name)..') '
                    ..tostring(info and info.previous)..' -> '..tostring(status)
                    ..(info and info.error and(': '..tostring(info.error))or''))
            end}
        return self.hd2.events.run_as(self.id,function()return self.hd2.ensure(request)end)
    end)
    if not ok then return {status='rejected',error=tostring(watch)}end
    if type(watch)~='table'then return {status='rejected',error='the Runtime returned no operation'}end
    return watch
end

-- The Runtime's code of a stopped operation (its result's code: CONFLICT, VALIDATION_FAILED ...), or nil.
local function code_of(w)
    local result=type(w)=='table'and w.result
    local code=type(result)=='table'and result.code or(type(w)=='table'and w.code)
    return type(code)=='string'and code~=''and code or nil
end
-- A field's value was refused or failed: the error (with the value asked for, the Runtime's code when it gave one and
-- the time, for the errors list), and the field back to what it held.
local function fail(self,slot,why,code)
    slot.error=util.plain(why or'the operation was refused',300)
    slot.failed_value,slot.failed_code,slot.failed_at=slot.target,code,self.clock or 0
    slot.dirty,slot.readopts,slot.nudged=false,nil,nil
    -- a reset that failed: the field still holds the value it had (shown with the error), which is not saved again
    if slot.removing then
        slot.removing,slot.reset_failed=nil,true
        slot.origin={kind='reset'}
    end
    if slot.watch or slot.stranded~=nil then
        -- the bytes keep the value the editor's ensure last applied (slot.held): with that ensure still holding it,
        -- or left there by an ensure that stopped (slot.stranded), which a reset adopts again to take it back
        slot.phase=slot.watch and'hold'or'idle'
        slot.target=slot.held
        local base=self:base(slot.row)
        slot.user=slot.held~=nil and not util.same(slot.held,hold(slot.row,base))
    else
        slot.phase,slot.user,slot.target='idle',false,nil
    end
    note(self,'field '..tostring(slot.row.object and slot.row.object.name)..' · '..tostring(slot.row.label)..': '..slot.error)
    self:changed()
end

-- Starts adopting `slot` at the value the game holds now; with a mod's ensure on these bytes, its whole operation.
function Layer:adopt(slot)
    local row=slot.row
    local current
    if slot.watch then current=slot.held
    elseif slot.stranded~=nil then current=slot.stranded
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
                                m.origin=m.origin or{kind='mod',name=claim.mod}
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
    slot.steer_started,slot.stalled,slot.nudged=self.clock or 0,false,nil
    slot.rebinds_at=slot.watch.rebinds
    local changed=slot.handle:set(slot.target)
    -- the settle that follows must resolve again, never compare against what was applied before (see forget_applied)
    local forgot=changed and forget_applied(slot.watch)
    note(self,'steer '..tostring(slot.row.key)..' -> '..util.value_text(slot.target)..' (handle '
        ..(changed and'changed'or'unchanged')..(forgot and', re-resolve forced'or'')..'; '..watch_state(slot.watch)..')')
    if not changed then slot.held,slot.phase=slot.target,'hold'end
    self:changed()
end

local function release_if_done(self,slot)
    if slot.phase~='hold'or slot.user or slot.dirty or not util.same(slot.target,slot.held)then return end
    -- (a reset is done once its base is back: released here, or held at a mod's value)
    if slot.removing then slot.removing=nil;self:changed()end
    if slot.base_kind=='ensure'then return end
    if slot.watch then pcall(slot.watch.cancel)end
    self.slots[slot.loc]=nil
    self:changed()
end

local function step_group(self,group)
    local done,failed,code=true,nil,nil
    for _,s in ipairs(group.slots)do
        local w=s.next_watch
        if FAILED[w.status]then
            if not failed then failed,code=w.error or w.status,code_of(w)end
        elseif not(w.status=='waiting'and(w.runs or 0)>=1)then done=false end
    end
    if failed then
        for _,s in ipairs(group.slots)do
            pcall(s.next_watch.cancel)
            s.next_watch,s.next_handle,s.group=nil,nil,nil
            s.phase=s.watch and'hold'or'idle'
        end
        local first=group.slots[1]
        if first then fail(self,first,failed,code)end
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
        s.held,s.phase,s.stranded=s.adopt_value,'hold',nil
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

-- Beam conversions (HD2Runtime beam conversion, docs/beam-conversion.md): a converted weapon's own rate, pulse, damage
-- and range are accepted only once the weapon is converted (NOT_CONVERTED otherwise), and a conversion is never part
-- of a plan. Each field keeps its own ensure; a setting the user changes waits while its conversion is still being
-- applied, and is refused at once when the conversion is not on. True while the slot must wait (or just failed).
local function conversion_wait(self,slot)
    local enabled=slot.row.conversion_enabled
    if not enabled then return false end
    local value=self:value(enabled)
    if value~=true then
        fail(self,slot,'turn "'..tostring(enabled.label)..'" on first: its settings apply to a converted weapon only')
        return true
    end
    return self:state(enabled)=='applying'
end

-- The Eagle Rearm pool (HD2Runtime 0.31.0 stratagem.rearm_pool): a pool member keeps a finite use count, which the
-- Runtime checks against the row's bytes when it applies (REARM_POOL_UNLIMITED). Each field keeps its own ensure, so
-- joining the pool waits for a finite Mission uses being applied, and unlimited uses wait for the pool being left;
-- the combination itself is refused at once with the reason. True while the slot must wait (or just failed).
local function in_pool(value)return value==catalog_module.EAGLE_REARM or value=='eagle_rearm'end
local function rearm_wait(self,slot)
    local row=slot.row
    if row.uses_row and in_pool(slot.target)then
        if self:value(row.uses_row)=='unlimited'then
            fail(self,slot,'REARM_POOL_UNLIMITED: in the Eagle Rearm pool its Mission uses are charges: set "'
                ..tostring(row.uses_row.label)..'" to a number first')
            return true
        end
        return self:state(row.uses_row)=='applying'
    elseif row.pool_row and slot.target=='unlimited'then
        if in_pool((self:value(row.pool_row)))then
            fail(self,slot,'REARM_POOL_UNLIMITED: a stratagem in the Eagle Rearm pool keeps a finite use count: take it '
                ..'out of the pool ("'..tostring(row.pool_row.label)..'") first')
            return true
        end
        return self:state(row.pool_row)=='applying'
    end
    return false
end

-- Status slots (HD2Runtime 0.31.2, core/status_slots.lua): a damage row's statuses stay packed from slot 1, judged on
-- the live row when each write applies, and here every field is an ensure of its own. So a slot's status or strength
-- waits for the slot before it to be applied, and a slot is cleared only once the slots after it no longer hold a
-- status (resetting a slot resets the editor's later ones, release_dependents). An order that cannot come about is
-- refused at once with the reason. True while the slot must wait (or just failed).
local function has_status(value)return value~=nil and value~='none'end
-- The status the field's bytes hold as far as the editor knows: the held value of its ensure, else its base.
local function live_status(self,row)
    local slot=self.slots[row.loc]
    if slot and slot.watch then return has_status(slot.held)end
    return has_status((self:base(row)))
end
local function status_wait(self,slot)
    local s=slot.row.status_slot
    if not s or slot.target==nil then return false end
    -- (nothing to write: the bytes already hold the target)
    local now=slot.watch and slot.held or self:base(slot.row)
    if util.same(hold(slot.row,now),slot.target)then return false end
    if s.kind=='type'and not has_status(slot.target)then
        -- clearing: every later slot empty first
        for _,r in ipairs(s.later or{})do
            if r.status_slot.kind=='type'and has_status((self:value(r)))then
                fail(self,slot,'STATUS_SLOT_GAP: clear "'..tostring(r.label)..'" first: a status slot is emptied only '
                    ..'when the slots after it are empty')
                return true
            end
        end
        for _,r in ipairs(s.later or{})do if self:state(r)=='applying'then return true end end
        return false
    end
    if not s.prev or live_status(self,s.prev)then return false end
    if has_status((self:value(s.prev)))and self:state(s.prev)=='applying'then return true end
    fail(self,slot,'STATUS_SLOT_GAP: set "'..tostring(s.prev.label)..'" first: the status slots fill in order, from '
        ..'slot 1')
    return true
end

-- Projectile swaps (editor/catalog.lua "What a swapped weapon fires"): HD2Runtime resolves a weapon's own projectile,
-- damage and explosion rows through the projectile it fires, and refuses them while it fires a donor's
-- (COMPOSITION_TARGET_CHANGED). So a value of yours on such a row waits while its swap goes back to the weapon's own
-- projectile and is refused at once while the swap names a donor; a swap to a donor waits until those rows are back to
-- their base (release_dependents takes them back). True while the slot must wait (or just failed).
local function swap_wait(self,slot)
    local row=slot.row
    local swap=row.fires_from
    if swap and slot.user then
        local id=catalog_module.donor_of(swap,(self:value(swap)))
        if id then
            local owner=catalog_module.output_owner(id)
            fail(self,slot,'COMPOSITION_TARGET_CHANGED: '..tostring(row.object and row.object.name or'the weapon')
                ..' fires '..tostring(owner and owner.name or id)..' now, and HD2Runtime refuses its own projectile rows '
                ..'while it does: reset "'..tostring(swap.label)..'" first')
            return true
        end
        return self:state(swap)=='applying'
    end
    if row.swap_scope and slot.target~=nil and catalog_module.donor_of(row,slot.target)then
        for _,r in ipairs(row.fires_rows or{})do if self:state(r)=='applying'then return true end end
    end
    -- a weapon's own explosion rows and its payload slot, the same way
    local payload=row.payload_from
    if payload and slot.user then
        if payload_other(self,payload,(self:value(payload)))then
            fail(self,slot,'its payload slot "'..tostring(payload.label)..'" sets off another explosion now, and '
                ..'HD2Runtime refuses the rows of the weapon\'s own explosion while it does: set it back first')
            return true
        end
        return self:state(payload)=='applying'
    end
    if row.payload_rows and slot.target~=nil and payload_other(self,row,slot.target)then
        for _,r in ipairs(row.payload_rows)do if self:state(r)=='applying'then return true end end
    end
    return false
end

-- Drives every field one update further. Cheap when nothing changes.
function Layer:tick(dt)
    self.clock=(self.clock or 0)+(dt or 0)
    step_perks(self)
    for i=#self.groups,1,-1 do
        if step_group(self,self.groups[i])then table.remove(self.groups,i)end
    end
    -- A snapshot: adopting a field can add the slots of a mod operation's other fields.
    local adopts=0
    local list={}
    for _,slot in pairs(self.slots)do list[#list+1]=slot end
    for _,slot in ipairs(list)do
        if self.slots[slot.loc]~=slot or slot.passive then
            -- removed earlier in this pass, or an armor perk (step_perks)
        elseif slot.phase=='steer'then
            local w=slot.watch
            if FAILED[w.status]then
                -- (the stopped ensure leaves its last value in the game: a later reset takes it back from there)
                slot.watch,slot.stranded=nil,slot.held
                fail(self,slot,w.error or w.status,code_of(w))
            elseif w.status=='waiting'and(w.runs or 0)>slot.mark then
                slot.readopts,slot.nudged=nil,nil
                slot.held,slot.phase=slot.steering,'hold'
                slot.dirty=not util.same(slot.target,slot.held)
                self:changed()
            elseif slot.dirty and slot.target~=nil and not util.same(slot.target,slot.steering)and slot.handle
                and self:covers(slot.handle,slot.target)then
                -- another value asked for while this steer has not run (a reset, or a new value): the handle goes
                -- to it now, so the value asked for before is never written first
                slot.dirty=false
                self:steer(slot)
            else
                if queued(w)then slot.steer_started=(slot.steer_started or 0)+(dt or 0)end
                local waited=(self.clock or 0)-(slot.steer_started or 0)
                local settled=w.rebinds~=nil and w.rebinds~=slot.rebinds_at
                if waited>=STALL and not settled and not slot.stalled and not slot.nudged
                    and type(w.debug)=='function'and upvalue(w.debug,'applied_signature')then
                    -- first, settle the same ensure again now with nothing to compare against
                    local why=inspect(w,slot.handle)
                    forget_applied(w,true)
                    slot.nudged=true
                    slot.steer_started=self.clock or 0
                    note(self,'steer '..tostring(slot.row.key)..' did not settle after '..STALL..' s; settling it again ('
                        ..why..')')
                elseif waited>=STALL and not settled and not slot.stalled then
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
        elseif(slot.phase=='hold'or slot.phase=='idle')and slot.dirty
            and((slot.user and conversion_wait(self,slot))or rearm_wait(self,slot)or status_wait(self,slot)
                or swap_wait(self,slot))then
            -- a field that depends on another waits for it (or was refused): a beam conversion setting for its
            -- conversion, the rearm pool and the mission uses for each other, a status slot for its neighbours, a
            -- weapon's own projectile rows and its projectile swap for each other
        elseif slot.phase=='hold'or slot.phase=='idle'then
            if slot.dirty then
                local target=slot.target
                if target==nil then
                    slot.dirty=false
                    if not slot.watch then self.slots[slot.loc]=nil;self:changed()end
                elseif slot.phase=='hold'and util.same(slot.held,target)then
                    slot.dirty=false
                    release_if_done(self,slot)
                elseif slot.phase=='idle'and not slot.user and util.same(target,hold(slot.row,self:base(slot.row)))
                    and(slot.stranded==nil or util.same(slot.stranded,target))then
                    slot.dirty=false
                    self.slots[slot.loc]=nil;self:changed()
                elseif slot.watch and slot.handle and self:covers(slot.handle,target)then
                    slot.dirty=false
                    self:steer(slot)
                elseif adopts<ADOPTS_PER_TICK then
                    slot.dirty,adopts=false,adopts+1
                    self:adopt(slot)
                end
                -- (else: more fields than one update registers; this one starts on the next, still applying)
            elseif slot.phase=='hold'then
                if slot.watch and FAILED[slot.watch.status]then
                    local w=slot.watch
                    slot.watch,slot.stranded=nil,slot.held
                    fail(self,slot,'the editor ensure stopped: '..tostring(w.error or w.status),code_of(w))
                else
                    release_if_done(self,slot)
                end
            end
        end
    end
    if(self.removal_total or 0)>0 then
        local any=false
        for _,slot in pairs(self.slots)do if slot.removing and not slot.error then any=true;break end end
        if not any then self.removal_total=0 end
    end
end

return M

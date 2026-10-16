-- HD2R Editor (c) 2026 SkyeShade. All rights reserved except as granted in LICENSE
-- (https://github.com/SkyeShade/HD2Runtime-Editor). Do not redistribute or reuse without the credit it requires.
-- The saved session: the values applied last, restored once when the game starts and saved again whenever they change.
--
-- A saved value that does not come back at a start stays saved: its row may be missing from this catalogue, the Runtime
-- may refuse it this time (another mod's value, data not as reviewed), or its custom stratagem may not be registered.
-- Such values are carried into every later save until the player changes or resets that field (or resets everything),
-- so one start that cannot restore a value never erases it for the next. A field still being applied never holds the
-- save back either: the values asked for are saved at once, and a refused one leaves the session only through the
-- carried value it came from.
local M={}
local Session={};Session.__index=Session

function M.new(opts)
    local self=setmetatable({app=opts.app,layer=opts.layer,presets=opts.presets,log=opts.log or function()end,
        carried={},unresolved={},compat_pending={},saved_version=-1,restored=false},Session)
    local ctx=self.app.ctx
    ctx.before_apply=function()return self:begin_apply()end
    ctx.apply_failed=function(key)
        self.unresolved[key]=true
        local pending=self.app.pending[key]
        if pending and self.app:spawn_block(pending.row)then self.compat_pending[key]=true
        else self.restore_failed=true end
    end
    ctx.pending_removed=function(key)
        if self.quarantined or self.unresolved[key]then
            self.carried[key]=nil;self.unresolved[key]=nil
            self.restore_failed=self:has_failures()
            self.app.save_session=true
        end
    end
    ctx.discard_pending=function(values)return self:discard_pending(values)end
    ctx.forget_saved=function()self:forget_all()end
    return self
end

-- All recovered values are inert, including custom stratagem tunes and unknown catalogue keys.
function Session:has_failures()
    for key in pairs(self.unresolved)do if not self.compat_pending[key]then return true end end
    return false
end
function Session:recover(reason)
    local values=self.presets:session()
    self.carried=self.app:stage_recovered(values)
    self.quarantined,self.restored=true,true
    self.saved_version=self.layer.version
    self.app.recovery_notice=reason or'interrupted'
    self.log('previous application incomplete; saved changes are pending, automatic restore skipped')
    return 0,0
end
function Session:recover_interrupted()
    if self.presets:application()~=nil then self:recover();return true end
    return false
end
function Session:pending_values()
    local values=self:values()
    for key,p in pairs(self.app.pending)do
        -- (a field marked for reset is saved as gone, as once reset)
        if p.reset then values[key]=nil
        else
            local encoded=self.app:encode_values({[key]=p.value})
            values[key]=encoded[key]
        end
    end
    return values
end
function Session:begin_apply()
    local values=self:pending_values()
    local ok,why=self.presets:checkpoint(values,{state='applying'})
    if not ok then
        self.log('application not started: checkpoint failed: '..tostring(why))
        self.app.recovery_notice='storage'
        return false
    end
    for key in pairs(self.app.pending)do self.unresolved[key]=nil;self.compat_pending[key]=nil end
    for key in pairs(self.layer.touched)do self.unresolved[key]=nil end
    self.applying,self.restore_failed,self.quarantined=true,self:has_failures(),nil
    self.carried=values
    self.checked_version=nil
    self.restored=true
    return true
end
function Session:discard_pending(pending)
    if not self.quarantined and not self.applying then return end
    for key in pairs(pending)do self.carried[key]=nil;self.unresolved[key]=nil end
    self.quarantined,self.restore_failed=nil,self:has_failures()
    self.applying=true;self.checked_version=nil
    self.app.save_session=true
    self:tick()
end

-- Restores the saved values once. Returns applied, carried (the values that did not come back now).
function Session:restore()
    if self:recover_interrupted()then return 0,0 end
    local app,layer=self.app,self.layer
    local values=self.presets:session()
    if next(values)then
        local ok,why=self.presets:checkpoint(values,{state='applying'})
        if not ok then
            self.log('automatic restore skipped: checkpoint failed: '..tostring(why))
            return self:recover('storage')
        end
        self.applying=true
    end
    local applied,carried,reasons=0,0,{}
    -- projectile swaps first: a value of a weapon's own projectile row waits for (or is refused by) what it fires; then
    -- payload slots: a value of a weapon's own explosion row the same way by what its slot sets off
    local keys,first,slots={},{},{}
    for key in pairs(values)do
        local row=not app.is_custom_key(key)and app.catalog and app.catalog:row(key)
        if row and row.swap_scope then first[#first+1]=key
        elseif row and row.payload_rows then slots[#slots+1]=key
        else keys[#keys+1]=key end
    end
    table.sort(first)
    table.sort(slots)
    table.sort(keys)
    for _,key in ipairs(slots)do first[#first+1]=key end
    for _,key in ipairs(keys)do first[#first+1]=key end
    for _,key in ipairs(first)do
        local stored=values[key]
        local ok,why
        if app.is_custom_key(key)then
            -- a custom stratagem tune, applied through the Runtime again
            ok,why=app:apply_custom_value(key,stored)
        else
            local row,value=app:decode_value(key,stored)
            -- a mission timer saved above the game's 2500 s ceiling (allowed up to 7200 before): the mission started
            -- at 2500 s anyway, so it comes back as exactly that
            if row and row.field=='mission.duration_seconds'and type(value)=='number'and row.max and value>row.max then
                self.log('restored '..key..' at '..row.max..' s instead of '..value.." s (the game's mission timer limit)")
                value=row.max
            end
            if not row then why='no editable row now'
            elseif value==nil then why='the saved value cannot be read now'
            elseif row.fires_from and app:fires(row.fires_from)then
                -- (kept saved: it comes back at a start whose weapon fires its own projectile again)
                why='the weapon fires another projectile (its own projectile rows are refused while it does)'
            elseif row.payload_from and app.payload_block and app:payload_block(row)then
                -- (kept saved the same way, until its payload slot sets off its own explosion again)
                why='its payload slot sets off another explosion (its own explosion rows are refused while it does)'
            else
                ok,why=layer:set(row,value,{kind='session'})
                if not ok and app:spawn_block(row)then
                    self.compat_pending[key]=true
                    if not app.pending[key]then app.pending_n=app.pending_n+1 end
                    app.pending[key]={row=row,value=value,origin={kind='session'}}
                end
            end
        end
        -- every saved value is carried: a restored one that the Runtime refuses later stays saved as well
        self.carried[key]=stored
        if ok then applied=applied+1
        else
            self.unresolved[key]=true
            carried=carried+1
            if#reasons<8 then reasons[#reasons+1]=key..' ('..tostring(why or'refused')..')'end
        end
    end
    -- the restore's own changes are not the player's
    layer.touched={}
    self.restored=true
    self.restore_failed=false
    for key in pairs(self.unresolved)do if not self.compat_pending[key]then self.restore_failed=true;break end end
    self.saved_version=layer.version
    if applied+carried>0 then
        self.log('restored '..applied..' saved values'..(carried>0 and('; '..carried..' did not come back now and stay '
            ..'saved for the next start: '..table.concat(reasons,', ')..(carried>#reasons and', ...'or''))or''))
    end
    return applied,carried
end

-- Forgets every carried value (Reset to defaults).
function Session:forget_all()
    self.carried={};self.unresolved={};self.quarantined=nil;self.restore_failed=false;self.checked_version=nil
    if self.presets:application()~=nil then self.applying=true end
end

-- The values to save: the applied ones, then each carried value the player has not changed or reset since.
function Session:values()
    local app,layer=self.app,self.layer
    local values=layer:overrides()
    for key,value in pairs(app:custom_values())do values[key]=value end
    local stored=app:encode_values(values)
    for key,value in pairs(self.carried)do
        if layer.touched[key]then self.carried[key]=nil
        elseif stored[key]==nil then stored[key]=value end
    end
    -- An immediately refused application stays pending, even if an older override of that field is still active.
    for key in pairs(self.unresolved)do
        local pending=app.pending[key]
        if pending then stored[key]=app:encode_values({[key]=pending.value})[key]end
    end
    return stored
end

-- Saves the session when the values changed (once restored: before that the saved values are not in the game yet).
function Session:tick()
    local app,layer=self.app,self.layer
    if not self.restored then return false end
    local changed=app.save_session or layer.version~=self.saved_version
    if self.quarantined and app.pending_n==0 and next(self.carried)==nil then
        self.quarantined=nil;self.applying=true;self.restore_failed=false;self.checked_version=nil
    end
    -- No steady-state scan or disk polling: inspect completion only after an application/state change.
    if self.applying and(self.checked_version~=layer.version or app.save_session)then
        self.checked_version=layer.version
        local _,applying,errors=layer:counts()
        if applying==0 and errors==0 and not self.restore_failed then
            local ok,why=self.presets:checkpoint(self:values(),nil)
            if ok then self.log('application complete; startup recovery checkpoint cleared')
            else
                -- Keep the marker in memory too, so a later unrelated save cannot erase the barrier.
                if self.presets.store then pcall(self.presets.store.set,self.presets.store,'application',{state='applying'})end
                self.log('could not clear application checkpoint: '..tostring(why))
            end
            self.applying=false
        end
    end
    if not changed then return false end
    app.save_session=false
    self.saved_version=layer.version
    self.presets:set_session(self.quarantined and self:pending_values()or self:values())
    return true
end

return M

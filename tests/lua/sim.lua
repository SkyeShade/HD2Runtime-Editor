-- A simulated write path under the REAL Runtime API: hd2.patch / transaction / ensure, script values, bind-time
-- proofs, validation, owned transitions and the CONFLICT rule (core/ownership.expected) all run unchanged; only the
-- memory step (api/patch, api/transaction start_spec), the steady-state byte check and the write adapter are replaced
-- by a table of encoded bytes per native field. Returns the simulator: {hd2, memory, tick(seconds), value(row)}.
local catalog=require('mods/skyeshade/hd2runtime_editor/editor/catalog')
local S={memory={},writes=0,log={}}
_G.update=function()end

function S.selector_key(sel)
    local parts={}
    for _,k in ipairs({'output','weapon','attack','phase','is_null','catalogue','none','self'})do
        parts[#parts+1]=tostring(rawget(sel,k)or'')
    end
    return table.concat(parts,'|')
end
local function loc_of(change)return catalog.location(change.descriptor,'d:'..tostring(change.descriptor))end
local function claim(spec,kind)
    pcall(require('hd2runtime/core/shared_records').claim,spec,kind,spec.mod)
end
local function start_spec(kind)
    return function(runtime,emit,spec,startup)
        startup=startup==nil and 3 or startup
        local ownership=require('hd2runtime/core/ownership')
        local watch={status='waiting'}
        local elapsed=0
        -- S.serial = n: as in the game, one guarded operation at a time (runtime/exclusive.lua), each resolving for n
        -- updates while the others report 'queued'
        local exclusive=require('hd2runtime/runtime/exclusive')
        local steps=0
        -- S.asset_wait = seconds: a write that needs game packages (a catalogued payload explosion's) waits that long
        -- ('waiting_for_assets', as the real asset gate reports it), then goes ahead; with S.asset_fail it is refused
        -- then (ASSET_UNAVAILABLE, the gate's reason after its timeout)
        local packages={}
        pcall(function()packages=require('hd2runtime/core/assets').collect(spec)end)
        local loading=0
        function watch.cancel()
            if watch.status~='complete'and watch.status~='rejected'then watch.status='cancelled'end
            exclusive.release(watch)
        end
        function watch.tick(dt)
            if watch.status=='complete'or watch.status=='rejected'or watch.status=='cancelled'then return end
            elapsed=elapsed+dt
            if elapsed<startup then return end
            if#packages>0 and S.asset_wait then
                loading=loading+dt
                if loading<S.asset_wait then watch.status='waiting_for_assets';return end
                if S.asset_fail then
                    watch.status='rejected'
                    watch.error='ASSET_UNAVAILABLE: '..tostring(packages[1].label)..' requires package '
                        ..tostring(packages[1].name)..'; still requested after 90 seconds'
                    watch.result={status='REJECTED',code='ASSET_UNAVAILABLE',reason=watch.error}
                    S.log[#S.log+1]=kind..' '..tostring(spec.id)..' '..watch.error
                    return
                end
            end
            if S.serial then
                if not exclusive.acquire(watch)then watch.status='queued';return end
                steps=steps+1
                if steps<S.serial then watch.status='resolving';return end
                exclusive.release(watch)
            end
            -- references are encoded when the real prepare re-proves them live: here, from their selectors
            for _,change in ipairs(spec.changes or{})do
                if change.desired_selector then
                    change.desired='ref:'..S.selector_key(change.desired_selector)
                    change.expected='ref:'..S.selector_key(change.expected_selector or{})
                end
            end
            for _,change in ipairs(spec.changes or{})do
                local current=S.memory[loc_of(change)]or change.expected
                local ok,err=pcall(ownership.expected,change,current,change.field)
                if not ok then
                    watch.status,watch.error='rejected',tostring(err)
                    watch.result={status='REJECTED',code=tostring(err):find('CONFLICT',1,true)and'CONFLICT'or'VALIDATION_FAILED',
                        reason=watch.error}
                    S.log[#S.log+1]=kind..' '..tostring(spec.id)..' '..watch.error
                    if#S.log>400 then table.remove(S.log,1)end
                    return
                end
            end
            local wrote=false
            for _,change in ipairs(spec.changes or{})do
                local loc=loc_of(change)
                if S.memory[loc]~=change.desired then S.memory[loc]=change.desired;wrote=true;S.writes=S.writes+1 end
            end
            watch.result={status=wrote and'APPLIED'or'ALREADY_DESIRED'}
            watch.verification={spec=spec}
            claim(spec,kind)
            watch.status='complete'
        end
        return watch
    end
end
local patch_module={start_spec=start_spec('patch')}
function patch_module.start(runtime,emit,request)
    local spec=require('hd2runtime/domains/patches').validate(request)
    spec.mod=require('hd2runtime/core/shared_records').current_mod()
    return patch_module.start_spec(runtime,emit,spec,3)
end
local transaction_module={start_spec=start_spec('transaction')}
function transaction_module.start(runtime,emit,request)
    local spec=require('hd2runtime/domains/transactions').validate(request)
    spec.mod=require('hd2runtime/core/shared_records').current_mod()
    return transaction_module.start_spec(runtime,emit,spec,3)
end
package.loaded['hd2runtime/api/patch']=patch_module
package.loaded['hd2runtime/api/transaction']=transaction_module
package.loaded['hd2runtime/runtime/windows_write']={create=function()return {mode='simulated'}end}
package.loaded['hd2runtime/core/steady_state']={
    capture=function()return nil end,
    verify=function(runtime,verification)
        for _,change in ipairs(verification.spec.changes or{})do
            if S.memory[loc_of(change)]~=change.desired then return false,'target value drifted'end
        end
        return true
    end}

S.hd2=require('hd2runtime/api/hd2')
function S.tick(seconds,step)
    step=step or 0.1
    local t=0
    while t<seconds-1e-9 do _G.update(step);t=t+step end
end
-- The number a field's simulated bytes hold now (vanilla when never written).
function S.value(row)
    local bytes=S.memory[row.loc]
    if bytes==nil then return row.vanilla end
    local b=require('hd2runtime/core/bytes')
    local ok,value=pcall(b.value,bytes,0,row.storage)
    if ok then return value end
    return bytes
end
return S

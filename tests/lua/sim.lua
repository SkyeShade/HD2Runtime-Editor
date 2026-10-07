-- A simulated write path under the REAL Runtime API: hd2.patch / transaction / ensure, script values, bind-time
-- proofs, validation, owned transitions and the CONFLICT rule (core/ownership.expected) all run unchanged; only the
-- memory step (api/patch, api/transaction start_spec), the steady-state byte check and the write adapter are replaced
-- by a table of encoded bytes per native field. Returns the simulator: {hd2, memory, tick(seconds), value(row)}.
local catalog=require('mods/skyeshade/hd2runtime_editor/editor/catalog')
local S={memory={},writes=0,log={}}
_G.update=function()end

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
        function watch.cancel()
            if watch.status~='complete'and watch.status~='rejected'then watch.status='cancelled'end
        end
        function watch.tick(dt)
            if watch.status=='complete'or watch.status=='rejected'or watch.status=='cancelled'then return end
            elapsed=elapsed+dt
            if elapsed<startup then return end
            for _,change in ipairs(spec.changes or{})do
                local current=S.memory[loc_of(change)]or change.expected
                local ok,err=pcall(ownership.expected,change,current,change.field)
                if not ok then
                    watch.status,watch.error='rejected',tostring(err)
                    watch.result={status='REJECTED',code=tostring(err):find('CONFLICT',1,true)and'CONFLICT'or'VALIDATION_FAILED',
                        reason=watch.error}
                    S.log[#S.log+1]=kind..' '..tostring(spec.id)..' '..watch.error
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

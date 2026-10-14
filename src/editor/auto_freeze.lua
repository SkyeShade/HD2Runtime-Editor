-- Freezes the mission timer automatically when a mission of a ticked type starts (Mission Overview: "Freeze
-- automatically" per original duration). The host only: HD2Runtime's freeze, which the other players' Runtimes follow
-- (its runtime/mission_timer_sync.lua). The ticked types are timer sources ('terminids/mode_1', ...) kept in the
-- editor's settings. Nothing runs between missions: at mission start, one timer read a second until the countdown
-- exists (at most TRIES), then the freeze, once.
local M={}
M.SETTING='auto_freeze'
M.TRIES=30

-- {[source] = true}: the ticked timer sources.
function M.sources(presets)
    local v=presets and presets:setting(M.SETTING,nil)
    return type(v)=='table'and v or{}
end
-- Whether every source of a group is ticked.
function M.all(presets,sources)
    if#sources==0 then return false end
    local map=M.sources(presets)
    for _,s in ipairs(sources)do if not map[s]then return false end end
    return true
end
function M.set(presets,sources,on)
    if not presets then return end
    local map={}
    for k,v in pairs(M.sources(presets))do map[k]=v end
    for _,s in ipairs(sources)do map[s]=on and true or nil end
    presets:set_setting(M.SETTING,map)
end

-- The mission_started watcher (editor/main.lua). hd2: the editor's HD2Runtime API; mod: its mod handle.
function M.start(hd2,mod,presets,log)
    if type(hd2.freeze_mission_timer)~='function'or type(hd2.diagnostics)~='table'
        or type(hd2.diagnostics.mission_timer)~='function'or type(mod.on)~='function'then
        return false
    end
    mod:on('mission_started',function(e)
        if type(e)=='table'and e.host==false then return end   -- (a client follows the host's freeze)
        if not next(M.sources(presets))then return end
        local tries,timer=0,nil
        timer=mod:every(1,function()
            tries=tries+1
            local ok,report=pcall(hd2.diagnostics.mission_timer)
            local active=ok and type(report)=='table'and report.active
            if not active then
                if tries>=M.TRIES then
                    timer:cancel()
                    log('auto freeze: no mission countdown within '..M.TRIES..' s; nothing frozen')
                end
                return
            end
            timer:cancel()
            if report.host~=true or not M.sources(presets)[active.source]or active.paused then return end
            local okf,result,code,why=pcall(hd2.freeze_mission_timer,{frozen=true,allow_unverified_effect=true})
            if okf and result then
                log(('auto freeze: %s missions are ticked: the mission timer is frozen (%s)'):format(active.source,
                    tostring(result.status)))
            else
                log(('auto freeze: %s is ticked but the freeze was refused (%s: %s)'):format(active.source,
                    tostring(okf and code or'error'),tostring(okf and why or result)))
            end
        end,{scope='mission'})
    end)
    return true
end
return M

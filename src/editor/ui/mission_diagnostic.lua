-- User-requested sample only. No frame callback, timer, write or automatic retry.
local i18n=require('mods/skyeshade/hd2runtime_editor/editor/i18n')
local L,Lf=i18n.L,i18n.Lf
local C=require('mods/skyeshade/hd2runtime_editor/editor/ui/theme').colour
local M={}
-- The report as one JSON line for the log (plain tables of strings, numbers and booleans; keys sorted). Self-contained:
-- the packaged HD2Runtime ships no JSON encoder.
local function encode(v,depth)
    local t=type(v)
    if t=='string'then return(string.format('%q',v):gsub('\\\n','\\n'))end
    if t=='number'then return v~=v and'"nan"'or string.format('%.17g',v)end
    if t~='table'or depth>8 then return t=='boolean'and tostring(v)or'null'end
    local out={}
    if#v>0 then
        for i=1,#v do out[i]=encode(v[i],depth+1)end
        return '['..table.concat(out,',')..']'
    end
    local keys={}
    for k in pairs(v)do keys[#keys+1]=tostring(k)end
    table.sort(keys)
    for i,k in ipairs(keys)do out[i]=string.format('%q',k)..':'..encode(v[k],depth+1)end
    return '{'..table.concat(out,',')..'}'
end
M.encode=function(v)return encode(v,0)end
function M.check(app)
    local api=app.catalog.real_hd2.diagnostics
    local fn=api and api.mission_timer
    local ok,report,why
    if type(fn)=='function'then ok,report,why=pcall(fn)
    else why=L('This diagnostic requires HD2Runtime RC13.')end
    if not ok or not report then
        local reason=tostring(why or report or'Unavailable')
        if app.ctx.log then app.ctx.log('mission timer diagnostic unavailable: '..reason)end
        app:ask('mission_timer_report',{L('Unavailable'),reason});return
    end
    report.editor={}
    local rows={}
    for _,p in pairs(app.pending)do if p.row.field=='mission.duration_seconds'then rows[p.row.key]=p.row end end
    for _,s in pairs(app.layer.slots)do
        if s.row and s.row.field=='mission.duration_seconds'then rows[s.row.key]=s.row end
    end
    for key,row in pairs(rows)do
        local value,kind,state,_,err=app:row_view(row)
        report.editor[#report.editor+1]={key=key,source=row.descriptor.backing.source,value=value,
            kind=kind,state=state,error=err}
    end
    if app.ctx.log then
        app.ctx.log('mission timer diagnostic: '..encode(report,0))
    end
    local lines={Lf('Game state: %s',report.state),Lf('Selected mission: %s',report.selected and report.selected.name or L('Unavailable'))}
    if report.active then
        lines[#lines+1]=Lf('Host: %s',report.host and L('Yes')or L('No'))
        lines[#lines+1]=Lf('Timer source: %s',tostring(report.active.source))
        lines[#lines+1]=Lf('Base duration: %.3f s',report.active.baseSeconds)
        lines[#lines+1]=Lf('Effective duration: %.3f s',report.active.effectiveSeconds)
        lines[#lines+1]=Lf('Countdown: %.3f s',report.active.remainingSeconds)
        lines[#lines+1]=Lf('Private definition: %s',report.active.privateDefinition and L('Yes')or L('No'))
        if report.active.paused~=nil then
            app.mission_timer_frozen=report.active.paused
            lines[#lines+1]=Lf('Timer frozen: %s',report.active.paused and L('Yes')or L('No'))
        end
    else lines[#lines+1]=L('No active mission countdown.')end
    lines[#lines+1]=L('Details saved to Logs.')
    app:ask('mission_timer_report',lines)
end
local function clock(seconds)
    seconds=math.max(0,math.floor(seconds or 0))
    return ('%d:%02d'):format(math.floor(seconds/60),seconds%60)
end
-- FREEZE TIMER / RESUME TIMER: one explicit read of the timer's state, then HD2Runtime's guarded freeze (EXPERIMENTAL,
-- solo host only; the game's own timer pause; the next mission starts unpaused). Nothing polls or repeats.
function M.toggle_freeze(app)
    local hd2=app.catalog.real_hd2
    local read=hd2.diagnostics and hd2.diagnostics.mission_timer
    if type(hd2.freeze_mission_timer)~='function'or type(read)~='function'then
        app:toast(L('Freezing the timer needs a newer HD2Runtime.'),C.error);return
    end
    local ok,report,why=pcall(read)
    if not ok or not report then app:toast(Lf('Mission timer: %s',tostring(why or report)),C.error);return end
    if not report.active then app:toast(L('No active mission countdown.'),C.pending);app.mission_timer_frozen=nil;return end
    local want=not report.active.paused
    local okf,result,code,reason=pcall(hd2.freeze_mission_timer,{frozen=want,allow_unverified_effect=true})
    if not okf or not result then
        local text=tostring(okf and(reason or code)or result)
        if app.ctx.log then app.ctx.log('mission timer freeze refused: '..tostring(code)..': '..text)end
        if code=='HOST_ONLY'then app:toast(L('The host controls the mission timer.'),C.pending);return end
        app:toast(Lf('Mission timer: %s',text),C.error);return
    end
    app.mission_timer_frozen=result.frozen
    if app.ctx.log then app.ctx.log(('mission timer %s at %s (%s)'):format(result.frozen and'frozen'or'resumed',
        clock(result.remainingSeconds),tostring(result.status)))end
    local at=clock(result.remainingSeconds)
    app:toast(result.frozen and Lf('Mission timer frozen at %s.',at)or Lf('Mission timer resumed at %s.',at),C.ok)
end
return M

-- Canonical mission timer shortcuts. Nothing is written until normal Apply.
local theme=require('mods/skyeshade/hd2runtime_editor/editor/ui/theme')
local i18n=require('mods/skyeshade/hd2runtime_editor/editor/i18n')
local util=require('mods/skyeshade/hd2runtime_editor/editor/util')
local L,Lf,C=i18n.L,i18n.Lf,theme.colour
local M={}
function M.stage_group(app,group,value)
    for _,row in ipairs(group.rows)do if not app:stage(row,value)then return false end end
    return true
end
function M.group_value(app,group)
    local value,kind
    for _,row in ipairs(group.rows)do
        local current,source=app:row_view(row)
        if value~=nil and current~=value then return nil,'mixed'end
        value=current
        if source=='pending'or not kind then kind=source end
    end
    return value,kind
end
function M.begin_slider(app,state,at)
    local row=state.group.rows[1]
    local function move(px)
        local t=math.max(0,math.min(1,(px-state.x)/state.width))
        state.preview=math.floor(row.min+t*(row.max-row.min)+0.5)
    end
    move(at)
    app.drag={axis='x',mission_slider=state,move=move,finish=function()
        local value=state.preview;state.preview=nil;M.stage_group(app,state.group,value)
    end}
end
-- The Mission Timer page: FREEZE TIMER / RESUME TIMER (ui/mission_diagnostic.lua toggle_freeze). The host controls it;
-- the other players' HD2Runtime follows (HD2Runtime runtime/mission_timer_sync.lua).
function M.draw_timer(app,object,x,y,w,button,h)
    local cv=app.canvas
    cv:text(L('Mission Timer'),x+24,y+34,{font='title',size=23,colour=C.text,max=w-48})
    cv:text(L('Freeze the mission countdown. The host controls it; other players with HD2Runtime follow.'),x+24,y+64,
        {size=14,colour=C.dim,max=w-48})
    app.btn_mission_freeze=app.btn_mission_freeze or{click=function()
        require('mods/skyeshade/hd2runtime_editor/editor/ui/mission_diagnostic').toggle_freeze(app)
    end}
    -- (the state the last freeze read; nothing polls it)
    button(app,app.mission_timer_frozen and L('RESUME TIMER')or L('FREEZE TIMER'),x+24,y+92,220,40,'normal',
        app.btn_mission_freeze)
    cv:text(L('Experimental. Each new mission starts with its timer running.'),x+24,y+160,{size=13,colour=C.dim,max=w-48})
end
function M.draw(app,object,x,y,w,button,h)
    app.catalog:open(object)
    local cv=app.canvas
    app:draw_icon(object,x+24,y+12,48)
    cv:text(L(object.name),x+88,y+30,{font='title',size=23,colour=C.text,max=w-300})
    cv:text(L('Mission Overview'),x+88,y+55,{size=14,colour=C.dim,max=w-112})
    app.btn_mission_freeze=app.btn_mission_freeze or{click=function()
        require('mods/skyeshade/hd2runtime_editor/editor/ui/mission_diagnostic').toggle_freeze(app)
    end}
    -- (the state the last check or freeze read; nothing polls it)
    button(app,app.mission_timer_frozen and L('RESUME TIMER')or L('FREEZE TIMER'),x+w-190,y+17,166,30,'normal',
        app.btn_mission_freeze)
    local groups=object.timerGroups or{}
    -- (the rows' own range: HD2Runtime's reviewed one, at most the game's 2500 s mission timer limit)
    local first=groups[1]and groups[1].rows[1]
    if first then
        cv:text(Lf('One slider per original duration. Range: %s to %s seconds; the game cuts longer mission timers.',
            util.format(first.min),util.format(first.max)),x+24,y+85,{size=13,colour=C.dim,max=w-48})
    end
    app.mission_sliders=app.mission_sliders or{}
    app:list({x=x+20,y=y+102,w=w-40,h=h-157,count=#groups,row_h=104,
        scroll_key='mission_timer_scroll_'..object.missionFaction,
        draw=function(i,rx,ry,rw)
            local g=groups[i];local row=g.rows[1]
            local key=object.key..'/'..g.duration
            local state=app.mission_sliders[key]
            if not state then
                state={group=g};app.mission_sliders[key]=state
                state.action={click=function(px)M.begin_slider(app,state,px)end}
                state.reset={click=function()M.stage_group(app,g,g.duration)end}
                state.sources={}
                for _,r in ipairs(g.rows)do state.sources[#state.sources+1]=r.descriptor.backing.source end
                state.freeze={click=function()
                    local auto=require('mods/skyeshade/hd2runtime_editor/editor/auto_freeze')
                    auto.set(app.presets,state.sources,not auto.all(app.presets,state.sources))
                end}
            end
            if not app.drag or app.drag.mission_slider~=state then state.preview=nil end
            local value,kind=M.group_value(app,g)
            local mixed=value==nil and state.preview==nil
            value=state.preview or value or g.duration
            local ratio=math.max(0,math.min(1,(value-row.min)/(row.max-row.min)))
            local colour=kind=='pending'and C.pending or C.gold
            cv:text(Lf('%d-minute missions',g.duration/60),rx+4,ry+14,{size=16,font='title',colour=C.text,max=rw-240})
            cv:text(mixed and L('Mixed values')or string.format('%s s (%.2f min)',util.format(value),value/60),rx+rw-12,ry+14,
                {size=15,colour=colour,align='right',max=230})
            local sx,sw,sy=rx+9,rw-116,ry+45
            state.x,state.width=sx,sw
            cv:hit(sx-5,sy-13,sw+10,26,state.action)
            cv:rect(sx,sy-2,sw,4,C.line,2)
            cv:rect(sx,sy-2,sw*ratio,4,C.gold_dim,3)
            cv:rect(sx+sw*ratio-4,sy-9,8,18,colour,4)
            button(app,L('RESET'),rx+rw-94,ry+30,76,28,'normal',state.reset)
            cv:text(Lf('%d missions on this front',g.count),rx+4,ry+75,{size=13,colour=C.dim,max=rw/2-120})
            -- "Freeze automatically": the host's timer frozen when a mission of this type starts (editor/auto_freeze.lua)
            local ticked=require('mods/skyeshade/hd2runtime_editor/editor/auto_freeze').all(app.presets,state.sources)
            local bx=rx+math.floor(rw/2)-110
            cv:rect(bx,ry+67,16,16,ticked and C.gold or C.line,3)
            if not ticked then cv:rect(bx+2,ry+69,12,12,C.panel_alt,4)end
            cv:text(L('Freeze automatically'),bx+24,ry+75,{size=13,colour=ticked and C.gold or C.dim,max=200})
            cv:hit(bx-4,ry+63,230,24,state.freeze)
            if g.crossFaction then cv:text(L('Shared across factions'),rx+rw-12,ry+75,
                {size=13,colour=C.pending,align='right',max=rw/2})end
            cv:rect(rx,ry+96,rw-16,1,C.line,2)
        end})
    cv:text(L('Release to stage. Review Changes, then Apply. Ticked types freeze when you host them.'),x+24,y+h-36,
        {size=13,colour=C.gold,max=w-48})
    cv:text(L('Deselect the mission before applying timers.'),x+24,y+h-15,{size=13,colour=C.dim,max=w-48})
end
return M

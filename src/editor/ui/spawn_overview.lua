-- Shortcuts stage canonical fields, so presets, export and reset keep using the
-- normal override layer. Preparing fields is incremental; sliders write on release.
local theme=require('mods/skyeshade/hd2runtime_editor/editor/ui/theme')
local i18n=require('mods/skyeshade/hd2runtime_editor/editor/i18n')
local L,Lf=i18n.L,i18n.Lf
local C=theme.colour
local M={}
local FACTION_CHOICES={
        {id='patrol',label='Patrol enemy count',note='Size of ordinary patrol groups.'},
        {id='reinforcement',label='Reinforcement enemy count',note='Bug breaches and Automaton / Illuminate transport groups.'},
        {id='map',label='Map guard amount (budget)',note='Lowers group cost for more guards; not an exact count multiplier.'},
        {id='frequency',label='Patrol frequency',note='Faster patrol clock; population caps and mission gates still apply.'}}
local DIFFICULTY_CHOICES={
        {id='encounter_budget',label='Encounter budget',note='Budget for director selections, not a guaranteed head count.'},
        {id='map_budget',label='Map guard budget',note='Budget for map guards at this difficulty.'},
        {id='spawner_frequency',label='Shared spawner frequency',note='Inverse cooldown: 2x halves the shared spawner gate.'}}

local function recipe(app,kind,identity,multiplier,channel)
    local api=app.catalog.real_hd2.enemies
    if kind=='difficulty'then return api.difficulty_multiplier(identity,channel,multiplier)end
    if channel=='frequency'then return api.patrol_frequency(identity,multiplier)end
    return api.spawn_multiplier(identity,multiplier,channel)
end
function M.start(app,identity,multiplier,channel,kind)
    if app.spawn_job then app:toast(L('Spawn changes are still being prepared'),C.pending);return false end
    kind=kind or'faction';channel=channel or'all'
    local job={identity=identity,kind=kind,channel=channel,multiplier=multiplier,done=0,total=0}
    job.worker=coroutine.create(function()
        local r=recipe(app,kind,identity,multiplier,channel)
        job.total,job.clamped=r.fields,r.clamped
        coroutine.yield()
        for _,tx in ipairs(r.transactions)do
            local key=tx.target.resource=='enemy'and('en|'..tx.target.enemy)
                or('ed|'..tx.target.path..'/'..tx.target.key)
            local object=assert(app.catalog:object(key),'spawn object unavailable')
            app.catalog:open(object)
            local rows={};for _,row in ipairs(object.rows)do rows[row.field]=row end
            for _,change in ipairs(tx.changes)do
                local row=assert(rows[change.field],'spawn field unavailable')
                assert(row.editable,row.reason or'spawn field is locked')
                assert(app:stage_value(row,change.value,{kind='edit',name='Spawn tuning'}),'spawn value could not be staged')
                job.done=job.done+1
            end
            coroutine.yield()
        end
    end)
    app.spawn_job=job
    return true
end
function M.tick(app)
    local job=app.spawn_job
    if not job then return end
    local ok,why=coroutine.resume(job.worker)
    if not ok then
        app.spawn_job=nil
        app:toast(Lf('Spawn preparation stopped: %s',tostring(why)),C.error)
    elseif coroutine.status(job.worker)=='dead'then
        app.spawn_job=nil
        app.spawn_result=job
        app:toast(Lf('Prepared %d spawn fields; review Changes, then Apply',job.done),C.gold)
    end
end
-- Exposed for the input regression test. No periodic work and no writes while
-- dragging; a release queues one bounded preparation job.
function M.begin_slider(app,state,x,width,at,finish)
    if app.spawn_job then app:toast(L('Spawn changes are still being prepared'),C.pending);return end
    local function move(px)
        local ratio=math.max(0,math.min(1,(px-x)/width))
        state.value=math.floor((0.1+ratio*4.9)*10+0.5)/10
    end
    move(at)
    app.drag={axis='x',move=move,finish=function()finish(state.value)end}
end
local function slider(app,key,label,note,x,y,w,identity,channel,kind,button)
    app.spawn_sliders=app.spawn_sliders or{}
    local state=app.spawn_sliders[key]
    if not state then state={value=1};app.spawn_sliders[key]=state end
    local cv=app.canvas
    cv:text(L(label),x,y,{font='title',size=18,colour=C.text,max=w-120})
    cv:text(string.format('%.1fx',state.value),x+w-72,y,{font='title',size=18,colour=C.gold,align='right'})
    local sx,sw,sy=x+5,w-92,y+25
    state.x,state.width=sx,sw
    if not state.action then
        local function stage(value)M.start(app,identity,value,channel,kind)end
        state.action={click=function(px)M.begin_slider(app,state,state.x,state.width,px,stage)end}
        state.reset={click=function()
            if app.spawn_job then app:toast(L('Spawn changes are still being prepared'),C.pending);return end
            state.value=1;stage(1)
        end}
    end
    cv:hit(sx-5,sy-13,sw+10,26,state.action)
    cv:rect(sx,sy-2,sw,4,C.line,2)
    cv:rect(sx,sy-2,sw*(state.value-0.1)/4.9,4,C.gold_dim,3)
    cv:rect(sx+sw*(state.value-0.1)/4.9-4,sy-9,8,18,C.gold,4)
    button(app,L('1x'),x+w-62,y+8,58,28,'normal',state.reset)
    cv:text(L(note),x,y+53,{size=13,colour=C.dim,max=w})
end
local function status(app,x,y,w)
    local job=app.spawn_job
    local cv=app.canvas
    cv:text(job and Lf('Preparing %d/%d fields...',job.done,job.total)
        or L('Release a slider to prepare; review Changes, then Apply.'),x,y,
        {size=14,colour=job and C.pending or C.gold,max=w})
end
function M.draw(app,object,x,y,w,button,h)
    local cv=app.canvas
    app:draw_icon(object,x+24,y+16,58)
    cv:text(L(object.name),x+100,y+37,{font='title',size=25,colour=C.text,max=w-120})
    cv:text(L('PREPARE SPAWN MULTIPLIERS'),x+100,y+64,{font='title',size=12,colour=C.faint})
    local gap=math.min(85,math.max(57,((h or 600)-220)/4))
    for i,s in ipairs(FACTION_CHOICES)do
        slider(app,object.key..'/'..s.id,s.label,s.note,x+24,y+107+(i-1)*gap,w-48,object.spawnFaction,s.id,'faction',button)
    end
    local foot=y+112+4*gap
    status(app,x+24,foot,w-48)
    cv:text(L('0.1x to 5x, from defaults. Shown values are preparation choices.'),x+24,foot+28,{size=13,colour=C.dim,max=w-48})
    cv:text(L('Apply on the ship before launch. Counts round and respect field limits.'),x+24,foot+52,{size=13,colour=C.dim,max=w-48})
    cv:text(L('Transport capacity and budgets still apply; larger spawns cost performance.'),x+24,foot+76,{size=13,colour=C.dim,max=w-48})
end
-- Compact block above the real difficulty rows, retaining advanced editing and
-- honest source/value feedback below. Each difficulty has independent native fields.
function M.draw_difficulty(app,object,x,y,w,button)
    app.canvas:text(L('PREPARE DIFFICULTY MULTIPLIERS'),x+24,y+19,{size=13,font='title',colour=C.gold})
    for i,s in ipairs(DIFFICULTY_CHOICES)do
        slider(app,object.key..'/'..s.id,s.label,s.note,x+24,y+48+(i-1)*73,w-48,object.spawnDifficulty,s.id,'difficulty',button)
    end
    status(app,x+24,y+270,w-48)
    app.canvas:text(L('0.1x to 5x from defaults. Apply before launch; exact values below.'),x+24,y+294,
        {size=13,colour=C.dim,max=w-48})
    return 311
end
return M

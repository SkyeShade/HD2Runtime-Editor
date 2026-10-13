-- Faction shortcuts stage ordinary composition rows, preserving preset/export
-- identities and the override layer's fresh write guards.
local theme=require('mods/skyeshade/hd2runtime_editor/editor/ui/theme')
local i18n=require('mods/skyeshade/hd2runtime_editor/editor/i18n')
local L,Lf=i18n.L,i18n.Lf
local C=theme.colour
local M={}
function M.start(app,faction,multiplier)
    if app.spawn_job then app:toast(L('Spawn changes are still being prepared'),C.pending);return false end
    local job={faction=faction,multiplier=multiplier,done=0,total=0}
    job.worker=coroutine.create(function()
        local recipe=app.catalog.real_hd2.enemies.spawn_multiplier(faction,multiplier)
        job.total,job.clamped=recipe.fields,recipe.clamped
        coroutine.yield()
        for _,tx in ipairs(recipe.transactions)do
            local object=assert(app.catalog:object('ed|composition/'..tx.target.key))
            app.catalog:open(object)
            local rows={};for _,r in ipairs(object.rows)do rows[r.field]=r end
            for _,change in ipairs(tx.changes)do
                local row=assert(rows[change.field],'composition field unavailable')
                assert(row.editable,row.reason or'composition field is locked')
                assert(app:stage_value(row,change.value,{kind='edit',name='Enemy Overview'}),'spawn value could not be staged')
                job.done=job.done+1
            end
            -- One composition at most per UI frame; large factions never build
            -- hundreds of catalogue pages inside a single click callback.
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
        app.spawn_result={faction=job.faction,fields=job.done,clamped=job.clamped,multiplier=job.multiplier}
        app:toast(Lf('Prepared %d spawn fields; review Changes, then Apply',job.done),C.gold)
    end
end
function M.draw(app,object,x,y,w,button)
    local cv=app.canvas
    app:draw_icon(object,x+24,y+16,58)
    cv:text(L(object.name),x+100,y+37,{font='title',size=25,colour=C.text,max=w-120})
    cv:text(L('ENEMY OVERVIEW'),x+100,y+64,{font='title',size=12,colour=C.faint})
    cv:text(L('Spawn amount'),x+24,y+112,{font='title',size=21,colour=C.gold})
    cv:text(L('Scale authored composition counts for this faction.'),x+24,y+144,{size=15,colour=C.text,max=w-48})
    cv:text(L('Based on defaults each time; pressing 2x twice stays at 2x.'),x+24,y+170,{size=14,colour=C.dim,max=w-48})
    app.spawn_actions=app.spawn_actions or{}
    for i,factor in ipairs({0.5,1,2,3})do
        local key=object.spawnFaction..'/'..factor
        local action=app.spawn_actions[key]
        if not action then
            local faction,value=object.spawnFaction,factor
            action={click=function()M.start(app,faction,value)end};app.spawn_actions[key]=action
        end
        local bw=math.min(105,(w-66)/4)
        button(app,tostring(factor)..'x',x+24+(i-1)*(bw+6),y+197,bw,38,'normal',action)
    end
    local job=app.spawn_job
    local progress=job and Lf('Preparing %d/%d fields...',job.done,job.total)
        or L('Choose a multiplier, review Changes, then Apply.')
    cv:text(progress,x+24,y+269,{size=15,colour=job and C.pending or C.dim,max=w-48})
    cv:text(L('Apply aboard the ship before the next mission.'),x+24,y+312,{size=15,colour=C.gold,max=w-48})
    cv:text(L('Counts round to whole enemies and stop at supported limits.'),x+24,y+346,{size=14,colour=C.dim,max=w-48})
    cv:text(L('Transport capacity, budgets and scripted spawns still apply.'),x+24,y+373,{size=14,colour=C.dim,max=w-48})
    cv:text(L('This changes group sizes, not patrol frequency or roster odds.'),x+24,y+400,{size=14,colour=C.dim,max=w-48})
    local result=app.spawn_result
    if result and result.faction==object.spawnFaction then
        cv:text(Lf('Last preparation: %d fields; %d reached their limit',result.fields,result.clamped),
            x+24,y+443,{size=14,colour=C.faint,max=w-48})
    end
end
return M

-- HD2Runtime Editor: wiring. Every module is required here, at load: the engine resolves a mod's archived Lua
-- resources only while its startup package is loaded.
local util=require('mods/skyeshade/hd2runtime_editor/editor/util')
local catalog_module=require('mods/skyeshade/hd2runtime_editor/editor/catalog')
local ledger_module=require('mods/skyeshade/hd2runtime_editor/editor/ledger')
local layer_module=require('mods/skyeshade/hd2runtime_editor/editor/layer')
local presets_module=require('mods/skyeshade/hd2runtime_editor/editor/presets')
local app_module=require('mods/skyeshade/hd2runtime_editor/editor/ui/app')
-- The game's own icons, when tools/game_icons.py generated them for this build (optional; never committed).
local game_icons
do
    local ok,value=pcall(require,'mods/skyeshade/hd2runtime_editor/editor/generated/game_icons')
    if ok and type(value)=='table'then game_icons=value end
end
local M={}

M.VERSION='0.2.0'
M.HOTKEY='F8'
local RESTORE_MIN,RESTORE_MAX=6,90   -- game seconds: earliest restore, and the latest wait for other mods to settle
local SETTLED={complete=true,rejected=true,cancelled=true,blocked=true,disabled=true,unavailable=true}

-- The Runtime services the editor stands on (HD2Runtime 0.30.0-dev with the UI and game-mod services).
function M.missing(hd2)
    local missing={}
    if not(type(hd2.ui)=='table'and type(hd2.ui.overlay)=='function')then missing[#missing+1]='hd2.ui.overlay'end
    if type(hd2.on_frame)~='function'then missing[#missing+1]='hd2.on_frame'end
    if not(type(hd2.input)=='table'and type(hd2.input.pressed)=='function')then missing[#missing+1]='hd2.input.pressed'end
    if type(hd2.ensure)~='function'then missing[#missing+1]='hd2.ensure'end
    if type(hd2.mod)~='function'then missing[#missing+1]='hd2.mod'end
    return missing
end

-- Whether every other mod's registered operation has reached a resting state (so restored values adopt theirs).
local function others_settled(hd2,editor)
    local ok,list=pcall(function()return hd2.diagnostics.operations()end)
    if not ok or type(list)~='table'then return true end
    for _,op in ipairs(list)do
        if op.mod~=editor then
            local resting=SETTLED[op.status]or(op.kind=='ensure'and(op.runs or 0)>=1)
            if not resting then return false end
        end
    end
    return true
end

function M.start(hd2,id)
    local mod=hd2.mod(id)
    local function log(message)pcall(mod.log,mod,'[editor] '..tostring(message))end
    local missing=M.missing(hd2)
    if#missing>0 then
        log('HD2Runtime Editor '..M.VERSION..' is inactive: this HD2Runtime ('..tostring(hd2.version_label or hd2.version)
            ..') lacks '..table.concat(missing,', ')..'. Install HD2Runtime 0.30.0-dev with the UI services or newer.')
        return {status='unavailable',missing=missing}
    end
    local ledger=ledger_module.install(hd2,id)
    if ledger.error then log(ledger.error)end
    local catalog=catalog_module.new(hd2)
    local layer=layer_module.new({hd2=hd2,id=id,ledger=ledger,catalog=catalog,log=log})
    local store
    do
        local ok,value=pcall(function()return mod:store()end)
        if ok and value then store=value else log('saved data unavailable: '..tostring(value))end
    end
    local presets=presets_module.new(store)
    local hotkey=presets:setting('hotkey',M.HOTKEY)
    local overlay=hd2.ui.overlay({id='editor',visible=false})
    -- Icons: one image handle per generated icon (needs the overlay's d:image, HD2Runtime r50).
    local icons
    if game_icons and type(hd2.resources)=='table'and type(hd2.resources.image)=='function'then
        icons={stratagems={},boosters={}}
        local count=0
        for kind,list in pairs({stratagems=game_icons.stratagems or{},boosters=game_icons.boosters or{}})do
            for name,entry in pairs(list)do
                local ok,handle=pcall(hd2.resources.image,entry.image)
                if ok and handle then icons[kind][name]={handle=handle,accent=entry.accent};count=count+1 end
            end
        end
        log(count..' game icons available')
    end
    -- The cursor capture (HD2Runtime r50, experimental): freed while the editor is open, when the setting is on.
    local function set_free_cursor(on)
        if type(overlay.free_cursor)=='function'then pcall(overlay.free_cursor,overlay,on)end
    end
    set_free_cursor(presets:setting('free_cursor',true))
    local app=app_module.new({hd2=hd2,catalog=catalog,layer=layer,ledger=ledger,presets=presets,hotkey=hotkey,
        label='HD2Runtime '..tostring(hd2.version_label or hd2.version)..'  ·  Editor '..M.VERSION,
        mouse=function()return overlay:mouse()end,log=log,icons=icons,choices=type(mod.choice)=='function',
        set_free_cursor=type(overlay.free_cursor)=='function'and set_free_cursor or nil})
    local state={status='ready',app=app,layer=layer,ledger=ledger,catalog=catalog,presets=presets,overlay=overlay}

    -- Drawing: a failing frame is logged once per message and replaced by a one-line notice.
    local last_error
    overlay:draw(function(d,dt)
        local ok,why=xpcall(function()app:frame(d,dt)end,function(e)return debug.traceback(tostring(e),2)end)
        if not ok then
            if why~=last_error then last_error=why;log('frame failed: '..why)end
            d:rect(40*d.scale,64*d.scale,760*d.scale,44*d.scale,{120,24,20,230})
            d:text('HD2Runtime Editor hit an error; see HD2Runtime.log. Press '..hotkey..' to close.',
                56*d.scale,76*d.scale,{size=18*d.scale})
        end
    end)
    local function toggle()
        if overlay:status().visible then
            overlay:hide()
            app.input:reset()
            app.edit=nil
        else
            overlay:show()
        end
    end
    state.toggle=toggle
    app.ctx.close=function()if overlay:status().visible then toggle()end end
    local binding=mod:bind('hd2runtime_editor.toggle',{key=hotkey,on_press=toggle})
    if type(binding)=='table'and binding.state=='conflict'then
        log('the hotkey '..hotkey..' is used by another mod; rebind it in the Presets tab settings or saved data')
    end

    -- Every frame: drive the override layer; restore the last session once; save the session when it settles.
    local clock,restored,saved_version=0,false,-1
    local restore=presets:setting('restore_session',true)
    mod:on_frame(function(dt)
        clock=clock+(dt or 0)
        layer:tick(dt or 0)
        if not restored and clock>=RESTORE_MIN then
            local ready=others_settled(hd2,id)
            local build=type(hd2.build)=='function'and select(2,pcall(hd2.build))or'matched'
            if(ready and build~='not_ready')or clock>=RESTORE_MAX then
                restored=true
                if restore then
                    local values=presets:session()
                    local applied,missing_rows=0,0
                    for key,stored in pairs(values)do
                        local row,value=app:decode_value(key,stored)
                        if row and value~=nil and layer:set(row,value)then applied=applied+1 else missing_rows=missing_rows+1 end
                    end
                    if applied+missing_rows>0 then
                        log('restored '..applied..' saved values'..(missing_rows>0 and(' ('..missing_rows..' no longer available)')or''))
                    end
                end
                saved_version=layer.version
            end
        end
        if restored and(app.save_session or layer.version~=saved_version)and not layer:busy()then
            app.save_session=false
            saved_version=layer.version
            presets:set_session(app:encode_values(layer:overrides()))
        end
    end,{id='hd2runtime_editor.layer'})
    log('HD2Runtime Editor '..M.VERSION..' ready; press '..hotkey..' to open')
    return state
end

return M

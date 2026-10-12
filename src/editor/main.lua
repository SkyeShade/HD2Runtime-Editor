-- HD2R Editor (c) 2026 SkyeShade. All rights reserved except as granted in LICENSE
-- (https://github.com/SkyeShade/HD2Runtime-Editor). Do not redistribute or reuse without the credit it requires.
-- HD2R Editor: wiring. Every module is required here, at load: the engine resolves a mod's archived Lua
-- resources only while its startup package is loaded.
local util=require('mods/skyeshade/hd2runtime_editor/editor/util')
local catalog_module=require('mods/skyeshade/hd2runtime_editor/editor/catalog')
local ledger_module=require('mods/skyeshade/hd2runtime_editor/editor/ledger')
local layer_module=require('mods/skyeshade/hd2runtime_editor/editor/layer')
local presets_module=require('mods/skyeshade/hd2runtime_editor/editor/presets')
local session_module=require('mods/skyeshade/hd2runtime_editor/editor/session')
local app_module=require('mods/skyeshade/hd2runtime_editor/editor/ui/app')
local sounds_module=require('mods/skyeshade/hd2runtime_editor/editor/sounds')
local i18n=require('mods/skyeshade/hd2runtime_editor/editor/i18n')
local game_names_module=require('mods/skyeshade/hd2runtime_editor/editor/game_names')
local strings=require('mods/skyeshade/hd2runtime_editor/editor/strings')
require('mods/skyeshade/hd2runtime_editor/editor/installed')
require('mods/skyeshade/hd2runtime_editor/editor/json')
require('mods/skyeshade/hd2runtime_editor/editor/modbuilder')
require('mods/skyeshade/hd2runtime_editor/editor/preset_files')
require('mods/skyeshade/hd2runtime_editor/editor/ui/search_view')
require('mods/skyeshade/hd2runtime_editor/editor/ui/errors_view')
-- Generated for this build (optional; never committed): the game's own stratagem and booster icons
-- (tools/game_icons.py), the installed mods' own icons (tools/mod_icons.py) and pictures for presets
-- (tools/preset_icons.py).
local function optional(name)
    local ok,value=pcall(require,'mods/skyeshade/hd2runtime_editor/editor/generated/'..name)
    return ok and type(value)=='table'and value or nil
end
local game_icons=optional('game_icons')
local mod_icon_map=optional('mod_icons')
local preset_icon_map=optional('preset_icons')
local M={}

M.VERSION='1.0.0'
M.HOTKEY='F8'
local RESTORE_MIN,RESTORE_MAX=6,90   -- game seconds: earliest restore, and the latest wait for other mods to settle
local SETTLED={complete=true,rejected=true,cancelled=true,blocked=true,disabled=true,unavailable=true}

-- The Runtime services the editor stands on (HD2Runtime 0.30.0: the UI and game-mod services).
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
        log('HD2R Editor '..M.VERSION..' is inactive: this HD2Runtime ('..tostring(hd2.version_label or hd2.version)
            ..') lacks '..table.concat(missing,', ')..'. Install HD2Runtime 0.30.0 or newer.')
        return {status='unavailable',missing=missing}
    end
    local ledger=ledger_module.install(hd2,id)
    if ledger.error then log(ledger.error)end
    local catalog=catalog_module.new(hd2)
    -- The Runtime's shared-record index (every catalogue's native locations) builds on its first use, about 60-130 ms
    -- in one call: built now, while the game loads, instead of on the first frame the window is open.
    pcall(function()
        local shared_records=require('hd2runtime/core/shared_records')
        if type(shared_records.entry)=='function'then shared_records.entry({})end
    end)
    -- The explosion catalogue's own field descriptors (HD2Runtime 0.31.1 ProgrammableAmmo burst rows), resolved while
    -- the game loads like every other module.
    pcall(require,'hd2runtime/domains/explosion_writes')
    local layer=layer_module.new({hd2=hd2,id=id,ledger=ledger,catalog=catalog,log=log})
    local store
    do
        local ok,value=pcall(function()return mod:store()end)
        if ok and value then store=value else log('saved data unavailable: '..tostring(value))end
    end
    local presets=presets_module.new(store)
    local hotkey=presets:setting('hotkey',M.HOTKEY)
    -- the language chosen in Settings (a file in the localisation folder); none chosen yet: the game's language when a
    -- localisation file for it is there (hd2.ui.language, HD2Runtime 0.31.1), English otherwise. Checked again each
    -- time the window opens (the game reads its language once its world is up, and the player may change it).
    local language=presets:setting('language',nil)
    local auto_language
    local function follow_game_language()
        if presets:setting('language',nil)~=nil then return false end
        local auto=i18n.use_game_language(hd2)
        if not auto and i18n.language()~='English'then i18n.use('English')end
        if auto==auto_language then return false end
        auto_language=auto
        if auto then log('language '..tostring(auto)..' (the game language; pick another in Settings)')end
        return true
    end
    if language==nil then follow_game_language()
    elseif language~='English'then
        local ok,why=i18n.use(language)
        if not ok then log('language '..tostring(language)..' unavailable: '..tostring(why))end
    end
    -- The game's own names of weapons, stratagems, boosters ... in its language (HD2Runtime game text API,
    -- feature-detected; Settings: "Use the game's names"). Looked up again each time the window opens.
    local game_names=game_names_module.new(hd2,function()return presets:setting('game_names',true)end):install()
    if game_names.ready then log('the game\'s own names are shown ('..tostring(game_names.language)..')')end
    local overlay=hd2.ui.overlay({id='editor',visible=false})
    local icons,count=require('mods/skyeshade/hd2runtime_editor/editor/icons').load(hd2,game_icons)
    log(count..' game icons available')
    local icon_assets=require('mods/skyeshade/hd2runtime_editor/editor/icons').warm(hd2,icons,log)
    -- The editor's own mask icons (images/ui_*.png: the mod marker and the category glyphs).
    local ui_icons
    if type(hd2.resources)=='table'and type(hd2.resources.image)=='function'then
        ui_icons={}
        for _,name in ipairs({'mod','edited','pending','error'})do
            local ok,handle=pcall(hd2.resources.image,'ui_'..name)
            if ok and handle then ui_icons[name]=handle end
        end
    end
    -- The installed mods' own icons: each a few colour layers of its picture (tools/mod_icons.py).
    local mod_icons
    if mod_icon_map and type(hd2.resources)=='table'and type(hd2.resources.image)=='function'then
        mod_icons={}
        local count=0
        for key,layers in pairs(mod_icon_map.icons or{})do
            local list={}
            for _,layer in ipairs(layers)do
                local ok,handle=pcall(hd2.resources.image,layer.image)
                if ok and handle then list[#list+1]={handle=handle,colours=layer.colours}end
            end
            if#list==#layers then mod_icons[key]=list;count=count+1 end
        end
        log(count..' mod icons available')
    end
    -- Pictures for presets (tools/preset_icons.py): built into this editor like the mod icons. The Runtime draws only
    -- images a mod's build compiled (docs/custom-images.md), so a picture file cannot be loaded while the game runs.
    local preset_icons
    if preset_icon_map and type(hd2.resources)=='table'and type(hd2.resources.image)=='function'then
        preset_icons={}
        local count=0
        for _,entry in ipairs(preset_icon_map.icons or{})do
            local list={}
            for _,layer in ipairs(entry.layers or{})do
                local ok,handle=pcall(hd2.resources.image,layer.image)
                if ok and handle then list[#list+1]={handle=handle,colours=layer.colours}end
            end
            if type(entry.name)=='string'and#list>0 and#list==#(entry.layers or{})then
                preset_icons[entry.name]=list;count=count+1
            end
        end
        log(count..' preset pictures available')
    end
    local sounds=sounds_module.new(hd2,function()return presets:setting('ui_sounds',true)end)
    -- The cursor capture (HD2Runtime r50, experimental): freed while the editor is open, when the setting is on.
    local function set_free_cursor(on)
        if type(overlay.free_cursor)=='function'then pcall(overlay.free_cursor,overlay,on)end
    end
    set_free_cursor(presets:setting('free_cursor',true))
    local app=app_module.new({hd2=hd2,catalog=catalog,layer=layer,ledger=ledger,presets=presets,hotkey=hotkey,
        label='HD2Runtime '..tostring(hd2.version_label or hd2.version)..'  ·  Editor '..M.VERSION,
        mouse=function()return overlay:mouse()end,log=log,icons=icons,ui_icons=ui_icons,choices=type(mod.choice)=='function',
        id=id,sounds=sounds,mod_icons=mod_icons,preset_icons=preset_icons,strings=strings,version=M.VERSION,game_names=game_names,
        minimum=tostring(hd2.version or'0.30.0'),
        set_free_cursor=type(overlay.free_cursor)=='function'and set_free_cursor or nil})
    local state={status='ready',app=app,layer=layer,ledger=ledger,catalog=catalog,presets=presets,overlay=overlay,
        icon_assets=icon_assets}

    -- Drawing: a failing frame is logged once per message and replaced by a one-line notice.
    local last_error
    overlay:draw(function(d,dt)
        local ok,why=xpcall(function()app:frame(d,dt)end,function(e)return debug.traceback(tostring(e),2)end)
        if not ok then
            if why~=last_error then last_error=why;log('frame failed: '..why)end
            d:rect(40*d.scale,64*d.scale,760*d.scale,44*d.scale,{120,24,20,230})
            d:text('HD2R Editor hit an error; see HD2Runtime.log. Press '..hotkey..' to close.',
                56*d.scale,76*d.scale,{size=18*d.scale})
        end
    end)
    -- Keep the game from acting on keys, clicks and the wheel while the editor is open (HD2Runtime r52
    -- hd2.input.block, a lease renewed every frame; the editor reads input with GetAsyncKeyState, which it never blocks).
    local can_block=type(hd2.input)=='table'and type(hd2.input.block)=='function'
    local function block(on)
        if can_block then pcall(hd2.input.block,on and{keyboard=true,mouse=true}or false)end
    end
    local function toggle()
        if overlay:status().visible then
            app:end_key_capture()
            block(false)
            overlay:hide()
            app.input:reset()
            app.edit=nil
        else
            -- (texts cached in the game's language before it changed are built again)
            local changed=follow_game_language()
            if game_names:refresh()then changed=true end
            if changed then app.tab_actions,app.mods_cache,app.changes_key=nil,nil,nil end
            overlay:show()
        end
    end
    state.toggle=toggle
    app.ctx.close=function()if overlay:status().visible then toggle()end end
    local binding=mod:bind('hd2runtime_editor.toggle',{key=hotkey,on_press=toggle})
    if type(binding)=='table'and binding.state=='rejected'and hotkey~=M.HOTKEY then
        log('the saved hotkey '..tostring(hotkey)..' is not a key ('..tostring(binding.reason)..'); using '..M.HOTKEY)
        hotkey=M.HOTKEY
        app.ctx.hotkey=hotkey
        binding=mod:bind('hd2runtime_editor.toggle',{key=hotkey,on_press=toggle})
    end
    if type(binding)=='table'and binding.state=='conflict'then
        log('the hotkey '..hotkey..' is used by another mod; choose another in the editor\'s Settings tab')
    end
    -- Settings: another open key. The Runtime refuses a chord another binding holds; the editor then keeps its key.
    -- ok, or false and 'conflict' and the holder's mod, or false and why.
    if type(binding)=='table'and type(binding.rebind)=='function'and binding.state~='rejected'then
        app.ctx.set_hotkey=function(text)
            local previous=hotkey
            local ok,why=binding:rebind(text)
            if not ok then
                local holder=type(binding.conflict)=='table'and binding.conflict.owner or nil
                if binding.key==nil then binding:rebind(previous)end
                return false,why,holder
            end
            hotkey=binding.key or text
            app.ctx.hotkey=hotkey
            presets:set_setting('hotkey',hotkey)
            log('the editor now opens with '..hotkey)
            return true
        end
        app.ctx.hold_hotkey=function(on)
            if on then binding:disable()else binding:enable()end
        end
    end

    -- Every frame: advance unfinished layer work; restore once; save only when the session changes.
    -- The layer returns immediately once settled, waking on edits and ensure status callbacks.
    -- (editor/session.lua: a saved value that does not come back at this start stays saved).
    local session=session_module.new({app=app,layer=layer,presets=presets,log=log})
    state.session=session
    app.ctx.forget_saved=function()session:forget_all()end
    local clock=0
    local restore=presets:setting('restore_session',true)
    local background_error
    mod:on_frame(function(dt)
        clock=clock+(dt or 0)
        local visible=overlay:status().visible
        layer:set_visible(visible)
        if visible or layer.pending~=false then layer:tick(dt or 0)end
        -- a preset import (and the Windows dialog it waits for) goes on while the window is closed
        if not visible and(app.pf_job or app.pf_picking)then
            local ok,why=pcall(app.background_tick,app)
            if not ok and why~=background_error then background_error=why;log('preset import failed: '..tostring(why))end
        end
        if can_block and visible and presets:setting('block_game_input',true)then block(true)end
        if not session.restored and clock>=RESTORE_MIN then
            local ready=others_settled(hd2,id)
            local build=type(hd2.build)=='function'and select(2,pcall(hd2.build))or'matched'
            if(ready and build~='not_ready')or clock>=RESTORE_MAX then
                if restore then session:restore()
                else session.restored,session.saved_version=true,layer.version end
            end
        end
        session:tick()
    end,{id='hd2runtime_editor.layer'})
    log('HD2R Editor '..M.VERSION..' ready; press '..hotkey..' to open')
    return state
end

return M

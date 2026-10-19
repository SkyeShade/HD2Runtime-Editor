-- The shipped addon as the game loads it: the SDK's wrapper (dependency check, run_as), the Runtime's library entry,
-- then the editor's start. Offline there is no engine GUI, so the overlay waits; everything else must be ready.
local args=...
_G.CowboyBingusModLoader={api=1,version=16,modules={}}
_G.update=function()end
package.preload['mods/skyeshade/hd2runtime']=function()return require('hd2runtime/api/hd2')end
local hd2=require('hd2runtime/api/hd2')
local heard={}
hd2.sounds.play=function(event)heard[#heard+1]=event;return{}end
local chunk=assert(loadstring(args.wrapped,'@mods/skyeshade/hd2runtime_editor'))
local state=chunk()
assert(type(state)=='table','the addon returned '..tostring(state))
assert(state.status=='ready','editor status '..tostring(state.status)..' missing='..table.concat(state.missing or{},','))
local hd2=require('hd2runtime/api/hd2')
-- the wrapper's guard: loading again returns the same state
if type(hd2.diagnostics.save_application_optimizations)=='function'then
    -- HD2Runtime 0.40.1 and later: off by default, the Runtime saves the choice (F10 > Settings); the editor does not
    -- turn it on at start.
    local settings=require('hd2runtime/runtime/runtime_settings')
    assert(hd2.diagnostics.application_optimizations()==false,'the editor turned the optimizations on at start')
    assert(state.app:set_optimized_application(true))
    assert(hd2.diagnostics.application_optimizations()==true and settings.enabled('optimized_application')==true)
    assert(state.app:set_optimized_application(false))
    assert(hd2.diagnostics.application_optimizations()==false and settings.enabled('optimized_application')==false)
else
    assert(hd2.diagnostics.application_optimizations()==true)
    assert(state.app:set_optimized_application(false))
    assert(hd2.diagnostics.application_optimizations()==false)
    assert(state.presets:setting('optimized_application',true)==false)
    assert(state.app:set_optimized_application(true))
    assert(hd2.diagnostics.application_optimizations()==true)
end
assert(chunk()==state,'a second load must return the same state')
-- Optional local mod artwork must survive handle initialization for every alias.
local has_icons,icons=pcall(require,'mods/skyeshade/hd2runtime_editor/editor/generated/mod_icons')
if has_icons then
    local loaded=assert(state.app.ctx.mod_icons,'mod icon map not attached to the UI')
    for key,layers in pairs(icons.icons)do
        assert(loaded[key]and#loaded[key]==#layers,'mod icon layers missing: '..key)
    end
end

-- the toggle shows and hides the overlay
state.toggle()
assert(state.overlay:status().visible==true,'overlay shown')
assert(#heard==1 and heard[1]=='ui/slot_select','editor opening must match F10')
for _=1,30 do _G.update(1/30)end
local status=state.overlay:status()
state.toggle()
assert(state.overlay:status().visible==false,'overlay hidden')
-- the keybind is registered for the editor
local binding=hd2.input.get('hd2runtime_editor.toggle')
assert(binding,'toggle binding registered')
-- the session restore runs once the other operations settle (none here)
for _=1,100 do _G.update(0.1)end
state.toggle();assert(#heard==2 and heard[2]=='ui/slot_select','reopening after idle did not play')
state.toggle();state.presets:set_setting('ui_sounds',false)
for _=1,10 do _G.update(0.1)end
state.toggle();assert(#heard==2,'muted opening played a sound');state.toggle()
return 'ready; overlay state while shown offline: '..tostring(status.state)..' ('..tostring(status.reason)..')'

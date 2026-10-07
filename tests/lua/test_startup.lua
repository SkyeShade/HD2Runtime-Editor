-- The shipped addon as the game loads it: the SDK's wrapper (dependency check, run_as), the Runtime's library entry,
-- then the editor's start. Offline there is no engine GUI, so the overlay waits; everything else must be ready.
local args=...
_G.CowboyBingusModLoader={api=1,version=16,modules={}}
_G.update=function()end
package.preload['mods/skyeshade/hd2runtime']=function()return require('hd2runtime/api/hd2')end
local chunk=assert(loadstring(args.wrapped,'@mods/skyeshade/hd2runtime_editor'))
local state=chunk()
assert(type(state)=='table','the addon returned '..tostring(state))
assert(state.status=='ready','editor status '..tostring(state.status)..' missing='..table.concat(state.missing or{},','))
local hd2=require('hd2runtime/api/hd2')
-- the wrapper's guard: loading again returns the same state
assert(chunk()==state,'a second load must return the same state')
-- the toggle shows and hides the overlay
state.toggle()
assert(state.overlay:status().visible==true,'overlay shown')
for _=1,30 do _G.update(1/30)end
local status=state.overlay:status()
state.toggle()
assert(state.overlay:status().visible==false,'overlay hidden')
-- the keybind is registered for the editor
local binding=hd2.input.get('hd2runtime_editor.toggle')
assert(binding,'toggle binding registered')
-- the session restore runs once the other operations settle (none here)
for _=1,100 do _G.update(0.1)end
return 'ready; overlay state while shown offline: '..tostring(status.state)..' ('..tostring(status.reason)..')'

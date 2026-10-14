local args=...
local H=assert(loadfile(args.harness))({sim=args.sim})
-- Settings: a key the game's keybind page (MODS tab) controls is shown struck out, its CHANGE / DEFAULT gone and the
-- note saying how to get it back; HD2Runtime's settings row names the MODS keybind. Nothing controls it: as before.
local native={}
H.app.hd2.input=H.app.hd2.input or{}
local bindings=H.app.hd2.input.bindings
H.app.hd2.input.bindings=function()
    return {{id='hd2runtime_editor.toggle',key='F8',native=native.editor},
        {id='hd2runtime.settings',key='F10',native=native.runtime}}
end
local function texts(frame)
    local out={}
    for _,item in ipairs(frame.items or{})do if item.k=='t'then out[#out+1]=item.s end end
    return table.concat(out,'\n')
end
H.app:set_view('settings')
local f=H.frame({});assert(#f.refused==0)
assert(not H.app:native_key('hd2runtime_editor.toggle'))
native.editor={registered=true,bound=true}
native.runtime={registered=true,bound=false}
H.app.native_list_time=nil -- (read once per frame)
assert(H.app:native_key('hd2runtime_editor.toggle')and not H.app:native_key('hd2runtime.settings'))
f=H.frame({});assert(#f.refused==0)
local t=texts(f)
assert(t:find('MODS keybind',1,true)and t:find('Empty it there to use F8 again',1,true),t:sub(1,400))
local NL=string.char(10)
assert(not(NL..t..NL):find(NL..'CHANGE'..NL,1,true),'no CHANGE while the MODS keybind controls the key')
native.runtime={registered=true,bound=true};H.app.native_list_time=nil
t=texts(H.frame({}))
assert(t:find('HD2Runtime settings (MODS keybind)',1,true))
-- An older HD2Runtime (rc21: owned only) and an unregistered binding.
native.editor={registered=true,owned=true};H.app.native_list_time=nil;assert(H.app:native_key('hd2runtime_editor.toggle'))
native.editor={registered=false,bound=true};H.app.native_list_time=nil;assert(not H.app:native_key('hd2runtime_editor.toggle'))
H.app.hd2.input.bindings=bindings
return 'native keys settings ok'

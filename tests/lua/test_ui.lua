-- The editor window driven like a player would: three mods installed (an ensure, a one-shot patch, a refused patch),
-- browse to the Liberator, type a value, nudge another, apply, look at Mods and Presets, save a preset, reset to
-- defaults. Every frame must stay inside the overlay's limits. args.dump (a folder) writes each named frame as JSON
-- for tests/render_frames.py.
local args=...
local H=assert(loadfile(args.harness))({sim=args.sim})
local hd2=H.hd2
local frames=0
local function check(d,label)
    frames=frames+1
    assert(#d.refused==0,label..': the overlay would refuse '..tostring(d.refused[1]))
    assert(#d.items<=1024,label..': '..#d.items..' items (limit 1024)')
end
local function save(name,d)
    if not args.dump then return end
    local f=assert(io.open(args.dump..'/'..name..'.json','wb'))
    f:write(H.dump(d))
    f:close()
end
local function step(keys,opts,name)
    local d=H.frame(keys,opts)
    check(d,name or'frame')
    if name then save(name,d)end
    return d
end
local function settle(seconds)
    local t=0
    while t<seconds do local d=H.frame({},{dt=0.1});check(d,'settle');t=t+0.1 end
end

hd2.events.run_as('mods/someone/liberator_overdrive',function()
    return hd2.ensure({transaction={id='overdrive',target=hd2.weapon('AR-23 Liberator'),changes={
        {field='weapon.fire_rate',expect=640,value=1200}}}})
end)
hd2.events.run_as('mods/someone/eagle_tweaks',function()
    return hd2.patch({id='eagle-cd',target=hd2.stratagem('Eagle 500kg Bomb'),field='stratagem.cooldown',expect=15,value=8})
end)
hd2.events.run_as('mods/someone/broken_mod',function()
    return hd2.patch({id='bad',target=hd2.weapon('AR-23 Liberator'),field='weapon.fire_rate',expect=1,value=2})
end)
settle(5)
step({},nil,'01_browse')
-- Browse: Primary -> AR-23 Liberator -> fields
step({'RIGHT'})
for _=1,40 do
    local objects=H.app:objects()
    if objects[H.app.obj]and objects[H.app.obj].name=='AR-23 Liberator'then break end
    step({'DOWN'})
end
assert(H.app:object().name=='AR-23 Liberator','found the Liberator')
step({'RIGHT'})
assert(H.app.focus=='fields','fields focused')
step({},nil,'02_liberator')
local rof=H.catalog:row('pw|AR-23 Liberator|weapon.fire_rate')
assert(select(2,H.layer:value(rof))=='mod','the mod value shows')
-- type 1300 into the fire rate
local items,selectable=H.app:field_items(H.app:object())
for s,index in ipairs(selectable)do if items[index].row==rof then H.app.field=s end end
step({'1'});step({'3'});step({'0'})
step({'0'},nil,'03_typing')
assert(H.app.edit and H.app.edit.buffer=='1300','typed 1300: '..tostring(H.app.edit and H.app.edit.buffer))
step({'DOWN'})
assert(H.app.pending[rof.key]and H.app.pending[rof.key].value==1300,'1300 pending')
-- nudge the next field up by ten steps
local nudged=H.app:focused_row()
step({'RIGHT'},{down={'SHIFT'}},'04_pending')
assert(H.app.pending[nudged.key],'nudge staged')
assert(H.app.pending_n==2,'two pending')
-- apply
step({'F9'},nil,'05_applying')
assert(H.app.pending_n==0,'pending cleared on apply')
settle(6)
step({},nil,'06_applied')
assert(H.sim.value(rof)==1300,'1300 written: '..tostring(H.sim.value(rof)))
assert(H.layer:state(rof)=='active','fire rate active')
-- Mods tab: three mods, one refused operation
step({'TAB'},{down={'SHIFT'}},'07_mods')
assert(H.app.view=='mods','mods view')
local mods=H.app:mods_list()
assert(#mods==3,'three mods listed: '..#mods)
local refused=0
for _,m in ipairs(mods)do refused=refused+m.refused end
assert(refused==1,'one refused operation')
-- jump from a mod write to its field
for i,m in ipairs(mods)do if m.id=='mods/someone/eagle_tweaks'then H.app.mod_index=i end end
step({'RIGHT'})
assert(H.app.view=='browse'and H.app:focused_row().key=='st|Eagle 500kg Bomb|'..H.app:focused_row().key:match('|([^|]+)$'),
    'jumped to the eagle cooldown')
assert(H.app:focused_row().field=='stratagem.cooldown','focused the cooldown row')
-- Presets: save the current values
step({'TAB'},{down={'SHIFT'}})
step({'TAB'},{down={'SHIFT'}},'08_presets')
assert(H.app.view=='presets','presets view')
step({'INSERT'})
assert(H.app.rename and H.app.rename.create,'naming a new preset')
step({'TAB'})
assert(#H.presets:list()==1,'preset saved')
step({'DOWN'},nil,'09_preset')
local preset=H.presets:list()[1]
assert(preset.count==2,'preset has two fields: '..preset.count)
-- reset to defaults (asks first)
step({'F10'},nil,'10_confirm')
assert(H.app.confirm and H.app.confirm.kind=='reset','confirm dialog')
step({'ENTER'})
settle(8)
step({},nil,'11_after_reset')
assert(H.sim.value(rof)==1200,'reset returned the mod value 1200: '..tostring(H.sim.value(rof)))
assert(math.abs(H.sim.value(nudged)-nudged.vanilla)<1e-3,'reset returned the nudged field to vanilla')
local active,applying,errors=H.layer:counts()
assert(active==0 and applying==0 and errors==0,'nothing active after reset')
-- load the preset back: it stages, then applies
H.app:load_preset(preset.name)
assert(H.app.pending_n==2,'preset staged two values')
step({'F9'})
settle(6)
assert(H.sim.value(rof)==1300,'preset applied 1300')
-- value fields: a status from the picker, a calldown code, mission uses typed as digits
local function row_where(object_key,pred)
    local o=H.catalog:object(object_key);H.catalog:open(o)
    for _,r in ipairs(o.rows)do if pred(r)then return r end end
    error('no row on '..object_key)
end
local status=row_where('pw|BR-14 Adjudicator',function(r)return r.kind=='choice'and r.field=='damage.status_1_type'end)
H.app:reveal(status)
step({'ENTER'})
assert(H.app.picker and H.app.picker.row==status,'picker open for the status')
step({'DOWN'},nil,'15_picker')
step({'ENTER'})
assert(H.app.picker==nil and H.app.pending[status.key],'status staged')
local code=row_where('st|Eagle Smoke Strike',function(r)return r.kind=='code'end)
H.app:reveal(code)
step({'ENTER'})
assert(H.app.coder and H.app.coder.row==code,'code editor open')
step({'BACKSPACE'});step({'LEFT'})
step({},nil,'16_code')
local edited=H.app.coder.code
assert(edited[#edited]=='left','arrow key appended a direction')
step({'ENTER'})
assert(H.app.pending[code.key],'code staged')
local uses=row_where('st|EXO-55 Breakthrough Exosuit',function(r)return r.kind=='uses'end)
H.app:reveal(uses)
step({'5'})
assert(H.app.picker and H.app.picker.filter=='5','digits open the uses picker filtered')
step({'ENTER'})
assert(H.app.pending[uses.key]and H.app.pending[uses.key].value==5,'5 uses staged')
step({},nil,'17_value_pending')
step({'F9'})
settle(8)
step({},nil,'18_value_applied')
for _,r in ipairs({status,code,uses})do
    assert(H.layer:state(r)=='active',r.label..' active: '..tostring(H.layer:state(r))..' '..tostring((select(2,H.layer:state(r)))))
end
-- a preset keeps non-numeric values (stored by name) and loads them back
H.app.view='presets';step({'INSERT'});step({'TAB'})
local saved=H.presets:list()[#H.presets:list()]
local found=0
for _,item in ipairs(saved.fields)do
    if item.k==code.key and type(item.v)=='table'then found=found+1 end
    if item.k==uses.key and item.v==5 then found=found+1 end
end
assert(found==2,'code and uses stored in the preset: '..found)
H.app.view='browse'
-- Escape closes the window
local closed=false
H.app.ctx.close=function()closed=true end
step({'ESCAPE'})
assert(closed,'Escape closes the editor')
-- search: Ctrl+F, type, filter
H.app:set_view('browse')
H.app.focus='objects'
H.input.pressed={}
step({'F'},{down={'CTRL'}})
assert(H.app.search and H.app.search.active,'search active')
step({'l'})
H.frame({'I'});H.frame({'B'})
step({},nil,'12_search')
-- a big category (Automatons) renders inside the limits
H.app.search=nil
for i,item in ipairs(H.app.categories)do if item.id=='automatons'then H.app:select_category(i)end end
H.app.focus='objects'
step({},nil,'13_automatons')
-- stratagem icons render in the list and the header (when tools/game_icons.py generated them)
for i,item in ipairs(H.app.categories)do if item.id=='offensive'then H.app:select_category(i)end end
H.app.focus='objects'
step({},nil,'19_icons')
H.app.focus='fields'
for _=1,40 do step({'DOWN'})end
step({},nil,'14_enemy_fields')
return 'ui ok ('..frames..' frames)'

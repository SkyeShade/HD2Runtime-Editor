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
-- nudge the next numeric field up by ten steps
for _=1,10 do
    local r=H.app:focused_row()
    if r and not r.kind then break end
    step({'DOWN'})
end
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
-- Changes tab: the two applied editor values, never the mods' own
step({'TAB'},{down={'SHIFT'}},'30_changes')
assert(H.app.view=='changes','changes view')
local changes=H.app:changes()
assert(#changes==2,'two editor changes: '..#changes)
for _,c in ipairs(changes)do assert(c.state=='active','applied: '..tostring(c.state))end
-- Mods tab: the three HD2Runtime mods and the mod manager's asset mod; one refused operation
-- Export: the wizard, step 1 lists the two changes, all picked
step({'TAB'},{down={'SHIFT'}},'38_export_pick')
assert(H.app.view=='export','export view')
local exp_list,x=H.app:export_changes()
assert(#exp_list==2 and x.selected[exp_list[1].row.key]and x.selected[exp_list[2].row.key],'both changes picked')
step({'RIGHT'})
assert(x.step=='details','details step')
-- type a name (letters and digits through the keys), set the version and description
x.field=1
x.meta.name=''
for _,key in ipairs({'L','I','B','SPACE','B','U','F','F'})do step({key})end
assert(x.meta.name=='lib buff','typed the name: '..x.meta.name)
x.meta.name,x.meta.version,x.meta.description='Lib Buff','1.0.0','Faster Liberator.'
-- the image comes from the Windows open-file dialog (stubbed here: no real dialog in tests); the game keeps drawing
-- while it is open, and its answer is picked up by the next frame
local folder=(os.getenv('TEMP')or'.')
local img=folder..'\\hd2r_test_icon.png'
local fi=assert(io.open(img,'wb'));fi:write('\137PNG\r\n\26\n test');fi:close()
local win=require('mods/skyeshade/hd2runtime_editor/editor/win')
local real_pick=win.pick_file
local answer,asked
win.pick_file=function(opts)
    asked=opts
    return {poll=function()return answer end}
end
H.app:export_pick_image()
assert(asked and asked.filter:find('%*%.png'),'the dialog filters images')
step({},nil,'39_export_dialog_open')
assert(x.picking and not x.meta.image,'waiting for the dialog')
answer=img
step({})
assert(x.meta.image==img and not x.picking,'image from the dialog: '..tostring(x.meta.image))
x.meta.image=nil
answer=false
H.app:export_pick_image();step({})
assert(not x.picking and not x.meta.image,'a cancelled dialog leaves no image')
-- without the dialog, the in-game browser lists a folder; picking a file sets the image
win.pick_file=function()return nil,'no FFI'end
H.app:export_pick_image()
assert(x.browser,'falls back to the in-game browser')
win.pick_file=real_pick
H.app:export_browse(folder)
step({},nil,'39_export_browser')
assert(x.browser and#x.browser.entries>0,'browser lists the folder')
local picked
for _,e in ipairs(x.browser.entries)do if e.name=='hd2r_test_icon.png'then picked=e end end
assert(picked,'the test image is listed')
H.app:export_browser_pick(picked)
assert(x.meta.image==img and not x.browser,'image picked')
step({},nil,'40_export_details')
-- export into a temporary folder
local export_module=require('mods/skyeshade/hd2runtime_editor/editor/export')
local real_folder=export_module.folder
export_module.folder=function()return folder..'\\hd2r_test_exports'end
H.app:export_run()
export_module.folder=real_folder
assert(x.step=='done','export done: '..tostring(H.app.toast_msg and H.app.toast_msg.text))
step({},nil,'41_export_done')
assert(x.done.count==2 and x.done.zip:find('Lib%-Buff%-1%.0%.0%.zip$'),'zip: '..tostring(x.done.zip))
local zf=assert(io.open(x.done.zip,'rb'));local zdata=zf:read('*a');zf:close()
assert(zdata:sub(1,4)=='PK\3\4','a zip')
assert(H.presets:find('Lib Buff 1.0.0'),'a preset with the exported values')
os.remove(img)
-- Mods tab: the three HD2Runtime mods and the mod manager's asset mod; one refused operation
step({'TAB'},{down={'SHIFT'}},'07_mods')
assert(H.app.view=='mods','mods view')
local mods=H.app:mods_list()
assert(#mods==4,'four mods listed: '..#mods)
local refused,assets=0,0
for _,m in ipairs(mods)do refused=refused+m.refused;if not m.runtime then assets=assets+1 end end
assert(refused==1,'one refused operation')
assert(assets==1 and mods[#mods].name=='Orbital Laser Colors','the asset mod is listed last')
local tweaks
for _,m in ipairs(mods)do if m.resource=='mods/someone/eagle_tweaks'then tweaks=m end end
assert(tweaks and tweaks.name=='Eagle Tweaks'and tweaks.applied>0,'the manager entry carries the mod values')
-- jump from a mod write to its field
for i,m in ipairs(mods)do if m.resource=='mods/someone/eagle_tweaks'then H.app.mod_index=i end end
step({'RIGHT'})
assert(H.app.view=='browse'and H.app:focused_row().key=='st|Eagle 500kg Bomb|'..H.app:focused_row().key:match('|([^|]+)$'),
    'jumped to the eagle cooldown')
assert(H.app:focused_row().field=='stratagem.cooldown','focused the cooldown row')
-- Presets: save the current values (Browse -> Changes -> Mods -> Custom -> Presets)
for _=1,4 do step({'TAB'},{down={'SHIFT'}})end
assert(H.app.view=='custom','custom view')
step({'TAB'},{down={'SHIFT'}},'08_presets')
assert(H.app.view=='presets','presets view')
step({'INSERT'})
assert(H.app.rename and H.app.rename.create,'naming a new preset')
step({'TAB'})
assert(#H.presets:list()==2,'preset saved (with the export preset)')
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
-- mission uses: 0 or -1 typed means unlimited; a typed count picks that count; Left below the lowest is unlimited
local unl
for _,cat in ipairs({'offensive','defensive','support_weapons','vehicles'})do
    for _,o in ipairs(H.catalog:objects(cat))do
        if not unl then
            H.catalog:open(o)
            for _,r in ipairs(o.rows)do if r.kind=='uses'and r.unlimited and r.vanilla~='unlimited'then unl=r end end
        end
    end
end
assert(unl,'a stratagem that can be made unlimited')
for _,typed in ipairs({'0','-1'})do
    H.app:open_picker(unl,typed)
    local p=H.app.picker
    assert(#p.shown==1 and p.items[p.shown[p.cursor]].value=='unlimited','typing '..typed..' offers unlimited')
    H.app.picker=nil
end
H.app:open_picker(unl,'5')
assert(H.app.picker.items[H.app.picker.shown[H.app.picker.cursor]].value==5,'typing 5 selects 5')
H.app.picker=nil
H.app:stage(unl,unl.min or 1)
H.app:nudge(unl,-1)
assert(H.app.pending[unl.key]and H.app.pending[unl.key].value=='unlimited','Left below the lowest count is unlimited')
H.app:unstage(unl)
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
-- composites: a support weapon with its call-in and hellpod; a backpack with its drone; a vehicle with zones
local function open_object(key)
    local o=assert(H.catalog:object(key),'no '..key);H.catalog:open(o);return o
end
local ac=open_object('sp|AC-8 Autocannon')
local has={}
for _,r in ipairs(ac.rows)do
    local part=r.key:match('^sp|AC%-8 Autocannon|(%w+)')
    has[part]=true
end
assert(has.st and has.sw and has.pod,'support weapon composite: call-in, weapon and hellpod')
assert(H.catalog:object('st|AC-8 Autocannon')==ac and H.catalog:object('sw|AC-8 Autocannon')==ac,'old keys resolve to the composite')
local dog=open_object('sb|AX/AR-23 Guard Dog')
local drone=false
for _,r in ipairs(dog.rows)do if r.group=='Drone Weapon'then drone=true end end
assert(drone,'guard dog carries its drone weapon')
assert(H.catalog:object('bp|AX/AR-23 Guard Dog')==dog,'the backpack key resolves to the backpack stratagem')
-- a vehicle: Damage Zones closed by default, opened by Enter, a zone opened by Enter
local frv=open_object('ve|M-103 Supply FRV')
H.app:reveal(frv.rows[1])
local items,selectable=H.app:field_items(frv)
local zones_index
for s2,index in ipairs(selectable)do if items[index].header=='Damage Zones'then zones_index=s2 end end
assert(zones_index,'a Damage Zones header')
local before=#items
H.app.field=zones_index
step({},nil,'20_vehicle_closed')
step({'ENTER'})
items,selectable=H.app:field_items(frv)
assert(#items>before,'Damage Zones opened')
step({'DOWN'})
step({'ENTER'})
local opened=#H.app:field_items(frv)
assert(opened>#items,'a zone opened')
step({},nil,'21_vehicle_zones')
step({'LEFT'})
assert(#H.app:field_items(frv)<opened,'Left closes the zone')
-- an edit inside a closed group marks the group header, its section and the category
local zone_row
for _,r in ipairs(frv.rows)do if r.group=='Damage Zones'and not r.kind and r.editable then zone_row=r;break end end
assert(H.app:stage(zone_row,zone_row.vanilla+1),'zone field staged')
local marks_header,marks_section
for _,it in ipairs((H.app:field_items(frv)))do
    if it.header=='Damage Zones'then marks_header=H.app:header_marks(it,H.app:markers())end
    if it.header==zone_row.section and it.depth==1 then marks_section=H.app:header_marks(it,H.app:markers())end
end
assert(marks_header and marks_header.pending,'the closed group header shows the pending edit')
assert(not marks_section or marks_section.pending,'its section shows it too')
assert((H.app:markers().category.vehicles or{}).pending,'the category shows it')
step({},nil,'22_group_marks')
H.app:unstage(zone_row)
for _,it in ipairs((H.app:field_items(frv)))do
    if it.header=='Damage Zones'then assert(not H.app:header_marks(it,H.app:markers()).pending,'cleared with the edit')end
end
-- magazines live inside the weapon that uses them
local conc=open_object('pw|AR-23C Liberator Concussive')
local mags=0
for _,r in ipairs(conc.rows)do if r.group=='Magazines'then mags=mags+1 end end
assert(mags>0,'the Concussive carries its magazine options')
-- fire modes and rate-of-fire modes
local p19=open_object('pw|P-19 Redeemer')
local modes,rates
for _,r in ipairs(p19.rows)do if r.kind=='modes'then modes=r end if r.kind=='rates'then rates=r end end
assert(modes and rates,'fire mode and rate rows')
H.app:reveal(modes)
step({'ENTER'})
assert(H.app.moder,'fire mode editor open')
step({'DOWN'});step({'DOWN'});step({'RIGHT'})
step({},nil,'22_modes')
step({'ENTER'})
assert(H.app.pending[modes.key],'fire modes staged: '..tostring(H.app.toast_msg and H.app.toast_msg.text))
H.app:reveal(rates)
step({'ENTER'})
assert(H.app.rater,'rate editor open')
-- the editor opens on the weapon's own rate slot; filling a second slot would need a selector binding (refused with
-- the Runtime's reason), so change the slot it has
local slot=H.app.rater.cursor
step({'9'});step({'0'});step({'0'})
step({},nil,'23_rates')
step({'ENTER'})
assert(H.app.pending[rates.key]and H.app.pending[rates.key].value[slot]==900,'rates staged: '..tostring(H.app.toast_msg and H.app.toast_msg.text))
-- the calldown editor: right-click removes an arrow, DEFAULT restores the native code, the X closes
local smoke=row_where('st|Eagle Smoke Strike',function(r)return r.kind=='code'end)
H.app:reveal(smoke)
step({'ENTER'})
step({})
local n=#H.app.coder.code
H.app.code_tiles[1].rclick()
assert(#H.app.coder.code==n-1,'right-click removed an arrow')
H.app.code_reset.click()
assert(#H.app.coder.code==#smoke.vanilla,'DEFAULT restored the native code')
step({},nil,'24_code_buttons')
H.app.popup_close.click()
assert(H.app.coder==nil,'the X closes the popup')
-- a hellpod slot offers pickups
local pod
for _,r in ipairs(ac.rows)do if r.field=='payload.entity'then pod=r;break end end
H.app:reveal(pod)
step({'ENTER'})
assert(H.app.picker and#H.app.picker.items>5,'pickups offered: '..tostring(H.app.picker and#H.app.picker.items))
step({},nil,'25_pod_picker')
H.app.picker=nil
-- the scrollbar: a click on its track jumps, and dragging follows the mouse
for i,item in ipairs(H.app.categories)do if item.id=='automatons'then H.app:select_category(i)end end
H.app.focus='objects'
step({})
local bar=H.app.scrollbars and H.app.scrollbars.obj_scroll
assert(bar,'the object list has a scrollbar')
local top=H.app.obj_scroll
bar.click(nil,700)
assert(H.app.obj_scroll>top and H.app.drag,'track click scrolled and started a drag')
H.app.drag.move(200)
assert(H.app.obj_scroll<70,'dragging follows the mouse')
H.app.drag=nil
-- the window X closes the editor
local shut=false
H.app.ctx.close=function()shut=true end
local heard=#H_sounds
H.app.btn_close.click()
assert(shut,'the window X closes the editor')
assert(H_sounds[heard+1]=='back'and#H_sounds==heard+1,'the X plays the close sound Escape plays')
assert(H.app.btn_close.sound==false,'and not the click sound')
-- the weapon-group filter: Primary only, the game's groups
for i,item in ipairs(H.app.categories)do if item.id=='primary'then H.app:select_category(i)end end
H.app.focus='objects'
step({})
local groups=H.app:weapon_groups('primary')
assert(groups[1]=='All'and groups[2]=='Assault Rifle','groups in the armory order: '..table.concat(groups,','))
assert(H.app:weapon_groups('offensive')==nil,'no filter on stratagems')
H.app.group_actions['primary|Shotgun'].click()
step({},nil,'26_filter')
for _,o in ipairs(H.app:objects())do assert(o.subtitle=='Shotgun','only shotguns: '..o.name)end
step({'RIGHT'},{down={'CTRL'}})
assert(H.app.weapon_group.primary=='Explosive','Ctrl+Right steps to the next group: '..tostring(H.app.weapon_group.primary))
H.app:set_weapon_group('primary','All')
-- vehicle mounts: swap the Patriot's left arm; its stats section then edits the weapon now mounted
local patriot=open_object('ve|EXO-45 Patriot Exosuit')
local mount
for _,r in ipairs(patriot.rows)do if r.mount_slot=='slot_0'then mount=r end end
assert(mount,'a mount row for slot_0')
local donor
for _,o in ipairs(mount.options(mount))do
    if o.value~=mount.vanilla and o.sub:find('EXO%-49')then donor=o.value;break end
end
assert(donor,'an Emancipator arm among the candidates')
assert(H.app:stage(mount,donor),'swap staged: '..tostring(H.app.toast_msg and H.app.toast_msg.text))
local items=H.app:field_items(patriot)
local swapped_header
for _,it in ipairs(items)do if it.header and it.header:find('now')then swapped_header=it end end
assert(swapped_header,'the arm group names the weapon now mounted')
H.app:reveal(mount)
H.app:toggle(patriot,swapped_header.key,true)
items=H.app:field_items(patriot)
local shared=false
for _,it in ipairs(items)do if it.header and it.header:find('shared with EXO%-49')then shared=true end end
assert(shared,'the donor stats say they are shared with their home vehicle')
step({},nil,'27_mount_swap')
H.app:unstage(mount)
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
-- with generated icons, every stratagem and booster has one (vector library or HUD atlas), except the two items
-- without a call-in stratagem, which have no icon anywhere in the game
local icons=H.app.ctx.icons
if icons then
    local NONE={['SG-88 Break-Action Shotgun']=true,['CQC-72 Entrenchment Tool']=true}
    local missing={}
    for _,id in ipairs({'offensive','defensive','support_weapons','support_backpacks','vehicles','resupply','boosters'})do
        for _,object in ipairs(H.catalog:objects(id))do
            local list=id=='boosters'and icons.boosters or icons.stratagems
            local name=id=='boosters'and object.name or(object.stratagem or object.name)
            -- a vehicle without a stratagem (FRV Super Earth variant, GATER Oil Rig) has no stratagem icon
            local plain=object.key:match('^ve|')and not object.stratagem
            if not list[name]and not NONE[name]and not plain then missing[#missing+1]=id..': '..name end
        end
    end
    assert(#missing==0,'no icon: '..table.concat(missing,', '))
end
for i,item in ipairs(H.app.categories)do if item.id=='support_weapons'then H.app:select_category(i)end end
H.app.obj_scroll=0
step({},nil,'28_support_icons')
for i,item in ipairs(H.app.categories)do if item.id=='boosters'then H.app:select_category(i)end end
step({},nil,'29_booster_icons')
for i,item in ipairs(H.app.categories)do if item.id=='offensive'then H.app:select_category(i)end end
H.app.focus='fields'
for _=1,40 do step({'DOWN'})end
step({},nil,'14_enemy_fields')
-- the Mods tab shows a mod's in-game options with their current values
H.app.mods_cache,H.app.options_cache=nil,nil
H.app:set_view('mods')
local list=H.app:mods_list()
for i,m in ipairs(list)do if m.resource=='mods/someone/eagle_tweaks'then H.app.mod_index=i end end
step({},nil,'34_mod_options')
assert(#list[H.app.mod_index].pages==1 and list[H.app.mod_index].pages[1].options[1].value==4,'options listed')
-- Custom: tune a custom stratagem's cooldown with the keys, then back to its registered values
H.app:set_view('custom')
step({},nil,'31_custom')
assert(#H.app:custom_list()==1,'one custom stratagem')
step({'RIGHT'})
assert(H.app.custom_field==1,'on the cooldown')
step({'RIGHT'})
assert(H_custom.cooldown==305 and H_custom.tuned,'nudged to 305: '..tostring(H_custom.cooldown))
step({'ENTER'});step({'1'});step({'2'});step({'0'});step({'ENTER'})
assert(H_custom.cooldown==120,'typed 120: '..tostring(H_custom.cooldown))
step({},nil,'31_custom_tuned')
step({'DELETE'})
assert(H_custom.cooldown==300 and not H_custom.tuned,'untuned')
step({'ESCAPE'})
assert(H.app.view=='custom'and H.app.custom_field==0,'Escape leaves the fields first')
-- Settings: toggles and a language
H.app:set_view('settings')
step({},nil,'32_settings')
local sounds_on=H.presets:setting('ui_sounds',true)
H.app.settings_index=3
step({'ENTER'})
assert(H.presets:setting('ui_sounds',true)==not sounds_on,'menu sounds toggled')
step({'ENTER'})
local i18n=require('mods/skyeshade/hd2runtime_editor/editor/i18n')
i18n.set({['BROWSE']='DURCHSUCHEN',['SETTINGS']='EINSTELLUNGEN'},'Deutsch')
H.app.tab_actions=nil
step({},nil,'33_language')
i18n.set({},'English')
-- the menu sounds played on clicks and keys
assert(#H_sounds>0,'menu sounds played')
-- the armory's displayed traits editor
H.app:set_view('browse')
local liberator=H.catalog:object('pw|AR-23 Liberator')
H.catalog:open(liberator)
local traits
for _,r in ipairs(liberator.rows)do if r.kind=='traits'then traits=r end end
H.app:reveal(traits)
H.app:begin_edit(traits)
assert(H.app.traiter,'traits editor open')
step({},nil,'35_traits')
H.app:trait_toggle('explosive')
H.app:traits_save()
assert(H.app.pending[traits.key]and#H.app.pending[traits.key].value==2,'traits staged')
H.app:discard()
-- the wheel scrolls a popup's list (a mount's weapon picker: 60 weapons)
local patriot=H.catalog:object('ve|EXO-45 Patriot Exosuit')
H.catalog:open(patriot)
local mount
for _,r in ipairs(patriot.rows)do if r.mount_slot then mount=r;break end end
H.app:reveal(mount)
H.app:begin_edit(mount)
assert(H.app.picker and#H.app.picker.shown>14,'mount picker open')
step({})
local before=H.app.picker.scroll
-- the cursor over the list (screen pixels: the panel is centred at 1080p, the list starts below the filter)
step({},{mouse={x=720,y=420,left=false},wheel=-1})
step({},{mouse={x=720,y=420,left=false},wheel=-1})
assert(H.app.picker.scroll==before+6,'wheel scrolled the picker: '..before..' -> '..H.app.picker.scroll)
step({},{mouse={x=720,y=420,left=false},wheel=1})
assert(H.app.picker.scroll==before+3,'and back up')
H.app.picker=nil
-- the Mods tab: a header above the HD2Runtime mods and one above the other mods
H.app:set_view('mods')
step({},nil,'36_mod_sections')
local headers={}
for _,item in ipairs(H.last.items)do
    if item.k=='t'and(item.s=='HD2RUNTIME MODS'or item.s=='OTHER MODS')then headers[#headers+1]=item.s end
end
assert(#headers==2 and headers[1]=='HD2RUNTIME MODS','section headers: '..table.concat(headers,', '))
-- a custom stratagem takes its carrier group's colour (any_red: offensive)
assert(H.app:custom_tone(H_custom)=='offensive','offensive tone')
assert(H.app:custom_tone({group='sentry'})=='defensive'and H.app:custom_tone({carrier={family='backpack'}})=='support')
-- Logs: a log file followed live, coloured by kind, filtered
local logfile=require('mods/skyeshade/hd2runtime_editor/editor/logfile')
local tmp=(os.getenv('TEMP')or'.')..'\\hd2r_editor_test.log'
local f=assert(io.open(tmp,'wb'))
f:write('[HD2Runtime] HD2Runtime 0.30.0-dev initialized (API 1)\n',
    '[HD2Runtime] patch bad rejected: expect differs from reviewed current value\n',
    '[HD2Runtime] ensure overdrive verified status=APPLIED cycle=1 next=60\n',
    '[HD2Runtime] [mods/skyeshade/hd2runtime_editor] [editor] HD2R Editor ready; press F8 to open\n')
f:close()
H.app.logs=logfile.new(tmp)
H.app:set_view('logs')
step({},nil,'37_logs')
local shown,logs=H.app:log_lines()
assert(#shown==4 and logs.kinds[2]=='error'and logs.kinds[3]=='ok'and logs.kinds[4]=='editor','classified: '..table.concat(logs.kinds,','))
f=assert(io.open(tmp,'ab'));f:write('[HD2Runtime] startup: READY in 3.00 s\n');f:close()
for _=1,40 do step({})end
shown=H.app:log_lines()
assert(#shown==5 and H.app.log_index==5,'followed the new line: '..#shown..' '..tostring(H.app.log_index))
step({'RIGHT'})
shown=H.app:log_lines()
assert(H.app.log_filter=='error'and#shown==1,'errors only')
H.app.log_filter='all'
os.remove(tmp)

-- Reset rules: a value equal to the base (the mod's value over a mod, else the game's) is a reset, and each change
-- in the Changes tab has a RESET button that resets it now. The Liberator's fire rate is held by a mod (1200).
H.app:set_view('browse')
if H.layer:state(rof)~='active'then
    assert(H.app:stage(rof,1300));H.app:apply();settle(6)
end
assert(H.layer:state(rof)=='active','the fire rate holds an editor value')
local base=H.layer:base(rof)
assert(base==1200,'the base is the mod value: '..tostring(base))
-- typing the mod's value stages a reset; applying it gives the field back to the mod
assert(H.app:stage(rof,base))
H.app:set_view('changes')
step({},nil,'31_changes_pending_reset')
local pend
for _,c in ipairs(H.app:changes())do if c.row==rof then pend=c end end
assert(pend and pend.state=='pending'and pend.value==base,'pending reset listed')
H.app:apply();settle(6)
assert(H.layer:state(rof)~='active'and H.layer:overrides()[rof.key]==nil and H.sim.value(rof)==1200,
    'applying the mod value reset the field to it: '..tostring(H.layer:state(rof))..' '..tostring(H.sim.value(rof)))
-- the RESET button: edit again, then reset from the Changes tab without Apply
assert(H.app:stage(rof,1500));H.app:apply();settle(6)
assert(H.sim.value(rof)==1500,'1500 written')
step({},nil,'32_changes_reset_button')
local list=H.app:changes()
local index
for i,c in ipairs(list)do if c.row==rof then index=i end end
assert(index and H.app.change_reset_actions[index],'a RESET button on the change')
H.app.change_reset_actions[index].click()
settle(6)
assert(H.layer:state(rof)~='active'and H.sim.value(rof)==1200,'RESET returned the field to the mod value: '
    ..tostring(H.sim.value(rof)))
for _,c in ipairs(H.app:changes())do assert(c.row~=rof,'the change is gone from the list')end
-- without locally built icons, the game's own HUD icons through HD2Runtime (hd2.resources.game_icon): a stratagem's
-- category layer in its category colour, a booster as the Runtime draws it
do
    local util=require('mods/skyeshade/hd2runtime_editor/editor/util')
    local theme=require('mods/skyeshade/hd2runtime_editor/editor/ui/theme')
    local saved,real_image=H.app.ctx.icons,H.app.canvas.image
    local seen={}
    H.app.canvas.image=function(cv,handle,x,y,w,h,opts)seen[#seen+1]={handle=handle,opts=opts}end
    local strat,boost
    for _,o in ipairs(H.catalog:objects('offensive'))do strat=strat or o end
    for _,o in ipairs(H.catalog:objects('boosters'))do boost=boost or o end
    local SH,BH={game_icon='strat'},{game_icon='boost'}
    H.app.ctx.icons={game=true,stratagems={[strat.stratagem or strat.name]={handle=SH,game=true}},
        boosters={[boost.name]={handle=BH,game=true}}}
    assert(H.app:draw_icon(strat,0,0,40)and H.app:draw_icon(boost,0,0,40))
    assert(seen[1].handle==SH and util.same(seen[1].opts.colours.r,theme.tone.offensive),'stratagem in its category colour')
    assert(seen[2].handle==BH and seen[2].opts.colours==nil,'booster as the Runtime draws it')
    H.app.ctx.icons,H.app.canvas.image=saved,real_image
end
-- a mod's title shows its version once: not again when the name already ends with it
local title=H.app.mod_title
assert(title({name='AMR Fixed 1.0.0',version='1.0.0'})=='AMR Fixed 1.0.0','name ending in the version')
assert(title({name='Roulette v2.1',version='2.1'})=='Roulette v2.1','name ending in v + version')
assert(title({name='Buff (0.6.0)',version='0.6.0'})=='Buff (0.6.0)','name ending in (version)')
assert(title({name='Concussive1100',version='0.6.0'})=='Concussive1100  0.6.0','version appended when missing')
assert(title({name='Mod 11.0',version='1.0'})=='Mod 11.0  1.0','11.0 is not 1.0')
assert(title({name='No version'})=='No version','no version')
return 'ui ok ('..frames..' frames)'

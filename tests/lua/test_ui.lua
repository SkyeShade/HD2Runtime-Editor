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
step({'TAB'},{down={'SHIFT'}})
assert(H.app.view=='search','Shift+Tab: the search tab after browse')
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
-- Presets: save the current values (Browse -> Search -> Changes -> Export -> Mods -> Custom -> Presets)
for _=1,5 do step({'TAB'},{down={'SHIFT'}})end
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
-- reset to defaults (asks first); F10 is HD2Runtime's settings panel (0.30.2), not the editor's
step({'F10'})
assert(not H.app.confirm,'F10 does nothing in the editor')
H.app:ask('reset')
step({},nil,'10_confirm')
assert(H.app.confirm and H.app.confirm.kind=='reset','confirm dialog')
step({'ENTER'})
settle(4)
-- (1.0.1) REVERT ALL marks every field: nothing changes until Apply (F9)
assert(H.sim.value(rof)~=1200 and H.app:reset_mark(rof),'marked, not yet reset')
step({'F9'})
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
    if part then has[part]=true else assert(r.group=='Melee'and r.key:sub(1,3)=='me|')end
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
-- a two-mode weapon carries its underbarrel weapon (a separate entity): the One-Two's launcher rounds and resupply
do
    local one_two=open_object('pw|AR/GL-21 One-Two')
    local ub={}
    for _,r in ipairs(one_two.rows)do if r.group=='Underbarrel Weapon'then ub[r.field]=r end end
    for _,id in ipairs({'rounds.spare_rounds','rounds.rounds_from_supply','rounds.starting_rounds','weapon.fire_rate'})do
        assert(ub[id]and ub[id].editable,'the One-Two underbarrel has '..id)
    end
    local spare=ub['rounds.spare_rounds']
    assert(spare.target().weapon=='AR/GL-21 One-Two / underbarrel','written on the underbarrel weapon')
    local host_spare
    for _,r in ipairs(one_two.rows)do if r.field=='rounds.spare_rounds'and r.group==nil then host_spare=r end end
    assert(not host_spare or host_spare.key~=spare.key and host_spare.loc~=spare.loc,'apart from the rifle\'s own rounds')
    assert(H.app:stage(spare,spare.vanilla+4));H.app:apply();settle(6)
    assert(H.layer:state(spare)=='active'and H.sim.value(spare)==spare.vanilla+4,'the launcher spare rounds applied')
    assert(H.app:stage(spare,spare.vanilla));H.app:apply();settle(6)
    assert(H.layer:state(spare)~='active','and reset')
    local arb,stoker=open_object('pw|AR-11 Arbitrator'),open_object('pw|SMG/FLAM-34 Stoker')
    local n_arb,n_stoker=0,0
    for _,r in ipairs(arb.rows)do if r.group=='Underbarrel Weapon'then n_arb=n_arb+1 end end
    for _,r in ipairs(stoker.rows)do if r.group=='Underbarrel Weapon'then n_stoker=n_stoker+1 end end
    assert(n_arb>=7 and n_stoker>=2,'the Arbitrator and Stoker underbarrels: '..n_arb..' '..n_stoker)
end
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
            -- a vehicle without a stratagem (FRV Super Earth variant, GATER Oil Rig) has no stratagem icon, nor has an
            -- object that is only its explosion (the NUX-223 Hellbomb)
            local plain=object.key:match('^ve|')and not object.stratagem or object.key:match('^ex|')
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
-- uses: unlimited (HD2Runtime 0.30.3: 0 or -1) by typing 0, then 1 by stepping right, unlimited again stepping left
H_custom.uses,H_custom.registered.uses=5,5
H_custom.limits=nil
H.app.custom_cache=nil
step({'DOWN'})
assert(H.app.custom_field==2,'on the uses')
step({'ENTER'});step({'MINUS'});step({'1'});step({'ENTER'})
assert(H_custom.uses==5 and H.app.toast_msg.text:find('0.30.3',1,true),'an older Runtime: refused with why')
H_custom.limits={cooldown={0,600},uses={1,100},unlimited_uses={0,-1}}
H.app.custom_cache=nil
step({'ENTER'});step({'0'});step({'ENTER'})
assert(H_custom.uses==nil and H.app.toast_msg.text:find('unlimited',1,true),'typed 0: unlimited')
step({},nil,'31_custom_unlimited')
step({'RIGHT'})
assert(H_custom.uses==1,'right from unlimited: 1')
step({'LEFT'})
assert(H_custom.uses==nil,'left from 1: unlimited')
step({'ENTER'});step({'MINUS'});step({'1'});step({'ENTER'})
assert(H_custom.uses==nil,'typed -1: unlimited')
step({'DELETE'})
H_custom.uses,H_custom.registered.uses,H_custom.limits=nil,nil,nil
H.app.custom_cache=nil
step({'UP'})
step({'ESCAPE'})
assert(H.app.view=='custom'and H.app.custom_field==0,'Escape leaves the fields first')
-- custom stratagem tunes are editor values: in presets (with readable names), in the saved session, applied again by
-- loading the preset, and returned to their registered values by Reset to defaults
do
    H_custom.limits={cooldown={0,600},uses={1,100},unlimited_uses={0,-1}}
    H_custom.uses,H_custom.registered.uses=4,4
    H.app.custom_cache=nil
    local entry=H.app:custom_list()[1]
    H.app:custom_tune(entry,'cooldown',90)
    H.app:custom_tune(H.app:custom_list()[1],'uses',0)
    local values=H.app:current_values()
    assert(values['custom|pelican_gas|cooldown']==90 and values['custom|pelican_gas|uses']=='unlimited',
        'tunes are current values')
    local stored=H.app:encode_values(values)
    assert(stored['custom|pelican_gas|uses']=='unlimited','and stored as they are (the saved session)')
    H.app:save_preset('Custom Tunes',true)
    local preset=H.presets:find('Custom Tunes')
    assert(preset and preset.count>=2,'a preset holds them')
    -- shown with names, not as unknown fields
    H.app:set_view('presets')
    for i,e in ipairs(H.app:preset_entries())do if e.kind=='preset'and e.preset.name=='Custom Tunes'then H.app.preset_index=i end end
    local d=step({},nil,'62_custom_preset')
    local named,unknown
    for _,it in ipairs(d.items)do
        if it.k=='t'and it.s=='Pelican Gas Support'then named=true end
        if it.k=='t'and it.s:find('Unknown field: custom|',1,true)then unknown=true end
    end
    assert(named and not unknown,'the preset names the custom stratagem')
    -- back to registered, then the preset applies them again
    H.app:custom_untune(H.app:custom_list()[1])
    assert(next(H.app:custom_values())==nil,'untuned: no values')
    H.app:load_preset('Custom Tunes')
    assert(H_custom.cooldown==90 and H_custom.uses==nil,'loading the preset tunes it again')
    -- Reset to defaults untunes it, on Apply (1.0.1); Discard keeps the tune
    H.app:reset_defaults()
    assert(H_custom.tuned and H.app:has_pending(),'REVERT ALL waits for Apply')
    H.app:discard()
    assert(H_custom.tuned and not H.app:has_pending(),'Discard keeps the tune')
    H.app:reset_defaults()
    H.app:apply()
    assert(not H_custom.tuned and next(H.app:custom_values())==nil,'reset to defaults returns it to its registered values')
    H.presets:delete('Custom Tunes')
    H_custom.uses,H_custom.registered.uses,H_custom.limits=nil,nil,nil
    H.app.custom_cache=nil
    H.app:set_view('custom')
end
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
-- a language the overlay's font cannot draw (Chinese: the HD2Runtime font has Latin letters only): counted and shown
do
    local n,sample=i18n.undrawable({BROWSE='浏览',SETTINGS='设置 Réglages'})
    assert(n==4 and#sample==3,'four Chinese characters cannot be drawn, Latin-1 can: '..tostring(n))
    H.app.language_cache={{name='English',count=0},{name='中文',file='zh.txt',count=2,undrawable=4,sample=sample}}
    H.app:set_view('settings')
    local d=step({},nil,'63_language_undrawable')
    local warned
    for _,it in ipairs(d.items)do if it.k=='t'and it.s:find('cannot be drawn yet',1,true)then warned=true end end
    assert(warned,'Settings says the language cannot be drawn')
    H.app.language_cache=nil
end
-- HD2Runtime 0.31.0+ (issue #8): the game's own fonts draw Chinese in any game language; only characters no game font
-- has count (hd2.ui.unsupported), in one call for the whole file
do
    local before=package.loaded['mods/skyeshade/hd2runtime']
    local hd2=before or{}
    package.loaded['mods/skyeshade/hd2runtime']=hd2
    local had=hd2.ui and hd2.ui.unsupported
    hd2.ui=hd2.ui or{}
    local seen
    hd2.ui.unsupported=function(text)seen=text;return text:find('',1,true)and 1 or 0,{''}end
    assert(i18n.drawing()=='game_fonts')
    local n=i18n.undrawable({BROWSE='浏览',SETTINGS='设置 Réglages'})
    assert(n==0 and seen:find('浏览',1,true)and seen:find('设置',1,true),'Chinese draws with the game fonts')
    local m,sample=i18n.undrawable({GREEK=''})
    assert(m==1 and sample[1]=='','Greek is in no game font')
    hd2.ui.unsupported=had
    package.loaded['mods/skyeshade/hd2runtime']=before
    assert(i18n.drawing()=='latin'or before,'restored')
end
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
-- the settle summary is green unless something was rejected; a zero count never makes a line red
local LF=require('mods/skyeshade/hd2runtime_editor/editor/logfile')
assert(LF.classify('1 registered operations settled in 0 s: 1 applied, 0 rejected, 0 other (see earlier lines)')=='ok')
assert(LF.classify('931 registered operations settled in 216 s: 923 applied, 7 rejected, 1 other (see earlier lines)')=='warning')
assert(LF.classify('plan stratagem-plan-2991 REJECTED code=CONFLICT reason=SEMANTIC_CONFLICT')=='error')
assert(LF.classify('import done: 12 loaded, 0 failed')~='error')
assert(LF.classify('scan errors=0 items=40')~='error')
assert(LF.classify('scan errors=3 items=40')=='error')
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
-- the RESET button: edit again, then RESET in the Changes tab marks the field (1.0.1); Apply resets it
assert(H.app:stage(rof,1500));H.app:apply();settle(6)
assert(H.sim.value(rof)==1500,'1500 written')
step({},nil,'32_changes_reset_button')
local list=H.app:changes()
local index
for i,c in ipairs(list)do if c.row==rof then index=i end end
assert(index and H.app.change_reset_actions[index],'a RESET button on the change')
H.app.change_reset_actions[index].click()
settle(6)
assert(H.sim.value(rof)==1500 and H.layer:state(rof)=='active','RESET only marks: 1500 stays until Apply')
H.app:apply()
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
-- the interface size: Settings steps it, every view still fits the screen (the panel gives up height, never width)
do
    local theme=require('mods/skyeshade/hd2runtime_editor/editor/ui/theme')
    H.app:set_view('settings')
    H.app.settings_index=H.app.SETTINGS_TOGGLES+1
    for _=1,6 do step({'RIGHT'})end
    assert(H.app:ui_scale()==1.5,'stepped up to 150%: '..tostring(H.app:ui_scale()))
    step({},nil,'50_scale_settings')
    local k=H.app.ui_scale_now
    assert(k>1.4 and k<=1.5,'the size that fits 1920 x 1080: '..tostring(k))
    assert(theme.panel.w==1260 and theme.panel.h<=1080/k-24 and theme.panel.h>=theme.PANEL_MIN_H,
        'the panel keeps its width, gives up height: '..theme.panel.h)
    assert(math.abs(H.app.canvas.s-k)<1e-9,'drawn at that scale')
    -- the category column scrolls instead of running past the panel: the last category comes into view when chosen
    H.app:set_view('browse')
    assert((H.app.cat_scroll or 0)>=0)
    for i,item in ipairs(H.app.categories)do if item.id=='structures'then H.app:select_category(i)end end
    step({})
    assert((H.app.cat_scroll or 0)>0,'scrolled to the last category')
    for _,view in ipairs({'browse','search','changes','export','mods','custom','presets','logs','settings'})do
        H.app:set_view(view)
        step({},nil,view=='browse'and'51_scale_browse'or nil)
    end
    H.app:set_view('settings');H.app.settings_index=H.app.SETTINGS_TOGGLES+1
    for _=1,8 do step({'LEFT'})end
    assert(H.app:ui_scale()==0.9,'stepped down to 90%')
    step({})
    assert(theme.panel.h==theme.PANEL_H,'full height again')
    H.presets:set_setting('ui_scale',1)
    step({})
end
-- Settings: the open key. Enter waits for a key with the current one held off; a key the editor uses is refused; the
-- new chord is taken once released; a key another mod holds is refused; Esc cancels; Del returns to F8
do
    H.app:set_view('settings');H.app.settings_index=H.app.SETTINGS_TOGGLES+2
    step({'ENTER'})
    assert(H.app.key_capture and H_hotkey.held==true,'waiting for a key, the current one held off')
    step({'UP'})
    assert(H.app.key_capture and not H.app.key_capture.chord and H.app.toast_msg.text:find('already uses',1,true),
        'the editor keys are refused')
    step({'A'})
    assert(not H.app.key_capture.chord and H.app.toast_msg.text:find('Ctrl or Alt',1,true),'a typing key needs Ctrl or Alt')
    step({'F4'},{down={'ALT'}})
    assert(not H.app.key_capture.chord,'not Alt+F4')
    step({'F6'},{down={'CTRL'}},'54_hotkey_capture')
    assert(H.app.key_capture.chord=='Ctrl+F6','the chord: '..tostring(H.app.key_capture.chord))
    step({},{down={'F6','CTRL'}})
    assert(H.app.key_capture and H.app:hotkey()=='F8','taken only once the key is up')
    step({})
    assert(not H.app.key_capture and H.app:hotkey()=='Ctrl+F6'and H_hotkey.held==false,'Ctrl+F6 taken on release')
    step({},nil,'55_hotkey_set')
    local found
    for _,it in ipairs(H.frame({}).items)do if it.k=='t'and it.s:find('Ctrl+F6 close',1,true)then found=true end end
    assert(found,'the footer hint names the new key')
    step({'ENTER'});step({'F7'});step({})
    assert(H.app:hotkey()=='Ctrl+F6'and H.app.toast_msg.text:find('already used by mods/someone/other',1,true),
        'a key another mod holds is refused')
    step({'ENTER'});step({'ESCAPE'})
    assert(not H.app.key_capture and H_hotkey.held==false and H.app.view=='settings','Esc cancels; the window stays')
    step({'DELETE'})
    assert(H.app:hotkey()=='F8','Del returns to F8')
end
-- a weapon HD2Runtime blocks (a duplicate identity) shows its stats as locked rows with the reason; one it no longer
-- blocks is editable (HD2Runtime 0.30.2 resolves the seven 0.30.1 duplicates)
do
    local W=require('hd2runtime/domains/player_weapon_authoring')
    local blocked
    for name,w in pairs(W.weapons)do
        if w.ordinaryWritesBlocked and not w.subweaponOf and(w.slot=='primary'or w.slot=='secondary')
            and(not blocked or name<blocked)then blocked=name end
    end
    if blocked then
        local weapon=H.catalog:object('pw|'..blocked)
        H.catalog:open(weapon)
        local locked,row=0,nil
        for _,r in ipairs(weapon.rows)do
            if not r.editable and r.reason and r.reason:find('two game records',1,true)then
                locked=locked+1
                row=row or r
            end
        end
        assert(row and locked>=5,blocked..': its stats are shown locked with the reason: '..locked)
        assert(weapon.detail and weapon.detail:find('read only',1,true),'the header says so')
        local before=H.app.pending_n
        assert(H.app:stage(row,(type(row.vanilla)=='number'and row.vanilla or 0)+1)==false and H.app.pending_n==before,
            'a locked row cannot be staged')
        for i,item in ipairs(H.app.categories)do if item.id==W.weapons[blocked].slot then H.app:select_category(i)end end
        H.app:set_view('browse')
        H.app:reveal(row)
        step({},nil,'52_locked_weapon')
    else
        local scythe=H.catalog:object('pw|LAS-5 Scythe')
        H.catalog:open(scythe)
        local editable=0
        for _,r in ipairs(scythe.rows)do if r.editable and not r.group then editable=editable+1 end end
        assert(editable>0 and not scythe.detail,'the Scythe is editable once HD2Runtime resolves it: '..editable)
    end
end
-- shared values: rows on different objects that write the same bytes. The index covers the whole catalogue; a value
-- staged through one shows on every other, marks every object, and says what else it changes
do
    local guard=0
    while not H.catalog:index_step(200)do guard=guard+1;assert(guard<1000,'the index completes')end
    assert(H.catalog.indexed)
    local a_row,b_row
    for _,c in ipairs({'primary','secondary'})do
        for _,o in ipairs(H.catalog:objects(c))do
            for _,r in ipairs(o.rows or{})do
                if not a_row and r.editable and not r.kind and r.group=='Magazines'then
                    local others=H.catalog:shared_with(r)
                    if#others>0 and others[1].editable then a_row,b_row=r,others[1]end
                end
            end
        end
    end
    assert(a_row and b_row and a_row.object~=b_row.object and a_row.loc==b_row.loc,'a magazine shared by two weapons')
    local names=H.app:shared_names(a_row)
    assert(names and names:find(b_row.object.name,1,true),'the warning names the other weapon: '..tostring(names))
    local before=H.app.pending_n
    local v=(a_row.vanilla or 1)+1
    assert(H.app:stage(a_row,v))
    assert(H.app.toast_msg and H.app.toast_msg.text:find('also changes',1,true),'a toast warns about the shared value')
    local shown,source=H.app:row_view(b_row)
    assert(source=='pending'and shown==v,'the other weapon shows the pending value: '..tostring(source)..' '..tostring(shown))
    H.app:set_view('browse')
    H.app:reveal(b_row)
    step({},nil,'53_shared_value')
    local m=H.app:markers()
    assert(m.pending[a_row.object.key]and m.pending[b_row.object.key],'both weapons are marked')
    assert(m.row_pending[b_row.key],'and the other weapon\'s row')
    -- staging through the other weapon replaces it: one pending value for the bytes
    assert(H.app:stage(b_row,v+1))
    assert(H.app.pending_n==before+1 and H.app.pending[b_row.key]and not H.app.pending[a_row.key],'one value per location')
    shown=H.app:row_view(a_row)
    assert(shown==v+1,'the first weapon shows the new value')
    H.app:unstage(b_row)
    assert(H.app.pending_n==before)
end
-- ModBuilder: its projects (a library in a temp folder) list under Presets; a project's edits match editor fields by
-- weapon + field, an older project's support key by weapon / role / field, and its custom Lua's hd2.ensure patches by
-- target code; unknown fields are listed with why; STAGE CHOSEN stages the chosen ones. The Export tab saves the
-- changes back as a ModBuilder project (custom Lua) that imports again.
do
    local modbuilder=require('mods/skyeshade/hd2runtime_editor/editor/modbuilder')
    local win=require('mods/skyeshade/hd2runtime_editor/editor/win')
    local base=(os.getenv('TEMP')or'.')..'\\hd2r_mb_test_'..tostring(os.time())
    modbuilder.base=base
    local root=base..'\\HD2RuntimeGUI'
    local id='11111111-2222-4333-8444-555555555555'
    win.mkdir(root..'\\Projects\\'..id)
    local function put(path,text)local f=assert(io.open(path,'wb'));f:write(text);f:close()end
    put(root..'\\library.json',[[{"formatVersion":1,"projects":[{"id":"]]..id..[[","displayName":"Railgun And Rifle",
        "resourceId":"mods/someone/railgun_and_rifle","sdkVersion":"0.28.1","modifiedAt":"2026-09-30T10:00:00+00:00"}]}]])
    put(root..'\\Projects\\'..id..'\\project.hd2mod.json',[[{"formatVersion":11,"id":"]]..id..[[",
        "displayName":"Railgun And Rifle","author":"someone","resourceId":"mods/someone/railgun_and_rifle",
        "version":"1.0.0","sdkVersion":"0.28.1","runtimeApi":1,
        "weaponChanges":[{"weapon":"AR-23P Liberator Penetrator","semanticFieldId":"weapon.fire_rate","fieldType":"number",
            "expectedValue":640,"desiredValue":777,"enabled":true},
          {"weapon":"AR-23P Liberator Penetrator","semanticFieldId":"weapon.made_up","fieldType":"number",
            "expectedValue":1,"desiredValue":2,"enabled":true}],
        "supportChanges":[{"instanceKey":"support-field/v1/rs-422-railgun/projectile-reference/primary/damage-standard-damage/0000000000000000",
            "weapon":"RS-422 Railgun","attackRole":"primary","semanticFieldId":"damage.standard_damage","fieldType":"integer",
            "expectedValue":600,"desiredValue":900,"enabled":true}],
        "customLua":{"enabled":true,"source":"local hd2=require('mods/skyeshade/hd2runtime')\nhd2.ensure({patch={id='x',target=hd2.weapon('AR-23P Liberator Penetrator'),field='weapon.ergonomics',expect=1,value=2}})\nhd2.on_frame(function() end)\n"}}]])
    H.app:set_view('presets')
    H.app.mb_list=nil
    assert(#H.app:mb_projects()==1,'the library lists the project')
    local mb_header=assert(H.app:preset_index_of('mb_header'))
    H.app.preset_index=mb_header
    step({},nil,'56_modbuilder_header')
    H.app.preset_index=mb_header+1
    step({},nil,'57_modbuilder_project')
    local open=H.app.mb_open
    assert(open and not open.error,'read: '..tostring(open and open.error))
    local by={}
    for _,it in ipairs(open.items)do by[(it.row and(it.row.object.name..'|'..tostring(it.row.field))or it.label)]=it end
    local rate=by['AR-23P Liberator Penetrator|weapon.fire_rate']
    assert(rate and rate.selected and rate.value==777,'the weapon change matches')
    local rail
    for _,it in ipairs(open.items)do if it.row and it.row.object.name:find('Railgun',1,true)then rail=it end end
    assert(rail and rail.selected and rail.value==900,'the support change matches by weapon, role and field')
    local unknown=by['AR-23P Liberator Penetrator: weapon.made_up']
    assert(unknown and not unknown.selected and unknown.why,'an unknown field is listed with why')
    local ergo=by['AR-23P Liberator Penetrator|weapon.ergonomics']
    assert(ergo and ergo.why==nil or ergo and ergo.row,'the custom Lua patch matches by target code')
    -- choose none, then one, then stage
    local before=H.app.pending_n
    H.app:mb_action_run(3,H.app:mb_projects()[1])
    rate.selected=true
    H.app:mb_action_run(1,H.app:mb_projects()[1])
    assert(H.app.pending_n==before+1 and H.app.pending[rate.row.key],'only the chosen edit is staged')
    assert(H.app.toast_msg.text:find('Staged 1 values',1,true),'and says so: '..H.app.toast_msg.text)
    -- back to ModBuilder from the Export tab
    H.app:set_view('export')
    local list,x=H.app:export_changes()
    for key in pairs(x.selected)do x.selected[key]=false end
    x.selected[rate.row.key]=true
    x.meta.name,x.meta.version,x.meta.author='Roundtrip From Editor','1.0.0','Tester'
    H.app:export_modbuilder()
    assert(H.app.toast_msg.text:find('ModBuilder project',1,true),'saved: '..H.app.toast_msg.text)
    H.app.mb_list=nil
    local saved
    for _,p in ipairs(H.app:mb_projects())do if p.resource=='mods/tester/roundtrip_from_editor'then saved=p end end
    assert(saved,'the library lists the saved project')
    local items=modbuilder.items(H.catalog,assert(modbuilder.read(saved.id)))
    assert(#items==1 and items[1].row==rate.row and items[1].value==777,'it imports again')
    -- a project ModBuilder owns is never overwritten
    x.meta.name,x.meta.author='Railgun And Rifle','someone'
    H.app:export_modbuilder()
    assert(H.app.toast_msg.text:find('changes of its own',1,true),'refused: '..H.app.toast_msg.text)
    H.app:unstage(rate.row)
    modbuilder.base=nil
    H.app.mb_list=nil
    os.execute('rmdir /s /q "'..base..'" 2>nul')
end
-- armor class tables and the damage curve write game.dll's own data: GAMEGUARD RISK on those rows, a warning on the
-- first stage, none on a kit's piece weights
do
    local classes=H.catalog:object('ar|classes')
    if classes then
        H.catalog:open(classes)
        local row
        for _,r in ipairs(classes.rows)do if r.editable and not row then row=r end end
        assert(row and row.risk=='gameguard','a class value carries the risk')
        assert(classes.detail and classes.detail:find('GameGuard',1,true),'the object says so in the list')
        H.app.gameguard_warned=nil
        assert(H.app:stage(row,row.vanilla+0.5))
        assert(H.app.toast_msg.text:find('GameGuard',1,true),'staging warns: '..H.app.toast_msg.text)
        H.app:set_view('browse')
        H.app:reveal(row)
        local d=step({},nil,'58_gameguard_risk')
        local chip,text
        for _,it in ipairs(d.items)do
            if it.k=='t'and it.s=='GAMEGUARD RISK'then chip=true end
            if it.k=='t'and it.s:find('GameGuard was reported',1,true)then text=true end
        end
        assert(chip and text,'the status bar shows the risk and why')
        H.app:unstage(row)
        local kit
        for _,o in ipairs(H.catalog:objects('armor'))do if o.key~='ar|classes'and o.key~='ar|damage curve'then kit=o;break end end
        H.catalog:open(kit)
        for _,r in ipairs(kit.rows)do assert(r.risk==nil,'kit piece weights are ordinary data')end
    end
end
-- shared preset files: SHARE writes a preset to the shared folder (a temp folder here), the Presets tab lists the
-- folder, a file's values load as pending changes or save as a preset, and a file from elsewhere is imported into it
do
    local preset_files=require('mods/skyeshade/hd2runtime_editor/editor/preset_files')
    local win=require('mods/skyeshade/hd2runtime_editor/editor/win')
    local base=(os.getenv('TEMP')or'.')..'\\hd2r_presets_test_'..tostring(os.time())
    preset_files.base=base..'\\Presets'
    H.app:set_view('presets')
    -- a preset with one field
    local row
    for _,o in ipairs(H.catalog:objects('primary'))do
        H.catalog:open(o)
        for _,r in ipairs(o.rows)do if not row and r.editable and not r.kind and r.field=='weapon.fire_rate'then row=r end end
    end
    assert(H.presets:save('Share Me',{[row.key]=row.vanilla+5}))
    local preset=H.presets:find('Share Me')
    H.app:share_preset(preset)
    assert(H.app.toast_msg.text:find('Shared as',1,true),'shared: '..H.app.toast_msg.text)
    local files=H.app:preset_files()
    assert(#files==1 and files[1].name=='Share-Me','the folder lists it: '..tostring(files[1]and files[1].name))
    local text=preset_files.read_file(files[1].path)
    assert(text:find('"format": "hd2r-editor-preset"',1,true)and text:find(row.object.name,1,true),'a readable file')
    -- the list shows it under its header; its detail reads it
    local header=assert(H.app:preset_index_of('file_header'))
    H.app.preset_index=header
    step({},nil,'59_shared_files_header')
    H.app.preset_index=header+1
    step({},nil,'60_shared_file')
    local open=H.app.pf_open
    assert(open and open.preset and open.preset.values[row.key]==row.vanilla+5,'the file reads back')
    -- LOAD stages it; SAVE AS PRESET keeps it
    local before=H.app.pending_n
    H.app:preset_file_action_run(1,files[1])
    assert(H.app.pending[row.key]and H.app.pending[row.key].value==row.vanilla+5,'LOAD stages the value')
    H.app:unstage(row)
    assert(H.app.pending_n==before)
    H.app:preset_file_action_run(2,files[1])
    assert(H.presets:find('Share Me (2)')or H.presets:find('Share Me 2'),'SAVE AS PRESET keeps it: '..H.app.toast_msg.text)
    -- a file from elsewhere: checked, then copied into the folder; a non-preset file is refused
    local other=base..'\\Elsewhere'
    win.mkdir(other)
    local f=assert(io.open(other..'\\from-a-friend.json','wb'))
    f:write(preset_files.encode('From A Friend',{[row.key]=row.vanilla+7},nil,{editor='0.8.4'}));f:close()
    local path,got=preset_files.import(other..'\\from-a-friend.json',preset_files.folder(),win.mkdir)
    assert(path and got.name=='From A Friend','imported')
    f=assert(io.open(other..'\\not-a-preset.json','wb'));f:write('{"hello":1}');f:close()
    local bad,why=preset_files.import(other..'\\not-a-preset.json',preset_files.folder(),win.mkdir)
    assert(not bad and why:find('not an HD2R Editor preset',1,true),'refused: '..tostring(why))
    H.app.pf_list=nil
    assert(#H.app:preset_files()==2,'both files listed')
    for _,name in ipairs({'Share Me','Share Me (2)','Share Me 2'})do if H.presets:find(name)then H.presets:delete(name)end end
    preset_files.base=nil
    H.app.pf_list=nil
    os.execute('rmdir /s /q "'..base..'" 2>nul')
end
-- HD2Runtime 0.30.2 in the editor: sentry and emplacement projectile swaps (MG-43 / G-16 read-only with the reason),
-- exported and imported through the Lua that reaches their target; a team-reload weapon's own ammunition rows locked
-- (the backpack holds it); the wheel hook install choice shown in the footer and Settings; F10 refused as the open key
do
    local catalog_module=require('mods/skyeshade/hd2runtime_editor/editor/catalog')
    local export=require('mods/skyeshade/hd2runtime_editor/editor/export')
    local modbuilder=require('mods/skyeshade/hd2runtime_editor/editor/modbuilder')
    local VW=require('hd2runtime/domains/vehicle_weapon_authoring')
    if VW.weapons['A/AC-8 Autocannon Sentry / weapon']then
        local function swap_of(name)
            local o=H.catalog:object('st|'..name)
            H.catalog:open(o)
            for _,r in ipairs(o.rows)do if r.field=='attack.projectile'then return r end end
        end
        local ac=swap_of('A/AC-8 Autocannon Sentry')
        assert(ac and ac.editable and ac.kind=='reference','the Autocannon Sentry has a projectile swap')
        local donor
        for _,o in ipairs(ac.options(ac))do if o.label=='PLAS-1 Scorcher'then donor=o.value end end
        assert(donor,'donors offered')
        local ok,acks=catalog_module.probe(ac,donor)
        assert(ok,'the Runtime validator accepts a donor: '..tostring(acks))
        local text=assert(export.operation(catalog_module,{row=ac,value=donor},'x'))
        assert(text:find('projectile_source().target',1,true)and text:find('hd2.attack_output(',1,true),
            'exported through projectile_source(): '..text)
        -- the exported patch imports again by its target code
        local patches=modbuilder.lua_patches("local hd2=require('mods/skyeshade/hd2runtime')\n"
            ..text:gsub('^%-%-[^\n]*\n',''):gsub('add%(function%(%) return ',''):gsub(' end%)\n$',''))
        assert(patches and patches[1]and patches[1].target==ac.target_code,'the target code round-trips: '
            ..tostring(patches and patches[1]and patches[1].target))
        local mg=swap_of('A/MG-43 Machine Gun Sentry')
        assert(mg and not mg.editable and mg.reason:find('magazine',1,true),'MG-43 read-only with the reason')
    end
    -- team-reload ammunition rows: locked, saying the backpack holds it, while the Runtime flags them noEffect
    -- (HD2Runtime 0.30.2 to 0.31.0 rc1); editable own rounds with their note since the 0.31.0 rc2
    local S=require('hd2runtime/domains/support_weapon_authoring')
    local flagged,own
    for _,f in ipairs((S.weapons['AC-8 Autocannon']or{}).fields or{})do
        if f.noEffect then flagged=true end
        if f.semanticFieldId=='rounds.spare_rounds'and type(f.teamReload)=='table'and f.teamReload.ownSpares then
            own=true end
    end
    if flagged or own then
        local o=H.catalog:object('sp|AC-8 Autocannon')
        H.catalog:open(o)
        local spare,start
        for _,r in ipairs(o.rows)do
            if r.field=='rounds.spare_rounds'then spare=r end
            if r.field=='rounds.starting_rounds'then start=r end
        end
        if flagged then
            assert(spare and not spare.editable and spare.reason:find('backpack',1,true),'AC-8 spare rounds locked')
        else
            assert(spare and spare.editable and spare.note and spare.note:find('Most own rounds',1,true),
                'AC-8 spare rounds editable with the own-rounds note: '..tostring(spare and spare.note))
            assert(start and start.editable and start.note:find('Spare rounds',1,true),
                'AC-8 starting rounds capped by Spare rounds: '..tostring(start and start.note))
            assert(spare.descriptor.max==511 and spare.descriptor.acknowledgement=='allow_unverified_effect',
                'the Runtime range and acknowledgement')
            local ok,why=catalog_module.probe(spare,20)
            assert(ok,'the Runtime validator accepts 20 own rounds: '..tostring(why))
        end
    end
    -- the wheel: footer and Settings say it is off; nothing when it works
    H_wheel={native=false,install_option='hook_off',
        notice='GameGuard safety: mouse wheel scrolling is off in mod windows.'}
    H.app.wheel_checked=nil
    H.app:set_view('settings')
    local d=step({},nil,'61_wheel_off_settings')
    local footer,settings
    for _,it in ipairs(d.items)do
        if it.k=='t'and it.s:find('Wheel off',1,true)then footer=true end
        if it.k=='t'and it.s:find('GameGuard safety',1,true)then settings=true end
    end
    assert(footer and settings,'the footer and Settings say the wheel is off')
    H_wheel={native=true,install_option='hook_on'}
    H.app.wheel_checked=nil
    d=step({})
    for _,it in ipairs(d.items)do assert(not(it.k=='t'and it.s:find('Wheel off',1,true)),'nothing when the wheel works')end
    H_wheel=nil
    H.app.wheel_checked=nil
    assert(H.app.hotkey_refusal_fn('F10',false,false,false):find('HD2Runtime',1,true),'F10 is HD2Runtime\'s')
end
-- SEARCH: typing finds objects (never single fields) in every category (a weapon, a sentry, a vehicle, the boosters by
-- their category's name); Enter or one click opens the object in BROWSE, whatever filter BROWSE was left on;
-- Escape clears the query first
do
    H.app:set_view('search')
    local function type_text(text)
        for ch in text:gmatch('.')do step({ch==' 'and'SPACE'or ch:upper()})end
    end
    type_text('sentry')
    local results=H.app:search_results(H.app.gsearch.text)
    local sentry,vehicle
    for _,r in ipairs(results)do
        if r.kind=='object'and r.label=='A/MG-43 Machine Gun Sentry'then sentry=r end
    end
    assert(sentry,'a sentry is found by "sentry": '..#results..' results')
    step({},nil,'64_search_objects')
    step({'DELETE'})
    type_text('maelstrom')
    results=H.app:search_results(H.app.gsearch.text)
    for _,r in ipairs(results)do if r.kind=='object'and r.object.key=='ve|TD-110 Maelstrom'then vehicle=r end end
    assert(vehicle and results[1]==vehicle,'the vehicle is the first result')
    step({'ENTER'})
    assert(H.app.view=='browse'and H.app:object()==vehicle.object,'Enter opens it in BROWSE')
    -- only objects: "liberator projectile" lists no field
    H.catalog:index_step(100000)
    H.app:set_view('search')
    step({'DELETE'})
    type_text('liberator')
    results=H.app:search_results(H.app.gsearch.text)
    for _,r in ipairs(results)do assert(r.kind=='object','only objects are listed: '..tostring(r.label))end
    local liberator
    for i,r in ipairs(results)do if r.label=='AR-23 Liberator'then liberator=i end end
    assert(liberator,'the Liberator is found')
    -- the reported bug: BROWSE left on a weapon type the Liberator is not (a "Shotgun" chip) opened another weapon
    local primary
    for _,c in ipairs(H.app.categories)do if c.id=='primary'then primary=c end end
    local groups=H.app:weapon_groups('primary')or{}
    local other
    for _,g in ipairs(groups)do
        if g~='All'and g~=results[liberator].object.subtitle then other=g;break end
    end
    if other then H.app:set_weapon_group('primary',other)end
    H.app.search={text='breaker'}
    H.app.gsearch.index=liberator
    step({'ENTER'})
    assert(H.app.view=='browse'and H.app:object()==results[liberator].object,
        'Enter opens the Liberator, whatever filter BROWSE was on: '..tostring(H.app:object()and H.app:object().name))
    -- one click opens a result, of THIS query: the rows' actions persist across frames, and a click kept from an
    -- earlier query's first frame opened that query's row (the player's report: "it brings me to another weapon")
    H.app:set_view('search')
    step({'DELETE'})
    type_text('sentry')
    step({})
    step({'DELETE'})
    type_text('maelstrom')
    results=H.app:search_results(H.app.gsearch.text)
    H.app.search_actions[1].click()
    assert(H.app.view=='browse'and H.app:object()==results[1].object,'one click opens a row of this query: '
        ..tostring(H.app:object()and H.app:object().name))
    -- a category by name, from four letters; two letters match names only
    H.app:set_view('search')
    step({'DELETE'})
    type_text('boost')
    results=H.app:search_results(H.app.gsearch.text)
    local boosters=0
    for _,r in ipairs(results)do if r.object.category=='boosters'then boosters=boosters+1 end end
    assert(boosters>=10,'"boost" lists the boosters: '..boosters)
    step({'DELETE'})
    type_text('ar')
    results=H.app:search_results(H.app.gsearch.text)
    for _,r in ipairs(results)do
        assert((r.object.name..' '..tostring(r.object.subtitle or'')..' '
            ..tostring(r.object.search_terms or'')):lower():find('ar',1,true),
            '"ar" matches names and aliases, not categories: '..r.label)
    end
    step({'ESCAPE'})
    assert(H.app.view=='search'and H.app.gsearch.text=='','Escape clears the query first')
end
-- HD2Runtime 0.31.0 (where the Runtime has them): status effects as their own category, beam swaps, support weapon
-- projectile swaps (exported through projectile_source), status choices on vehicle weapons, the Laser Sentry's beam
do
    local catalog_module=require('mods/skyeshade/hd2runtime_editor/editor/catalog')
    local export=require('mods/skyeshade/hd2runtime_editor/editor/export')
    local function rows_of(key)
        local o=H.catalog:object(key)
        if not o then return nil end
        H.catalog:open(o)
        return o.rows
    end
    local fire=rows_of('se|fire')
    if fire then
        local duration,damage
        for _,r in ipairs(fire)do
            if r.field=='status.duration'then duration=r end
            if r.field=='damage.standard_damage'then damage=r end
        end
        assert(duration and duration.editable and damage and damage.section=='Damage while active','fire: duration and damage')
        assert(export.trace(damage.target)=='hd2.status_effect("fire"):damage()','status damage target')
        local constitution=rows_of('se|constitution')
        for _,r in ipairs(constitution or{})do
            if r.field=='status.duration'then assert(r.exact,'a native value outside the range gets exact values')end
        end
    end
    local trident=rows_of('pw|LAS-13 Trident')
    local beam
    for _,r in ipairs(trident or{})do if r.field=='attack.beam'then beam=r end end
    if beam then
        assert(beam.editable and beam.target_code=='hd2.weapon("LAS-13 Trident"):beam_source().target','Trident beam swap')
        local donor
        for _,o in ipairs(beam.options(beam))do if o.label=='LAS-98 Laser Cannon'then donor=o.value end end
        assert(donor and catalog_module.probe(beam,donor),'a beam donor validates')
    end
    local eat=rows_of('sp|EAT-17 Expendable Anti-Tank')
    local swap
    for _,r in ipairs(eat or{})do if r.field=='attack.projectile'and r.target_code then swap=r end end
    if swap then
        local donor
        for _,o in ipairs(swap.options(swap))do if o.label=='EAT-700 Expendable Napalm'then donor=o.value end end
        if donor then
            local text=assert(export.operation(catalog_module,{row=swap,value=donor},'x'))
            assert(text:find('projectile_source("primary").target',1,true),'support swap exported: '..text)
        end
    end
    local patriot=rows_of('ve|EXO-45 Patriot Exosuit')
    local status
    for _,r in ipairs(patriot or{})do if r.kind=='choice'and tostring(r.field):find('status_1_type',1,true)then status=r end end
    local VW=require('hd2runtime/domains/vehicle_weapon_authoring')
    if VW.weapons['A/LAS-98 Laser Sentry / weapon']then
        assert(status,'vehicle weapons have status choices')
        local sentry=rows_of('st|A/LAS-98 Laser Sentry')
        local pulse,sbeam
        for _,r in ipairs(sentry or{})do
            if r.field=='beam.pulse_seconds'then pulse=r end
            if r.field=='attack.beam'then sbeam=r end
        end
        assert(sbeam and pulse and pulse.target_code:find('beam_source().target',1,true),'Laser Sentry beam swap and pulse')
    end
end
-- a translated catalogue (a Chinese file): names, subtitles, sections and values are shown translated, the search
-- finds an object by its English and its translated name, and every frame stays inside the overlay's limits
do
    local i18n=require('mods/skyeshade/hd2runtime_editor/editor/i18n')
    i18n.set({['AR-23 Liberator']='AR-23 解放者',['Assault Rifle']='突击步枪',Damage='伤害',Projectile='弹药',
        On='开',Off='关',['%d fields']='%d 个字段',['Fire rate']='射速'},'中文')
    H.app:set_view('browse')
    local found
    for _,r in ipairs(H.app:search_results('解放者'))do if r.object.name=='AR-23 Liberator'then found=r end end
    assert(found and found.label=='AR-23 解放者','search by the translated name')
    found=nil
    for _,r in ipairs(H.app:search_results('liberator'))do if r.object.key=='pw|AR-23 Liberator'then found=r end end
    assert(found,'search by the English name')
    H.app:goto_object(found.object)
    local d=step({},nil,'64_translated_browse')
    local shown={}
    for _,item in ipairs(d.items)do if item.k=='t'then shown[#shown+1]=item.s end end
    -- (a text the body font lacks characters of is drawn in runs: the Chinese part is a run of its own)
    local all=table.concat(shown,'\n')
    assert(all:find("解放者",1,true)and all:find("突击步枪",1,true),"translated name and subtitle shown: "..all:sub(1,600))
    i18n.set({},'English')
    step({},nil,'65_back_to_english')
end
-- status slots fill in order (HD2Runtime 0.31.2): slot 2 is greyed out until slot 1 holds a status (staged or applied),
-- emptying slot 1 while slot 2 is staged is refused, unstaging slot 1 drops slot 2, a preset stages both
do
    local o=H.catalog:object('pw|GL-15 Evictor');H.catalog:open(o)
    local s={}
    for _,r in ipairs(o.rows)do
        if r.status_slot and r.field:find('^explosion%.')then s[r.status_slot.kind..r.status_slot.n]=r end
    end
    if s.type2 then
        H.app:discard()
        assert(H.app:slot_block(s.type2)and H.app:slot_block(s.strength2)and not H.app:slot_block(s.type1),
            'slot 2 greyed out while slot 1 is empty')
        assert(not H.app:stage(s.type2,'gas_confusion')and not H.app:stage(s.strength2,50),'slot 2 refused first')
        H.app:reveal(s.type2)
        local d=step({},nil,'66_status_slot_in_order')
        local chip,line=false,false
        for _,item in ipairs(d.items)do
            if item.k=='t'and item.s=='IN ORDER'then chip=true end
            if item.k=='t'and tostring(item.s):find('Status 1',1,true)and tostring(item.s):find('fill in order',1,true)then
                line=true
            end
        end
        assert(chip and line,'the window says why slot 2 waits')
        assert(H.app:stage(s.type1,'gas'),'slot 1 staged')
        assert(not H.app:slot_block(s.type2),'slot 2 open once slot 1 is staged')
        assert(H.app:stage(s.type2,'gas_confusion'),'slot 2 staged')
        step({},nil,'67_status_slots_staged')
        assert(not H.app:stage(s.type1,'none'),'emptying slot 1 refused while slot 2 is staged')
        H.app:unstage(s.type1)
        assert(not H.app.pending[s.type2.key],'slot 2 dropped with slot 1')
        assert(H.app:stage_map({[s.type2.key]='gas_confusion',[s.type1.key]='gas'})==0
            and H.app.pending[s.type1.key]and H.app.pending[s.type2.key],'a preset stages both slots')
        H.app:discard()
    end
end
-- the game's own names (HD2Runtime game text API, feature-detected): shown in the game's language, cached per language,
-- searched with the English names too, never the identity; Settings turns them off; a failing call shows English
do
    local util=require('mods/skyeshade/hd2runtime_editor/editor/util')
    local game_names=require('mods/skyeshade/hd2runtime_editor/editor/game_names')
    local lang,calls,broken='de',{},false
    local NAMES={de={['weapon|AR-23 Liberator']='AR-23 Befreier',['stratagem|Eagle 500kg Bomb']='Adler-500-kg-Bombe',
        ['stratagem|M-1000 Maxigun']='M-1000 Maxikanone'},fr={['weapon|AR-23 Liberator']='AR-23 Libérateur'}}
    local fake={text={available=function()return true end,language=function()return lang end,
        name=function(kind,key)
            calls[#calls+1]=kind..'|'..key
            if broken then error('game text unavailable')end
            local name=NAMES[lang]and NAMES[lang][kind..'|'..key]
            if name then return name end
            return nil,'no such name'
        end}}
    assert(not game_names.available({})and game_names.available(fake),'feature detection')
    local names=game_names.new(fake,function()return H.presets:setting('game_names',true)end):install()
    H.app.ctx.game_names=names
    local liberator=H.catalog:object('pw|AR-23 Liberator')
    local eagle=H.catalog:object('st|Eagle 500kg Bomb')
    local maxigun=H.catalog:object('sp|M-1000 Maxigun')
    assert(util.display_name(liberator)=='AR-23 Befreier'and util.display_name(eagle)=='Adler-500-kg-Bombe','game names')
    -- a support weapon by its weapon kind first, then as a stratagem
    assert(util.display_name(maxigun)=='M-1000 Maxikanone','support weapon name through its stratagem')
    local tried={}
    for _,c in ipairs(calls)do tried[c]=true end
    assert(tried['support_weapon|M-1000 Maxigun']and tried['stratagem|M-1000 Maxigun'],'support weapon kinds tried')
    local before=#calls
    util.display_name(liberator)
    assert(#calls==before,'cached')
    local function finds(word,object)
        for _,r in ipairs(H.app:search_results(word))do if r.object==object then return r end end
    end
    assert(finds('befreier',liberator)and finds('liberator',liberator),'search by the game name and by the English one')
    assert(finds('befreier',liberator).label=='AR-23 Befreier','the result shows the game name')
    assert(liberator.key=='pw|AR-23 Liberator'and liberator.name=='AR-23 Liberator','the English name stays the identity')
    H.app:set_view('browse');H.app:goto_object(liberator)
    local d=step({},nil,'68_game_names')
    local shown=false
    for _,item in ipairs(d.items)do if item.k=='t'and item.s=='AR-23 Befreier'then shown=true end end
    assert(shown,'the game name is drawn')
    -- another game language: looked up again when the window opens (refresh), each language cached on its own
    lang='fr'
    assert(names:refresh(),'a new game language')
    assert(util.display_name(liberator)=='AR-23 Libérateur'and util.display_name(eagle)=='Eagle 500kg Bomb',
        'French names, English where the game has none')
    lang='de'
    names:refresh()
    before=#calls
    assert(util.display_name(liberator)=='AR-23 Befreier'and#calls==before,'each language cached')
    -- Settings: off shows the editor's own names at once, and the search follows
    H.app:set_view('settings')
    H.app.settings_index=5
    step({'ENTER'},nil,'69_game_names_off')
    assert(H.presets:setting('game_names',true)==false and util.display_name(liberator)=='AR-23 Liberator','off')
    assert(not finds('befreier',liberator),'the search follows the setting')
    step({'ENTER'})
    assert(util.display_name(liberator)=='AR-23 Befreier','on again')
    -- a failing call: the English name
    broken=true;lang='es'
    names:refresh()
    assert(util.display_name(liberator)=='AR-23 Liberator','a failing call shows English')
    -- the game switching language (UNAVAILABLE): the editor's names until the window opens again, nothing cached
    broken=false;lang='pl'
    local unavailable=true
    local name=fake.text.name
    fake.text.name=function(kind,key)if unavailable then return nil,'UNAVAILABLE','switching'end return name(kind,key)end
    names:refresh()
    assert(util.display_name(eagle)=='Eagle 500kg Bomb'and not names.ready,'not available now')
    unavailable,lang=false,'de'
    assert(names:refresh()and util.display_name(eagle)=='Adler-500-kg-Bombe','available again on the next open')
    fake.text.name=name
    -- without the API (an older Runtime): the editor's own names, Settings says what it needs
    local plain=game_names.new({},function()return true end):install()
    H.app.ctx.game_names=plain
    assert(not plain.ready and util.display_name(liberator)=='AR-23 Liberator','no API, English')
    H.app:set_view('settings')
    d=step({},nil,'70_game_names_unavailable')
    local note=false
    for _,item in ipairs(d.items)do if item.k=='t'and item.s=='needs HD2Runtime 0.31.2'then note=true end end
    assert(note,'Settings says the game names need a newer Runtime')
    util.game_name,util.names_version,H.app.ctx.game_names=nil,nil,nil
end
-- the errors list: a refused value marks its field (ERROR), its object and its category with the red piece; the ERRORS
-- badge (a click) or Ctrl+E lists it with the value, the Runtime's code and reason and where it came from; Enter opens
-- the field in BROWSE with its group opened; Ins writes the list to the log and shows LOGS
do
    local o=H.catalog:object('pw|GL-15 Evictor');H.catalog:open(o)
    local s={}
    for _,r in ipairs(o.rows)do
        if r.status_slot and r.field:find('^explosion%.')then s[r.status_slot.kind..r.status_slot.n]=r end
    end
    if s.type2 then
        H.app:discard()
        -- slot 2 without slot 1, as a preset could ask for it: refused with STATUS_SLOT_GAP when it would apply
        assert(H.layer:set(s.type2,'gas_confusion',{kind='preset',name='Gas kit'}))
        settle(1)
        local _,_,errors=H.layer:counts()
        assert(errors==1 and H.layer:state(s.type2)=='error','one error: '..tostring(errors))
        local m=H.app:markers()
        assert(m.error[o.key]and m.loc_error[s.type2.loc]and m.category[o.category].error,'object and category marked')
        H.app:set_view('browse')
        local d=step({},nil,'71_error_markers')
        local icon,badge=false,nil
        for _,item in ipairs(d.items)do
            if item.k=='i'and item.image=='ui_error'then icon=true end
            if item.k=='t'and item.s=='1 ERROR'then badge=item end
        end
        assert(icon and badge,'the red error piece and the badge are drawn')
        -- Ctrl+E opens the list
        step({'E'},{down={'CTRL'}})
        assert(H.app.errors_popup,'Ctrl+E opens the errors list')
        d=step({},nil,'72_errors_list')
        local texts={}
        for _,item in ipairs(d.items)do if item.k=='t'then texts[#texts+1]=item.s end end
        local all=table.concat(texts,'\n')
        assert(all:find('STATUS_SLOT_GAP',1,true)and all:find('Preset: Gas kit',1,true)
            and all:find(H.app:text(s.type2,'gas_confusion'),1,true)and all:find(s.type2.label,1,true),
            'the list shows code, source, value and field: '..all:sub(1,800))
        -- Enter: the field in BROWSE, its group and section opened, the row selected
        step({'ENTER'})
        assert(not H.app.errors_popup and H.app.view=='browse'and H.app.focus=='fields','opened in BROWSE')
        local row=H.app:focused_row()
        assert(row and row.key==s.type2.key,'the failed row is selected: '..tostring(row and row.key))
        assert(H.app:object()==o,'its object is selected')
        d=step({},nil,'73_error_field')
        local chip=false
        for _,item in ipairs(d.items)do if item.k=='t'and item.s=='ERROR'then chip=true end end
        assert(chip,'the field shows its ERROR chip')
        -- the badge, clicked
        for _,item in ipairs(d.items)do if item.k=='t'and item.s=='1 ERROR'then badge=item end end
        step({},{mouse={x=badge.x+4,y=badge.y,left=false}})
        step({},{mouse={x=badge.x+4,y=badge.y,left=true}})
        step({},{mouse={x=badge.x+4,y=badge.y,left=false}})
        assert(H.app.errors_popup,'a click on the badge opens the list')
        -- Ins: written to the log, LOGS shown on its Errors filter
        local logged={}
        local log=H.app.ctx.log
        H.app.ctx.log=function(text)logged[#logged+1]=text end
        step({'INSERT'})
        H.app.ctx.log=log
        assert(not H.app.errors_popup and H.app.view=='logs'and H.app.log_filter=='error','shown in LOGS')
        assert(#logged==2 and logged[2]:find('STATUS_SLOT_GAP',1,true)and logged[2]:find('Gas kit',1,true),
            'one line per error: '..tostring(logged[2]))
        H.app.log_filter=nil
        -- Esc closes it; resetting the field clears the error and the markers
        H.app:open_errors();step({'ESCAPE'})
        assert(not H.app.errors_popup and H.app.view=='logs','Esc closes only the list')
        H.app:goto_error(H.app:error_list()[1])
        d=step({})
        local function click_reset(d)
            local reset
            for _,item in ipairs(d.items)do if item.k=='t'and item.s=='RESET'then reset=item end end
            assert(reset,'failed field has a visible RESET button')
            step({},{mouse={x=reset.x,y=reset.y,left=false}})
            step({},{mouse={x=reset.x,y=reset.y,left=true}})
            step({},{mouse={x=reset.x,y=reset.y,left=false}})
        end
        local function click_text(d,text)
            local hit
            for _,item in ipairs(d.items)do if item.k=='t'and item.s==text then hit=item end end
            assert(hit,'visible: '..text)
            step({},{mouse={x=hit.x,y=hit.y,left=false}})
            step({},{mouse={x=hit.x,y=hit.y,left=true}})
            step({},{mouse={x=hit.x,y=hit.y,left=false}})
        end
        click_reset(d)
        settle(1)
        -- (1.0.1) RESET marks the failed field: its error stays until Apply; a click on the PENDING RESET tag takes the
        -- mark back, RESET marks it again
        assert(select(3,H.layer:counts())==1 and H.app:has_pending(),'marked: the error stays until Apply')
        click_text(step({}),'PENDING RESET')
        assert(not H.app:has_pending()and select(3,H.layer:counts())==1,'the tag click takes the mark back')
        click_reset(step({}))
        assert(H.app:has_pending(),'marked again')
        H.app:apply()
        settle(1)
        assert(select(3,H.layer:counts())==0 and not H.app:markers().error[o.key],'reset: no error left')
        assert(H.layer:set(s.type2,'gas_confusion',{kind='preset',name='Gas kit'}))
        settle(1);H.app:open_errors()
        click_reset(step({}))
        -- (marked in the errors list too: UNDO there, Apply resets it)
        assert(H.app:has_pending(),'marked from the errors list')
        H.app:apply()
        settle(1)
        assert(#H.app:error_list()==0,'RESET in errors popup did not discard the failed value')
        H.app:close_errors()
        H.app:set_view('browse')
    end
end
-- a used status slot's own stats under the slot (catalog status_children): the TX-41 Sterilizer's child status attacks
-- (primary_status_43 / 45) are slot 1's and slot 2's strength (the same bytes) and their status's shared duration,
-- matched by native identity; no "Primary status 43" section is left; keys unchanged; a duration follows its slot's
-- status (hidden while the slot shows another one, unless it holds a value of yours)
do
    local o=H.catalog:object('sp|TX-41 Sterilizer')
    if o then
        H.catalog:open(o)
        local base='sp|TX-41 Sterilizer|sw|'
        local strength1=H.catalog:row(base..'status.primary_status_43.strength@primary_status_43')
        local duration1=H.catalog:row(base..'status.primary_status_43.duration@primary_status_43')
        local type1=H.catalog:row(base..'damage.primary.status_1_type@primary')
        if strength1 and duration1 and type1 then
            assert(strength1.loc==type1.loc:gsub('@44$','@48'),'slot 1 strength is the child strength (same bytes)')
            assert(strength1.label=='Status 1 strength'and duration1.label=='Status 1 duration (Gas 2, all uses)',
                'labels: '..strength1.label..' / '..duration1.label)
            assert(strength1.section==type1.section and duration1.section==type1.section,'in the slot\'s section')
            for _,section in ipairs(o.sections)do
                assert(not section.label:find('Primary status',1,true),'no child section left: '..section.label)
            end
            H.app:discard()
            assert(H.app:reveal(type1),'the slot is shown')
            local function order()
                local items=H.app:field_items(H.app:object())
                local labels,at={},nil
                for i,item in ipairs(items)do
                    if item.row==type1 then at=i end
                    if at and item.row and i<at+6 then labels[#labels+1]=item.row.label end
                end
                return table.concat(labels,' | ')
            end
            assert(order():find('^Status 1 | Status 1 strength | Status 1 duration %(Gas 2, all uses%) | Status 2 | '
                ..'Status 2 strength | Status 2 duration'),'each slot\'s stats under it: '..order())
            step({},nil,'74_status_slot_stats')
            -- another status in slot 1: its strength stays (the slot's bytes), Gas 2's duration goes
            local other
            for _,l in ipairs(type1.labels)do if l.value~='gas_2'and l.value~='none'then other=l.value;break end end
            assert(H.app:stage(type1,other),'slot 1 changed')
            assert(order():find('^Status 1 | Status 1 strength | Status 2 | '),'the duration follows the status: '..order())
            H.app:discard()
            assert(order():find('Status 1 duration',1,true),'back with its status')
        end
    end
end
-- object pages in categories (ui/sections.lua): Projectile holds everything a round carries, round by round (its type
-- swap first, flight, direct hit and its status slots, impact and expiry explosions with their payload slot first), one
-- set per feed (the AC-8's Flak); Damage only for damage no round carries (a beam's); Handling / Fire, Ammunition,
-- Armory, Hellpod / Call-in last on a weapon's page. A part or a category of one row is that row without a header
-- (its feed or title before its label when needed). Every header collapsible, remembered per kind in the settings,
-- closed headers skipped by the keyboard and marked with what their fields hold.
do
    local function shows(d,text)
        for _,it in ipairs(d.items)do if it.k=='t'and it.s:find(text,1,true)then return true end end
        return false
    end
    local sections=require('mods/skyeshade/hd2runtime_editor/editor/ui/sections')
    -- the page's outline: headers (a part indented) and the rows shown without a header of their own ('* ')
    local function outline(object)
        local out={}
        for _,it in ipairs((H.app:field_items(object)))do
            local pad=string.rep('  ',it.depth or 0)
            if it.header then out[#out+1]=pad..it.header
            elseif it.fold then out[#out+1]=pad..'* '..(it.prefix and(it.prefix..' · ')or'')..it.row.label end
        end
        return out
    end
    local function starts(list,expected,what)
        for i,e in ipairs(expected)do
            assert(list[i]==e,what..': item '..i..' is '..tostring(list[i])..', not '..e..'\n'..table.concat(list,'\n'))
        end
    end
    local function index_of(list,text)for i,t in ipairs(list)do if t==text then return i end end end
    H.app:set_view('browse')
    -- AC-8: the main round, then the Flak round, each with its swap, flight, direct hit and explosion; no Damage
    local ac8=H.catalog:object('sp|AC-8 Autocannon')
    H.app:reveal(ac8.rows[1])
    H.app:set_page_open(ac8,true)
    local list=outline(ac8)
    -- (HD2Runtime 0.31.2: each round's impact and expiry payload slots, the flak's burst its impact explosion)
    local payloads=ac8.payload_slots~=nil
    if payloads then
        starts(list,{'Projectile','  * Projectile','  Flight','  Direct hit','  Direct hit · Status','  Impact explosion',
            '  Impact explosion · Status','  * Expiry payload','  * Flak · Projectile','  Flak · Flight',
            '  Flak · Direct hit','  Flak · Direct hit · Status','  Flak · Impact explosion','  * Flak · Expiry payload',
            'Handling / Fire'},'AC-8')
    else
        starts(list,{'Projectile','  * Projectile','  Flight','  Direct hit','  Direct hit · Status','  Impact explosion',
            '  Impact explosion · Status','  * Flak · Projectile','  Flak · Flight','  Flak · Direct hit',
            '  Flak · Direct hit · Status','  Flak · Explosion','Handling / Fire'},'AC-8')
    end
    assert(not index_of(list,'Damage'),'AC-8: no Damage category (its direct hits are its rounds\')')
    local f,a,ar,c=index_of(list,'Handling / Fire'),index_of(list,'Ammunition'),index_of(list,'Armory'),
        index_of(list,'Hellpod / Call-in')
    assert(f and a and ar and c and f<a and a<ar and ar<c,'AC-8 categories in order: '..table.concat(list,', '))
    assert(index_of(list,'  Call-in')and index_of(list,'  Hellpod'),'AC-8 call-in parts')
    -- a category of one part shows its rows under the category itself (Armory)
    assert(not index_of(list,'  Armory'),'no Armory subsection under Armory')
    -- (the AC-8 page starts with its Projectile header and the main round's swap: a page that starts at Flight is a
    -- scrolled one)
    local items=H.app:field_items(ac8)
    assert(items[1].header=='Projectile'and items[1].depth==0 and items[2].fold and items[2].row.field=='attack.projectile',
        'AC-8: Projectile first, its swap right under it')
    -- the headers COLLAPSE ALL closes: never a part shown without one
    for _,key in ipairs(H.app:page_headers(ac8))do
        assert(key~='c|projectile|Projectile type'and key~='c|projectile|Flak · Projectile type',
            'a part of one row has no header: '..key)
    end
    -- APW-1: swap, flight, direct hit and its status in Projectile
    local apw=H.catalog:object('sp|APW-1 Anti-Materiel Rifle')
    H.app:reveal(apw.rows[1])
    if payloads then
        starts(outline(apw),{'Projectile','  * Projectile','  Flight','  Direct hit','  Direct hit · Status',
            '  * Impact payload','  * Expiry payload','Handling / Fire'},'APW-1')
    else
        starts(outline(apw),{'Projectile','  * Projectile','  Flight','  Direct hit','  Direct hit · Status',
            'Handling / Fire'},'APW-1')
    end
    -- the ammunition supply in one place (0.9.4): the MG-43's capacity heads Ammunition, before its spare, starting and
    -- supply magazines and its reload; Handling / Fire keeps the fire rate
    local mg=H.catalog:object('sp|MG-43 Machine Gun')
    H.app:reveal(mg.rows[1])
    local function under(object,header)
        local fields,inside={},false
        for _,it in ipairs((H.app:field_items(object)))do
            if it.header and(it.depth or 0)==0 then inside=it.header==header
            elseif inside and it.row then fields[#fields+1]=it.row.field end
        end
        return fields
    end
    local ammo,fire=under(mg,'Ammunition'),under(mg,'Handling / Fire')
    assert(ammo[1]=='weapon.capacity'and ammo[2]=='magazine.spare_magazines'and ammo[3]=='magazine.starting_magazines'
        and ammo[4]=='magazine.magazines_from_supply'and ammo[5]=='reload.duration',
        'MG-43 Ammunition: '..table.concat(ammo,', '))
    assert(index_of(fire,'weapon.fire_rate')and not index_of(fire,'weapon.capacity'),
        'MG-43 Handling / Fire: '..table.concat(fire,', '))
    -- a vehicle mount (a group): the capacity in its Ammo & Magazine part, the fire rate alone in Weapon
    local bastion=H.catalog:object('ve|TD-220 Bastion MK XVI')
    if bastion then
        H.app:reveal(bastion.rows[1])
        H.app:toggle(bastion,'g|Weapon · Coaxial MG',true)
        H.app:toggle(bastion,'s|Weapon · Coaxial MG|Ammo & Magazine',true)
        local part,first,rate
        for _,it in ipairs((H.app:field_items(bastion)))do
            if it.header=='Ammo & Magazine'and it.parent=='g|Weapon · Coaxial MG'then part=it end
            if part and not first and it.row and it.parent==part.key then first=it.row end
            if it.row and it.row.field=='weapon.fire_rate'and it.parent=='g|Weapon · Coaxial MG'then rate=it end
        end
        assert(part and first and first.field=='weapon.capacity','Bastion MG: the capacity first in Ammo & Magazine: '
            ..tostring(first and first.field))
        assert(rate and rate.fold and rate.prefix=='Weapon','Bastion MG: the fire rate alone in Weapon')
    end
    -- AR-2 Coyote: no swap; its payload slots alone are rows of Projectile after the direct hit
    local coyote=H.catalog:object('pw|AR-2 Coyote')
    H.app:reveal(coyote.rows[1])
    starts(outline(coyote),{'Projectile','  Flight','  Direct hit','  Direct hit · Status','  * Impact payload',
        '  * Expiry payload','Handling / Fire'},'AR-2')
    -- the Liberator: the projectile swap first, each payload slot a row of Projectile while it is alone
    local lib=H.catalog:object('pw|AR-23 Liberator')
    H.app:reveal(lib.rows[1])
    items=H.app:field_items(lib)
    assert(items[1].header=='Projectile'and items[2].fold and items[2].row and items[2].row.field=='ammunition.projectile'
        and items[2].parent=='c|projectile','Liberator: its swap first: '..tostring(items[2].header))
    local impact
    for _,it in ipairs(items)do if it.row and it.row.field=='terminal.explosion'then impact=impact or it end end
    assert(impact and impact.fold and impact.depth==1 and impact.parent=='c|projectile','the impact payload slot alone')
    -- a beam's damage is no round's: Damage (with its status), and the beam swap first in Beam / Arc
    local las=H.catalog:object('sp|LAS-98 Laser Cannon')
    H.app:reveal(las.rows[1])
    list=outline(las)
    assert(list[1]=='Damage'and not index_of(list,'Projectile'),'LAS-98: Damage first: '..table.concat(list,', '))
    local beam,swap=index_of(list,'  Beam'),index_of(list,'  * Beam')
    assert(beam and(not swap or swap<beam),'LAS-98: the beam swap before the beam: '..table.concat(list,', '))
    -- row keys and sections are unchanged (presentation only)
    for _,r in ipairs(lib.rows)do assert(r.key:find('^pw|AR%-23 Liberator|')or(r.group=='Melee'and r.key:find('^me|AR%-23 Liberator|')),'row key unchanged: '..r.key)end
    assert(sections.classify('Damage · Flak direct hit · Status')=='projectile','classification table')
    assert(sections.classify('Damage · Status')=='damage','a beam\'s damage')
    -- single rows: the layout folds a part of one row (its feed before it), a category of one row is that row alone; a
    -- part that grows gets its header back
    local function row(label)return {label=label}end
    local cats=sections.layout({{label='Projectile · Swap',rows={row('Projectile')}},
        {label='Projectile',rows={row('Projectile velocity'),row('Projectile mass')}},
        {label='Projectile · Flak · Swap',rows={row('Projectile')}},{label='Projectile · Flak',rows={row('Projectile velocity')}},
        {label='Explosion · Impact',rows={{label='Impact payload',field='terminal.explosion'}}},
        {label='Armory',rows={row('Displayed traits')}},{label='Weapon',rows={row('Fire rate')}},
        {label='Handling',rows={row('Ergonomics'),row('Sway multiplier')}}},'support_weapons')
    local by={}
    for _,cat in ipairs(cats)do by[cat.id]=cat end
    local subs={}
    for _,s in ipairs(by.projectile.subs)do subs[#subs+1]=s.title..(s.fold and(' [fold '..tostring(s.prefix)..']')or'')end
    assert(table.concat(subs,', ')=='Projectile type [fold nil], Flight, Impact explosion [fold nil], Flak · Projectile type '
        ..'[fold Flak], Flak · Flight [fold Flak · Flight]','folds: '..table.concat(subs,', '))
    assert(by.armory.plain and by.armory.prefix=='Armory','a category of one row is that row: '..tostring(by.armory.prefix))
    local fire={}
    for _,s in ipairs(by.fire.subs)do fire[s.title]=s end
    assert(not by.fire.plain and not fire.Handling.fold and fire.Weapon.fold and fire.Weapon.prefix=='Weapon',
        'Weapon · Fire rate folded into Handling / Fire')
    cats=sections.layout({{label='Projectile',rows={row('Projectile velocity'),row('Projectile mass')}},
        {label='Explosion · Impact',rows={{label='Impact payload',field='terminal.explosion'},row('Standard damage')}}},
        'primary')
    assert(cats[1].subs[2].title=='Impact explosion'and not cats[1].subs[2].fold,'two rows: a part with its header')
    -- attacks and mounts: a direct hit when its round is on the page; status sections with their own section
    cats=sections.layout({{label='Attack · Delivery 1 projectile · Projectile',rows={row('Speed'),row('Mass')}},
        {label='Attack · Delivery 1 projectile damage · Damage',rows={row('Damage'),row('Durable')}},
        {label='Attack · Delivery 1 projectile impact damage · Explosion',rows={row('Damage'),row('AP')}},
        {label='Attack · Delivery 1 projectile impact damage · Status',rows={row('Status 1'),row('Status 1 strength')}},
        {label='Attack · Beam damage · Damage',rows={row('Damage'),row('Durable')}}},'offensive')
    by={}
    for _,cat in ipairs(cats)do by[cat.id]=cat end
    assert(by.projectile and#by.projectile.subs==4 and by.projectile.subs[2].title=='Attack · Delivery 1 projectile damage'
        and by.projectile.subs[4].title=='Attack · Delivery 1 projectile impact damage · Status',
        'an attack\'s round, direct hit, explosion and its status together')
    assert(by.damage and#by.damage.subs==1 and not by['h:Attack'],'the beam\'s damage stays in Damage')
    -- a part of a group of one row: that row under the group, named by its part (an attachment)
    for _,o in ipairs({coyote,lib})do
        H.app:set_page_open(o,true)
        for _,it in ipairs((H.app:field_items(o)))do
            if it.fold and it.parent and it.parent:sub(1,2)=='g|'then
                assert(it.depth==1 and it.prefix,'a folded attachment row carries its name: '..it.row.label)
            end
        end
    end
    -- indentation: a part's fields start right of the part's title, a folded row with the parts' titles; the DEFAULT,
    -- VALUE and SOURCE columns stay where they are on every row; a click in the indentation selects the row
    H.app:reveal(ac8.rows[1])
    H.app:set_page_open(ac8,true)
    H.app.field_scroll,H.app.field=0,1
    local d=step({},nil,'84_indentation')
    local cat_t
    for _,it in ipairs(d.items)do if it.k=='t'and it.s=='PROJECTILE'and it.font=='title'then cat_t=it end end
    assert(cat_t,'the AC-8 page drawn from its top')
    local function text_at(s)
        for _,it in ipairs(d.items)do
            if it.k=='t'and it.s==s and it.font=='body'and it.x>cat_t.x-30 and it.y>cat_t.y then return it end
        end
    end
    local flight_t,folded_t,velocity_t=text_at('Flight'),text_at('Projectile'),text_at('Projectile velocity')
    assert(flight_t and folded_t and velocity_t,'the AC-8 page drawn from its top')
    local step_x=flight_t.x-cat_t.x
    assert(step_x>0,'a part\'s title right of its category\'s')
    assert(math.abs(folded_t.x-flight_t.x)<=1,'a folded row starts with the parts\' titles: '..folded_t.x..' / '..flight_t.x)
    assert(velocity_t.x-flight_t.x>=step_x*0.5,'a part\'s fields start right of its title: '..velocity_t.x..' / '..flight_t.x)
    local boxes={}
    for _,it in ipairs(d.items)do
        if it.k=='r'and it.c[1]==5 and it.c[2]==7 and it.c[3]==9 and it.c[4]==255 and it.x>cat_t.x then boxes[#boxes+1]=it end
    end
    assert(#boxes>=8,'value boxes drawn: '..#boxes)
    local function right_edge(t)return t.x+d:text_width(t.s,t.size,t.font)end
    local edge
    for _,b in ipairs(boxes)do
        assert(b.x==boxes[1].x and b.w==boxes[1].w,'every value box in the same column: '..b.x..' / '..boxes[1].x)
        -- on its row, left of the box: the name, then the default
        local on={}
        for _,it in ipairs(d.items)do
            if it.k=='t'and it.x<b.x and it.x>cat_t.x-30 and it.y>=b.y-2 and it.y<=b.y+b.h+2 then on[#on+1]=it end
        end
        table.sort(on,function(p,q)return p.x<q.x end)
        local name,default=on[1],on[#on]
        if name and default and name~=default then
            if name.x>default.x then name,default=default,name end
            edge=edge or right_edge(default)
            assert(math.abs(right_edge(default)-edge)<=1,'the DEFAULT column does not move with the indentation: '
                ..default.s)
            assert(right_edge(name)<=default.x+1,'the name ends before the default: '..name.s)
        end
    end
    assert(edge,'defaults drawn')
    -- a click left of an indented name selects that row (the hit area spans the whole row)
    step({},{mouse={x=cat_t.x-4,y=velocity_t.y+4,left=false}})
    step({},{mouse={x=cat_t.x-4,y=velocity_t.y+4,left=true}})
    assert(H.app:focused_row()and H.app:focused_row().field=='projectile.velocity',
        'a click in the indentation selects the row: '..tostring(H.app:focused_row()and H.app:focused_row().field))
    step({},{mouse={x=cat_t.x-4,y=velocity_t.y+4,left=false}})
    -- a long name before a long label: the name is cut first, the label stays whole
    local long=H.app:item_label({row={label='Armor penetration: extreme angle'},
        prefix='Muzzle brake Custom Assault Rifle Large Calibre'},230)
    assert(long:find('... · Armor penetration: extreme angle',1,true),'the name is cut first: '..long)
    -- Enter on a category closes it; the keyboard skips its rows; the choice is saved for every page of that kind
    H.app:reveal(lib.rows[1])
    H.app.focus='fields'
    local _,selectable=H.app:field_items(lib)
    local before=#selectable
    H.app.field=1
    step({'ENTER'},nil,'80_category_closed')
    local after
    items,selectable=H.app:field_items(lib)
    after=#selectable
    assert(after<before and items[selectable[1]].header=='Projectile'and not items[selectable[1]].open,
        'Projectile closed: '..before..' -> '..after)
    assert(items[selectable[2]].header=='Handling / Fire','Down from a closed category goes to the next one')
    local saved=H.store.data.settings and H.store.data.settings.collapsed_sections
    assert(saved and saved['c|projectile']==true,'the closed category is saved')
    local sw=H.catalog:object('sp|GL-21 Grenade Launcher')
    H.app:reveal(sw.rows[1])
    items=H.app:field_items(sw)
    local closed
    for _,it in ipairs(items)do if it.header=='Projectile'then closed=not it.open end end
    assert(closed,'closed on every weapon page')
    -- an edit inside a closed category marks its header
    local vel
    for _,r in ipairs(sw.rows)do if r.field=='projectile.velocity'then vel=r end end
    assert(H.app:stage(vel,(vel.vanilla or 0)+5),'velocity staged')
    for _,it in ipairs((H.app:field_items(sw)))do
        if it.header=='Projectile'then assert(H.app:header_marks(it,H.app:markers()).pending,'closed category marked')end
    end
    H.app:discard()
    -- Ctrl+Down expands everything, Ctrl+Up collapses everything (the page header button too)
    step({'DOWN'},{down={'CTRL'}},'81_expand_all')
    assert(H.app:page_open(sw),'expanded')
    items,selectable=H.app:field_items(sw)
    for _,it in ipairs(items)do if it.header then assert(it.open,'every header open: '..it.header)end end
    step({'UP'},{down={'CTRL'}},'82_collapse_all')
    items,selectable=H.app:field_items(sw)
    for _,index in ipairs(selectable)do assert(items[index].header and items[index].depth==0,'only categories left')end
    assert(shows(step({},nil,'83_collapsed'),'EXPAND ALL'),'the button offers EXPAND ALL')
    H.app.btn_page_open.click()
    assert(H.app:page_open(sw)and shows(step({}),'COLLAPSE ALL'),'the button expands the page')
    -- reveal opens a closed category to show its row
    H.app:set_page_open(sw,false)
    assert(H.app:reveal(vel),'revealed')
    assert(H.app:focused_row()==vel,'the row in a closed category is shown and focused')
    H.app:set_page_open(sw,true)
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

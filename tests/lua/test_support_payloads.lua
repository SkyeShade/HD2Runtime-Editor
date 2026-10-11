-- Support weapon payloads and the payload picker (HD2Runtime 0.31.2), in the window over the real app, layer and
-- Runtime ensure (tests/lua/ui_harness.lua): every published terminal.<role>.<phase>.explosion is an Impact / Expiry
-- payload row in the round's explosion section, per feed (AC-8 "Flak · Expiry payload"); the missiles offer impact only
-- and say why; the picker lists HD2Runtime's payload options by group, searchable, with warning badges, explanations and
-- acknowledgements; a catalogued explosion's package load shows as LOADING, a failed one as ASSET_UNAVAILABLE. On an
-- older Runtime the picker keeps the old donor list. Returns one line per check that ran.
local args=...
local H=assert(loadfile(args.harness))({sim=args.sim})
local app,layer,catalog,S=H.app,H.layer,H.catalog,H.sim
local catalog_module=require('mods/skyeshade/hd2runtime_editor/editor/catalog')
local export=require('mods/skyeshade/hd2runtime_editor/editor/export')
local out={}
local function check(cond,msg)
    if not cond then error('FAILED: '..msg..'\n'..table.concat(S.log,'\n')..'\n'..table.concat(layer.history,'\n'),2)end
end
local function frame(keys)
    local d=H.frame(keys)
    check(#d.refused==0,'the overlay would refuse '..tostring(d.refused[1]))
    check(#d.items<=1024,#d.items..' items (limit 1024)')
    return d
end
local function run(seconds)
    local t=0
    while t<seconds do H.frame({},{dt=0.1});t=t+0.1 end
end
local function texts(d)
    local all={}
    for _,it in ipairs(d.items)do if it.k=='t'then all[#all+1]=it.s end end
    return table.concat(all,'\n')
end
local function open(key)
    local o=assert(catalog:object(key),key)
    catalog:open(o)
    return o
end
local function slot_of(object,role,phase)
    for _,r in ipairs(object.payload_slots or{})do
        if r.swap and r.swap.role==role and r.swap.phase==phase then return r end
    end
end
local function item_of(object,row)
    for _,it in ipairs((app:field_items(object)))do if it.row==row then return it end end
end
local function views(object,slot)
    local list={}
    for _,it in ipairs((app:field_items(object)))do
        if it.row and it.row.shown_by==slot then list[#list+1]=it.row end
    end
    return list
end
local function state(r)local st,why=layer:state(r);return tostring(st)..' '..tostring(why)end

local apw=open('sp|APW-1 Anti-Materiel Rifle')
local impact=slot_of(apw,'primary','impact')
if not impact then
    -- An older HD2Runtime: no support payloads; the primaries' picker keeps its donor list (no groups, no options).
    local coyote=open('pw|AR-2 Coyote')
    local slot=slot_of(coyote,'primary','impact')
    check(slot,'the Coyote\'s impact payload slot')
    check(catalog_module.payload_options(slot)==nil,'no payload options on this Runtime')
    local items=app:picker_items(slot)
    check(#items>1 and items[1].label=='None'and not items[2].group and not items[2].checked,'the old donor list')
    app:open_picker(slot)
    check(app.picker and not app.picker.details,'the old picker')
    frame()
    app.picker=nil
    out[#out+1]='older runtime fallback ok'
    return table.concat(out,'\n')
end

-- 1. The APW-1: an impact and an expiry payload, no explosion of its own, both folded into Projectile.
local expiry=slot_of(apw,'primary','expiry')
check(impact.editable and expiry and expiry.editable,'APW-1 impact and expiry payload rows')
check(impact.label=='Impact payload'and expiry.label=='Expiry payload','labelled as the primaries\' slots')
check(impact.section=='Explosion · Primary impact'and expiry.section=='Explosion · Primary expiry',
    'in the round\'s explosion sections: '..impact.section)
check(impact.shared and impact.unverified and impact.acks.allow_shared and impact.acks.allow_unverified_effect,
    'allow_shared and allow_unverified_effect on every write')
check(expiry.note and expiry.note:find('no lifetime',1,true),'the Runtime\'s note on the expiry: '..tostring(expiry.note))
check(#impact.payload_rows==0,'no explosion of its own')
check(app:reveal(impact),'the impact payload is shown')
frame()
local it=item_of(apw,impact)
check(it and it.fold and it.parent=='c|projectile','folded into Projectile')

-- 2. The picker: HD2Runtime's payload options, own / none first, then by group, with headers, badges and details.
app:open_picker(impact)
local p=app.picker
check(p and p.details,'the payload picker')
check(p.items[1].label=='None'and not p.items[1].group,'None first (no explosion of its own)')
local groups,order={},{}
for _,item in ipairs(p.items)do
    if item.group and not groups[item.group]then groups[item.group]=0;order[#order+1]=item.group end
    if item.group then groups[item.group]=groups[item.group]+1 end
end
check(#p.items>=100,'every payload option: '..#p.items)
local expected={'Weapons','Support weapons','Throwables','Orbitals','Eagles','Hellbombs','Sentries','Mines','Vehicles',
    'Backpacks','Enemies','Other'}
for i,g in ipairs(expected)do check(order[i]==g,'group '..i..' is '..tostring(order[i])..', not '..g)end
check(groups.Hellbombs==2,'two Hellbombs: '..tostring(groups.Hellbombs))
local d=frame()
local shown=texts(d)
check(shown:find('\nWEAPONS\n',1,true),'the first group header drawn')
check(shown:find('CURRENT',1,true),'the current value marked')
-- search: by label, owner and group
local function search(text)
    p.filter=text
    app:picker_filter()
    local list={}
    for _,i in ipairs(p.shown)do list[#list+1]=p.items[i]end
    return list
end
local found=search('g-6 frag')
check(#found>=1 and found[1].label:find('G-6 Frag',1,true),'found by its label')
found=search('hellbombs')
check(#found==2 and found[1].group=='Hellbombs','found by its group: '..#found)
for _,item in ipairs(found)do
    local very
    for _,w in ipairs(item.warnings)do if w=='very_large'then very=true end end
    check(very,'a Hellbomb is VERY LARGE')
end
d=frame()
shown=texts(d)
check(shown:find('VERY LARGE',1,true),'the warning badge drawn')
check(shown:find('it can kill the shooter',1,true),'the highlighted option\'s warning explained')
check(shown:find('Acknowledgements:',1,true)and shown:find('+allow_unverified_reference',1,true),
    'the acknowledgements it adds: '..shown)
found=search('support weapons')
check(#found>=20 and found[1].group=='Support weapons','found by its group\'s name: '..#found)
d=frame()
check(texts(d):find('\nSUPPORT WEAPONS\n',1,true),'its group header drawn')
found=search('Eagle Airstrike')
check(#found>=1 and found[1].group=='Eagles','found by its owner')
found=search('smokescreen')
local smoke=found[1]
check(smoke and#smoke.warnings>=2,'G-89: lingering field, no damage')
found=search('g-6 frag')
local frag=found[1]
check(frag and frag.explosion=='throwable/g6_frag/detonation','the G-6 Frag\'s explosion')
p.cursor=1
app:picker_choose()
check(app.pending[impact.key]and app.pending[impact.key].value.explosion=='throwable/g6_frag/detonation',
    'the grenade explosion staged as the impact payload')
local ok,acks=catalog_module.probe(impact,frag.value)
check(ok and acks.allow_shared and acks.allow_unverified_effect and acks.allow_unverified_reference,
    'the validator asks for allow_shared, allow_unverified_effect and allow_unverified_reference')
out[#out+1]='payload picker ok'

-- 3. The grenade's settings under the slot, as the G-6 page's own rows; the part gets its header.
frame()
local under=views(apw,impact)
check(#under>=9,'the G-6 Frag explosion\'s settings under the slot: '..#under)
local damage
for _,r in ipairs(under)do if r.field=='explosion.damage.standard_damage'then damage=r end end
check(damage and damage.canonical.object.key=='th|G-6 Frag','its damage is the G-6 Frag page\'s row: '
    ..tostring(damage and damage.canonical.object.key))
check(app:row_label(damage):find('G-6 Frag',1,true),'labelled by its explosion: '..app:row_label(damage))
local items=app:field_items(apw)
local header
for _,x in ipairs(items)do if x.header=='Impact explosion'then header=x end end
check(header,'the part gets its header back')
check(app:text(impact,app.pending[impact.key].value):find('G-6 Frag',1,true),'the value named by its label')
out[#out+1]='support payload rows ok'

-- 4. Applied: the package loads first (LOADING), then the payload applies.
S.asset_wait=2
app:apply()
local saw_loading,saw_chip,saw_status=false,false,false
for _=1,60 do
    d=frame()
    if layer:loading(impact)then
        saw_loading=true
        local all=texts(d)
        if all:find('LOADING',1,true)then saw_chip=true end
        if all:find('loads first',1,true)then saw_status=true end
    end
    run(0.1)
    if layer:state(impact)=='active'then break end
end
check(saw_loading,'waiting for the grenade\'s package: '..state(impact))
check(saw_chip,'shown as LOADING on the row')
check(saw_status,'and said in the status line')
for _=1,60 do run(0.5);if layer:state(impact)~='applying'then break end end
check(layer:state(impact)=='active','the payload applied: '..state(impact))
local value=layer:value(impact)
check(type(value)=='table'and value.explosion=='throwable/g6_frag/detonation','the grenade explosion held')
-- the Changes list says LOADING too while a package loads (checked through its state function)
out[#out+1]='loading state ok'

-- 5. A package that does not load: ASSET_UNAVAILABLE, with the reason, in the errors list; the row keeps its value.
S.asset_fail=true
local orbital
for _,o in ipairs(expiry.options(expiry))do if o.group=='Orbitals'and not orbital then orbital=o end end
check(orbital,'an orbital explosion offered')
check(app:stage(expiry,orbital.value),'the orbital explosion staged as the expiry payload')
app:apply()
for _=1,80 do run(0.5);if layer:state(expiry)~='applying'then break end end
local st,why=layer:state(expiry)
check(st=='error'and tostring(why):find('ASSET_UNAVAILABLE',1,true)and tostring(why):find('did not load',1,true),
    'refused: '..state(expiry))
local listed
for _,e in ipairs(layer:errors())do if e.row==expiry and e.code=='ASSET_UNAVAILABLE'then listed=true end end
check(listed,'in the errors list with its code')
check(app:markers().error[apw.key],'error marker on the APW-1')
check(app:row_view(expiry).path=='no_explosion','the row keeps its value')
S.asset_wait,S.asset_fail=nil,nil
out[#out+1]='asset unavailable ok'

-- 6. Presets, the saved session and exports: the catalogued explosion by its name.
local stored=app:encode_values({[impact.key]=frag.value})
check(type(stored[impact.key])=='table'and stored[impact.key].ref=='explosion','stored by its name')
local decoded=select(2,app:decode_value(impact.key,stored[impact.key]))
check(decoded and decoded.explosion=='throwable/g6_frag/detonation','read back')
local source,skipped=export.addon(catalog_module,{{row=impact,value=frag.value}},
    {name='Support Payload',version='1.0.0',resource='mods/t/sp'})
check(#skipped==0,'exported: '..tostring(skipped[1]and skipped[1].why))
check(source:find('hd2.explosion("throwable/g6_frag/detonation")',1,true)
    and source:find('terminal_action("impact")',1,true)and source:find(':current()',1,true)
    and source:find('allow_unverified_reference=true',1,true)and source:find('allow_shared=true',1,true),source)
local ac8=open('sp|AC-8 Autocannon')
local he=slot_of(ac8,'primary','impact')
local enc=catalog_module.encode(he,he.vanilla)
check(enc.ref=='terminal'and enc.resource=='support_weapon','a support weapon\'s own explosion keeps its resource')
local back=catalog_module.decode(catalog,he,enc)
check(back and back.weapon=='AC-8 Autocannon'and back.phase=='impact'and back.path=='explosion','read back as its own')
out[#out+1]='support payload presets ok'
layer:reset(impact)
run(8)

-- 7. The AC-8: its HE round's slots, and the flak's, per feed; the flak's burst is its impact explosion.
local flak_impact,flak_expiry=slot_of(ac8,'programmable','impact'),slot_of(ac8,'programmable','expiry')
check(he and#he.payload_rows>=9,'the HE round\'s impact slot holds its explosion rows')
check(flak_impact and flak_impact.section=='Explosion · Flak · Impact'and flak_expiry
    and flak_expiry.section=='Explosion · Flak · Expiry','the flak\'s slots: '..tostring(flak_impact and flak_impact.section))
check(#(flak_impact.payload_soft or{})>=9 and#flak_impact.payload_rows==0,
    'the flak burst (a catalogued explosion) is its impact explosion, set aside but never locked')
app:reveal(flak_expiry)
frame()
local fit=item_of(ac8,flak_expiry)
check(fit and fit.fold and fit.prefix=='Flak','"Flak · Expiry payload": '..tostring(fit and fit.prefix))
check(app:item_label(fit,600)=='Flak · Expiry payload','labelled '..app:item_label(fit,600))
local shell
for _,o in ipairs(flak_expiry.options(flak_expiry))do
    if not shell and tostring(o.explosion):find('orbital_120mm_he_barrage',1,true)then shell=o end
end
check(shell,'the 120mm barrage shell offered for the flak')
check(app:stage(flak_expiry,shell.value),'the barrage shell staged as the flak\'s expiry payload')
frame()
under=views(ac8,flak_expiry)
check(#under>=5,'the shell\'s settings under the flak\'s expiry slot: '..#under)
local heads={}
for _,x in ipairs(app:field_items(ac8))do if x.header then heads[x.header]=true end end
check(heads['Flak · Expiry explosion'],'the flak\'s expiry part gets its header')
-- the flak's impact naming another explosion: its burst is set aside (not locked: the catalogue edits it as ever)
local burst=flak_impact.payload_soft[1]
check(app:stage(flak_impact,shell.value),'the shell as the flak\'s impact payload too')
local rows={}
for _,x in ipairs(app:field_items(ac8))do if x.row then rows[x.row]=true end end
check(not rows[burst],'the flak burst set aside')
check(not app:fires_block(burst),'but not locked')
app:discard()
out[#out+1]='flak expiry payload ok'

-- 8. The missiles: impact only, and why there is no expiry.
for _,name in ipairs({'FAF-14 Spear','MLS-4X Commando','StA-X3 W.A.S.P. Launcher'})do
    local m=open('sp|'..name)
    check(slot_of(m,'primary','impact'),name..': an impact payload')
    check(not slot_of(m,'primary','expiry'),name..': no expiry payload')
    local note
    for _,r in ipairs(m.rows)do if r.field=='info'and r.section=='Explosion · Primary expiry'then note=r end end
    check(note and note.label=='Expiry payload'and not note.editable and note.reason:find('SeekingMissile lifetime',1,true),
        name..': the Runtime\'s reason for no expiry: '..tostring(note and note.reason))
end
local wasp=open('sp|StA-X3 W.A.S.P. Launcher')
local ws=slot_of(wasp,'primary','impact')
app:open_picker(ws)
check(app.picker.note and app.picker.note[1]:find('RECURSIVE_COMPOSITION',1,true),'the option it refuses, with why')
app.picker=nil
out[#out+1]='missile impact only ok'
return table.concat(out,'\n')

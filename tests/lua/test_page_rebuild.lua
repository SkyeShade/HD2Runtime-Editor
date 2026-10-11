-- A page whose rows change while it is shown, driven as a player does (tests/lua/ui_harness.lua: the real app, layer and
-- Runtime ensure; the keyboard, the value picker and mouse clicks on the drawn rows): a payload slot that grows its
-- explosion's settings and an Impact / Expiry explosion header (picked, switched, None, applied, LOADING, a preset,
-- reset), a projectile swap's donor rows, a status slot's duration and the next slot opening. The page is rebuilt at once
-- and every click lands on the row or header drawn under the mouse: the new header opens and closes, the new rows can
-- be edited, without leaving the page. Returns one line per check that ran.
local args=...
local H=assert(loadfile(args.harness))({sim=args.sim})
local app,layer,catalog,S=H.app,H.layer,H.catalog,H.sim
local catalog_module=require('mods/skyeshade/hd2runtime_editor/editor/catalog')
local out={}
local function check(cond,msg)
    if not cond then error('FAILED: '..msg..'\n'..table.concat(S.log,'\n')..'\n'..table.concat(layer.history,'\n'),2)end
end
local function frame(keys,opts)
    local d=H.frame(keys,opts)
    check(#d.refused==0,'the overlay would refuse '..tostring(d.refused[1]))
    check(#d.items<=1024,#d.items..' items (limit 1024)')
    return d
end
local function run(seconds)
    local t=0
    while t<seconds do frame({},{dt=0.1});t=t+0.1 end
end
local function texts(d)
    local all={}
    for _,it in ipairs(d.items)do if it.k=='t'then all[#all+1]=it.s end end
    return table.concat(all,'\n')
end
local function open(key)
    local o=catalog:object(key)
    if o then catalog:open(o)end
    return o
end
local function slot_of(object,role,phase)
    for _,r in ipairs(object and object.payload_slots or{})do
        if r.swap and r.swap.phase==phase and(role==nil and not r.group or r.swap.role==role)then return r end
    end
end
local function state(r)local st,why=layer:state(r);return tostring(st)..' '..tostring(why)end
-- the page as listed now: the index of a row (or a header by its title), and the item
local function find(object,what)
    local items=app:field_items(object)
    for i,it in ipairs(items)do
        if(type(what)=='string'and it.header==what)or(type(what)=='table'and it.row==what)then return i,it end
    end
end
local function views(object,slot)
    local list={}
    for _,it in ipairs((app:field_items(object)))do
        if it.row and it.row.shown_by==slot then list[#list+1]=it.row end
    end
    return list
end
local function view_field(object,slot,field)
    for _,r in ipairs(views(object,slot))do if r.field==field then return r end end
end
-- A click as the player makes it: on the region the last drawn frame registered for that item (its row, or the value
-- box with box=true), hover, press, release.
-- (the mouse position of an item as the last frame drew it, in screen pixels)
local function locate(object,what,box)
    app.view,app.focus='browse','fields'
    frame()
    local i=find(object,what)
    check(i,'shown: '..tostring(type(what)=='table'and what.key or what))
    -- (scrolled into view through the keyboard selection when it is off the list)
    local action=app.fields_actions and app.fields_actions[i]
    local region
    for _,h in ipairs(app.canvas.hits)do if action and h.action==action then region=h end end
    if not region then
        local _,selectable=app:field_items(object)
        for s,index in ipairs(selectable)do if index==i then app.field=s end end
        frame()
        action=app.fields_actions[i]
        for _,h in ipairs(app.canvas.hits)do if h.action==action then region=h end end
    end
    check(region,'drawn: '..tostring(type(what)=='table'and what.key or what))
    local cv=app.canvas
    local ux=box and(region.x+app.FX.box+10)or(region.x+region.w*0.5)
    local uy=region.y+region.h*0.5
    return {x=(cv.ox+ux)*cv.s,y=(cv.oy+uy)*cv.s}
end
local function click(object,what,box)
    local m=locate(object,what,box)
    frame({},{mouse={x=m.x,y=m.y,left=false}})
    frame({},{mouse={x=m.x,y=m.y,left=true}})
    frame({},{mouse={x=m.x,y=m.y,left=false}})
end
local function focused_item()
    local it=app:focused_item()
    return it and(it.header or(it.row and it.row.key))
end
-- An option's value by its label (or the label it starts: "CB-9 Exploding Crossbow (impact)" on HD2Runtime 0.31.2).
local function option(slot,label)
    for _,o in ipairs(slot.options(slot))do
        if o.label==label or tostring(o.label):find(label,1,true)==1 then return o.value end
    end
end
-- The value picker as the player uses it: Enter on the focused slot, the option by its label, Enter.
local function pick(slot,label)
    -- (selected where it is shown, else revealed: the search, the errors list)
    local i=find(slot.object,slot)
    if i and app:object()==slot.object then
        local _,selectable=app:field_items(slot.object)
        for s,index in ipairs(selectable)do if index==i then app.field=s end end
    else check(app:reveal(slot),'shown: '..slot.key)end
    app.view,app.focus='browse','fields'
    frame()
    frame({'ENTER'})
    local p=app.picker
    check(p and p.row==slot,'the picker opened for '..slot.key)
    local found
    for s,i in ipairs(p.shown)do
        local item=p.items[i]
        if not found and(item.label==label or tostring(item.label):find(label,1,true)==1)then found=s end
    end
    check(found,'offered: '..label)
    p.cursor=found
    frame({'ENTER'})
    check(app.picker==nil,'picked '..label)
end
-- Edits a field through a click on its value box and typed digits; returns the value staged.
local function edit_by_click(object,row)
    click(object,row,true)
    check(app.edit and app.edit.row==row,'a click on its box edits '..row.key..', not '
        ..tostring(app.edit and app.edit.row.key or(app.picker and app.picker.row.key)))
    local value=(row.vanilla or 0)+7
    app.edit.buffer,app.edit.fresh=tostring(value),false
    frame({'ENTER'})
    check(app.edit==nil,'committed')
    return value
end
-- An Impact / Expiry explosion header that grew: open, opened and closed by clicks and by Enter, focus kept.
local function header_works(object,title,first_row)
    local i,head=find(object,title)
    check(head and head.depth==1,'the part has its header: '..title)
    click(object,title)
    _,head=find(object,title)
    check(head and not head.open,'a click on the new header closes it')
    check(focused_item()==title,'and focuses it: '..tostring(focused_item()))
    check(not find(object,first_row),'its rows hidden')
    click(object,title)
    _,head=find(object,title)
    check(head.open and find(object,first_row),'a second click opens it again')
    frame({'ENTER'})
    _,head=find(object,title)
    check(not head.open,'Enter closes it')
    frame({'RIGHT'})
    _,head=find(object,title)
    check(head.open and focused_item()==title,'Right opens it')
end

app:set_view('browse')
app:discard()

-- 1. AR-2 Coyote: the impact payload picked in the picker; its header comes open (nothing remembered closed), the slot
-- stays focused, the header opens and closes by click and key, the explosion's rows edit right away.
local coyote=open('pw|AR-2 Coyote')
local impact=slot_of(coyote,nil,'impact')
check(impact and impact.editable and#impact.payload_rows==0,'the Coyote\'s impact payload slot')
local crossbow=open('pw|CB-9 Exploding Crossbow')
local own_damage
for _,r in ipairs(crossbow.rows)do
    if r.field=='explosion.damage.standard_damage'and r.section=='Explosion · Impact'then own_damage=r end
end
check(own_damage,'the CB-9 page\'s impact damage')
local title
local i0=find(coyote,impact)
pick(impact,'CB-9 Exploding Crossbow')
check(app.pending[impact.key],'staged through the picker')
local damage=view_field(coyote,impact,'explosion.damage.standard_damage')
check(damage and damage.canonical==own_damage,'the CB-9 explosion\'s settings under the slot at once')
local _,slot_item=find(coyote,impact)
for i=find(coyote,impact),1,-1 do
    local it=app:field_items(coyote)[i]
    if it.header then title=it.header;break end
end
check(title=='Impact explosion','in its own part: '..tostring(title))
local hi,head=find(coyote,title)
check(head.open,'the part comes open (nothing remembered closed)')
check(hi==i0,'its header where the slot was')
check(app:focused_row()==impact and slot_item.depth==2,'the slot stays focused, under its header')
check(texts(frame()):find('Impact explosion',1,true),'the header drawn')
header_works(coyote,title,damage)
local value=edit_by_click(coyote,damage)
check(app.pending[own_damage.key]and app.pending[own_damage.key].value==value,'staged on the CB-9 page\'s row')
check((app:row_view(damage))==value,'shown under the slot')
-- a click on the slot's value box opens the picker for the slot, not for what was drawn there before
click(coyote,impact,true)
check(app.picker and app.picker.row==impact,'the slot\'s picker')
app.picker=nil
-- a click made in the very frame the list changes (None staged after the frame it was drawn in): it lands on the row
-- drawn there or on nothing, never on what the new list holds at that index
local m=locate(coyote,damage,true)
check(app:stage(impact,impact.vanilla),'None staged')
frame({},{mouse={x=m.x,y=m.y,left=true}})
frame({},{mouse={x=m.x,y=m.y,left=false}})
check(app.edit==nil and app.picker==nil,'no edit of a row no longer shown: '
    ..tostring(app.edit and app.edit.row.key or app.picker and app.picker.row.key))
check(app:focused_row()==impact,'the slot stays focused')
pick(impact,'CB-9 Exploding Crossbow')
out[#out+1]='picked payload opens and edits ok'

-- 2. Switched to another explosion in the picker: those rows, at once, editable; None: the slot alone again, its own
-- clicks; the header of a part closed before comes back closed, opens with one click.
pick(impact,'R-36 Eruptor')
local r36=view_field(coyote,impact,'explosion.damage.standard_damage')
check(r36 and r36.canonical.object.key=='pw|R-36 Eruptor','the R-36 explosion\'s rows at once')
value=edit_by_click(coyote,r36)
check(app.pending[r36.canonical.key]and app.pending[r36.canonical.key].value==value,'an R-36 row edited at once')
check(app.pending[own_damage.key],'the CB-9 edit stays pending')
pick(impact,'None')
check(not find(coyote,title)and find(coyote,impact)==i0,'None: the slot alone again, where the header was')
check(#views(coyote,impact)==0,'nothing under None')
click(coyote,impact)
check(app:focused_row()==impact,'a click on the slot selects it: '..tostring(focused_item()))
click(coyote,impact,true)
check(app.picker and app.picker.row==impact,'and its box opens its picker')
app.picker=nil
-- (closed, then None from elsewhere: a reset, a preset; the slot is inside the closed part)
pick(impact,'CB-9 Exploding Crossbow')
click(coyote,title)
check(not select(2,find(coyote,title)).open,'closed by a click')
check(app:stage(impact,impact.vanilla),'None while closed')
check(find(coyote,impact)==i0,'the slot alone again')
check(app:reveal(impact)and app:focused_row()==impact,'the folded slot revealed')
pick(impact,'CB-9 Exploding Crossbow')
hi,head=find(coyote,title)
check(head and not head.open and focused_item()==title,'back closed as left, its header focused: '
    ..tostring(head and head.open)..' '..tostring(focused_item()))
click(coyote,title)
check(select(2,find(coyote,title)).open and find(coyote,damage),'one click opens it')
out[#out+1]='payload switch and none ok'

-- 3. COLLAPSE ALL / EXPAND ALL follows the page's headers as they are now (a header that grew counts).
app:discard()
frame()
app:set_page_open(coyote,false)
check(not app:page_open(coyote)and texts(frame()):find('EXPAND ALL',1,true),'EXPAND ALL on a closed page')
app:toggle(coyote,head.key,true)
check(app:stage(impact,option(impact,'CB-9 Exploding Crossbow')),'CB-9 staged on the closed page')
check(app:page_open(coyote),'the grown header is open: COLLAPSE ALL')
check(texts(frame()):find('COLLAPSE ALL',1,true),'the button says so')
app:set_page_open(coyote,true)
out[#out+1]='page open state ok'

-- 4. Applied, then reset: the rows stay through the apply and edit afterwards; a reset takes them away at once.
app:apply()
for _=1,60 do
    run(0.5)
    check(view_field(coyote,impact,'explosion.damage.standard_damage'),'shown through the apply: '..state(impact))
    if layer:state(impact)~='applying'then break end
end
check(layer:state(impact)=='active','applied: '..state(impact))
value=edit_by_click(coyote,damage)
check(app.pending[own_damage.key]and app.pending[own_damage.key].value==value,'an applied payload\'s rows edit')
app:discard()
layer:reset(impact)
run(1)
for _=1,60 do run(0.5);if layer:state(impact)~='applying'then break end end
check(#views(coyote,impact)==0 and not find(coyote,title),'reset: the slot alone at once: '..state(impact))
click(coyote,impact,true)
check(app.picker and app.picker.row==impact,'its box opens its picker after the reset')
app.picker=nil
out[#out+1]='payload applied and reset ok'

-- 5. A preset: the slot and an explosion value staged together; the rows shown and clickable at once.
local cb9=option(impact,'CB-9 Exploding Crossbow')
check(app:reveal(impact),'the slot shown')
frame()
local missing=app:stage_map(app:encode_values({[impact.key]=cb9,[own_damage.key]=own_damage.vanilla+3}),
    {kind='preset',name='Payload preset'})
check(missing==0 and app.pending[impact.key]and app.pending[own_damage.key],'the preset staged both')
check(find(coyote,damage),'its rows at once')
value=edit_by_click(coyote,damage)
check(app.pending[own_damage.key].value==value,'and they edit')
click(coyote,title)
check(not select(2,find(coyote,title)).open,'the preset\'s header closes by a click')
click(coyote,title)
app:discard()
out[#out+1]='preset payload ok'

-- 6. A support weapon (HD2Runtime 0.31.2): the APW-1's grenade explosion picked, waiting for its package (LOADING) and
-- applied, its rows shown and editable throughout; the AC-8 flak's expiry slot ("Flak · Expiry explosion").
local apw=open('sp|APW-1 Anti-Materiel Rifle')
local apw_impact=slot_of(apw,'primary','impact')
if apw_impact and catalog_module.payload_options and catalog_module.payload_options(apw_impact)then
    pick(apw_impact,'G-6 Frag')
    local frag_damage=view_field(apw,apw_impact,'explosion.damage.standard_damage')
    check(frag_damage,'the G-6 Frag\'s settings under the APW-1 slot at once')
    header_works(apw,'Impact explosion',frag_damage)
    S.asset_wait=2
    app:apply()
    local loading=false
    for _=1,60 do
        local d=frame()
        if layer:loading(apw_impact)then
            loading=true
            check(texts(d):find('LOADING',1,true),'LOADING drawn while the package loads')
            check(view_field(apw,apw_impact,'explosion.damage.standard_damage'),'its rows shown while LOADING')
        end
        run(0.1)
        if layer:state(apw_impact)=='active'then break end
    end
    check(loading,'waited for the package')
    for _=1,60 do run(0.5);if layer:state(apw_impact)~='applying'then break end end
    check(layer:state(apw_impact)=='active','applied: '..state(apw_impact))
    S.asset_wait=nil
    value=edit_by_click(apw,frag_damage)
    check(app.pending[frag_damage.canonical.key].value==value,'the grenade\'s explosion edits after the apply')
    app:discard()
    layer:reset(apw_impact)
    for _=1,60 do run(0.5);if layer:state(apw_impact)~='applying'then break end end
    local ac8=open('sp|AC-8 Autocannon')
    local flak_expiry=slot_of(ac8,'programmable','expiry')
    check(flak_expiry,'the AC-8 flak\'s expiry slot')
    pick(flak_expiry,'G-6 Frag')
    local flak_damage=view_field(ac8,flak_expiry,'explosion.damage.standard_damage')
    check(flak_damage,'the grenade\'s settings under the flak\'s expiry slot')
    header_works(ac8,'Flak · Expiry explosion',flak_damage)
    value=edit_by_click(ac8,flak_damage)
    check(app.pending[flak_damage.canonical.key].value==value,'edited at once on the AC-8')
    pick(flak_expiry,'None')
    check(not find(ac8,'Flak · Expiry explosion')and#views(ac8,flak_expiry)==0,'None on the AC-8')
    click(ac8,flak_expiry,true)
    check(app.picker and app.picker.row==flak_expiry,'the flak slot\'s own picker')
    app.picker=nil
    app:discard()
    out[#out+1]='support payload rebuild ok'
end

-- 7. A projectile swap: the donor's rows ("Fires", its stats, the link) appear at once and every click lands on the row
-- drawn there; the swap back to its own projectile brings the own rows back, clickable.
local object,swap
for _,key in ipairs({'sp|LAS-99 Quasar Cannon','pw|BR-14 Adjudicator'})do
    local o=open(key)
    for _,r in ipairs(o and o.swap_rows or{})do if r.swap_scope=='attack:primary'and r.editable then swap=r end end
    if swap then object=o;break end
end
if swap then
    local donor
    for _,o in ipairs(swap.options(swap))do
        if catalog_module.donor_of(swap,o.value)and catalog_module.probe(swap,o.value)then donor=donor or o end
    end
    check(donor,'a donor')
    pick(swap,donor.label)
    local fires,first_info
    for _,it in ipairs((app:field_items(object)))do
        if it.row and it.row.fires_info and it.row.label=='Fires'then fires=it.row end
        if it.row and it.row.info and it.row~=fires and not first_info and it.row.key:find('|flight.',1,true)then
            first_info=it.row
        end
    end
    check(fires,'the Fires row at once')
    click(object,fires)
    check(app:focused_row()==fires,'a click on Fires selects it: '..tostring(focused_item()))
    if first_info then
        click(object,first_info)
        check(app:focused_row()==first_info,'a click on a donor stat selects it: '..tostring(focused_item()))
    end
    pick(swap,(swap.options(swap)[1]or{}).label)
    local own=swap.fires_rows[1]
    for _,r in ipairs(swap.fires_rows)do if r.editable and not r.kind and find(object,r)then own=r;break end end
    check(find(object,own),'the own rows back at once')
    value=edit_by_click(object,own)
    check(app.pending[own.key]and app.pending[own.key].value==value,'an own projectile row edits again at once')
    app:discard()
    out[#out+1]='swap rebuild ok'
end

-- 8. Status slots (HD2Runtime 0.31.2): slot 1 picked shows its duration under it and opens slot 2 (no longer IN
-- ORDER), both clickable at once.
local evictor=open('pw|GL-15 Evictor')
local s={}
for _,r in ipairs(evictor and evictor.rows or{})do
    if r.status_slot and r.field:find('^explosion%.')then s[r.status_slot.kind..r.status_slot.n]=r end
end
if s.type2 then
    app:discard()
    app:set_page_open(evictor,true)
    check(app:slot_block(s.type2),'slot 2 waits for slot 1')
    local before=find(evictor,s.duration1)
    local gas
    for _,o in ipairs(s.type1.options(s.type1))do if o.value=='gas'then gas=o.label end end
    check(gas,'the gas status offered')
    pick(s.type1,gas)
    check(app.pending[s.type1.key],'slot 1 staged through the picker')
    check(not app:slot_block(s.type2),'slot 2 open at once')
    if s.duration1 and s.duration1.status_child then
        check(not before and find(evictor,s.duration1),'slot 1\'s duration shown at once')
        value=edit_by_click(evictor,s.duration1)
        check(app.pending[s.duration1.key].value==value,'the duration edits at once')
    end
    click(evictor,s.type2,true)
    check(app.picker and app.picker.row==s.type2,'slot 2\'s picker opens at once')
    app.picker=nil
    app:discard()
    out[#out+1]='status slot rebuild ok'
end
return table.concat(out,'\n')

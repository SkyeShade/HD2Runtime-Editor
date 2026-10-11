-- What a payload slot sets off, in the window, over the real app, layer and Runtime ensure (tests/lua/ui_harness.lua):
-- the settings of the explosion an impact or expiry payload names (staged or applied) are shown under the slot, in its
-- own subsection, as views of that explosion's rows on its owner's page (the same keys and bytes: shared with every
-- weapon that sets it off); they switch with the slot, go with None, are never shown twice, and a weapon's own
-- explosion rows are set aside while its slot names another explosion. Returns one line per check that ran.
local args=...
local H=assert(loadfile(args.harness))({sim=args.sim})
local app,layer,catalog,S=H.app,H.layer,H.catalog,H.sim
local catalog_module=require('mods/skyeshade/hd2runtime_editor/editor/catalog')
local util=require('mods/skyeshade/hd2runtime_editor/editor/util')
local out={}
local function check(cond,msg)
    if not cond then error('FAILED: '..msg..'\n'..table.concat(S.log,'\n')..'\n'..table.concat(layer.history,'\n'),2)end
end
local function frame(keys)
    local d=H.frame(keys)
    check(#d.refused==0,'the overlay would refuse '..tostring(d.refused[1]))
    return d
end
local function run(seconds)
    local t=0
    while t<seconds do H.frame({},{dt=0.1});t=t+0.1 end
end
local function open(key)
    local o=assert(catalog:object(key),key)
    catalog:open(o)
    return o
end
local function slot_of(object,phase)
    for _,r in ipairs(object.payload_slots or{})do if r.swap and r.swap.phase==phase and not r.group then return r end end
end
-- (by its weapon's name: "CB-9 Exploding Crossbow", or the payload option "CB-9 Exploding Crossbow (impact)" of
-- HD2Runtime 0.31.2)
local function option(slot,label)
    for _,o in ipairs(slot.options(slot))do
        if o.label==label or o.label==label..' (impact)'then return o.value end
    end
end
-- the page as shown: its items, the views under each slot (by field), and the subsection holding a row
local function page(object)
    local items=app:field_items(object)
    local views,rows={},{}
    for i,it in ipairs(items)do
        if it.row then
            rows[it.row]=i
            if it.row.shown_by then
                local by=views[it.row.shown_by]or{}
                views[it.row.shown_by]=by
                by[it.row.field]=it.row
                by[#by+1]=it.row
            end
        end
    end
    return items,views,rows
end
local function subsection(items,index)
    for i=index,1,-1 do if items[i].header and(items[i].depth or 0)==1 then return items[i]end end
end

local coyote=open('pw|AR-2 Coyote')
local impact,expiry=slot_of(coyote,'impact'),slot_of(coyote,'expiry')
check(impact and expiry and impact.editable,'the AR-2 Coyote has impact and expiry payload slots')
check(#impact.payload_rows==0,'the Coyote has no explosion of its own')
local cb9=option(impact,'CB-9 Exploding Crossbow')
local eruptor=option(impact,'R-36 Eruptor')
check(cb9 and eruptor,'the CB-9 and R-36 explosions are offered')
check(catalog_module.probe(impact,cb9),'the validator takes the CB-9 explosion as the Coyote\'s impact payload')
local crossbow=open('pw|CB-9 Exploding Crossbow')
local own_damage
for _,r in ipairs(crossbow.rows)do
    if r.field=='explosion.damage.standard_damage'and r.section=='Explosion · Impact'then own_damage=r end
end
check(own_damage and own_damage.editable,'the CB-9 page has its impact explosion damage')
check(app:reveal(impact),'the Coyote\'s impact payload is shown')
frame()
local _,views=page(coyote)
check(views[impact]==nil and views[expiry]==nil,'nothing under None')
-- (a slot alone is a single row: shown in Projectile without an "Impact explosion" header)
local function header_of(items,title)for _,it in ipairs(items)do if it.header==title then return it end end end
local function item_of(items,row)for _,it in ipairs(items)do if it.row==row then return it end end end
local items0=page(coyote)
check(not header_of(items0,'Impact explosion')and item_of(items0,impact).fold,'the slot alone: a row without a header')
check(app:focused_row()==impact,'the slot focused')

-- 1. Staged: the CB-9 explosion's settings under the slot, in its subsection, keyed as on the CB-9 page.
check(app:stage(impact,cb9),'CB-9 explosion staged as the impact payload')
frame()
local items,rows
items,views,rows=page(coyote)
local shown=views[impact]
check(shown and#shown>=9,'the CB-9 explosion\'s settings are shown under the slot: '..tostring(shown and#shown))
local damage=shown['explosion.damage.standard_damage']
check(damage and damage.canonical==own_damage and damage.key==own_damage.key and damage.loc==own_damage.loc,
    'its damage row is the CB-9 page\'s own (key and bytes)')
check(damage.vanilla==own_damage.vanilla and damage.field==own_damage.field,'with its values')
for _,f in ipairs({'explosion.inner_radius','explosion.outer_radius','explosion.shockwave_radius',
    'explosion.damage.durable_damage','explosion.damage.ap_direct','explosion.damage.demolition',
    'explosion.damage.stagger','explosion.damage.push_force','explosion.damage.status_1_type'})do
    check(shown[f],'shown: '..f)
end
check(rows[shown[1]]==rows[impact]+1,'right under the slot')
check(app:focused_row()==impact,'the slot stays focused when its part gets its header')
local sub=subsection(items,rows[damage])
check(sub and sub.header=='Impact explosion'and sub==subsection(items,rows[impact]),
    'in the slot\'s own subsection: '..tostring(sub and sub.header))
check(shown['explosion.damage.status_1_type'].status_slot and subsection(items,rows[shown['explosion.damage.status_1_type']])
    ==sub,'its status slots in the same subsection')
local label=app:row_label(damage)
check(label:find('CB-9 Exploding Crossbow · ',1,true)==1,'labelled by its explosion: '..label)
local names,n=app:shared_names(damage)
check(n>=1 and names:find('CB-9 Exploding Crossbow',1,true),'marked shared with the CB-9: '..tostring(names))
check(views[expiry]==nil,'the expiry slot still shows nothing')
out[#out+1]='payload rows shown ok'

-- 2. An edit of the explosion here is the CB-9 page's field: one pending value, under the CB-9's key.
check(app:stage(damage,own_damage.vanilla+50),'explosion damage staged under the slot')
check(app.pending[own_damage.key]and app.pending[own_damage.key].row==own_damage,'pending under the CB-9 row')
check(app.toast_msg and app.toast_msg.text:find('CB-9 Exploding Crossbow',1,true),
    'said it is shared: '..tostring(app.toast_msg and app.toast_msg.text))
check(select(2,app:row_view(own_damage))=='pending'and(app:row_view(damage))==own_damage.vanilla+50,
    'the same pending value on both pages')
local acks=select(2,catalog_module.probe(own_damage,own_damage.vanilla+50))
for k,v in pairs(own_damage.acks)do check(not v or acks[k],'its acknowledgement '..k)end
local m=app:markers()
check(m.pending[crossbow.key],'the CB-9 marked pending')
check(app:header_marks(sub,m).pending,'the subsection marked pending')
local listed
for _,c in ipairs(app:changes())do if c.row==own_damage then listed=true end end
check(listed,'listed in Changes as the CB-9\'s field')
local encoded=app:encode_values({[own_damage.key]=own_damage.vanilla+50})
check(encoded[own_damage.key]==own_damage.vanilla+50,'one preset key')
-- the expiry slot naming the same explosion: its rows are not shown twice
check(app:stage(expiry,option(expiry,'CB-9 Exploding Crossbow')),'CB-9 explosion staged as the expiry payload too')
items,views=page(coyote)
check(views[impact]and views[expiry]==nil,'shown once, under the impact slot')
check(app:unstage(expiry),'expiry unstaged')
out[#out+1]='payload edit ok'

-- 3. Collapsed: the subsection keeps the views' markers; open again, they are back.
app:toggle(coyote,sub.key,false)
items,views=page(coyote)
check(views[impact]==nil,'closed: no rows')
local closed
for _,it in ipairs(items)do if it.key==sub.key then closed=it end end
check(closed and not closed.open and app:header_marks(closed,app:markers()).pending,'the closed subsection is marked')
-- back to None the slot is a row again; an explosion again brings the part back closed, its header focused
check(app:stage(impact,impact.vanilla),'None while closed')
items=page(coyote)
check(not header_of(items,'Impact explosion')and item_of(items,impact)and app:focused_row()==impact,
    'None: the slot alone again, focused')
check(app:stage(impact,cb9),'CB-9 while closed')
items=page(coyote)
local head=header_of(items,'Impact explosion')
check(head and not head.open and app:focused_item()==head,'the part back closed, its header focused')
app:toggle(coyote,sub.key,true)
out[#out+1]='payload collapse ok'

-- 4. Switched to another explosion: its rows instead; the CB-9 edit stays pending (it is the CB-9's).
check(app:stage(impact,eruptor),'R-36 explosion staged instead')
items,views=page(coyote)
local r36=views[impact]and views[impact]['explosion.damage.standard_damage']
check(r36 and r36.canonical.object.key=='pw|R-36 Eruptor','the R-36 explosion\'s rows: '..tostring(r36 and r36.key))
for _,p in ipairs(views[impact])do check(p.canonical.object.key=='pw|R-36 Eruptor','no CB-9 row left: '..p.key)end
check(app.pending[own_damage.key],'the CB-9 edit is still pending')
-- 5. None: nothing under the slot.
check(app:stage(impact,impact.vanilla),'back to None')
items,views=page(coyote)
check(views[impact]==nil,'None: nothing under the slot')
check(app.pending[own_damage.key],'the CB-9 edit is still pending after None')
out[#out+1]='payload switch ok'

-- 6. Applied: the slot and the explosion edit apply; the views show the applied values.
check(app:stage(impact,cb9),'CB-9 again')
app:apply()
for _=1,60 do run(0.5);if layer:state(impact)~='applying'and layer:state(own_damage)~='applying'then break end end
local function state(r)local st,why=layer:state(r);return tostring(st)..' '..tostring(why)end
check(layer:state(impact)=='active','the payload applied: '..state(impact))
check(layer:state(own_damage)=='active','the explosion damage applied: '..state(own_damage))
items,views=page(coyote)
damage=views[impact]and views[impact]['explosion.damage.standard_damage']
check(damage,'applied: the CB-9 explosion still shown')
local value,source=app:row_view(damage)
check(source=='editor'and value==own_damage.vanilla+50,'shown as edited: '..tostring(source))
-- the errors list opens a failed one on its owner's page
check(app:reveal(damage.canonical)and app:object()==crossbow,'opened on the CB-9 page')
out[#out+1]='payload applied ok'

-- 7. The weapon's own explosion: not shown twice; set aside while its slot names another explosion.
local eru=open('pw|R-36 Eruptor')
local eslot=slot_of(eru,'impact')
check(eslot and#eslot.payload_rows>=9,'the R-36 impact slot and its own explosion rows')
local view=catalog:payload_view(eslot,eslot.vanilla)
check(view and not view.other,'its own explosion is not another one')
app:reveal(eslot)
items,views=page(eru)
check(views[eslot]==nil,'its own explosion is not shown twice')
local own
for _,r in ipairs(eslot.payload_rows)do if r.field=='explosion.damage.standard_damage'then own=r end end
local _,_,shown_rows=page(eru)
check(own and shown_rows[own],'its own explosion damage is on its page')
check(app:stage(eslot,option(eslot,'PLAS-1 Scorcher')),'R-36 sets off the Scorcher\'s explosion')
items,views,shown_rows=page(eru)
check(views[eslot]and views[eslot]['explosion.damage.standard_damage'],'the Scorcher\'s explosion shown')
check(not shown_rows[own],'its own explosion rows set aside')
check(app:fires_block(own),'its own rows locked')
check(not app:stage(own,own.vanilla+1),'own explosion value refused while it does')
check(app:unstage(eslot),'payload unstaged')
_,_,shown_rows=page(eru)
check(shown_rows[own]and not app:fires_block(own),'its own explosion rows back')
-- an applied own value, then the slot: the own value goes back first (HD2Runtime refuses it, its reset included, once
-- the slot sets off another explosion), then the slot applies
check(app:stage(own,own.vanilla+1),'own explosion value staged')
app:apply()
for _=1,60 do run(0.5);if layer:state(own)~='applying'then break end end
check(layer:state(own)=='active','own explosion value applied: '..state(own))
check(app:stage(eslot,option(eslot,'PLAS-1 Scorcher')),'the Scorcher\'s explosion staged over it')
_,_,shown_rows=page(eru)
check(shown_rows[own]and app:fires_block(own),'the applied own value stays shown, locked, to be reset')
app:apply()
for _=1,60 do run(0.5);if layer:state(own)~='applying'and layer:state(eslot)~='applying'then break end end
check(layer:state(eslot)=='active','the slot applied: '..state(eslot))
check(layer:state(own)=='idle'and(layer:value(own))==own.vanilla,'the own value went back: '..state(own))
_,_,shown_rows=page(eru)
check(not shown_rows[own],'and its row is set aside')
out[#out+1]='own explosion ok'

-- 8. Presets, exports and the saved session: the slot first; an own explosion value next to another explosion is left
-- out (with the count, the reason, kept saved).
local scorcher=option(eslot,'PLAS-1 Scorcher')
app:discard()
layer:reset(eslot)
for _=1,60 do run(0.5);if layer:state(eslot)~='applying'then break end end
check(not app:payload_view(eslot).other,'the R-36 sets off its own explosion again: '..state(eslot))
local missing,dropped=app:stage_map(app:encode_values({[own.key]=own.vanilla+4,[eslot.key]=scorcher}),
    {kind='preset',name='Both'})
check(missing==0 and dropped==1 and app.pending[eslot.key]and not app.pending[own.key],
    'slot staged first, own value left out: '..tostring(missing)..'/'..tostring(dropped))
check(app.loaded_text('Both',app.pending_n,missing,dropped):find('explosion left out',1,true),'the toast says so')
app:discard()
local export=require('mods/skyeshade/hd2runtime_editor/editor/export')
local source,skipped=export.addon(catalog_module,{{row=eslot,value=scorcher},{row=own,value=own.vanilla+1}},
    {name='Payload Test',version='1.0.0',resource='mods/t/p'})
check(#skipped==1 and skipped[1].entry.row==own and skipped[1].why:find('another explosion',1,true),
    'own explosion value skipped in an export: '..tostring(skipped[1]and skipped[1].why))
check(select(2,source:gsub('hd2%.ensure',''))==1,'the slot exported')
local session=require('mods/skyeshade/hd2runtime_editor/editor/session').new({app=app,layer=layer,presets=H.presets})
H.presets:set_session(app:encode_values({[own.key]=own.vanilla+5,[eslot.key]=scorcher}))
local applied,carried=session:restore()
check(applied==1 and carried==1,'slot restored, own value kept saved: '..applied..'/'..carried)
for _=1,60 do run(0.5);if layer:state(eslot)~='applying'then break end end
check(layer:state(own)=='idle'and app:payload_view(eslot).other,'no refused own value: '..state(own))
layer:reset(eslot)
run(8)
out[#out+1]='payload presets ok'

-- 9. A catalogued explosion (hd2.explosion, a mod's value): the owner page's rows; a note when none can be shown.
if type(H.hd2.explosion)=='function'then
    local E=require('hd2runtime/domains/explosion_catalogue')
    local v=catalog:payload_view(impact,H.hd2.explosion('weapon/cb9_exploding_crossbow/impact'))
    local d
    for _,p in ipairs(v and v.rows or{})do if p.field=='explosion.damage.standard_damage'then d=p end end
    check(d and d.key==own_damage.key,'the catalogued CB-9 explosion is the CB-9 page\'s rows')
    local unknown=catalog:payload_view(impact,{resource='explosion',explosion='weapon/nothing/impact'})
    check(unknown and unknown.note and#unknown.rows==0 and unknown.note.reason==catalog_module.PAYLOAD_TEXTS.unknown,
        'an unknown explosion: a note')
    local refused
    for id,e in pairs(E.explosions)do if e.payload==false then refused=id;break end end
    if refused then
        local nv=catalog:payload_view(impact,H.hd2.explosion(refused))
        check(nv.note and nv.note.reason==catalog_module.PAYLOAD_TEXTS.package,'an explosion without a package: a note')
    end
    -- an explosion no page has: keyed by the explosion itself, found again by its key
    local lone
    for _,id in ipairs(util.sorted_keys(E.explosions))do
        local e=E.explosions[id]
        if e.payload==true and e.family=='enemy'then lone=id;break end
    end
    if lone then
        local lv=catalog:payload_view(impact,H.hd2.explosion(lone))
        local r=lv.rows[1]
        check(r and r.canonical.key:find('ex|'..lone..'|',1,true)==1,'keyed by the explosion: '..tostring(r and r.key))
        check(catalog:row(r.canonical.key)==r.canonical,'found by its key')
    end
    out[#out+1]='catalogued payload ok'
end
return table.concat(out,'\n')

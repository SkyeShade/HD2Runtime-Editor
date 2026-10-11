-- Projectile swaps in the window, over the real app, layer and Runtime ensure (tests/lua/ui_harness.lua): while a swap
-- names a donor (staged or applied) the page sets the weapon's own projectile rows aside (HD2Runtime refuses them,
-- COMPOSITION_TARGET_CHANGED) and shows what it fires instead: "Fires", the donor's vanilla stats (HD2Runtime 0.31.2
-- hd2.attack_output(id):stats()) and a link to the donor's own projectile. Values of those rows are dropped or taken
-- back in an order the Runtime accepts, in the window, presets, the saved session and exports. Returns one line per
-- check that ran.
local args=...
local H=assert(loadfile(args.harness))({sim=args.sim})
local app,layer,catalog,S=H.app,H.layer,H.catalog,H.sim
local catalog_module=require('mods/skyeshade/hd2runtime_editor/editor/catalog')
local export=require('mods/skyeshade/hd2runtime_editor/editor/export')
local util=require('mods/skyeshade/hd2runtime_editor/editor/util')
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
    while t<seconds do frame();t=t+0.1 end
end
local function shown(object)
    local items=app:field_items(object)
    local rows,headers={},{}
    for _,it in ipairs(items)do
        if it.row then rows[it.row]=true end
        if it.header then headers[#headers+1]=it.header end
    end
    return rows,headers
end
local function has(list,text)for _,x in ipairs(list)do if x==text then return true end end return false end

-- The host: the LAS-99 Quasar where HD2Runtime 0.31.2 makes its swap writable, else the BR-14 Adjudicator (every
-- Runtime the editor supports swaps it).
local object,swap
for _,key in ipairs({'sp|LAS-99 Quasar Cannon','pw|BR-14 Adjudicator'})do
    local o=catalog:object(key)
    if o then
        catalog:open(o)
        for _,r in ipairs(o.swap_rows or{})do if r.swap_scope=='attack:primary'and r.editable then swap=r end end
        if swap then object=o;break end
    end
end
check(object and swap and#(swap.fires_rows or{})>0,'a host with a writable swap and own projectile rows')
out[#out+1]='host '..object.name
-- the donor: the EAT-17's rocket where the validator takes it, else the first donor it takes
local donor
for _,o in ipairs(swap.options(swap))do
    local id=catalog_module.donor_of(swap,o.value)
    if id and catalog_module.probe(swap,o.value)then
        if o.label=='EAT-17 Expendable Anti-Tank'then donor=o.value;break end
        donor=donor or o.value
    end
end
check(donor,'a donor the validator takes')
local id=catalog_module.donor_of(swap,donor)
check(catalog_module.donor_of(swap,swap.vanilla)==nil,'the own projectile names no donor')
local own
for _,r in ipairs(swap.fires_rows)do if r.field=='projectile.velocity'or r.field=='damage.standard_damage'then own=own or r end end
check(own and own.editable and not own.kind,'an own numeric projectile row: '..tostring(own and own.key))
local other
for _,r in ipairs(object.rows)do if r.editable and not r.kind and not r.fires_from and r~=swap then other=r;break end end
check(other,'a row the swap does not touch')
check(app:reveal(swap),'the swap row is shown')
frame()

-- 1. Staged: a pending own value is dropped with a toast; the own rows are set aside, the donor's shown instead.
check(app:stage(own,own.vanilla+1),'own value staged')
check(app:stage(other,other.vanilla==0 and 1 or other.vanilla*2),'another value staged')
check(app:stage(swap,donor),'swap staged')
check(app.pending[own.key]==nil and app.pending[other.key]~=nil,'the own pending value dropped, the other kept')
check(app.toast_msg and app.toast_msg.text:find('dropped',1,true),'said so: '..tostring(app.toast_msg and app.toast_msg.text))
check(app:fires(swap)==id,'fires the donor')
local rows,headers=shown(object)
check(not rows[own],'own row set aside')
check(rows[other],'the other row stays')
local fires_row,link
for r in pairs(rows)do
    if r.fires_info and r.label=='Fires'then fires_row=r end
    if r.link then link=r end
end
check(fires_row and catalog_module.text(fires_row,fires_row.vanilla)~='','the Fires row: '..tostring(fires_row))
check(fires_row.section==swap.section,'Fires sits with the swap: '..tostring(fires_row.section))
check(app:fires_block(own)~=nil,'own row locked while swapped')
check(not app:stage(own,own.vanilla+2)and app.pending[own.key]==nil,'own value refused while swapped')
check(app.toast_msg.text:find('COMPOSITION_TARGET_CHANGED',1,true),'with the reason: '..app.toast_msg.text)
frame()
-- the donor's stats (HD2Runtime 0.31.2)
local stats=type(H.hd2.attack_output)=='function'and type(H.hd2.attack_output(id).stats)=='function'
if stats then
    local s=H.hd2.attack_output(id):stats()
    check(has(headers,'Donor\'s projectile (vanilla) · Flight'),'donor flight shown: '..table.concat(headers,' | '))
    check(has(headers,'Donor\'s projectile (vanilla) · Direct hit'),'donor direct hit shown')
    local velocity
    for r in pairs(rows)do if r.key:find('|flight.velocity',1,true)then velocity=r end end
    check(velocity and not velocity.editable and velocity.info
        and catalog_module.text(velocity,velocity.vanilla)==util.format(s.flight.velocity),'donor velocity shown read-only')
    if s.impact then check(has(headers,'Donor\'s projectile (vanilla) · Impact explosion'),'donor impact shown')end
    out[#out+1]='donor stats ok'
end
out[#out+1]='swap staged ok'

-- 2. The link to the donor's own projectile opens its owner's page (shared there).
if link then
    local items,selectable=app:field_items(object)
    for s,index in ipairs(selectable)do if items[index].row==link then app.field=s end end
    app.focus='fields'
    frame({'ENTER'})
    local owner=catalog_module.output_owner(id)
    check(app:object()and app:object().name==owner.name,'the owner page opened: '..tostring(app:object()and app:object().name))
    local focused=app:focused_row()
    check(focused and focused.fires_scope=='attack:primary','at its own projectile: '..tostring(focused and focused.key))
    check(app:row_label(link):find(owner.name,1,true),'the link names it: '..app:row_label(link))
    app:reveal(swap)
    frame()
    out[#out+1]='link ok'
end

-- 3. Reset before Apply: the own rows come back.
check(app:unstage(swap),'swap unstaged')
rows=shown(object)
check(rows[own]and not app:fires_block(own),'own row back and editable')
app:discard()

-- 4. Applied own value, then the swap: the own value goes back first, then the swap applies.
check(app:stage(own,own.vanilla+1),'own value staged again')
app:apply()
run(8)
check(layer:state(own)=='active','own value applied: '..tostring(layer:state(own)))
check(app:stage(swap,donor),'swap staged over an applied own value')
rows=shown(object)
check(rows[own]and app:fires_block(own),'an applied own value stays shown, locked, to be reset')
app:apply()
local order={}
for _=1,120 do
    frame()
    local s_own,s_swap=layer:state(own),layer:state(swap)
    if s_own~='idle'and s_swap=='active'then order.overlap=true end
    if s_own=='idle'and not order.own_back then order.own_back=true end
    if s_swap=='active'then order.swap_on=true;if not order.own_back then order.early=true end end
    if order.own_back and order.swap_on then break end
end
check(order.own_back and order.swap_on and not order.early,'own value back before the swap: '..tostring(order.early))
check(util.same(S.value(own),own.vanilla),'own bytes back to the game\'s')
check(catalog_module.donor_of(swap,(layer:value(swap)))==id,'swap applied')
rows=shown(object)
check(not rows[own],'own row set aside once back')
out[#out+1]='swap order ok'

-- 5. A value of an own row while the swap is applied (an old saved session): refused at once with the reason, shown
-- with its error and in the errors list.
layer:set(own,own.vanilla+3,{kind='session'})
run(1)
check(layer:state(own)=='error','refused: '..tostring(layer:state(own)))
local _,err=layer:state(own)
check(err:find('COMPOSITION_TARGET_CHANGED',1,true),'with the reason: '..tostring(err))
check(util.same(S.value(own),own.vanilla),'nothing written')
rows=shown(object)
check(rows[own],'a failed own row stays shown')
local listed=false
for _,e in ipairs(layer:errors())do if e.row==own then listed=true end end
check(listed,'in the errors list')
local m=app:markers()
check(m.error[object.key],'error marker on the object')
layer:reset(own)
run(2)
out[#out+1]='swap errors ok'

-- 6. Presets: an own value next to a swap to a donor is left out, with the count.
app:discard()
local missing,dropped=app:stage_map(app:encode_values({[own.key]=own.vanilla+4,[other.key]=other.vanilla==0 and 2
    or other.vanilla*3}),{kind='preset',name='Swapped'})
check(missing==0 and dropped==1,'one own value left out: '..tostring(missing)..'/'..tostring(dropped))
check(app.pending[own.key]==nil and app.pending[other.key],'the other value staged')
check(app.loaded_text('Swapped',app.pending_n,missing,dropped):find('left out',1,true),'the toast says so')
app:discard()

-- 7. Reset the swap: the own rows return; a preset with both then stages the swap first and leaves the own value out.
layer:reset(swap)
run(8)
check(app:fires(swap)==nil,'swap reset')
rows=shown(object)
check(rows[own]and not app:fires_block(own),'own rows back after the reset')
missing,dropped=app:stage_map(app:encode_values({[own.key]=own.vanilla+4,[swap.key]=donor}),
    {kind='preset',name='Both'})
check(dropped==1 and app.pending[swap.key]and not app.pending[own.key],'swap staged, own value left out: '..dropped)
app:discard()
out[#out+1]='swap presets ok'

-- 8. Exports: an own value next to a swap to a donor is left out with the Runtime's reason.
local source,skipped=export.addon(catalog_module,{{row=swap,value=donor},{row=own,value=own.vanilla+1},
    {row=other,value=other.vanilla==0 and 1 or other.vanilla*2}},{name='Swap Test',version='1.0.0',resource='mods/t/s'})
check(#skipped==1 and skipped[1].entry.row==own and skipped[1].why:find('COMPOSITION_TARGET_CHANGED',1,true),
    'own value skipped: '..tostring(skipped[1]and skipped[1].why))
check(source:find('attack_output',1,true)and select(2,source:gsub('hd2%.ensure',''))==2,'swap and other value exported')
-- without the swap, the own value exports as before
source,skipped=export.addon(catalog_module,{{row=own,value=own.vanilla+1}},{name='Own',version='1.0.0',resource='mods/t/o'})
check(#skipped==0,'own value alone exported')
out[#out+1]='swap export ok'

-- 9. The saved session: swaps first; an own value saved with a swap to a donor is kept saved, not applied.
local session=require('mods/skyeshade/hd2runtime_editor/editor/session').new({app=app,layer=layer,presets=H.presets})
H.presets:set_session(app:encode_values({[own.key]=own.vanilla+5,[swap.key]=donor}))
local applied,carried=session:restore()
check(applied==1 and carried==1,'swap restored, own value kept: '..applied..'/'..carried)
run(8)
check(layer:state(own)=='idle'and catalog_module.donor_of(swap,(layer:value(swap)))==id,'no refused own value')
check(H.presets:session()[own.key]~=nil or session:values()[own.key]~=nil,'own value still saved')
layer:reset(swap)
run(8)
out[#out+1]='swap session ok'
return table.concat(out,'\n')

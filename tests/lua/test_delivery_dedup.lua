local args=...
local H=assert(loadfile(args.harness))({sim=args.sim})
local C=require('mods/skyeshade/hd2runtime_editor/editor/catalog')
local MB=require('mods/skyeshade/hd2runtime_editor/editor/modbuilder')
local export=require('mods/skyeshade/hd2runtime_editor/editor/export')
local report={}
for _,o in ipairs(H.catalog:objects('offensive'))do
 local raw=o:build();H.catalog:open(o);assert(not o.error,o.error)
 -- Every old native control still resolves, including hidden duplicate preset keys.
 for _,r in ipairs(raw)do
  local target=r.descriptor and r.descriptor.target or{}
  if tostring(target.attack):match('^delivery_%d+_')then
   local kept=assert(H.catalog:row(r.key),r.key)
   assert(kept.loc==r.loc and kept.field==r.field,'merged different native fields')
  end
 end
 if o.name:find('Barrage')then report[#report+1]=o.name..': '..#raw..' -> '..#o.rows end
end
local o=assert(H.catalog:object('st|Orbital 380mm HE Barrage'))
assert(#o.rows==50,'380mm count '..#o.rows)
local raw=o:build();local old,first,second,third
for _,r in ipairs(raw)do
 local role=(r.descriptor.target or{}).attack
 if role=='delivery_3_projectile_damage'and r.field=='damage.standard_damage'then old=r end
 if r.field=='projectile.velocity'then
  if role=='delivery_1_projectile'then first=r elseif role=='delivery_2_projectile'then second=r
  elseif role=='delivery_3_projectile'then third=r end
 end
end
local canonical=assert(H.catalog:row(old.key))
assert(canonical.key~=old.key and canonical.section:find('Deliveries 1, 2, 3',1,true))
assert(H.catalog:row(first.key)~=H.catalog:row(second.key),'distinct projectile records were hidden')
assert(H.catalog:row(second.key)==H.catalog:row(third.key),'identical projectile record duplicated')
local value=canonical.vanilla+10
local map={[old.key]=value,[canonical.key]=value}
local missing,dropped=H.app:stage_map(map,'preset')
assert(missing==0 and dropped==0 and H.app.pending_n==1)
H.app:apply();for _=1,240 do H.sim.tick(0.1);H.layer:tick(0.1)end
assert(H.sim.value(canonical)==value)
assert(H.layer:reset(canonical));for _=1,240 do H.sim.tick(0.1);H.layer:tick(0.1)end
assert(H.sim.value(canonical)==canonical.held_vanilla)
local items=MB.items(H.catalog,{stratagemChanges={{instanceKey=old.descriptor.instanceKey,
 semanticFieldId=old.field,desiredValue=value}}})
assert(#items==1 and items[1].row==canonical and items[1].selected)
local lookup=H.catalog:import_index();local found=false
for _,r in ipairs(lookup.rows)do
 if r.key==canonical.key and export.trace(r.target)==export.trace(old.target)then found=true end
end
assert(found,'legacy Lua target missing from import index')
-- Equal values with distinct records, and unknown locations, must never be merged.
local function fake(loc,n)
 return {key='test'..n,field='projectile.velocity',loc=loc,editable=true,vanilla=100,section='Delivery '..n..' projectile',
 descriptor={target={path='attack',attack='delivery_'..n..'_projectile'}}}
end
assert(#C.delivery_rows({fake('settings/projectile/1@32',1),fake('settings/projectile/2@32',2)})==2)
assert(#C.delivery_rows({fake('row:unknown',1),fake('row:unknown',2)})==2)
H.app:reveal(canonical);local frame=H.frame({});assert(#frame.refused==0)
if args.frame then local f=assert(io.open(args.frame,'wb'));f:write(H.dump(frame));f:close()end
return 'delivery identity dedup presets imports apply reset render ok\n'..table.concat(report,'\n')

local args=...
local H=assert(loadfile(args.harness))({sim=args.sim})
local export=require('mods/skyeshade/hd2runtime_editor/editor/export')
local function open(key)
 local o=assert(H.catalog:object(key),key);H.catalog:open(o);assert(not o.error,o.error);return o
end
local function field(o,id)
 for _,r in ipairs(o.rows)do if r.field==id then return r end end
 error(o.name..' missing '..id)
end
local function settle()for _=1,240 do H.sim.tick(0.1);H.layer:tick(0.1)end end
local pack=open('st|B-1 Supply Pack')
for id,value in pairs({['deposit.capacity']=8,['deposit.start_amount']=8,['deposit.refill_amount']=2})do
 local r=field(pack,id);assert(r.editable and r.section:find('Supply boxes',1,true),r.section)
 assert(H.layer:set(r,value));settle();assert(H.sim.value(r)==value)
 assert(H.layer:reset(r));settle();assert(H.sim.value(r)==r.held_vanilla)
end
local alias=field(pack,'helldiver.supply.stims_from_supply')
local player=open('hd|Helldiver');local canonical=field(player,alias.field)
assert(alias.key==canonical.key and alias.loc==canonical.loc and alias.shared and canonical.shared)
assert(export.trace(alias.target)==export.trace(canonical.target))
assert(H.app:stage(alias,4));assert(H.app:row_view(canonical)==4)
H.app:apply();settle();assert(H.sim.value(canonical)==4)
assert(H.layer:reset(canonical));settle();assert(H.sim.value(alias)==2)
-- All recipient views preserve the item's own key, location and export target.
local delivered,types=0,{}
for _,r in ipairs(pack.rows)do
 if r.group=='Supplies delivered'then
  delivered=delivered+1;assert(r.canonical and r.key==r.canonical.key and r.loc==r.canonical.loc)
  assert(export.trace(r.target)==export.trace(r.canonical.target))
  types[r.field]=true
 end
end
for _,r in ipairs(pack.rows)do
 if r.group=='Supplies delivered'then
  local owner=r.canonical.object;H.catalog:open(owner)
  local found=false;for _,own in ipairs(owner.rows)do if own==r.canonical then found=true end end
  assert(found,owner.name..' lost canonical supply field on opening')
 end
end
assert(delivered>100 and types['magazine.magazines_from_supply'] and types['heatsink.from_supply']
 and types['throwable.count_from_supply'] and types['rounds.rounds_from_supply'])
for _,id in ipairs({'magazine.magazines_from_supply','heatsink.from_supply','throwable.count_from_supply'})do
 local r=field(pack,id);local value=math.min(r.max or 31,r.held_vanilla+1)
 assert(H.app:stage(r,value));assert(H.app:row_view(r.canonical)==value)
 H.app:apply();settle();assert(H.sim.value(r.canonical)==value)
 assert(H.layer:reset(r.canonical));settle();assert(H.sim.value(r)==r.held_vanilla)
end
H.app:reveal(alias);local frame=H.frame({});assert(#frame.refused==0)
return 'supply pack controls shared stim alias apply reset export render ok'

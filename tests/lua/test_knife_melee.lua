local args=...
local H=assert(loadfile(args.harness))({sim=args.sim})
local C=require('mods/skyeshade/hd2runtime_editor/editor/catalog')
local export=require('mods/skyeshade/hd2runtime_editor/editor/export')
local function row(key,field)
 local o=assert(H.catalog:object(key),key);H.catalog:open(o);assert(not o.error,o.error)
 for _,r in ipairs(o.rows)do if r.field==field and(key:sub(1,3)~='me|'or r.group=='Melee')then return r end end
 error(key..' missing '..field)
end
for _,g in ipairs(C.GROUPS)do for _,c in ipairs(g.items)do assert(c.id~='melee','standalone melee tab remains')end end
local D=require('hd2runtime/domains/melee_authoring')
for name in pairs(D.entries)do
 local o=assert(H.catalog:object('me|'..name),'missing normal weapon page: '..name)
 assert(o.category=='primary'or o.category=='secondary'or o.category=='support_weapons')
 H.catalog:open(o);assert(not o.error,o.error)
 local found=false
 for _,r in ipairs(o.rows)do if r.group=='Melee'and r.field then
  assert(r.object==o and r.key:sub(1,3)=='me|','legacy field lost its stable key or new owner')
  assert(H.catalog:row(r.key)==r,'saved melee preset cannot resolve');found=true
 end end
 assert(found,'missing Melee group: '..name)
end
local function settle()for _=1,240 do H.sim.tick(0.1);H.layer:tick(0.1)end end
for _,item in ipairs({
 {'th|K-2 Throwing Knife','throwable.launch_speed_override',50},
 {'th|K-2 Throwing Knife','throwable.launch_distance_max',40},
 {'th|K-2 Throwing Knife','throwable.spin_min_x',-25},
 {'me|CQC-2 Saber','melee.volume_z',1.5},
 {'me|CQC-19 Stun Lance','melee.offset_z',2},
 {'me|CQC-20 Breaching Hammer','melee.stamina_cost',0},
 {'me|CQC-9 Defoliation Tool','melee.repeat_hit_interval',0.2},
 {'me|AR-23 Liberator','damage.standard_damage',150},
})do
 local r=row(item[1],item[2]);assert(r.editable,tostring(r.reason))
 local ok,why=C.probe(r,item[3]);assert(ok,tostring(why))
 assert(H.layer:set(r,item[3]));settle()
 assert(math.abs(H.sim.value(r)-item[3])<0.00001,item[2]..' did not apply')
 local code=export.trace(r.target)
 assert(code:find(item[1]:sub(1,3)=='me|'and'hd2.melee('or':flight()',1,true),code)
 local target=assert(loadstring('local hd2=require("hd2runtime/api/hd2");return '..code))()
 assert(target.resource==r.target().resource and target.path==r.target().path,code)
 assert(H.layer:reset(r));settle()
 assert(math.abs(H.sim.value(r)-r.held_vanilla)<0.00001,'reset mismatch')
 H.app:reveal(r);local frame=H.frame({});assert(#frame.refused==0,tostring(frame.refused[1]))
end
local explosions=require('hd2runtime/domains/explosion_catalogue')
local bytes=require('hd2runtime/core/bytes')
local donor=H.hd2.explosion('support_weapon/plas45_epoch/impact')
local throwables=require('hd2runtime/domains/throwable_authoring')
local count=0
for name,e in pairs(throwables.throwables)do if e.targets.detonation then
 local r=row('th|'..name,'throwable.explosion');count=count+1
 local options=r.options();assert(#options>100,'full explosion catalogue is missing')
 local o=r.object;assert(o.payload_slots and o.payload_slots[1]==r)
 local ok,why=C.probe(r,donor);assert(ok,tostring(why))
 assert(H.layer:set(r,donor));settle()
 assert(H.sim.memory[r.loc]==bytes.encode(explosions.explosions[donor.explosion].type,'u32'))
 local encoded=C.encode(r,donor);local decoded=C.decode(H.catalog,r,encoded)
 assert(decoded.explosion==donor.explosion,'preset payload lost its semantic identity')
 H.app:reveal(r);local frame=H.frame({});assert(#frame.refused==0,tostring(frame.refused[1]))
 local code=export.trace(r.target);assert(code:find(':detonation()',1,true),code)
 assert(H.layer:reset(r));settle()
 local vanilla=explosions.explosions[e.targets.detonation.fields['throwable.explosion'].currentDefault]
 assert(H.sim.memory[r.loc]==bytes.encode(vanilla.type,'u32'),'grenade reset mismatch')
 assert(H.layer:set(r,'none'));settle();assert(H.sim.memory[r.loc]==string.rep('\0',4))
 assert(H.layer:reset(r));settle()
end end
assert(count==22)
-- Clearing a grenade payload restores its edited original explosion rows before the reference is removed.
local slot=row('th|G-6 Frag','throwable.explosion')
local damage=row('th|G-6 Frag','explosion.damage.standard_damage')
assert(damage.payload_from==slot)
assert(H.layer:set(damage,damage.vanilla+1));settle();assert(H.layer:state(damage)=='active')
assert(H.layer:set(slot,'none'));settle()
assert(H.layer:state(damage)~='active'and H.sim.value(damage)==damage.vanilla)
assert(H.catalog:payload_view(slot,'none').other and C.payload_other(slot,'none'))
assert(H.app:payload_block(damage),'old explosion fields are not blocked after clearing payload')
assert(H.layer:reset(slot));settle()

local a=row('me|AR-23 Liberator','melee.volume_z')
local b=row('me|AR-23A Liberator Carbine','melee.volume_z')
assert(a.loc==b.loc,'shared melee field must have one editor location')
local other=C.new(H.hd2);local o=other:object(a.object.key);other:open(o)
local matched=false;for _,r in ipairs(o.rows)do if r.field==a.field and r.group=='Melee'then assert(r.loc==a.loc);matched=true;break end end
assert(matched,'stable melee location')
return 'knife and melee apply/reset/export/render ok'

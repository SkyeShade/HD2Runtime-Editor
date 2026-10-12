local args=...
local H=assert(loadfile(args.harness))({sim=args.sim})
local C=require('mods/skyeshade/hd2runtime_editor/editor/catalog')
local export=require('mods/skyeshade/hd2runtime_editor/editor/export')
local function row(key,field)
 local o=assert(H.catalog:object(key),key);H.catalog:open(o);assert(not o.error,o.error)
 for _,r in ipairs(o.rows)do if r.field==field then return r end end
 error(key..' missing '..field)
end
assert(#H.catalog:objects('melee')==112)
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
local a=row('me|AR-23 Liberator','melee.volume_z')
local b=row('me|AR-23A Liberator Carbine','melee.volume_z')
assert(a.loc==b.loc,'shared melee field must have one editor location')
local other=C.new(H.hd2);local o=other:object(a.object.key);other:open(o)
local matched=false;for _,r in ipairs(o.rows)do if r.field==a.field then assert(r.loc==a.loc);matched=true;break end end
assert(matched,'stable melee location')
return 'knife and melee apply/reset/export/render ok'

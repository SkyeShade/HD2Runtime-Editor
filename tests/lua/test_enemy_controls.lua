local args=...
local H=assert(loadfile(args.harness))({sim=args.sim})
local C=require('mods/skyeshade/hd2runtime_editor/editor/catalog')
local export=require('mods/skyeshade/hd2runtime_editor/editor/export')
local cat=H.catalog
local function row(key,field)
 local o=assert(cat:object(key),key);cat:open(o);assert(not o.error,o.error)
 for _,r in ipairs(o.rows)do if r.field==field then return r end end
 error(key..' missing '..field)
end
assert(#cat:objects('structures')==429)
assert(#cat:objects('enemy_entities')>=568)
assert(#cat:objects('enemy_rosters')==191 and #cat:objects('enemy_compositions')==452)
assert(#cat:objects('enemy_difficulty')==10 and #cat:objects('destruction_models')==1641)
assert(#H.app:search_results('HiveMind')==19,'unresolved HiveMind controllers are searchable')
assert(#H.app:search_results('Bughole')>=2,'breach controllers are searchable')
local cases={
 {'en|Charger','unit.scale_min',1.5},
 {'en|il_spawner_ship','entity.health',6000},
 {'en|cy_stratagem_blocker','jammer.radius',75},
 {'en|illuminate_dropship','transport.grid_dimension_0',4},
 {'ed|difficulty/10','difficulty.encounter_points',450},
 {'ed|roster/terminids/row_0','spawn.weight_1',0},
 {'ed|composition/terminids/family_1/row_0','composition.group_0_count',6},
 {'ed|demolition_template/OrbitalBombardment','demolition.force',45},
}
local function settle()
 for _=1,240 do H.sim.tick(0.1);H.layer:tick(0.1)end
end
for i,t in ipairs(cases)do
 local r=row(t[1],t[2]);assert(r.editable,t[2]..': '..tostring(r.reason))
 local ok,why=C.probe(r,t[3]);assert(ok,tostring(why))
 assert(H.layer:set(r,t[3]));settle()
 assert(H.sim.value(r)==t[3],t[2]..' did not apply: '..tostring(H.layer:state(r)))
 local code=export.trace(r.target)
 assert(code:find('hd2.',1,true),code)
 local target=assert(loadstring('local hd2=require("hd2runtime/api/hd2");return '..code))()
 assert(target.resource==r.target().resource,'exported target differs')
 if t[1]:find('ed|',1,true)then assert(code:find('hd2.enemies.',1,true),code)end
 assert(H.layer:reset(r));settle();assert(H.sim.value(r)==r.held_vanilla,t[2]..' did not reset')
 -- Render the actual page using the overlay's own geometry/item limits.
 H.app:reveal(r)
 local frame=H.frame({})
 assert(#frame.refused==0,t[1]..': '..tostring(frame.refused[1]))
 assert(#frame.items<=1024,'overlay item limit')
 if args.dump then local f=assert(io.open(args.dump..'/enemy-'..i..'.json','wb'));f:write(H.dump(frame));f:close()end
end
local max=row('en|Charger','unit.scale_max');assert(not max.editable)
local placeholder=row('ed|composition/terminids/family_3/row_0','composition.group_0_count')
assert(not placeholder.editable and placeholder.vanilla==999)
local first=row('ed|difficulty/10','difficulty.encounter_points')
local mod=H.hd2.events.run_as('mods/test/director',function()
 return H.hd2.ensure({patch={id='other-director',target=first.target(),field=first.field,expect=600,value=500,
  allow_shared=true,allow_unverified_effect=true}})
end)
settle()
local base,origin=H.layer:value(first);assert(base==500 and origin=='mod','director mod claim is visible')
assert(H.layer:set(first,450));settle()
assert(H.sim.value(first)==450 and mod.status=='cancelled','director ensure takeover')
H.layer:reset(first);settle();assert(H.sim.value(first)==500,'reset returns the mod value')
local other=C.new(H.hd2);local o=other:object(first.object.key);other:open(o)
assert(first.loc==o.rows[2].loc,'director identity survives catalogue reload')
assert(require('mods/skyeshade/hd2runtime_editor/editor/ledger').object_key({kind='enemy_director',row='difficulty/10'})==first.object.key)
return 'enemy controls apply/reset/export/render ok'

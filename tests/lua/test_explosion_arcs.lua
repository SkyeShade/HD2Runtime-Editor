local args=...
local H=assert(loadfile(args.harness))({sim=args.sim})
local export=require('mods/skyeshade/hd2runtime_editor/editor/export')
local function rows(key)
 local o=assert(H.catalog:object(key));H.catalog:open(o);assert(not o.error,o.error);return o.rows
end
local function find(key,field,attack,path)
 for _,r in ipairs(rows(key))do
  if r.field==field then
   local t=r.target()
   if (not attack or t.attack==attack)and(not path or t.path==path)then return r end
  end
 end
 error(key..' missing '..field..' / '..tostring(attack or path))
end
local function settle()for _=1,240 do H.sim.tick(0.1);H.layer:tick(0.1)end end
for _,item in ipairs({
 {'sw|GL-52 De-Escalator','arc.range',25,'primary_impact_arc'},
 {'sw|GL-52 De-Escalator','arc.distance_at_max_spread_first_shot',10,'primary_impact_arc'},
 {'sw|GL-52 De-Escalator','arc.chain_count',4,'primary_impact_arc'},
 {'sw|GL-52 De-Escalator','damage.standard_damage',150,'primary_impact_arc'},
 {'sw|GL-52 De-Escalator','status.strength',3,'primary_impact_arc_status_37'},
 {'th|G-31 Arc','arc.range',20,nil,'arc'},
 {'th|G-31 Arc','arc.max_split',4,nil,'arc'},
 {'th|G-31 Arc','damage.standard_damage',200,nil,'arc'},
 {'th|G-31 Arc','damage.status_1_strength',5,nil,'arc'},
})do
 local r=find(item[1],item[2],item[4],item[5]);assert(r.editable)
 assert(H.layer:set(r,item[3]));settle();assert(math.abs(H.sim.value(r)-item[3])<0.00001,item[2]..' apply')
 local code=export.trace(r.target)
 local t=assert(loadstring('local hd2=require("hd2runtime/api/hd2");return '..code))()
 assert(t.resource==r.target().resource and t.path==r.target().path and t.attack==r.target().attack)
 assert(H.layer:reset(r));settle();assert(math.abs(H.sim.value(r)-r.held_vanilla)<0.00001,item[2]..' reset')
 H.app:reveal(r);assert(#H.frame({}).refused==0)
end
local hd2=require('hd2runtime/api/hd2')
assert(#hd2.throwable('G-31 Arc'):explosion():status_effects()==0)
assert(#hd2.throwable('G-31 Arc'):arc():status_effects()==1)
assert(#hd2.throwable('G-31 Arc'):status_effects()==1)
assert(hd2.throwable('G-31 Arc'):arc():status_effect(1).status=='arc-stun-small')
return 'explosion arcs apply reset export render ok'

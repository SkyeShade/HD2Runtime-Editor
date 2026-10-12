local args=...
local H=assert(loadfile(args.harness))({sim=args.sim})
local C=require('mods/skyeshade/hd2runtime_editor/editor/catalog')
local export=require('mods/skyeshade/hd2runtime_editor/editor/export')
local statuses=require('hd2runtime/domains/status_catalog').statuses
local bytes=require('hd2runtime/core/bytes')
local function value(row,v)
 if row.kind=='choice'then return v=='none'and 0 or statuses[v].nativeType end
 return v
end
local function held(row)
 return bytes.value(assert(H.sim.memory[row.loc],'no write at '..row.loc),0,row.descriptor.backing.storage)
end
local function settle()for _=1,600 do H.sim.tick(0.1);H.layer:tick(0.1)end end
local function open(name)
 local o=assert(H.catalog:object('th|'..name));H.catalog:open(o);assert(not o.error,o.error)
 return o
end
local function slots(o,path)
 local out={}
 for _,r in ipairs(o.rows)do if r.status_slot and r.target().path==path then
  out[r.status_slot.kind..r.status_slot.n]=r
 end end
 for i=1,4 do assert(out['type'..i]and out['strength'..i],o.name..' missing slot '..i)end
 return out
end
for _,item in ipairs({{'G-12 High Explosive','explosion'},{'K-2 Throwing Knife','damage'},
 {'G-6 Frag','shrapnel'},{'G-7 Pineapple','bomblet_explosion'}})do
 local o=open(item[1]);local s=slots(o,item[2]);local map,entries={},{}
 local choices={'fire','gas','stun_small','poison'}
 assert(H.app:slot_block(s.type4),'fourth slot should need its predecessors')
 assert(not H.app:stage(s.type4,'poison'),'cannot stage fourth slot first')
 for i=1,4 do
  map[s['type'..i].key]=choices[i];map[s['strength'..i].key]=i
  entries[#entries+1]={row=s['type'..i],value=choices[i]}
  entries[#entries+1]={row=s['strength'..i],value=i}
 end
 local missing,dropped=H.app:stage_map(map)
 assert(missing==0 and(dropped or 0)==0,'preset did not stage all eight values')
 H.app:apply();settle()
 for _,e in ipairs(entries)do assert(held(e.row)==value(e.row,e.value),e.row.field..' apply')end
 local source,skipped=export.addon(C,entries,{name='Four Effects',version='1.0.0',resource='mods/test/four_effects'})
 assert(#skipped==0,'export skipped status changes')
 assert(select(2,source:gsub('hd2%.ensure', ''))==1 and source:find('transaction=',1,true),'status export must be atomic')
 assert(loadstring(source),'export syntax')
 H.app:reveal(s.type4);local frame=H.frame({});assert(#frame.refused==0,'overlay limit')
 assert(H.app:stage(s.type1,'none'),'reset to vanilla should reset dependent slots')
 H.app:apply();settle()
 for i=1,4 do assert(held(s['type'..i])==value(s['type'..i],s['type'..i].held_vanilla),'dependent reset '..i)end
 for i=1,4 do H.layer:reset(s['strength'..i])end;settle()
 H.app:discard()
end
local gas=open('G-4 Gas');local s=slots(gas,'explosion');local strength=s.strength1
assert(#(strength.alias_keys or{})==1,'old named Gas strength must be an alias')
assert(H.catalog:row(strength.alias_keys[1])==strength,'old preset key resolves to canonical strength')
local same=0;for _,r in ipairs(gas.rows)do if r.loc==strength.loc then same=same+1 end end
assert(same==1,'duplicate strength displayed')
local other=C.new(H.hd2);local aliased=other:row(strength.alias_keys[1])
assert(aliased and aliased.loc==strength.loc,'old key loads from a fresh catalogue')
return 'throwable four-status apply reset preset export render ok'

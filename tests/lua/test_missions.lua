local args=...
local H=assert(loadfile(args.harness))({sim=args.sim})
local export=require('mods/skyeshade/hd2runtime_editor/editor/export')
local function open(key)
 local o=assert(H.catalog:object(key),key);H.catalog:open(o);assert(not o.error,o.error);return o
end
local function settle()for _=1,240 do H.sim.tick(0.1);H.layer:tick(0.1)end end
local seen,count={},0
for _,front in ipairs({'terminids','automatons','illuminate'})do
 local list=H.catalog:objects('missions_'..front);assert(#list>40)
 for _,o in ipairs(list)do
  open(o.key);count=count+1
  assert(o.iconKind=='faction'and o.iconName==front)
  local r=o.rows[1];assert(r.field=='mission.duration_seconds'and r.editable and r.shared)
  if seen[r.loc]then assert(seen[r.loc].key==r.key)else seen[r.loc]=r end
 end
end
assert(count==162)
local normal=open('mi|automatons/c8859069').rows[1]
local shared=open('mi|automatons/19e3e290').rows[1]
local blitz=open('mi|automatons/a41d64ac').rows[1]
local defence=open('mi|automatons/44f0b9ab').rows[1]
assert(normal.vanilla==2400 and blitz.vanilla==720 and defence.vanilla==1200)
assert(normal.key==shared.key and normal.loc~=blitz.loc and normal.loc~=defence.loc)
assert(H.app:stage(shared,1800));assert(H.app:row_view(normal)==1800)
H.app:apply();settle();assert(H.sim.value(normal)==1800)
assert(H.layer:reset(normal));settle();assert(H.sim.value(shared)==2400)
assert(export.trace(shared.target):find('hd2.mission(',1,true))
H.app:reveal(blitz);local frame=H.frame({});assert(#frame.refused==0)
local groups=0;for _ in pairs(seen)do groups=groups+1 end;assert(groups==19)
return 'mission fronts shared timers apply reset export render ok'

local args=...
local H=assert(loadfile(args.harness))({sim=args.sim})
local export=require('mods/skyeshade/hd2runtime_editor/editor/export')
local o=assert(H.catalog:object('sp|StA-X3 W.A.S.P. Launcher'));H.catalog:open(o)
assert(not o.error,o.error)
local found={}
for _,r in ipairs(o.rows)do
 if r.field=='attack.projectile'or r.field=='function_ammo.projectile'then
  assert(r.editable and r.kind=='reference',r.reason)
  assert(r.note and r.note:find('Missile flight',1,true))
  assert(#r.options(r)>20)
  assert(r.target_code and r.expect_code)
  found[r.field]=true
 end
end
assert(found['attack.projectile'] and found['function_ammo.projectile'])
for _,name in ipairs({'CQC-20 Breaching Hammer','AR-23 Liberator'})do
 local w=H.catalog:object('pw|'..name)or H.catalog:object('sp|'..name)
 assert(w);H.catalog:open(w)
 for _,r in ipairs(w.rows)do assert(r.label~='Melee reach')end
end
return 'wasp mode selectors and melee visibility ok'

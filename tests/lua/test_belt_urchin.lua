local args=...
local H=assert(loadfile(args.harness))({sim=args.sim})
local C=require('mods/skyeshade/hd2runtime_editor/editor/catalog')
local export=require('mods/skyeshade/hd2runtime_editor/editor/export')
local function settle()for _=1,260 do H.sim.tick(0.1);H.layer:tick(0.1)end end
local function open(key)local o=assert(H.catalog:object(key));H.catalog:open(o);assert(not o.error,o.error);return o end
local gl=open('sw|GL-28 Belt-Fed Grenade Launcher');local swap
for _,r in ipairs(gl.rows)do if r.field=='attack.projectile'and r.editable then swap=r end end
assert(swap,'belt-fed projectile swap absent')
local shotgun
for _,o in ipairs(swap.options(swap))do if o.label=='SG-225 Breaker'then shotgun=o.value end end
assert(shotgun,'Breaker donor missing');assert(C.probe(swap,shotgun))
assert(H.layer:set(swap,shotgun));settle()
assert(tostring(H.sim.value(swap)):find('ref:',1,true),'projectile did not apply')
assert(H.layer:reset(swap));settle()
H.app:reveal(swap);assert(#H.frame({}).refused==0)
local th=open('th|G-109 Urchin');local pulse
for _,r in ipairs(th.rows)do if r.field=='throwable.pulse_explosion'then pulse=r end end
assert(pulse and pulse.editable,'pulse payload row absent')
local small,large
for _,o in ipairs(pulse.options(pulse))do
 if o.value.explosion=='support_weapon/plas45_epoch/impact'then small=o.value end
 if o.value.explosion=='support_weapon/plas45_epoch/charge_2_expiry'then large=o.value end
end
assert(small and large)
for _,value in ipairs({small,large})do
 assert(C.probe(pulse,value));assert(H.layer:set(pulse,value));settle()
 assert(H.sim.value(pulse)=='payload:'..value.explosion,'pulse apply/transition failed')
end
local source,skipped=export.addon(C,{{row=pulse,value=small},{row=swap,value=shotgun}},
 {name='Belt and Plasma',version='1.0.0',resource='mods/test/belt_plasma'})
assert(#skipped==0 and loadstring(source),'export failed '..tostring(skipped[1]and skipped[1].why)..' '..source)
assert(source:find('pulse()',1,true)and source:find('plas45_epoch/impact',1,true))
assert(H.layer:reset(pulse));settle()
assert(H.sim.value(pulse)=='payload:throwable/g109_urchin/detonation','pulse reset failed')
H.app:reveal(pulse);assert(#H.frame({}).refused==0)
return 'belt shotgun and Urchin plasma apply reset transition export render ok'

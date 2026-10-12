local args=...
local H=assert(loadfile(args.harness))({sim=args.sim})
local export=require('mods/skyeshade/hd2runtime_editor/editor/export')
local D=require('hd2runtime/domains/player_weapon_authoring')
local firearms=0
local function rows(name)
 local o=assert(H.catalog:object('pw|'..name));H.catalog:open(o);assert(not o.error,o.error)
 return o.rows
end
local function find(name,field)
 for _,r in ipairs(rows(name))do if r.field==field then return r end end
 error(name..' missing '..field)
end
for name,e in pairs(D.weapons)do
 for _,f in ipairs(e.fields)do if f.reloadTiming and not f.reloadTiming.noReloadAbility then
  local expected=f.reloadTiming.defaultAttachment and 'attachment.reload_duration'or'reload.duration'
  local r=find(name,expected);assert(r.editable,tostring(r.reason));firearms=firearms+1
 end end
end
assert(firearms==73,'reload coverage '..firearms)
local excluded=false
for _,r in ipairs(rows('ARC-12 Blitzer'))do if r.id=='reload.not_applicable'or r.label=='Reload'then
 assert(not r.editable);excluded=true
end end
assert(excluded,'Blitzer must explain why no reload control exists')
local function settle()for _=1,240 do H.sim.tick(0.1);H.layer:tick(0.1)end end
for _,item in ipairs({
 {'AR-23 Liberator','attachment.reload_duration',1.5},
 {'P-4 Senator','reload.duration',1.25},
 {'LAS-17 Double-Edge Sickle','heat.fire_rate_multiplier_max',2},
 {'LAS-17 Double-Edge Sickle','heat.fire_rate_curve_exponent',2},
 {'LAS-17 Double-Edge Sickle','heat.level_1.damage.standard_damage',150},
 {'LAS-17 Double-Edge Sickle','heat.level_2.projectile.velocity',900},
 {'LAS-17 Double-Edge Sickle','heat.level_3.self_damage.standard_damage',0},
 {'LAS-17 Double-Edge Sickle','heat.level_3.self_status_duration',0.25},
})do
 local r=find(item[1],item[2]);assert(H.layer:set(r,item[3]));settle()
 assert(math.abs(H.sim.value(r)-item[3])<0.00001,item[2]..' did not apply')
 local code=export.trace(r.target);local target=assert(loadstring('local hd2=require("hd2runtime/api/hd2");return '..code))()
 assert(target.resource==r.target().resource)
 assert(H.layer:reset(r));settle();assert(math.abs(H.sim.value(r)-r.held_vanilla)<0.00001)
 H.app:reveal(r);local frame=H.frame({});assert(#frame.refused==0,tostring(frame.refused[1]))
end
return '73 reloads and heat controls apply reset export render ok'

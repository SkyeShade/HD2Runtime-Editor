local args=...
local H=assert(loadfile(args.harness))({sim=args.sim})
local export=require('mods/skyeshade/hd2runtime_editor/editor/export')
local D=require('hd2runtime/domains/player_weapon_authoring')
local firearms=0
local function rows(name)
 local e=D.weapons[name]
 local o=assert(H.catalog:object('pw|'..(e.subweaponOf or name)));H.catalog:open(o);assert(not o.error,o.error)
 return o.rows
end
local function find(name,field,attachment)
 for _,r in ipairs(rows(name))do if r.field==field and r.target().weapon==name then return r end end
 -- Magazine shortcuts target the attachment, not the weapon.
 if field=='attachment.reload_duration'then
  for _,r in ipairs(rows(name))do if r.field==field and(not attachment or r.target().attachment==attachment)then return r end end
 end
 error(name..' missing '..field)
end
for name,e in pairs(D.weapons)do
 for _,f in ipairs(e.fields)do if f.reloadTiming and not f.reloadTiming.noReloadAbility then
  local expected=f.reloadTiming.defaultAttachment and 'attachment.reload_duration'or'reload.duration'
  local r=find(name,expected,f.reloadTiming.defaultAttachment);assert(r.editable,tostring(r.reason))
  assert(r.unit=='seconds',name..' reload unit');firearms=firearms+1
 end end
end
assert(firearms==77,'reload coverage '..firearms) -- Includes all three separate underbarrels.
-- Audit the whole primary/secondary page list, not just descriptors that already advertise timing.
local excluded_names={['ARC-12 Blitzer']=true,['CQC-2 Saber']=true,['CQC-5 Combat Hatchet']=true,
 ['CQC-19 Stun Lance']=true,['CQC-30 Stun Baton']=true,['CQC-42 Machete']=true,['CQC-73 Entrenchment Tool']=true}
local total,covered,excluded_count=0,0,0
for _,category in ipairs({'primary','secondary'})do for _,o in ipairs(H.catalog:objects(category))do
 H.catalog:open(o);assert(not o.error,o.error);total=total+1
 local has_reload=false
 for _,r in ipairs(o.rows)do if r.field=='reload.duration'or r.field=='attachment.reload_duration'then
  assert(r.editable and r.unit=='seconds',o.name..' invalid reload control')
  has_reload=true
 end end
 if excluded_names[o.name]then assert(not has_reload);excluded_count=excluded_count+1
 else assert(has_reload,o.name..' missing reload control');covered=covered+1 end
end end
assert(total==81 and covered==74 and excluded_count==7,'complete reload page coverage')

assert(find('AR-11 Arbitrator','reload.duration').label=='Reload duration (AR mode)')
local under=find('AR-11 Arbitrator / underbarrel','reload.duration')
assert(under.label=='Reload duration (underbarrel)'and under.group=='Underbarrel Weapon')
local excluded=false
for _,r in ipairs(rows('ARC-12 Blitzer'))do if r.id=='reload.not_applicable'or r.label=='Reload'then
 assert(not r.editable);excluded=true
end end
assert(excluded,'Blitzer must explain why no reload control exists')
local function settle()for _=1,240 do H.sim.tick(0.1);H.layer:tick(0.1)end end
for _,item in ipairs({
 {'AR-23 Liberator','attachment.reload_duration',1.5},
 {'P-4 Senator','reload.duration',1.25},
 {'LAS-22 Shear','reload.duration',1.5},
 {'AR-11 Arbitrator','reload.duration',1.75},
 {'AR-11 Arbitrator / underbarrel','reload.duration',2},
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
return '77 reloads and heat controls apply reset export render ok'

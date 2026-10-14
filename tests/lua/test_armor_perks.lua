local args=...
local H=assert(loadfile(args.harness))({sim=args.sim})
local export=require('mods/skyeshade/hd2runtime_editor/editor/export')
local icons=require('mods/skyeshade/hd2runtime_editor/editor/icons')
local function open(key)
 local o=assert(H.catalog:object(key),key);H.catalog:open(o);assert(not o.error,o.error);return o
end
local function settle()for _=1,240 do H.sim.tick(0.1);H.layer:tick(0.1)end end
local helldiver=open('hd|Helldiver')
assert(#H.catalog:objects('helldiver')==1,'old passive page still listed')
assert(H.catalog:object('hd|Armor perks')==helldiver,'old object key lost')
local armor=assert(H.catalog:row('hd|Armor perks|armor'))
local second=assert(H.catalog:row('hd|Armor perks|second'))
assert(armor.object==helldiver and second.object==helldiver)
assert(armor.controller=='passives'and second.controller=='passives')
local list=H.catalog:objects('armor_perks');assert(#list==32)
local all_icons=icons.load(H.hd2)
local deps={}
icons.warm({asset_dependency=H.hd2.asset_dependency,require_assets=function(r)deps=r.targets;return{}end},all_icons)
assert(#deps>=3,'perk atlas package is not preloaded')
local count=0;local locations={}
for _,o in ipairs(list)do
 open(o.key);assert(o.iconKind=='passive'and icons.entry(all_icons,o),'perk icon missing')
 for _,r in ipairs(o.rows)do if r.editable then
  assert(r.shared and r.unverified and r.descriptor and r.loc:find('armor_perk/',1,true))
  assert(not locations[r.loc],'perk fields alias another perk');locations[r.loc]=true;count=count+1
 end end
end
assert(count==75,tostring(count))
local scout=open('ap|2').rows[1];local fortified=open('ap|3').rows[1]
assert(H.app:stage(scout,4));H.app:apply();settle();assert(H.sim.value(scout)==4)
assert(H.sim.value(fortified)==fortified.vanilla,'unrelated perk changed')
assert(H.layer:reset(scout));settle();assert(H.sim.value(scout)==scout.vanilla)
local siege=open('ap|16');assert(siege.rows[1].field=='perk.stat_13.add')
local speed=siege.rows[2];assert(speed.field=='perk.stat_13.mul'and speed.vanilla==1.3)
assert(H.app:stage(speed,2));H.app:apply();settle();assert(H.sim.value(speed)==2)
assert(export.trace(speed.target):find('hd2.passives.perk(16)',1,true))
assert(H.layer:reset(speed));settle();assert(math.abs(H.sim.value(speed)-1.3)<0.000001)
H.app.ctx.icons=all_icons;H.app:reveal(scout);local frame=H.frame({});assert(#frame.refused==0)
assert(H.app:draw_icon(open('ap|18'),10,10,48))
return 'armor perks catalogue icons legacy selectors apply reset export render ok'

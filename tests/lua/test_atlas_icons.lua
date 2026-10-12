local args=...
local H=assert(loadfile(args.harness))({sim=args.sim})
local I=require('mods/skyeshade/hd2runtime_editor/editor/icons')
local api=H.hd2.resources
local icons,count=I.load({resources={image=function(id)return{image=id}end,
    game_icon=api.game_icon,game_icons=api.game_icons}},
    {stratagems={['Orbital Precision Strike']={image='existing',accent={255,200,50}}}})
assert(count>390 and icons.stratagems['Orbital Precision Strike'].handle.image=='existing')
assert(icons.weapons['AR-23 Liberator'].game and icons.throwables['G-109 Urchin'].game,
 'generated stratagems must not suppress native silhouettes')
local packed=I.load({resources={image=function(id)return{image=id}end,
 game_icon=function()error('native atlas unavailable')end,game_icons=api.game_icons}},
 {weapons={['AR-23 Liberator']={image='wi_ar_23_liberator',accent={255,255,238}}},
 throwables={['G-16 Impact']={image='ti_g_16_impact',accent={255,255,238}}}})
assert(I.entry(packed,{key='pw|AR-23 Liberator',name='AR-23 Liberator'}).handle.image=='wi_ar_23_liberator')
assert(I.entry(packed,{key='th|G-16 Impact',name='G-16 Impact'}).handle.image=='ti_g_16_impact')
H.frame({})
local original=H.app.canvas.image;local seen={}
H.app.ctx.icons=icons
H.app.canvas.image=function(_,handle,x,y,w,h,opts)seen[#seen+1]={handle=handle,w=w,h=h,opts=opts}end
for _,category in ipairs({'primaries','secondaries','throwables','terminids','automatons','illuminate','structures'})do
    local objects=assert(H.catalog:objects(category),category)
    for _,object in ipairs(objects)do
        local rendered=H.app:draw_icon(object,10,10,48)
        if category~='structures'or object.iconFaction then assert(rendered,'missing icon '..object.key)end
    end
end
local rifle=assert(H.catalog:object('pw|AR-23 Liberator'))
for key,label in pairs({spawner='Factory Strider',illuminate_dropship='Warp Ship',
    cy_stratagem_blocker='Stratagem Jammer',il_obj_asset_weather_device_core='Exospire Core',
    unnamed_entity_0034='MG Raider',boomer_nurser='Nursing Spewer'})do
    local object=assert(H.catalog:object('en|'..key),key)
    assert(object.name==label or object.name:sub(1,#label+3)==label..' - ',object.name)
    assert(object.search_terms:find(key,1,true),'canonical ID search lost')
end
local one=assert(H.catalog:object('en|warrior_tier_1'))
local two=assert(H.catalog:object('en|warrior_tier_2'))
assert(one.name=='Warrior - Warrior Tier 1'and two.name=='Warrior - Warrior Tier 2','variants collapsed')
assert(H.catalog:object('en|cha_soldier.cha_soldier_jumppack').name=='Devastator - Soldier Jumppack')
assert(H.app:draw_icon(rifle,10,10,48));local draw=seen[#seen]
assert(draw.w==48 and draw.h<draw.w and draw.opts.colours.g[4]==0,'aspect or mask lost')
assert(H.app:draw_icon({key='en|jammer',iconKind='objective',iconName='cy_destroy_stratagem_blocker'},10,10,48))
assert(seen[#seen].opts.colours==nil,'objective alpha art must use the image path')
assert(seen[#seen].opts.colour[3]>seen[#seen].opts.colour[1],'objectives must be blue')
for faction,channel in pairs({automatons=1,terminids=1,illuminate=3,super_earth=3})do
    assert(H.app:draw_icon({key='en|colour',iconKind='faction',iconName=faction},10,10,48))
    local opts=seen[#seen].opts
    local tint=opts.colours and opts.colours.r or opts.colour
    assert(tint and tint[channel]>=240,'faction tint missing: '..faction)
end
local warm
I.warm({asset_dependency=H.hd2.asset_dependency,require_assets=function(request)
    warm=request;return {status='waiting_for_assets'}end},icons)
assert(warm and#warm.targets==2,'preload only the two UI atlas packages')
local packages={}
for _,handle in ipairs(warm.targets)do packages[H.hd2.asset_dependency(handle).package]=true end
assert(packages.atlas_mission and packages.atlas_shared)
local called=false
I.warm({asset_dependency=function()return{known=false}end,require_assets=function()called=true end},icons)
assert(not called,'older Runtime without icon asset dependencies')
local kind,name=I.entity('cy_stratagem_blocker',{kind='structure',faction='automatons'})
assert(kind=='objective'and name=='cy_destroy_stratagem_blocker')
kind,name=I.entity('bug_spawner_shrieker',{kind='structure',faction='terminids'})
assert(name=='bug_shrieker_nest')
for _,faction in ipairs({'automatons','terminids','illuminate','super_earth','helldivers'})do
    local kind,name,fallback=I.entity('unknown_structure',{kind='structure',faction=faction})
    assert(I.entry(icons,{key='en|unknown_structure',iconKind=kind,iconName=name,iconFaction=fallback})
        ==icons.factions[faction=='helldivers'and'super_earth'or faction])
end
kind,name=I.entity('unknown_structure',{kind='structure',faction='unresolved'})
assert(I.entry(icons,{key='en|unknown_structure',iconKind=kind,iconName=name})==nil)
assert(I.entry({objectives={},factions=icons.factions},{iconKind='objective',
    iconName='cy_destroy_stratagem_blocker',iconFaction='automatons'})==icons.factions.automatons)
local old=I.load({resources={game_icons=function(kind)assert(kind=='stratagem'or kind=='booster');return{}end,
    game_icon=api.game_icon}})
assert(old and next(old.weapons)==nil,'older Runtime compatibility')
H.app.canvas.image=original
assert(H.app:goto_object(rifle));H.catalog:open(rifle);assert(#H.frame({}).refused==0)
return 'atlas silhouettes factions objectives mixed loading aspect fallback render ok'

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
H.frame({})
local original=H.app.canvas.image;local seen={}
H.app.ctx.icons=icons
H.app.canvas.image=function(_,handle,x,y,w,h,opts)seen[#seen+1]={handle=handle,w=w,h=h,opts=opts}end
for _,category in ipairs({'primaries','secondaries','throwables','terminids','automatons','illuminate','structures'})do
    local objects=assert(H.catalog:objects(category),category)
    for _,object in ipairs(objects)do assert(H.app:draw_icon(object,10,10,48),'missing icon '..object.key)end
end
local rifle=assert(H.catalog:object('pw|AR-23 Liberator'))
assert(H.app:draw_icon(rifle,10,10,48));local draw=seen[#seen]
assert(draw.w==48 and draw.h<draw.w and draw.opts.colours.g[4]==0,'aspect or mask lost')
assert(H.app:draw_icon({key='en|jammer',iconKind='objective',iconName='cy_destroy_stratagem_blocker'},10,10,48))
assert(seen[#seen].opts.colours==nil,'objective alpha art must use the image path')
local kind,name=I.entity('cy_stratagem_blocker',{kind='structure',faction='automatons'})
assert(kind=='objective'and name=='cy_destroy_stratagem_blocker')
kind,name=I.entity('bug_spawner_shrieker',{kind='structure',faction='terminids'})
assert(name=='bug_shrieker_nest')
kind,name=I.entity('unknown_structure',{kind='structure'})
assert(I.entry(icons,{key='en|unknown_structure',iconKind=kind,iconName=name})==icons.objectives.objective)
local old=I.load({resources={game_icons=function(kind)assert(kind=='stratagem'or kind=='booster');return{}end,
    game_icon=api.game_icon}})
assert(old and next(old.weapons)==nil,'older Runtime compatibility')
H.app.canvas.image=original
assert(H.app:goto_object(rifle));H.catalog:open(rifle);assert(#H.frame({}).refused==0)
return 'atlas silhouettes factions objectives mixed loading aspect fallback render ok'

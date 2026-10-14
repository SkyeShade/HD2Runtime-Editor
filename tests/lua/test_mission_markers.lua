local args=...
local H=assert(loadfile(args.harness))({sim=args.sim})
local ui=require('mods/skyeshade/hd2runtime_editor/editor/ui/mission_overview')
-- Boot order: restoring an applied timer opens its canonical mission page first (Catalog:row). Every page sharing that
-- timer is opened after that build, never inside it; the overview then still has its four groups.
assert(not H.catalog.indexed)
local D=require('hd2runtime/domains/missions')
local canonical='mi|'..D.sources['terminids/mode_1'].missions[1]
local first=assert(H.catalog:object(canonical));assert(first.rows==nil)
H.catalog:open(first);local restored=first.rows[1]
assert(#first.rows==3 and restored.field=='mission.duration_seconds'and not restored.canonical,
 'canonical mission page lost rows')
for _,o in ipairs((H.catalog:objects('missions_terminids')))do
 assert(o.rows and #o.rows==3 and o.rows[1].field=='mission.duration_seconds',o.key)
end
local count={}
for _,r in ipairs(H.catalog:siblings(restored))do assert(not count[r],'row indexed twice');count[r]=true end
-- An overview slider marks every mission page sharing the timer at once, before the background index gets there.
local overview=assert(H.catalog:object('mo|terminids'));H.catalog:open(overview)
assert(#overview.timerGroups==4 and #overview.rows==10,'terminid overview lost its sliders')
local cleanse=assert(H.catalog:object('mi|terminids/3428204c'))
assert(cleanse.rows,'mission pages are opened with the first mission view')
local group=overview.timerGroups[1];assert(group.duration==2400)
local s={group=group,x=10,width=100}
ui.begin_slider(H.app,s,60);H.app.drag.finish();H.app.drag=nil
assert(H.app.pending_n>0)
local m=H.app:markers()
assert(m.pending['mi|terminids/3428204c']and m.category.missions_terminids,'shared mission page not marked')
local marked=0
for _,o in ipairs((H.catalog:objects('missions_terminids')))do if m.pending[o.key]then marked=marked+1 end end
assert(marked>=39,marked)
assert(not H.catalog.indexed)
-- A page the background index opens later that shares a pending value redoes the markers at once.
local fake={rows={{loc=cleanse.rows[1].loc}}}
assert(H.app:marks_reach({fake})and not H.app:marks_reach({{rows={{loc='elsewhere'}}}}))
local before=H.app:markers()
H.catalog.index_step=function()return false,{{rows={{loc='elsewhere'}}}}end
H.frame({});assert(H.app:markers()==before,'an unrelated page redid the markers')
H.catalog.index_step=function()return false,{fake}end
H.frame({});assert(H.app:markers()~=before,'markers kept after a page sharing a pending value was indexed')
-- The game's mission timer limit: rows end at 2500 s (the host clamps its countdown to the replicated field's
-- range), a larger value is clamped when staged, and a saved larger value is restored as 2500.
H.app:discard()
assert(restored.max==2500 and require('mods/skyeshade/hd2runtime_editor/editor/catalog').NETWORK_MAX.mission_seconds==2500)
assert(H.app:stage(restored,5827)and H.app:row_view(restored)==2500);H.app:discard()
local logs={}
H.presets:set_session({[restored.key]=5827})
local session=require('mods/skyeshade/hd2runtime_editor/editor/session').new({app=H.app,layer=H.layer,presets=H.presets,
 log=function(s)logs[#logs+1]=s end})
local applied,carried=session:restore()
assert(applied==1 and carried==0,'a saved over-limit timer did not come back')
for _=1,240 do H.sim.tick(0.1);H.layer:tick(0.1)end
assert(H.sim.value(restored)==2500 and H.layer:value(restored)==2500)
local found=false;for _,l in ipairs(logs)do if l:find('at 2500 s instead of 5827 s',1,true)then found=true end end
assert(found,'the clamp on restore was not logged')
return 'mission markers immediate shared pages ok'

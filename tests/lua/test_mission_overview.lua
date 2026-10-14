local args=...
local H=assert(loadfile(args.harness))({sim=args.sim})
local ui=require('mods/skyeshade/hd2runtime_editor/editor/ui/mission_overview')
local function open(key)
 local o=assert(H.catalog:object(key));H.catalog:open(o);assert(not o.error,o.error);return o
end
local function settle()for _=1,240 do H.sim.tick(0.1);H.layer:tick(0.1)end end
local counts={terminids=10,automatons=7,illuminate=6}
local unique,total={},0
for front,n in pairs(counts)do
 local o=open('mo|'..front);assert(#o.rows==n and #o.timerGroups==4)
 local durations={}
 for _,g in ipairs(o.timerGroups)do
  assert(not durations[g.duration]);durations[g.duration]=true
  for _,row in ipairs(g.rows)do
   assert(row.canonical and row.key:sub(1,3)=='mi|'and row.vanilla==g.duration)
   unique[row.descriptor.backing.source]=row;total=total+1
  end
 end
 assert(durations[2400]and durations[1200]and durations[900]and durations[720])
 H.app:goto_object(o);local frame=H.frame({});assert(#frame.refused==0)
 H.app['mission_timer_scroll_'..front]=100;assert(#H.frame({}).refused==0)
end
local n=0;for _ in pairs(unique)do n=n+1 end;assert(n==19 and total==23)
local a=open('mo|automatons');local t=open('mo|terminids')
local shared,other
for _,row in ipairs(a.rows)do if row.descriptor.backing.source=='delta/857c2cd17f827849'then shared=row end end
for _,row in ipairs(t.rows)do if row.key==shared.key then other=row end end
assert(other.key==shared.key)
assert(H.app:stage(shared,1800));assert(H.app:row_view(other)==1800)
H.app:discard()
local normal=unique['terminids/mode_1'];local independent=unique['terminids/mode_6']
assert(normal.vanilla==independent.vanilla)
local group=t.timerGroups[1];assert(group.duration==2400 and #group.rows==3)
assert(H.app:stage(normal,1800));assert(ui.group_value(H.app,group)==nil,'mixed values were hidden')
assert(H.app:row_view(independent)==2400);H.app:discard()
local s={group=group,x=10,width=100}
ui.begin_slider(H.app,s,110);assert(H.app.pending_n==0 and s.preview==2500)
H.app.drag.finish();H.app.drag=nil
assert(H.app.pending_n==3 and H.app:row_view(normal)==2500)
assert(H.app:row_view(independent)==2500 and ui.group_value(H.app,group)==2500)
-- A selected/preparing mission blocks the whole batch before a checkpoint or write.
local checkpoints=0;H.app.ctx.before_apply=function()checkpoints=checkpoints+1;return true end
H.catalog.real_hd2.game_state=function()return{state=6,name='PrepareMission'}end
H.app:apply();assert(H.app.confirm.kind=='mission_timer_block'and H.app.pending_n==3 and checkpoints==0)
assert(#H.frame({}).refused==0);H.app:confirm_yes();assert(H.app.pending_n==3)
H.catalog.real_hd2.game_state=function()return{state=4,name='Mission'}end
H.app:apply();assert(H.app.confirm.kind=='mission_timer_block'and checkpoints==0);H.app:confirm_yes()
H.catalog.real_hd2.game_state=function()return{state=3,name='Ship'}end
H.app:apply();settle();assert(H.app.pending_n==0 and checkpoints==1 and H.sim.value(normal)==2500)
assert(H.sim.value(independent)==2500)
assert(ui.stage_group(H.app,group,group.duration));H.app:apply();settle()
for _,row in ipairs(group.rows)do assert(H.sim.value(row)==2400)end
-- Non-mission edits never query game state.
local called=false;H.catalog.real_hd2.game_state=function()called=true;error('unexpected')end
assert(not require('mods/skyeshade/hd2runtime_editor/editor/missions').apply_block(H.catalog,{}));assert(not called)
return 'mission overview canonical sliders state warning apply reset ok'

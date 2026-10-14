local args=...
local H=assert(loadfile(args.harness))({sim=args.sim})
local app,cat,layer=H.app,H.catalog,H.layer
cat.indexed=true
local object=cat:objects('enemy_difficulty')[9]
assert(app:goto_object(object));cat:open(object)
local row
for _,r in ipairs(object.rows)do if r.field=='difficulty.encounter_points'then row=r;break end end
assert(row and row.editable)
local wanted=row.vanilla+1
assert(app:stage(row,wanted))
PickYourBots={status='ready'}
assert(app:spawn_block(row))
assert(not app:stage(row,wanted+1),'direct edits must be disabled')
app:apply();assert(app.pending_n==1 and not next(layer.slots),'pending field was registered')
local d=H.frame({});assert(#d.refused==0 and#d.items<1024)
assert(app.btn_spawn_picker)
local closed=0;app.ctx.close=function()closed=closed+1 end
PickYourBots.open_settings=function()return true end
app.btn_spawn_picker.click();assert(closed==1)
local overview=require('mods/skyeshade/hd2runtime_editor/editor/ui/spawn_overview')
assert(not overview.start(app,'terminids',2))
assert(app:goto_object(cat:object('eo|terminids')))
d=H.frame({});assert(#d.refused==0 and#d.items<1024)
-- Automatic restore must keep spawn values pending without a false crash marker.
app:discard()
H.presets:set_session({[row.key]=wanted})
local session=require('mods/skyeshade/hd2runtime_editor/editor/session').new({app=app,layer=layer,presets=H.presets})
local applied,carried=session:restore()
assert(applied==0 and carried==1 and app.pending_n==1)
session:tick();assert(not H.presets:application(),'compatibility block left a crash-recovery marker')
assert(H.presets:session()[row.key]==wanted)
app:apply();session:tick()
assert(app.pending_n==1 and not H.presets:application(),'manual refusal left a crash marker')
-- Unrelated weapon fields still work while the foreign mod owns spawns.
local weapon=cat:object('pw|AR-23 Liberator');cat:open(weapon)
local rof
for _,r in ipairs(weapon.rows)do if r.field=='weapon.fire_rate'then rof=r end end
assert(rof and not app:spawn_block(rof))
assert(layer:set(rof,rof.vanilla+100))
PickYourBots=nil;assert(not app:spawn_block(row))
return 'spawn ownership pending restore render bridge ok'

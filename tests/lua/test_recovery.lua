-- Each phase runs in a fresh Lua state, sharing only the real on-disk mod store.
local args=...
local H=assert(loadfile(args.harness))({sim=args.sim})
local app,layer,presets,S=H.app,H.layer,H.presets,H.sim
local stores=require('hd2runtime/runtime/mod_store')
stores.set_folder(args.folder)
local store=stores.open('mods/test/recovery')
presets.store=store
local session=require('mods/skyeshade/hd2runtime_editor/editor/session').new({app=app,layer=layer,presets=presets})
local function row(field)
 local object=assert(H.catalog:object('pw|AR-23 Liberator'));H.catalog:open(object)
 for _,r in ipairs(object.rows)do if r.field==field then return r end end
 error(field)
end
local rof,erg=row('weapon.fire_rate'),row('weapon.ergonomics')
local custom='custom|'..H_custom.id..'|cooldown'
local function seed(extra)
 local values={[rof.key]=rof.vanilla+100,[erg.key]=erg.vanilla+5,[custom]=90}
 if extra then values['pw|Missing|weapon.fire_rate']=999 end
 presets:set_session(values);store:set('presets',{{name='Keep me',fields={}}})
end
local function run(n)for _=1,n do H.frame({},{dt=0.1});session:tick()end end
local function disk()
 local f=assert(io.open(args.folder..'/'..store:describe().file,'rb'));local text=f:read('*a');f:close()
 return stores.decode(text)
end
local set=layer.set
layer.set=function(self,...)
 assert(disk().application.state=='applying','checkpoint must reach disk before any set')
 return set(self,...)
end
if args.phase=='interrupted'then
 seed();assert(session:restore()==3)
 assert(S.writes==0 and H_custom.cooldown==90,'stop after partial synchronous work, before async writes')
 assert(disk().application.state=='applying'and #disk().session==3)
elseif args.phase=='recovery'then
 assert(session:recover_interrupted());assert(app.pending_n==3 and not layer:busy())
 local d=H.frame({})
 assert(app.confirm and app.confirm.kind=='recovery')
 assert(#app:changes()==3)
 H.frame({'ENTER'});assert(not app.confirm,'Enter only dismisses the notice')
 run(120)
 assert(S.writes==0 and H_custom.cooldown==300 and next(layer.slots)==nil,'recovery must not apply even custom tunes')
 assert(app.pending_n==3 and disk().application~=nil,'dismissal and another boot must preserve recovery')
elseif args.phase=='retry'then
 assert(session:recover_interrupted());H.frame({});H.frame({'ENTER'})
 app:stage(rof,rof.vanilla+140);app:apply()
 assert(disk().application~=nil,'queuing is not completion')
 run(300)
 assert(S.value(rof)==rof.vanilla+140 and S.value(erg)==erg.vanilla+5 and H_custom.cooldown==90)
 assert(app.pending_n==0 and disk().application==nil,'all applications completed')
 assert(disk().presets[1].name=='Keep me')
 local saves=store.saved;run(100);assert(store.saved==saves,'no steady-state checkpoint writes')
elseif args.phase=='success'then
 assert(not session:recover_interrupted());assert(session:restore()==3)
 assert(app.recovery_notice==nil);run(300);assert(disk().application==nil)
elseif args.phase=='discard'then
 assert(session:recover_interrupted());app:discard();run(5)
 assert(app.pending_n==0 and next(presets:session())==nil and disk().application==nil)
 assert(S.writes==0 and H_custom.cooldown==300 and disk().presets[1].name=='Keep me')
elseif args.phase=='remove_one'then
 assert(session:recover_interrupted())
 app:stage(rof,rof.vanilla);session:tick();run(20)
 assert(app.pending_n==2 and presets:session()[rof.key]==nil,'editing a recovered value back to default removes it durably')
 app:discard();run(5);assert(disk().application==nil)
elseif args.phase=='failure'then
 seed(true);S.memory[erg.loc]='foreign bytes';session:restore();run(300)
 assert(layer:state(erg)=='error'and not layer:busy())
 assert(disk().application~=nil,'idle with errors or unknown keys is not successful completion')
elseif args.phase=='missing'then
 assert(session:recover_interrupted());assert(app.pending_n==4)
 H.frame({});H.frame({'ENTER'});H.frame({})
 assert(#app:changes()==4 and S.writes==0)
 app:discard();run(5);assert(disk().application==nil and next(presets:session())==nil)
elseif args.phase=='storage'then
 seed();store.save=function()return false,'disk full'end
 session:restore();run(30)
 assert(app.pending_n==3 and S.writes==0 and H_custom.cooldown==300)
 app:apply();run(30)
 assert(app.pending_n==3 and S.writes==0 and H_custom.cooldown==300,'failed checkpoint must prevent manual retry too')
elseif args.phase=='clear_failure'then
 seed();session:restore()
 local save=store.save
 store.save=function(self)if self:get('application')==nil then return false,'disk full'end return save(self)end
 run(300)
 assert(not layer:busy()and store:get('application')~=nil and disk().application~=nil)
elseif args.phase=='immediate_failure'then
 seed();session:restore();run(300)
 local values={[rof.key]=rof.vanilla+200}
 app:stage_recovered(values)
 layer.set=function()return false,'refused'end
 app:apply();session:tick();run(20)
 assert(app.pending_n==1 and presets:session()[rof.key]==rof.vanilla+200,'save the refused request, not its older active override')
 assert(disk().application~=nil)
else error('unknown phase')end
return args.phase..' ok'

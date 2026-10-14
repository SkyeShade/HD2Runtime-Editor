local args=...
local H=assert(loadfile(args.harness))({sim=args.sim})
local A=require('mods/skyeshade/hd2runtime_editor/editor/auto_freeze')
local ui=require('mods/skyeshade/hd2runtime_editor/editor/ui/mission_overview')
local presets=H.presets
-- The overview's box ticks every source of its duration group (shared sources included) in the editor's settings.
local o=assert(H.catalog:object('mo|terminids'));H.catalog:open(o);H.app:goto_object(o)
assert(#H.frame({}).refused==0)
local g=o.timerGroups[1];assert(g.duration==2400)
local state=assert(H.app.mission_sliders[o.key..'/'..g.duration],'drawn')
assert(#state.sources==#g.rows and not A.all(presets,state.sources))
state.freeze.click()
assert(A.all(presets,state.sources)and A.sources(presets)['terminids/mode_1'])
assert(#H.frame({}).refused==0)
-- The watcher: one read a second at mission start, the host only, ticked types only, once.
local handlers,timers,freezes,logs={},{},{},{}
local mod={on=function(_,name,fn)handlers[name]=fn end,
  every=function(_,s,fn,opts)assert(opts.scope=='mission');local t={fn=fn};function t.cancel()t.cancelled=true end
    timers[#timers+1]=t;return t end}
local report
local hd2={diagnostics={mission_timer=function()return report end},
  freeze_mission_timer=function(r)assert(r.frozen and r.allow_unverified_effect);freezes[#freezes+1]=r
    return {status='APPLIED',frozen=true,remainingSeconds=2390}end}
assert(A.start(hd2,mod,presets,function(t)logs[#logs+1]=t end))
local function run(t)while not t.cancelled do t.fn()end end
report={state='Mission',host=true,active={source='terminids/mode_1',paused=false}}
handlers.mission_started({host=true});run(timers[1])
assert(#freezes==1 and logs[#logs]:find('frozen',1,true))
-- a client: nothing scheduled (it follows the host)
handlers.mission_started({host=false});assert(#timers==1)
-- an unticked type, an already frozen timer: nothing
report={state='Mission',host=true,active={source='automatons/mode_1',paused=false}}
handlers.mission_started({host=true});run(timers[2]);assert(#freezes==1)
report={state='Mission',host=true,active={source='terminids/mode_1',paused=true}}
handlers.mission_started({host=true});run(timers[3]);assert(#freezes==1)
-- no countdown within TRIES: gives up
report={state='Mission',host=true,active=false}
handlers.mission_started({host=true});local n=0
while not timers[4].cancelled do timers[4].fn();n=n+1 end
assert(n==A.TRIES and logs[#logs]:find('no mission countdown',1,true))
-- unticked again: no timer at all
state.freeze.click();assert(not A.all(presets,state.sources))
A.set(presets,{'terminids/mode_1'},false)
handlers.mission_started({host=true});assert(#timers==4 or not next(A.sources(presets)))
return 'auto freeze ok'

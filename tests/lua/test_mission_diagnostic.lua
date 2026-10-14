local args=...
local H=assert(loadfile(args.harness))({sim=args.sim})
local M=require('mods/skyeshade/hd2runtime_editor/editor/ui/mission_diagnostic')
local calls,logs=0,{}
-- the packaged HD2Runtime has no primary_mapper (a development tool in its checkout)
local real_require=require
require=function(name)
 if tostring(name):find('^hd2runtime/primary_mapper/')then error('module '..name..' not found')end
 return real_require(name)
end
H.app.ctx.log=function(s)logs[#logs+1]=s end
H.catalog.real_hd2.diagnostics.mission_timer=function()
 calls=calls+1
 return {state='Mission',host=true,selected={name='Launch ICBM'},definitions={},
 active={baseSeconds=7200,effectiveSeconds=2400,remainingSeconds=2520,privateDefinition=true}}
end
local o=H.catalog:object('mo|terminids');H.catalog:open(o);H.app:goto_object(o);H.frame({});assert(calls==0)
H.app:stage(o.rows[1],7200);local pending=H.app.pending_n
M.check(H.app);assert(calls==1 and H.app.confirm.kind=='mission_timer_report')
assert(#logs==1 and logs[1]:find('"baseSeconds":7200',1,true)and logs[1]:find('"remainingSeconds":2520',1,true))
local sample=M.encode({a='x\ny',b={1,true}})
assert(sample=='{"a":"x\\ny","b":[1,true]}',sample)
assert(#H.frame({}).refused==0 and calls==1 and H.app.pending_n==pending)
H.app:confirm_yes();assert(H.app.pending_n==pending)
H.catalog.real_hd2.diagnostics.mission_timer=function()return nil,'guard refused'end
M.check(H.app);assert(H.app.confirm.data[2]=='guard refused')
assert(#H.frame({}).refused==0);H.app:confirm_yes()
H.catalog.real_hd2.diagnostics.mission_timer=nil
M.check(H.app);assert(H.app.confirm.kind=='mission_timer_report')
-- FREEZE TIMER: one read, then the Runtime's freeze with the editor's own acknowledgement; the label follows.
local toasts={};local toast=H.app.toast;H.app.toast=function(self,text)toasts[#toasts+1]=text end
local paused,requests=false,{}
local real=H.catalog.real_hd2
real.diagnostics.mission_timer=function()return {state='Mission',host=true,active={remainingSeconds=1832.4,paused=paused}}end
real.freeze_mission_timer=function(r)
 requests[#requests+1]=r;assert(r.allow_unverified_effect==true)
 paused=r.frozen;return {status='APPLIED',frozen=r.frozen,remainingSeconds=1832.4,verified=true}
end
M.toggle_freeze(H.app);assert(#requests==1 and requests[1].frozen==true and H.app.mission_timer_frozen==true)
assert(toasts[#toasts]:find('30:32',1,true),toasts[#toasts])
local o=H.catalog:object('mo|terminids');H.app:goto_object(o);assert(#H.frame({}).refused==0)
M.toggle_freeze(H.app);assert(#requests==2 and requests[2].frozen==false and H.app.mission_timer_frozen==false)
real.freeze_mission_timer=function()return nil,'SOLO_ONLY','solo only for now'end
M.toggle_freeze(H.app);assert(toasts[#toasts]:find('solo only for now',1,true)and H.app.mission_timer_frozen==false)
real.diagnostics.mission_timer=function()return {state='Ship',active=false}end
M.toggle_freeze(H.app);assert(H.app.mission_timer_frozen==nil)
real.freeze_mission_timer=nil
M.toggle_freeze(H.app);assert(#toasts==5)
-- The Missions group lists the per-front overviews; the duration and Mission Timer pages stay resolvable, unlisted.
local C=require('mods/skyeshade/hd2runtime_editor/editor/catalog')
local listed={}
for _,g in ipairs(C.GROUPS)do if g.id=='missions'then for _,i in ipairs(g.items)do listed[#listed+1]=i.id end end end
assert(#listed==1 and listed[1]=='mission_overview',table.concat(listed,','))
assert(H.catalog:object('mi|terminids/3428204c')and H.catalog:object('mo|terminids'))
local page=assert(H.catalog:object('mt|freeze'));H.app:goto_object(page);assert(#H.frame({}).refused==0)
real.freeze_mission_timer=function()return nil,'HOST_ONLY','the host controls the mission timer'end
real.diagnostics.mission_timer=function()return {state='Mission',host=false,active={remainingSeconds=900,paused=false}}end
M.toggle_freeze(H.app);assert(#toasts==6)
H.app.toast=toast
require=real_require
return 'mission diagnostic explicit read only log popup failure ok'

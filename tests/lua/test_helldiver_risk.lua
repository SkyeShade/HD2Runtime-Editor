local args=...
local H=assert(loadfile(args.harness))({sim=args.sim})
local C=require('mods/skyeshade/hd2runtime_editor/editor/catalog')
-- The Helldiver's own stats carry the GameGuard warning (chip, note, the first stage's toast), with their own reason.
local o=assert(H.catalog:object('hd|Helldiver'));H.catalog:open(o)
local stat,count
count=0
for _,r in ipairs(o.rows)do
    if r.risk=='gameguard'then
        count=count+1
        assert(r.risk_note==C.HELLDIVER_GAMEGUARD_RISK)
        if not stat and not r.kind and type(r.vanilla)=='number'and r.max and r.max>r.vanilla then stat=r end
    end
end
assert(count>0 and stat,'Helldiver stat rows are marked')
local toasts={};local toast=H.app.toast;H.app.toast=function(self,text)toasts[#toasts+1]=text end
H.app.gameguard_warned=nil
assert(H.app:stage(stat,stat.vanilla+1))
local found=0
for _,t in ipairs(toasts)do if t:find(C.HELLDIVER_GAMEGUARD_RISK,1,true)then found=found+1 end end
assert(found==1,'the first stage warns once: '..table.concat(toasts,' | '))
assert(H.app:stage(stat,stat.vanilla+2))
found=0;for _,t in ipairs(toasts)do if t:find(C.HELLDIVER_GAMEGUARD_RISK,1,true)then found=found+1 end end
assert(found==1,'once a session')
H.app.toast=toast
H.app:goto_object(o);assert(#H.frame({}).refused==0)
return 'helldiver gameguard warning ok'

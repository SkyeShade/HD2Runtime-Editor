-- The saved session over the real app, layer and Runtime ensure (tests/lua/ui_harness.lua): a saved value that does not
-- come back at a start (refused by the Runtime this time, a row this catalogue lacks, a custom stratagem not registered)
-- stays saved for the next start until the player changes or resets it; a field still applying never holds a save back.
local args=...
local H=assert(loadfile(args.harness))({sim=args.sim})
local session_module=require('mods/skyeshade/hd2runtime_editor/editor/session')
local app,layer,presets,catalog,S=H.app,H.layer,H.presets,H.catalog,H.sim
local logged={}
local function check(cond,msg)
    if not cond then error('FAILED: '..msg..'\n'..table.concat(logged,'\n')..'\n'..table.concat(S.log,'\n'),2)end
end
local function row(object_key,field)
    local object=assert(catalog:object(object_key),'no object '..object_key)
    catalog:open(object)
    for _,r in ipairs(object.rows)do if r.field==field and r.section~=nil then return r end end
    error('no row '..field..' on '..object_key)
end
local function run(seconds,session)
    local t=0
    while t<seconds do H.frame({},{dt=0.1});session:tick();t=t+0.1 end
end
local out={}

local rof=row('pw|AR-23 Liberator','weapon.fire_rate')
local erg=row('pw|AR-23 Liberator','weapon.ergonomics')
local MISSING='pw|No Such Weapon|weapon.fire_rate'
local UNREGISTERED='custom|not_registered|cooldown'
presets:set_session({[rof.key]=rof.vanilla+100,[erg.key]=erg.vanilla+5,[MISSING]=900,[UNREGISTERED]=45})
-- this start, something outside HD2Runtime holds the ergonomics bytes: the Runtime refuses the editor's write
S.memory[erg.loc]='foreign bytes'
-- and only the harness's own custom stratagem is registered (the Runtime refuses to tune any other)
local api=app.hd2.custom_stratagem
local tune=api.tune
api.tune=function(id,v)
    if id~=H_custom.id then return nil,'no custom stratagem '..tostring(id)end
    return tune(id,v)
end

-- 1. The restore: the fire rate comes back; the other three do not, and every one stays saved.
local session=session_module.new({app=app,layer=layer,presets=presets,log=function(m)logged[#logged+1]=m end})
app.ctx.forget_saved=function()session:forget_all()end
local applied,carried=session:restore()
check(applied==2 and carried==2,'two values set (one refused later), two not available: '..applied..'/'..carried)
check(logged[1]and logged[1]:find(MISSING,1,true)and logged[1]:find(UNREGISTERED,1,true),'the log names them: '
    ..tostring(logged[1]))
-- a field still applying does not hold the save back
check(layer:busy(),'fields applying')
app.save_session=true
session:tick()
local saved=presets:session()
check(saved[rof.key]==rof.vanilla+100,'saved while applying')
run(30,session)
check(S.value(rof)==rof.vanilla+100,'the fire rate came back: '..tostring(S.value(rof)))
check(layer:state(erg)=='error','the ergonomics write was refused: '..tostring(layer:state(erg)))
saved=presets:session()
check(saved[rof.key]==rof.vanilla+100,'restored value saved')
check(saved[erg.key]==erg.vanilla+5,'refused value still saved')
check(saved[MISSING]==900,'missing row still saved')
check(saved[UNREGISTERED]==45,'unregistered custom stratagem still saved')
out[#out+1]='kept ok'

-- 2. The player's own changes win: a new value replaces the saved one, a reset drops it.
app:stage(rof,rof.vanilla+200)
app:apply()
run(10,session)
check(presets:session()[rof.key]==rof.vanilla+200,'changed value saved')
app:reset_change({row=erg})
run(5,session)
saved=presets:session()
check(saved[erg.key]==nil,'reset field dropped: '..tostring(saved[erg.key]))
check(saved[MISSING]==900 and saved[UNREGISTERED]==45,'the others stay')
out[#out+1]='player wins ok'

-- 3. Reset to defaults forgets the values that did not come back too.
app:reset_defaults()
-- (1.0.1: nothing changes until Apply)
run(5,session)
check(presets:session()[rof.key]~=nil,'REVERT ALL alone keeps the saved values until Apply')
app:apply()
run(10,session)
saved=presets:session()
check(next(saved)==nil,'nothing saved after Reset to defaults: '..tostring(next(saved)))
out[#out+1]='reset all ok'

-- 4. The next start restores what the previous start could not.
S.memory[erg.loc]=nil
presets:set_session({[erg.key]=erg.vanilla+5})
local again=session_module.new({app=app,layer=layer,presets=presets})
check(again:restore()==1,'restored at the next start')
run(30,again)
check(S.value(erg)==erg.vanilla+5,'ergonomics applied: '..tostring(S.value(erg)))
out[#out+1]='next start ok'
return table.concat(out,'\n')

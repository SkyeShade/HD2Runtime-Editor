-- The override layer against the real Runtime ensure / options / validation code (tests/lua/sim.lua).
local S=dofile(...)
local hd2=S.hd2
local EDITOR='mods/skyeshade/hd2runtime_editor'
local catalog=require('mods/skyeshade/hd2runtime_editor/editor/catalog')
local ledger=require('mods/skyeshade/hd2runtime_editor/editor/ledger').install(hd2,EDITOR)
local cat=catalog.new(hd2)
local layer=require('mods/skyeshade/hd2runtime_editor/editor/layer').new({hd2=hd2,id=EDITOR,ledger=ledger,catalog=cat})
local out={}
local function check(cond,msg)if not cond then error('FAILED: '..msg..'\n'..table.concat(S.log,'\n'),2)end end
local function run(seconds)
    local t=0
    while t<seconds do S.tick(0.1);layer:tick(0.1);t=t+0.1 end
end
local function row(object_key,field)
    local object=assert(cat:object(object_key),'no object '..object_key)
    cat:open(object)
    for _,r in ipairs(object.rows)do if r.field==field and(r.section~=nil)then return r end end
    error('no row '..field..' on '..object_key)
end
local function settle(r)
    for _=1,200 do
        run(0.5)
        local state=layer:state(r)
        if state~='applying'then return state end
    end
    return layer:state(r)
end

-- 1. A field no mod touches: set, then reset (the editor lets go; the bytes are vanilla again).
local rof=row('pw|AR-23 Liberator','weapon.fire_rate')
local vanilla=rof.vanilla
check(select(1,layer:value(rof))==vanilla,'vanilla first')
assert(layer:set(rof,vanilla+100))
check(settle(rof)=='active','active after apply: '..tostring((select(2,layer:state(rof)))))
check(S.value(rof)==vanilla+100,'bytes hold the editor value: '..tostring(S.value(rof)))
layer:reset(rof)
check(settle(rof)=='idle','released after reset')
check(S.value(rof)==vanilla,'bytes back at vanilla: '..tostring(S.value(rof)))
check(layer:slot_of(rof)==nil,'no slot left')
out[#out+1]='vanilla set/reset ok'

-- 2. A mod's ensure holds a transaction (fire rate + ergonomics). The editor takes the fire rate over: every field of
-- the operation is adopted first, then the mod's ensure is stopped; reset returns to the mod's value and keeps it.
local erg=row('pw|AR-23 Liberator','weapon.ergonomics')
local mod_watch=hd2.events.run_as('mods/test/liberator',function()
    return hd2.ensure({transaction={id='liberator-buff',target=hd2.weapon('AR-23 Liberator'),changes={
        {field='weapon.fire_rate',expect=vanilla,value=1200},
        {field='weapon.ergonomics',expect=erg.vanilla,value=erg.vanilla+10}}}})
end)
run(5)
check(S.value(rof)==1200,'mod applied 1200: '..tostring(S.value(rof)))
local value,source,holder=layer:value(rof)
check(value==1200 and source=='mod'and holder.mod=='mods/test/liberator','ledger names the mod: '..tostring(source))
assert(layer:set(rof,1300))
check(settle(rof)=='active','editor active over the mod: '..tostring((select(2,layer:state(rof)))))
check(S.value(rof)==1300,'bytes 1300: '..tostring(S.value(rof)))
check(mod_watch.status=='cancelled','the mod ensure was handed over: '..tostring(mod_watch.status))
check(layer:state(erg)=='held','the mod\'s other field is held by the editor: '..layer:state(erg))
check(S.value(erg)==erg.vanilla+10,'ergonomics keeps the mod value')
layer:reset(rof)
check(settle(rof)=='held','after reset the editor holds the mod value')
check(S.value(rof)==1200,'reset returns to the mod value 1200: '..tostring(S.value(rof)))
check(select(2,layer:value(rof))=='mod','shown as the mod value')
-- Edit again: the editor already holds it, so this is a single owned transition.
local writes=S.writes
assert(layer:set(rof,1250))
check(settle(rof)=='active','second edit')
check(S.value(rof)==1250 and S.writes==writes+1,'one write for one change')
layer:reset(rof);settle(rof)
check(S.value(rof)==1200,'back to the mod value again')
out[#out+1]='mod ensure takeover/reset ok'

-- 3. A one-shot mod patch on a shared projectile damage row: override, then reset releases (bytes = mod value).
local dmg=row('pw|AR-23 Liberator','damage.standard_damage')
local p=hd2.events.run_as('mods/test/damage',function()
    return hd2.patch({id='lib-dmg',target=hd2.weapon('AR-23 Liberator'):attack('primary'):projectile(),
        field='damage.standard_damage',expect=dmg.vanilla,value=dmg.vanilla+30,allow_shared=true})
end)
run(5)
check(p.status=='complete','mod patch applied: '..tostring(p.status)..' '..tostring(p.error))
check(S.value(dmg)==dmg.vanilla+30,'mod damage written')
assert(layer:set(dmg,dmg.vanilla+60))
check(settle(dmg)=='active','damage override active: '..tostring((select(2,layer:state(dmg)))))
check(S.value(dmg)==dmg.vanilla+60,'damage override written')
layer:reset(dmg)
check(settle(dmg)=='idle','released after reset (one-shot base)')
check(S.value(dmg)==dmg.vanilla+30,'mod damage value back')
out[#out+1]='one-shot mod patch override/reset ok'

-- 4. A value far outside the first handle's range: adopted again with a wider handle (the old ensure handed over).
local vel=row('pw|AR-23 Liberator','projectile.velocity')
assert(layer:set(vel,vel.vanilla+1))
check(settle(vel)=='active','velocity first edit')
assert(layer:set(vel,vel.vanilla*40))
check(settle(vel)=='active','velocity rebind: '..tostring((select(2,layer:state(vel)))))
check(math.abs(S.value(vel)-vel.vanilla*40)<1e-3,'velocity far value written: '..tostring(S.value(vel)))
layer:reset(vel);settle(vel)
check(math.abs(S.value(vel)-vel.vanilla)<1e-3,'velocity back to vanilla')
out[#out+1]='rebind ok'

-- 5. Refusals: too many decimals, outside the reviewed range.
local ok,why=layer:set(rof,1000.0001)
check(not ok and why:find('decimals'),'decimals refused')
local burst=row('pw|AR-23 Liberator','fire_mode.burst_rounds')
if burst.max then
    ok=layer:set(burst,burst.max+1)
    check(not ok,'range refused')
end
out[#out+1]='refusals ok'

-- 6. Reset everything.
assert(layer:set(rof,1400));assert(layer:set(vel,vel.vanilla+5))
run(3)
layer:reset_all()
for _=1,60 do run(0.5) end
check(S.value(rof)==1200 and math.abs(S.value(vel)-vel.vanilla)<1e-3,'reset all')
local active,applying,errors=layer:counts()
check(active==0 and applying==0 and errors==0,'nothing active after reset all')
out[#out+1]='reset all ok'
return table.concat(out,'\n')

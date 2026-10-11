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

-- 7. Values another mod owns (HD2Runtime 0.31.0 hd2.inspect): the rows hd2.inspect reports foreign or changed are
-- locked with the reason, one request per target; the others stay editable; an older Runtime changes nothing.
do
    local object=assert(cat:object('pw|AR-23 Liberator'))
    cat:open(object)
    local real=cat.real_hd2
    local requests={}
    cat.real_hd2=setmetatable({inspect=function(req)
        requests[#requests+1]=req
        local result={fields={}}
        for i,f in ipairs(req.fields)do
            result.fields[i]={field=f.field,state=(f.field=='weapon.fire_rate'and'foreign')
                or(f.field=='projectile.velocity'and'changed')or'vanilla',owner='unknown',value=1500}
        end
        req.on_result(result)
        return {}
    end},{__index=real})
    object.owners_checked=nil
    cat:check_owners(object)
    cat.real_hd2=real
    local by={}
    for _,r in ipairs(object.rows)do by[r.field]=by[r.field]or r end
    check(#requests>=2,'one request per target: '..#requests)
    check(by['weapon.fire_rate'].editable==false and by['weapon.fire_rate'].reason:find('another mod',1,true)
        and by['weapon.fire_rate'].reason:find('1500',1,true),'the foreign value is locked with its value')
    check(by['projectile.velocity'].editable==false,'the changed value is locked')
    check(by['weapon.ergonomics'].editable==true,'a vanilla value stays editable')
    local before=#requests
    cat:check_owners(object)
    check(#requests==before,'checked once')
    local other=assert(cat:object('pw|P-2 Peacemaker'))
    cat:open(other)
    cat.real_hd2=setmetatable({inspect=false},{__index=real})
    cat:check_owners(other)
    cat.real_hd2=real
    for _,r in ipairs(other.rows)do check(not r.foreign,'no inspect: nothing locked')end
    -- bytes HD2Runtime keeps no claim for (a booster table) read 'changed', no owner, no reason, even when the editor
    -- wrote them: such a field the editor (or an HD2Runtime mod) holds stays editable; one nothing explains is locked
    -- with the value the game holds
    local booster=cat:object('bo|Integrated Extinguishers')
    if booster then
        cat:open(booster)
        local burn=booster.rows[1]
        assert(layer:set(burn,0.9))
        check(settle(burn)=='active','booster value applied')
        local function changed(held)
            for _,r in ipairs(booster.rows)do r.editable,r.foreign,r.reason=true,nil,nil end
            booster.owners_checked=nil
            cat.real_hd2=setmetatable({inspect=function(req)
                local result={fields={}}
                for i,f in ipairs(req.fields)do result.fields[i]={field=f.field,state='changed',value=0.9}end
                req.on_result(result)
                return {}
            end},{__index=real})
            cat:check_owners(booster,held)
            cat.real_hd2=real
        end
        local function held(r)return layer:slot_of(r)~=nil end
        changed(held)
        check(burn.editable==true and not burn.foreign,'the editor\'s own booster value is not locked')
        changed(function()return false end)
        check(burn.editable==false and burn.reason:find('0.9',1,true)and burn.reason:find('another mod',1,true),
            'an unexplained value is locked with what the game holds: '..tostring(burn.reason))
        for _,r in ipairs(booster.rows)do r.editable,r.foreign,r.reason=true,nil,nil end
        layer:reset(burn)
        check(settle(burn)=='idle','booster value reset')
    end
end
out[#out+1]='foreign values locked'
return table.concat(out,'\n')

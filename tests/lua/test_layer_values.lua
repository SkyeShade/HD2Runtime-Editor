-- Non-numeric fields through the override layer (HD2Runtime r50 script choices) against the real Runtime ensure,
-- options and validation code (tests/lua/sim.lua): calldown codes, mission uses, booleans, statuses, projectile swaps
-- and terminal explosions; and a mod's calldown code taken over and given back.
local S=dofile(...)
local hd2=S.hd2
local EDITOR='mods/skyeshade/hd2runtime_editor'
local catalog=require('mods/skyeshade/hd2runtime_editor/editor/catalog')
local util=require('mods/skyeshade/hd2runtime_editor/editor/util')
local ledger=require('mods/skyeshade/hd2runtime_editor/editor/ledger').install(hd2,EDITOR)
local cat=catalog.new(hd2)
local layer=require('mods/skyeshade/hd2runtime_editor/editor/layer').new({hd2=hd2,id=EDITOR,ledger=ledger,catalog=cat})
local out={}
local function check(cond,msg)if not cond then error('FAILED: '..msg..'\n'..table.concat(S.log,'\n')..'\n'..table.concat(layer.history,'\n'),2)end end
local function run(seconds)local t=0;while t<seconds do S.tick(0.1);layer:tick(0.1);t=t+0.1 end end
local function settle(r)
    for _=1,200 do run(0.5);if layer:state(r)~='applying'then break end end
    return layer:state(r),select(2,layer:state(r))
end
local function row_of(object,predicate)
    local o=assert(cat:object(object),object);cat:open(o)
    for _,r in ipairs(o.rows)do if predicate(r)then return r end end
    error('no row on '..object)
end
local function cycle(r,value,label)
    run(1)
    local before=S.memory[r.loc]
    assert(layer:set(r,value))
    local state,why=settle(r)
    check(state=='active',label..' active: '..tostring(state)..' '..tostring(why))
    check(util.same((layer:value(r)),value),label..' shows the value')
    local written=S.memory[r.loc]
    check(written~=nil and written~=before,label..' written')
    layer:reset(r)
    state=settle(r)
    check(state=='idle',label..' released after reset: '..tostring(state))
    check(S.memory[r.loc]~=written,label..' bytes changed back')
    out[#out+1]=label..' ok'
end

local code=row_of('st|Eagle Smoke Strike',function(r)return r.kind=='code'end)
cycle(code,{'up','up','up','down'},'calldown code')
local uses=row_of('st|EXO-55 Breakthrough Exosuit',function(r)return r.kind=='uses'end)
cycle(uses,'unlimited','mission uses')
local bool=row_of('pw|P-19 Redeemer',function(r)return r.field=='weapon.suppressed'end)
cycle(bool,true,'boolean')
local status=row_of('pw|BR-14 Adjudicator',function(r)return r.kind=='choice'and r.field=='damage.status_1_type'end)
cycle(status,'fire','status')
local swap=row_of('pw|BR-14 Adjudicator',function(r)return r.kind=='reference'and r.field=='attack.projectile'end)
local donor
for _,o in ipairs(swap.options(swap))do
    if not util.same(o.value,swap.vanilla)and catalog.probe(swap,o.value)then donor=o.value;break end
end
check(donor,'a valid projectile donor')
cycle(swap,donor,'projectile swap')
local payload=row_of('pw|BR-14 Adjudicator',function(r)return r.kind=='reference'and r.field=='terminal.explosion'end)
local blast
for _,o in ipairs(payload.options(payload))do
    if not util.same(o.value,payload.vanilla)and catalog.probe(payload,o.value)then blast=o.value;break end
end
check(blast,'a valid explosion donor')
cycle(payload,blast,'terminal explosion')

-- refusals: a direction a code does not take, a code too long, uses out of range
check(not layer:set(code,{'up','sideways'}),'unknown direction refused')
check(not layer:set(code,{'up','up','up','up','up','up','up','up','up','up'}),'too long refused')
check(not layer:set(uses,0),'uses below the minimum refused')
out[#out+1]='refusals ok'
-- a first edit of a field that holds its original value writes directly: no adopt-then-steer
local spread=row_of('pw|AR-11 Arbitrator',function(r)return r.field=='weapon.horizontal_spread'end)
run(1)
local mark=#layer.history
assert(layer:set(spread,10))
check(settle(spread)=='active','spread active')
check(S.value(spread)==10,'spread written: '..tostring(S.value(spread)))
for i=mark+1,#layer.history do check(not layer.history[i]:find('^steer'),'no steer on a first edit: '..layer.history[i])end
layer:reset(spread)
check(settle(spread)=='idle','spread released')
check(S.value(spread)==spread.vanilla,'spread back to its original value')
out[#out+1]='direct first edit ok'
-- an empty rate slot filled on a weapon without a rate selector: one transaction binds the selector with the rates
local rates=row_of('pw|AR-23 Liberator',function(r)return r.kind=='rates'end)
check(catalog.rate_binding(rates,{450,640,950})~=nil,'the Liberator needs its selector bound for three rates')
check(catalog.rate_binding(rates,{0,700,0})==nil,'one rate needs no binding')
check(catalog.probe(rates,{450,640,950}),'three rates pass as a transaction')
cycle(rates,{450,640,950},'rate slots with selector binding')
-- the armory's displayed traits and displayed penetration: one at a time (they share five label slots)
local traits=row_of('pw|AR-23 Liberator',function(r)return r.kind=='traits'end)
local shown=row_of('pw|AR-23 Liberator',function(r)return r.field=='presentation.armor_penetration'end)
check(traits.section=='Armory'and shown.section=='Armory','armory section')
run(1)
assert(layer:set(traits,{'light_armor_penetrating','explosive'}))
check(settle(traits)=='active','traits active')
local refused,why=layer:set(shown,'heavy')
check(not refused and tostring(why):find('shares its game data'),'one at a time: '..tostring(why))
layer:reset(traits)
check(settle(traits)=='idle','traits released')
cycle(shown,'heavy','displayed penetration')
out[#out+1]='armory traits ok'
-- the steer watchdog: an ensure that never settles on a steer is replaced by a fresh one (adopted at the held
-- value), which applies the change; the decision is in the history
local wd=row_of('st|Eagle Smoke Strike',function(r)return r.kind=='code'end)
run(1)
assert(layer:set(wd,{'up','down','up','down'}))
check(settle(wd)=='active','watchdog field active')
local slot=layer:slot_of(wd)
slot.watch={status='waiting',runs=slot.watch.runs,rebinds=0,recoveries=0,cancel=function()end,
    debug=function()return {dirty=true,debounce=0.5,ticks=0}end}
-- back to the default: a reset, steered through the stuck ensure
assert(layer:set(wd,wd.vanilla))
run(3)
check(layer:state(wd)=='applying','still applying after 3 s')
local taken=false
local state=settle(wd)
for _,line in ipairs(layer.history)do if line:find('fresh ensure')and line:find('ticks=0')then taken=true end end
check(taken,'taken over by a fresh ensure, with the internals of the stuck ensure logged')
check(state=='idle'and util.same(layer:value(wd),wd.vanilla),'the reset applied and released the field: '..tostring(state))
layer:reset(wd)
settle(wd)
out[#out+1]='steer watchdog ok'

-- a steer the ensure skips (live r52-r55: its settle found the signature it applied last) is settled again: the
-- editor forgets the applied signature on every steer, and once more with a diagnostic when it still stalls
local function find_up(fn,name,depth,seen)
    seen=seen or{}
    if type(fn)~='function'or seen[fn]or(depth or 0)>4 then return nil end
    seen[fn]=true
    for i=1,255 do
        local n,v=debug.getupvalue(fn,i)
        if n==nil then break end
        if n==name then return fn,i,v end
        if type(v)=='function'then
            local f,k,x=find_up(v,name,(depth or 0)+1,seen)
            if f then return f,k,x end
        end
    end
end
local sk=row_of('pw|AR-2 Coyote',function(r)return r.field=='weapon.horizontal_spread'end)
run(1)
assert(layer:set(sk,10));check(settle(sk)=='active','skip: first edit')
assert(layer:set(sk,500));check(settle(sk)=='active','skip: re-adopted edit')
local w=layer:slot_of(sk).watch
check(select(2,find_up(w.debug,'applied_signature'))~=nil,'the ensure internals are reachable')
-- the live failure, made to happen: right after the next steer, the ensure records the new value as already applied
local function skip_now()
    local f,i=find_up(w.debug,'applied_signature')
    local build,signature,kind=select(3,find_up(w.tick,'build')),select(3,find_up(w.tick,'signature')),select(3,find_up(w.tick,'kind'))
    debug.setupvalue(f,i,signature(kind,build(),true))
end
assert(layer:set(sk,40))
layer:tick(0.1)
check(layer:slot_of(sk).phase=='steer','steering')
skip_now()
local state=settle(sk)
local diagnosed=false
for _,line in ipairs(layer.history)do if line:find('settling it again')and line:find('SAME')then diagnosed=true end end
check(diagnosed,'the skipped steer is diagnosed')
check(state=='active'and util.same(layer:value(sk),40),'the skipped steer applied after settling again: '..tostring(state))
layer:reset(sk);settle(sk)
out[#out+1]='skipped steer settled again ok'

-- a field with a disable sentinel (gore.whole_body_gib_damage: -1 disables, else above 0): its handle holds exact
-- values (no range could span the gap: live, a range starting at -1 was refused at -0.999); the gap is refused
local gib=row_of('en|hunter_base',function(r)return r.field=='gore.whole_body_gib_damage'end)
check(gib.disabled_value==-1 and gib.vanilla==500,'the gib threshold row knows its disable value')
local ok_gap,why_gap=layer:set(gib,-0.5)
check(ok_gap==false and tostring(why_gap):find('disables it',1,true),'a value in the gap is refused: '..tostring(why_gap))
assert(layer:set(gib,-1))
local gstate,gwhy=settle(gib)
check(gstate=='active','disabled (-1) applied: '..tostring(gstate)..' '..tostring(gwhy))
assert(layer:set(gib,250))
gstate,gwhy=settle(gib)
check(gstate=='active'and util.same(layer:value(gib),250),'re-enabled at 250: '..tostring(gstate)..' '..tostring(gwhy))
layer:reset(gib)
check(settle(gib)=='idle','reset to its own 500')
local hive=row_of('en|Hive Guard',function(r)return r.field=='gore.whole_body_gib_damage'end)
assert(layer:set(hive,300))
gstate,gwhy=settle(hive)
check(gstate=='active','enabled from the disable value: '..tostring(gstate)..' '..tostring(gwhy))
layer:reset(hive);settle(hive)
out[#out+1]='disable sentinel ok'

-- Helldiver fields (hd2.helldiver(), 0.30.0-dev): a speed, a damage zone's enum and health
local function cycle_number(r,value,label)
    run(1)
    assert(layer:set(r,value))
    local state,why=settle(r)
    check(state=='active',label..' active: '..tostring(state)..' '..tostring(why))
    check(S.memory[r.loc]~=nil,label..' written')
    layer:reset(r)
    check(settle(r)=='idle',label..' released')
end
cycle_number(row_of('hd|Helldiver',function(r)return r.field=='helldiver.speed.sprint'end),7,'helldiver sprint')
cycle(row_of('hd|Helldiver',function(r)return r.field=='zone.damage_multiplier'and r.key:find('|head:')end),'critical',
    'helldiver head multiplier')
cycle_number(row_of('hd|Helldiver',function(r)return r.field=='zone.health'and r.key:find('|leg_left:')end),200,
    'helldiver leg health')
out[#out+1]='helldiver fields ok'
-- Armor (hd2.armor_stats): a kit's piece weight, a class factor and the damage curve
cycle(row_of('ar|1F9BFA78',function(r)return r.field=='armor_kit.piece_weight.torso'end),'heavy','armor kit torso')
cycle_number(row_of('ar|classes',function(r)return r.field=='armor_class.speed'end),1.2,'armor class speed')
cycle_number(row_of('ar|damage curve',function(r)return r.field=='armor_damage_curve.at_0'end),1,'armor damage curve')
out[#out+1]='armor stats ok'
-- Armor perks: one hd2.player_passives.set for both rows; a refusal shows on the rows; reset stops the override
local real_perks=hd2.player_passives
local sets,stops={},0
hd2.player_passives={set=function(spec)
    sets[#sets+1]=spec
    local h={status=spec.second==17 and'refused'or'active',code=spec.second==17 and'ARMOR_SLOT_ONLY'or nil,
        reason='armor slot only'}
    function h.stop()stops=stops+1;h.status='stopped'end
    return h
end}
local perk_armor=row_of('hd|Armor perks',function(r)return r.field=='player_passives.armor'end)
local perk_second=row_of('hd|Armor perks',function(r)return r.field=='player_passives.second'end)
check(perk_armor.controller=='passives'and catalog.probe(perk_armor,2),'perk rows are controller rows')
assert(layer:set(perk_armor,2))
check(layer:state(perk_armor)=='applying','perk pending until the tick')
run(0.2)
check(layer:state(perk_armor)=='active'and#sets==1 and sets[1].armor==2 and sets[1].second==nil
    and sets[1].allow_unverified_effect==true,'armor perk set')
assert(layer:set(perk_second,7))
run(0.2)
check(#sets==2 and stops==1 and sets[2].armor==2 and sets[2].second==7,'both perks in one set, the old one stopped')
assert(layer:set(perk_second,17))
run(0.2)
local state,why=layer:state(perk_second)
check(state=='error'and tostring(why):find('ARMOR_SLOT_ONLY'),'a refused perk shows its reason: '..tostring(why))
layer:reset(perk_second)
run(0.2)
check(layer:state(perk_armor)=='active'and sets[#sets].second==nil,'second perk reset, the armor perk set again')
check(layer:overrides()[perk_armor.key]==2,'perks are saved with the session')
layer:reset(perk_armor)
run(0.2)
check(layer:state(perk_armor)=='idle'and layer.perks==nil and stops==#sets,'all perks reset: the override stopped')
local export=require('mods/skyeshade/hd2runtime_editor/editor/export')
local text,reason=export.operation(catalog,{row=perk_armor,value=2},'x')
check(text==nil and tostring(reason):find('not exported'),'perks are not exported: '..tostring(reason))
hd2.player_passives=real_perks
out[#out+1]='armor perks ok'

-- a mod's ensure sets a calldown code; the editor takes it over and gives it back
local precision=row_of('st|Orbital Precision Strike',function(r)return r.kind=='code'end)
local mod_code={'right','down','up'}
local watch=hd2.events.run_as('mods/test/codes',function()
    return hd2.ensure({patch={id='precision-code',target=hd2.stratagem('Orbital Precision Strike'),
        field='stratagem.calldown_code',expect=precision.vanilla,value=mod_code}})
end)
run(5)
local value,source,holder=layer:value(precision)
check(source=='mod'and holder.mod=='mods/test/codes'and util.same(value,mod_code),'the mod code is attributed: '..tostring(source))
local mod_bytes=S.memory[precision.loc]
assert(layer:set(precision,{'left','left','up'}))
local state,why=settle(precision)
check(state=='active','editor code over the mod: '..tostring(why))
check(watch.status=='cancelled','the mod ensure was handed over: '..tostring(watch.status))
layer:reset(precision)
settle(precision)
check(S.memory[precision.loc]==mod_bytes,'reset returns the mod code')
check(layer:state(precision)=='held','held at the mod code')
out[#out+1]='mod code takeover ok'
-- a value equal to the base is a reset: the mod's value over a mod, the game's value otherwise
assert(layer:set(precision,{'left','left','up'}))
check(settle(precision)=='active','editor code over the mod again')
assert(layer:set(precision,mod_code))
settle(precision)
check(layer:state(precision)=='held'and S.memory[precision.loc]==mod_bytes and layer:overrides()[precision.key]==nil,
    'setting the mod value resets to it: '..tostring(layer:state(precision)))
local plain=row_of('pw|AR-2 Coyote',function(r)return r.field=='weapon.horizontal_spread'end)
assert(layer:set(plain,9));check(settle(plain)=='active','plain field edited')
assert(layer:set(plain,plain.vanilla))
check(settle(plain)=='idle'and layer:overrides()[plain.key]==nil,'setting the default resets the field')
assert(layer:set(plain,plain.vanilla))
check(layer:slot_of(plain)==nil,'the default on an untouched field changes nothing')
out[#out+1]='base value is a reset ok'
return table.concat(out,'\n')

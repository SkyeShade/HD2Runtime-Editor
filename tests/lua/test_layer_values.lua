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
return table.concat(out,'\n')

-- Fields that depend on another field, in the override layer over the real ensure (tests/lua/sim.lua):
-- * the Eagle Rearm pool (HD2Runtime 0.31.0): a pool member keeps a finite use count (REARM_POOL_UNLIMITED), so joining
--   waits for finite Mission uses, the combination with unlimited uses is refused at once, and resetting the uses
--   takes the stratagem out of the pool the editor put it in;
-- * beam conversions (HD2Runtime 0.31.0, feature-detected): a converted weapon's own settings apply
--   only once the weapon is converted. The layer refuses a setting while the conversion is off, holds it back while
--   the conversion is being applied, and takes it back when the conversion is turned off.
local S=dofile(...)
local hd2=S.hd2
local EDITOR='mods/skyeshade/hd2runtime_editor'
local catalog=require('mods/skyeshade/hd2runtime_editor/editor/catalog')
local ledger=require('mods/skyeshade/hd2runtime_editor/editor/ledger').install(hd2,EDITOR)
local cat=catalog.new(hd2)
local layer=require('mods/skyeshade/hd2runtime_editor/editor/layer').new({hd2=hd2,id=EDITOR,ledger=ledger,catalog=cat})
local out={}
local function check(cond,msg)if not cond then error('FAILED: '..msg..'\n'..table.concat(S.log,'\n'),2)end end
local function run(n)for _=1,n do S.tick(0.1);layer:tick(0.1)end end

do
    local object=assert(cat:object('sp|GR-8 Recoilless Rifle'))
    cat:open(object)
    local uses,pool
    for _,r in ipairs(object.rows)do
        if r.field=='stratagem.max_uses'then uses=r end
        if r.field=='stratagem.rearm_pool'and r.editable then pool=r end
    end
    if pool and uses and uses.vanilla=='unlimited'then
        check(pool.uses_row==uses and uses.pool_row==pool,'pool and uses linked')
        assert(layer:set(pool,catalog.EAGLE_REARM))
        run(5)
        local state,why=layer:state(pool)
        check(state=='error'and tostring(why):find('REARM_POOL_UNLIMITED',1,true),'joining with unlimited uses refused: '
            ..tostring(state)..' '..tostring(why))
        assert(layer:set(uses,5))
        assert(layer:set(pool,catalog.EAGLE_REARM))
        local waited=false
        for _=1,200 do
            run(1)
            if layer:state(uses)=='applying'then
                waited=true
                local slot=layer:slot_of(pool)
                check(not(slot and(slot.phase=='adopt'or slot.phase=='steer')),'the pool waits for the uses')
            end
        end
        check(waited and layer:state(pool)=='active'and layer:state(uses)=='active','both applied: '
            ..layer:state(pool)..' '..layer:state(uses))
        layer:reset(uses)
        local slot=layer:slot_of(pool)
        check(slot and not slot.user,'resetting the uses leaves the pool')
        for _=1,200 do run(1)end
        check(layer:state(pool)=='idle'and layer:state(uses)=='idle','both released: '..layer:state(pool)..' '
            ..layer:state(uses))
        out[#out+1]='rearm pool order ok'
    end
end

if type(hd2.beam_conversion)~='function'or not catalog.conversion_entry('LAS-16 Sickle')then
    out[#out+1]='no beam conversion in this HD2Runtime'
    return table.concat(out,'\n')
end
local object=assert(cat:object('pw|LAS-16 Sickle'))
cat:open(object)
local enabled,rate
for _,r in ipairs(object.rows)do
    if r.key=='pw|LAS-16 Sickle|bc:beam_conversion.enabled'then enabled=r end
    if r.key=='pw|LAS-16 Sickle|bc:beam.fire_rate'then rate=r end
end
check(enabled and rate,'conversion rows')
check(enabled.acks.allow_component_swap and enabled.acks.allow_unverified_effect,'both acknowledgements')
check(rate.conversion_enabled==enabled,'the rate follows the conversion')

-- 1. A setting without the conversion is refused at once, with the reason.
assert(layer:set(rate,600))
for _=1,5 do S.tick(0.1);layer:tick(0.1)end
local state,why=layer:state(rate)
check(state=='error'and tostring(why):find('on first',1,true),'refused while off: '..tostring(state)..' '..tostring(why))
out[#out+1]='setting refused while off ok'

-- 2. The conversion and a setting together: the setting waits until the conversion is no longer being applied.
assert(layer:set(enabled,true))
assert(layer:set(rate,600))
local waited=false
for _=1,200 do
    S.tick(0.1);layer:tick(0.1)
    local slot=layer:slot_of(rate)
    if layer:state(enabled)=='applying'then
        waited=true
        check(not(slot and(slot.phase=='adopt'or slot.phase=='steer')),'the setting never starts before the conversion')
    end
end
check(waited,'the conversion was applied first')
out[#out+1]='setting waits for the conversion ok'

-- 3. Turning the conversion off takes its settings back.
layer:reset(enabled)
local slot=layer:slot_of(rate)
check(not slot or not slot.user,'the setting is reset with the conversion')
for _=1,100 do S.tick(0.1);layer:tick(0.1)end
out[#out+1]='settings released with the conversion ok'
return table.concat(out,'\n')

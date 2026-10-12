-- Closed-window work uses the real ensure scheduler; no UI rendering is involved.
local S=dofile(...)
local id='mods/skyeshade/hd2runtime_editor'
local cat=require(id..'/editor/catalog').new(S.hd2)
local ledger=require(id..'/editor/ledger').install(S.hd2,id)
local layer=require(id..'/editor/layer').new{hd2=S.hd2,id=id,ledger=ledger,catalog=cat,visible=false}
local object=assert(cat:object('pw|AR-23 Liberator'));cat:open(object)
local row
for _,r in ipairs(object.rows)do if r.field=='weapon.fire_rate'then row=r;break end end
assert(row)
local function advance(seconds)
    for _=1,math.floor(seconds/0.1+0.5)do update(0.1);layer:tick(0.1)end
end
local function settle()
    for _=1,300 do advance(0.1);if not layer:busy()then return end end
    error('layer did not settle')
end
assert(layer:set(row,row.vanilla+100));settle()
assert(layer:state(row)=='active'and S.value(row)==row.vanilla+100)
local watch=layer:slot_of(row).watch
local ticks,writes=watch.debug().ticks,S.writes
-- Count actual catalogue-sized walks, not just elapsed CPU time.
local old_pairs,walks=pairs,0
_G.pairs=function(t)if t==layer.slots then walks=walks+1 end;return old_pairs(t)end
advance(10)
_G.pairs=old_pairs
assert(walks==0,'settled layer scans every held field')
assert(watch.debug().ticks==ticks and S.writes==writes,'settled ensure still ticks/writes')
-- A new edit wakes it while closed, but still coalesces changes for 0.5 seconds.
assert(layer:set(row,row.vanilla+200));advance(0.1);advance(0.3)
assert(S.value(row)==row.vanilla+100,'idle time consumed the new edit debounce')
settle();assert(S.value(row)==row.vanilla+200)
-- Closed means no periodic checks, even when data drifts. Opening resumes verification.
S.memory[row.loc]=require('hd2runtime/core/bytes').encode(row.vanilla,row.storage)
ticks=watch.debug().ticks
advance(31)
assert(S.value(row)==row.vanilla and watch.debug().ticks==ticks,'closed Editor still verifies')
layer:set_visible(true);advance(2)
assert(S.value(row)==row.vanilla+200,'opening did not recover data drift')
local verifications=watch.verifications
advance(3)
assert(watch.verifications-verifications>=2 and watch.verifications-verifications<=3,'open upkeep is not once per second')
layer:set_visible(false)
-- A failure notification wakes the idle layer and displays the failure on its row.
watch.cancel();advance(0.1)
assert(layer:slot_of(row).error,'sleeping layer missed cancellation')
assert(layer:reset(row));settle()
assert(layer:state(row)=='idle'and S.value(row)==row.vanilla,'closed reset did not release')
assert(next(layer.slots)==nil)
return 'idle sleeps edit debounce drift cancellation reset ok'

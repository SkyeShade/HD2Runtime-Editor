-- The exporter, offline: its hashes, archive and ZIP (the Python test compares them with the HD2Runtime SDK), and a
-- generated mod run against the real Runtime ensure in the simulator: the exported operations apply the values.
local args=...
local S=dofile(args.sim)
local hd2=S.hd2
local EDITOR='mods/skyeshade/hd2runtime_editor'
local export=require('mods/skyeshade/hd2runtime_editor/editor/export')
local catalog_module=require('mods/skyeshade/hd2runtime_editor/editor/catalog')
local cat=catalog_module.new(hd2)
local out={}
local function hex(s)return(s:gsub('.',function(c)return string.format('%02x',c:byte())end))end
out[#out+1]='murmur packages/boot '..export.murmur64('packages/boot')
out[#out+1]='murmur lua '..export.murmur64('lua')
out[#out+1]='murmur resource '..export.murmur64('mods/skye/test5')
out[#out+1]='crc '..string.format('%08x',export.crc32('123456789'))
out[#out+1]='sha '..hex(export.sha256('abc'))
out[#out+1]='guid '..export.guid('mods/skye/test5')
out[#out+1]='archive '..hex(export.archive({['mods/skye/test5']='print(1)\n',['mods/skye/test5/x']='return 2\n'}))

-- three changes: a number, a calldown code, a projectile swap
local function row_of(object,predicate)
    local o=assert(cat:object(object),object);cat:open(o)
    for _,r in ipairs(o.rows)do if predicate(r)then return r end end
    error('no row on '..object)
end
local rof=row_of('pw|AR-23 Liberator',function(r)return r.field=='weapon.fire_rate'end)
local code=row_of('st|Eagle Smoke Strike',function(r)return r.kind=='code'end)
local swap=row_of('pw|BR-14 Adjudicator',function(r)return r.kind=='reference'and r.field=='attack.projectile'end)
local util=require('mods/skyeshade/hd2runtime_editor/editor/util')
local donor
for _,o in ipairs(swap.options(swap))do
    if not util.same(o.value,swap.vanilla)and catalog_module.probe(swap,o.value)then donor=o.value;break end
end
assert(donor,'a projectile donor')
local rates=row_of('pw|AR-23 Liberator',function(r)return r.kind=='rates'end)
local entries={{row=rof,value=1300},{row=code,value={'up','down','up','down'}},{row=swap,value=donor},
    {row=rates,value={450,640,950}}}
-- HD2Runtime 0.31.2: two statuses on the GL-15 Evictor's blast (slot 2 listed first): one transaction, in slot order
local slots={}
do
    local o=assert(cat:object('pw|GL-15 Evictor'));cat:open(o)
    for _,r in ipairs(o.rows)do
        local s=r.status_slot
        if s and r.field:find('^explosion%.')and s.n<=2 then slots[s.kind..s.n]=r end
    end
end
local evictor=slots.type2~=nil
if evictor then
    for _,e in ipairs({{row=slots.type2,value='gas_confusion'},{row=slots.strength2,value=100},
        {row=slots.type1,value='gas'},{row=slots.strength1,value=100}})do entries[#entries+1]=e end
end
local result=export.build(catalog_module,entries,{name='Test Export',version='1.2.3',description='Made in a test.',
    author='Skye Tester',image=args.image,minimum='0.30.0-dev',editor_version='test'})
assert(#result.skipped==0,'skipped: '..tostring(result.skipped[1]and result.skipped[1].why))
assert(result.resource=='mods/skye_tester/test_export','resource '..result.resource)
local path=export.write(result,args.folder,function(p)os.execute('mkdir "'..p..'" 2>nul')end)
out[#out+1]='zip '..path
out[#out+1]='guid2 '..result.guid

-- the exported body runs against the real Runtime: every operation registers and applies
package.preload['mods/skyeshade/hd2runtime']=package.preload['mods/skyeshade/hd2runtime']or function()return hd2 end
local fn=assert(loadstring(result.source,'@exported'))
local ops=fn()
assert(#ops==(evictor and 5 or 4),'operations: '..#ops)
if evictor then
    local a=result.source:find('explosion.damage.status_1_type',1,true)
    local b=result.source:find('explosion.damage.status_2_type',1,true)
    local t=result.source:find('status slots (one transaction',1,true)
    assert(t and a and b and t<a and a<b,'the Evictor statuses in one transaction, slot 1 first')
    assert(result.source:find('{field="explosion.damage.status_2_type"',1,true)
        and not result.source:find('\n        field="explosion.damage.status_2_type"',1,true),'never a patch of its own')
    -- the Runtime's own packing rule accepts that write set on an empty row, and refuses slot 2 alone
    local slots_module=require('hd2runtime/core/status_slots')
    local empty=string.rep('\0',80)
    local packing=slots_module.new()
    slots_module.note(packing,'row',empty,2,44,'status 2')
    slots_module.note(packing,'row',empty,1,42,'status 1')
    assert(pcall(slots_module.verify,packing),'slot 1 and slot 2 together')
    packing=slots_module.new()
    slots_module.note(packing,'row',empty,2,44,'status 2')
    assert(not pcall(slots_module.verify,packing),'slot 2 alone refused')
    out[#out+1]='status slots one transaction ok'
end
for _=1,60 do S.tick(0.1)end
for i,op in ipairs(ops)do
    assert(op.status~='rejected'and op.status~='blocked',('operation %d %s: %s'):format(i,tostring(op.id),tostring(op.error)))
    assert((op.runs or 0)>=1,('operation %d did not apply: %s'):format(i,tostring(op.status)))
end
assert(S.value(rof)==1300,'fire rate written: '..tostring(S.value(rof)))
out[#out+1]='applied ok'
-- the wrapped resource is valid Lua with the SDK header
assert(result.wrapped:sub(1,#('-- HD2-Addon: '..result.resource))=='-- HD2-Addon: '..result.resource)
assert(loadstring(result.wrapped,'@wrapped'),'the wrapped addon compiles')
out[#out+1]='wrapped ok'
return table.concat(out,'\n')

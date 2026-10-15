-- The actual window with the shipped Chinese pack, using the existing offline byte-store/overlay harness.
local args=...
local H=assert(loadfile(args.harness))({sim=args.sim})
local i=require('mods/skyeshade/hd2runtime_editor/editor/i18n')
local function frame()
    local d=H.frame({})
    assert(#d.refused==0,tostring(d.refused[1]))
    assert(#d.items<=1024,'overlay primitive budget')
    local text={}
    for _,item in ipairs(d.items)do if item.k=='t'then text[#text+1]=item.s end end
    return table.concat(text,'')
end
assert(i.use('简体中文',{}))
for _,view in ipairs({'browse','search','changes','export','mods','custom','presets','logs','settings'})do
    H.app:set_view(view)
    local text=frame()
    assert(text:find('应用',1,true),'translated Apply: '..view)
    assert(not text:find('APPLY',1,true),'no raw Apply: '..view)
end
local object=H.catalog:object('pw|AR-23 Liberator')
H.catalog:open(object)
local row
for _,r in ipairs(object.rows)do if r.field=='weapon.fire_rate'then row=r;break end end
assert(row)
H.app:reveal(row)
assert(H.app:stage(row,row.vanilla+1))
assert(H.app.pending_n==1)
assert(frame():find('应用  1',1,true),'translated counted Apply')
assert(object.key=='pw|AR-23 Liberator'and row.field=='weapon.fire_rate')
H.app:discard()
i.use('English')
H.app.tab_actions=nil
assert(frame():find('APPLY',1,true),'switch back to English')
return 'ok'

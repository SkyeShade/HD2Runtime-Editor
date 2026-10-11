-- REVERT ALL over 300 fields, as the game runs them: one guarded operation at a time (tests/lua/sim.lua S.serial), so
-- a 300-field apply or reset takes about 20 s. Every reset field stays listed as REMOVING until its base is back,
-- nothing the editor took back is ever written again (not the value that was still on its way, not at a later
-- update), failed fields are reset too, a reset that fails keeps its error and is not saved, and REVERT ALL works
-- again after manual resets and after failures.
local args=...
local H=assert(loadfile(args.harness))({sim=args.sim})
local S=H.sim
S.serial=4
local util=require('mods/skyeshade/hd2runtime_editor/editor/util')
local catalog_module=require('mods/skyeshade/hd2runtime_editor/editor/catalog')
local app,layer=H.app,H.layer
local out={}
local function check(cond,msg)
    if not cond then error('FAILED: '..msg..'\n'..table.concat(layer.history,'\n',math.max(1,#layer.history-15)),2)end
end
-- the saved session, saved as in the game (editor/main.lua): what would be applied again at the next start
local session=require('mods/skyeshade/hd2runtime_editor/editor/session').new({app=app,layer=layer,presets=H.presets})
session.restored,session.saved_version=true,layer.version
local function step(dt)
    local d=H.frame({},{dt=dt or 1/60})
    session:tick()
    check(#d.refused==0,'the overlay would refuse '..tostring(d.refused[1]))
    return d
end
local function shows(d,text)
    for _,it in ipairs(d.items)do if it.k=='t'and it.s:find(text,1,true)then return true end end
    return false
end

-- 300 plain numeric fields of the primary and support weapons, each set one step above its default
local list,used={},{}
for _,category in ipairs({'primary','secondary','support_weapons'})do
    for _,o in ipairs((H.catalog:objects(category)))do
        H.catalog:open(o)
        for _,r in ipairs(o.rows or{})do
            if#list<300 and r.editable and not r.kind and type(r.vanilla)=='number'and not r.shared and not used[r.loc]
                and not r.conversion_enabled and not r.conversion and r.disabled_value==nil and not r.status_slot then
                local v=util.representable(r.vanilla+1,r.integer,r.storage)
                if v and(not r.max or v<=r.max)and(not r.min or v>=r.min)then list[#list+1]={row=r,v=v};used[r.loc]=true end
            end
        end
    end
end
check(#list==300,'300 fields: '..#list)
local map={}
for _,it in ipairs(list)do map[it.row.key]=catalog_module.encode(it.row,it.v)end
-- what the game holds for a field, as the editor holds values (f32 values to three decimals)
local function game(row)
    local v=S.value(row)
    return util.representable(v,row.integer,row.storage)or v
end
local function base_of(row)return util.representable(row.vanilla,row.integer,row.storage)or row.vanilla end
-- how many fields the game holds at the preset's value
local function written()
    local n=0
    for _,it in ipairs(list)do if game(it.row)==it.v then n=n+1 end end
    return n
end
local function at_base()
    for _,it in ipairs(list)do if game(it.row)~=base_of(it.row)then return false end end
    return true
end
local function apply_preset()
    app:stage_map(map,{kind='preset',name='Big'})
    app:apply()
end
local function revert_all()
    app:ask('reset')
    check(app.confirm and app.confirm.kind=='reset','REVERT ALL asks to confirm (not "nothing to reset"): '
        ..tostring(app.toast_msg and app.toast_msg.text))
    app:confirm_yes()
end
local function rows_in_state(state)
    local n=0
    for _,e in ipairs(app:changes())do if e.state==state then n=n+1 end end
    return n
end
-- runs until every field is back (or the limit); fields leave the list one by one, never come back, and no value
-- of the preset is written once the revert started
local function until_reverted(seconds,label)
    local last=#app:changes()
    local most=written()
    local t=0
    while t<seconds do
        step()
        t=t+1/60
        local n=#app:changes()
        check(n<=last,label..': a reset row came back ('..last..' -> '..n..')')
        last=n
        local w=written()
        check(w<=most,label..': a preset value was written after REVERT ALL ('..most..' -> '..w..')')
        most=w
        if n==0 and next(layer.slots)==nil then break end
    end
    check(next(layer.slots)==nil and#app:changes()==0,label..': every field reset ('..#app:changes()..' left)')
    check(at_base(),label..': every field back to its default value in the game')
    return t
end
local function quiet(seconds,label)
    local writes=S.writes
    for _=1,seconds*10 do step(0.1)end
    check(S.writes==writes and at_base(),label..': nothing written again ('..(S.writes-writes)..' writes)')
    check(next(layer:overrides())==nil and next(H.presets:session())==nil,label..': nothing saved to apply again')
end

app:set_view('changes')
---------------------------------------------------------------------- 1. apply 300, then revert all once applied --
apply_preset()
for _=1,60*60 do step();if written()==300 and not layer:busy()then break end end
check(written()==300,'the preset applied: '..written())
revert_all()
local d=step()
check(#app:changes()==300 and rows_in_state('removing')==300,'every row stays, marked REMOVING: '..rows_in_state('removing'))
check(shows(d,'REMOVING')and shows(d,'Removing 0 of 300'),'the REMOVING chips and the counter are shown')
for _=1,60*6 do step()end
local done,total=layer:removal()
check(total==300 and done>0 and done<300 and#app:changes()==300-done,'the counter follows the resets: '..done..' of '
    ..total..', '..#app:changes()..' listed')
check(shows(step(),'Removing '..select(1,layer:removal())..' of 300'),'the counter is in the status line')
until_reverted(60,'revert all')
quiet(40,'revert all')
out[#out+1]='revert all ok'

---------------------------------------------- 2. revert all while the apply is still in progress (some written) --
apply_preset()
for _=1,60*5 do step()end
local part=written()
check(part>20 and part<280,'the apply is under way: '..part..' of 300 written')
revert_all()
check(rows_in_state('removing')==300,'every field is removing, written or not: '..rows_in_state('removing'))
local took=until_reverted(60,'revert during apply')
check(took<part*4/60*1.5+5,'only the fields already written are taken back ('..part..' in '..took..' s)')
quiet(40,'revert during apply')
out[#out+1]='revert during apply ok'

------------------------------------------------- 3. revert all after some manual RESETs (some still removing) --
apply_preset()
for _=1,60*60 do step();if written()==300 and not layer:busy()then break end end
local snapshot={}
for i,e in ipairs(app:changes())do snapshot[i]=e end
for i=1,20 do app:reset_change(snapshot[i])end
step()
check(rows_in_state('removing')==20 and#app:changes()==300,'20 manual resets are listed as removing')
revert_all()
check(rows_in_state('removing')==300,'revert all takes the other 280 too: '..rows_in_state('removing'))
until_reverted(60,'revert after manual resets')
quiet(20,'revert after manual resets')
out[#out+1]='revert after resets ok'

----------------------------------------------- 4. failed fields: revert all resets them, a failed reset stays --
-- Three fields fail as the Runtime would stop their ensures (rejected); every other field is applied.
local few={}
for i=1,6 do few[list[i].row.key]=map[list[i].row.key]end
app:stage_map(few,{kind='preset',name='Few'})
app:apply()
for _=1,60*20 do step();if not layer:busy()then break end end
local function break_ensure(row)
    local slot=layer:slot_of(row)
    pcall(slot.watch.cancel)
    slot.watch={status='rejected',error='CONFLICT: a test refusal',runs=slot.watch.runs,rebinds=slot.watch.rebinds,
        cancel=function()end,result={code='CONFLICT'}}
end
for i=1,3 do break_ensure(list[i].row)end
step()
local active,applying,errors=layer:counts()
check(errors==3 and active==3,'three failed, three active: '..active..' '..errors)
-- only failed fields left: REVERT ALL still resets them (it used to say "nothing to reset")
for i=4,6 do layer:reset(list[i].row)end
for _=1,60*10 do step()end
active,applying,errors=layer:counts()
check(active==0 and applying==0 and errors==3,'only the failed fields are left: '..active..' '..errors)
revert_all()
check(rows_in_state('removing')==3,'the failed fields are removing')
until_reverted(30,'revert failed fields')
for i=1,6 do check(game(list[i].row)==base_of(list[i].row),'failed field back to its default: '..list[i].row.key)end
-- a reset that fails keeps its error and reason, is not saved, and REVERT ALL takes it again
app:stage_map(few,{kind='preset',name='Few'})
app:apply()
for _=1,60*20 do step();if not layer:busy()then break end end
check(written()==6,'six applied again')
local victim=list[1].row
local slot=layer:slot_of(victim)
local real=slot.watch
slot.watch={status='running',runs=real.runs,rebinds=real.rebinds,recoveries=0,cancel=function()end,
    debug=function()return {child='resolving'}end}
pcall(real.cancel)
revert_all()
step()
slot.watch.status,slot.watch.error,slot.watch.result='rejected','CONFLICT: the reset was refused',{code='CONFLICT'}
for _=1,60*20 do step()end
local state,why=layer:state(victim)
check(state=='error'and tostring(why):find('the reset was refused',1,true),'the failed reset keeps its error: '
    ..tostring(state)..' '..tostring(why))
local entry
for _,e in ipairs(app:changes())do if e.row==victim then entry=e end end
check(entry and entry.state=='error'and entry.value==list[1].v,'listed with ERROR and the value still in the game')
check(layer:overrides()[victim.key]==nil,'a value whose reset failed is not saved')
local errs=layer:errors()
check(#errs==1 and errs[1].origin and errs[1].origin.kind=='reset','the errors list says it was a reset')
revert_all()
until_reverted(30,'revert a failed reset')
check(game(victim)==base_of(victim),'the failed reset taken back on the next REVERT ALL')
quiet(10,'revert a failed reset')
out[#out+1]='failed resets ok'
return table.concat(out,'\n')

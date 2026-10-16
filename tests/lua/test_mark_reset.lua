-- RESET in Changes (1.0.1) marks a field for reset instead of resetting it at once: nothing changes in the game, the
-- saved session and the export, until Apply; the row says PENDING RESET with the value it still holds and its button
-- UNDO; UNDO and Discard keep the value; Apply resets it exactly as an immediate reset does (REMOVING, then gone,
-- the default back in the game); a field with only a pending value just loses it; a failed field is marked and reset
-- on Apply too.
local args=...
local H=assert(loadfile(args.harness))({sim=args.sim})
local S=H.sim
local util=require('mods/skyeshade/hd2runtime_editor/editor/util')
local app,layer=H.app,H.layer
local out={}
local function check(cond,msg)
    if not cond then error('FAILED: '..msg..'\n'..table.concat(layer.history,'\n',math.max(1,#layer.history-15)),2)end
end
local session=require('mods/skyeshade/hd2runtime_editor/editor/session').new({app=app,layer=layer,presets=H.presets})
session.restored,session.saved_version=true,layer.version
local function step(dt)
    local d=H.frame({},{dt=dt or 1/60})
    session:tick()
    check(#d.refused==0,'the overlay would refuse '..tostring(d.refused[1]))
    return d
end
local function settle(seconds)for _=1,60*(seconds or 10)do step();if not layer:busy()then break end end;step()end
local function game(row)
    local v=S.value(row)
    return util.representable(v,row.integer,row.storage)or v
end
local function base_of(row)return util.representable(row.vanilla,row.integer,row.storage)or row.vanilla end
local function entry_of(row)for i,e in ipairs(app:changes())do if e.row==row then return e,i end end end
local function shows(d,text)
    for _,it in ipairs(d.items)do if it.k=='t'and it.s==text then return true end end
    return false
end

-- three plain numeric fields of a primary weapon, one step above their defaults
local rows={}
for _,o in ipairs((H.catalog:objects('primary')))do
    H.catalog:open(o)
    for _,r in ipairs(o.rows or{})do
        if#rows<3 and r.editable and not r.kind and type(r.vanilla)=='number'and not r.shared and not r.status_slot
            and r.disabled_value==nil and not r.conversion then
            local v=util.representable(r.vanilla+1,r.integer,r.storage)
            if v and(not r.max or v<=r.max)then rows[#rows+1]={row=r,v=v}end
        end
    end
    if#rows==3 then break end
end
check(#rows==3,'three fields')
for _,it in ipairs(rows)do check(app:stage(it.row,it.v),'staged '..it.row.key)end
app:apply()
settle()
for _,it in ipairs(rows)do check(game(it.row)==it.v,'applied '..it.row.key)end
local a,b,c=rows[1],rows[2],rows[3]

-- 1. RESET marks: nothing changes until Apply
app:set_view('changes')
local e=entry_of(a.row)
app:revert_change(e)
step()
e=entry_of(a.row)
check(e and e.state=='pending'and e.reset and e.value==a.v,'marked: pending, its value still listed')
check(app.pending_n==1 and layer:state(a.row)=='active','still active in the layer')
for _=1,60 do step()end
check(game(a.row)==a.v,'nothing changes in the game before Apply')
check(H.presets:session()[a.row.key]~=nil,'the saved session keeps the applied value until Apply')
local listed=false
for _,x in ipairs(app:export_changes())do if x.row==a.row then listed=true end end
check(not listed,'a field marked for reset is not offered for export')
check(app:current_values()[a.row.key]==nil,'nor saved in a preset')
local d=step()
check(shows(d,'PENDING RESET')and shows(d,'UNDO'),'the row says PENDING RESET, its button UNDO')
out[#out+1]='mark ok'

-- 2. UNDO (RESET again) and Discard keep the value
app:revert_change(entry_of(a.row))
check(app.pending_n==0 and not entry_of(a.row).reset and entry_of(a.row).state=='active','UNDO takes the mark back')
app:revert_change(entry_of(a.row))
app:revert_change(entry_of(b.row))
check(app.pending_n==2,'two marked')
app:discard()
settle(2)
check(app.pending_n==0 and game(a.row)==a.v and game(b.row)==b.v,'Discard keeps both values')
out[#out+1]='undo discard ok'

-- 3. Apply resets the marked field as an immediate reset does
app:revert_change(entry_of(a.row))
-- Backspace on the selected row marks too (it reset at once before)
local _,ib=entry_of(b.row)
app.change_index=ib
app:handle_changes_keys({keys={BACKSPACE=true},chars={}})
check(entry_of(b.row).reset,'Backspace marks')
app:apply()
step()
check(layer:removing(a.row)and layer:removing(b.row),'Apply: both REMOVING')
settle()
check(game(a.row)==base_of(a.row)and game(b.row)==base_of(b.row),'back to their defaults in the game')
check(entry_of(a.row)==nil and entry_of(b.row)==nil,'gone from Changes')
local saved=H.presets:session()
check(saved[a.row.key]==nil and saved[b.row.key]==nil and saved[c.row.key]~=nil,'the session drops only the reset fields')
check(game(c.row)==c.v,'the other field stays')
out[#out+1]='apply reset ok'

-- 4. a field with only a pending value: RESET drops that value (nothing applied to take back)
app:stage(a.row,a.v)
check(entry_of(a.row).state=='pending'and not entry_of(a.row).reset,'pending only')
app:revert_change(entry_of(a.row))
check(entry_of(a.row)==nil and app.pending_n==0,'the pending value is dropped, nothing is marked')
-- a pending value over an applied one: RESET replaces it with the mark
app:stage(c.row,util.representable(c.row.vanilla+2,c.row.integer,c.row.storage))
app:revert_change(entry_of(c.row))
check(entry_of(c.row).reset and entry_of(c.row).value==c.v and app.pending_n==1,
    'the pending value gives way to the mark (the applied value listed)')
app:apply()
settle()
check(game(c.row)==base_of(c.row)and entry_of(c.row)==nil,'reset on Apply')
out[#out+1]='pending only ok'

-- 5. a failed field is marked and reset on Apply
app:stage(a.row,a.v)
app:apply()
settle()
local slot=layer:slot_of(a.row)
pcall(slot.watch.cancel)
slot.watch={status='rejected',error='CONFLICT: a test refusal',runs=slot.watch.runs,rebinds=slot.watch.rebinds,
    cancel=function()end,result={code='CONFLICT'}}
step()
check(layer:state(a.row)=='error','failed')
app:revert_change(entry_of(a.row))
check(entry_of(a.row).reset and layer:state(a.row)=='error','marked, still failed until Apply')
app:apply()
settle()
check(entry_of(a.row)==nil and layer:slot_of(a.row)==nil or not(layer:slot_of(a.row).user or layer:slot_of(a.row).error),
    'the failed field is reset on Apply')
out[#out+1]='failed field ok'

-- 6. a click on the PENDING RESET tag in Changes takes the mark back
for _,it in ipairs(rows)do app:stage(it.row,it.v)end
app:apply()
settle()
app:set_view('changes')
app:revert_change(entry_of(b.row))
local d=step()
local tag
for _,it in ipairs(d.items)do if it.k=='t'and it.s=='PENDING RESET'then tag=it end end
check(tag,'the tag is drawn')
H.frame({},{mouse={x=tag.x,y=tag.y,left=false}})
H.frame({},{mouse={x=tag.x,y=tag.y,left=true}})
H.frame({},{mouse={x=tag.x,y=tag.y,left=false}})
check(not app:reset_mark(b.row)and app.pending_n==0 and game(b.row)==b.v,'the tag click takes the mark back')
out[#out+1]='tag click ok'

-- 7. REVERT ALL marks every field (after its confirmation); Discard keeps them, Apply resets them
app:ask('reset')
check(app.confirm and app.confirm.kind=='reset','REVERT ALL asks first')
app:confirm_yes()
for _,it in ipairs(rows)do check(app:reset_mark(it.row),'marked '..it.row.key)end
for _=1,60 do step()end
for _,it in ipairs(rows)do check(game(it.row)==it.v,'unchanged before Apply '..it.row.key)end
app:discard()
check(not app:has_pending(),'Discard drops the marks')
app:ask('reset');app:confirm_yes()
app:apply()
settle()
for _,it in ipairs(rows)do check(game(it.row)==base_of(it.row),'reset on Apply '..it.row.key)end
check(#app:changes()==0 and not app:has_pending(),'nothing left')
out[#out+1]='revert all ok'
return table.concat(out,'\n')

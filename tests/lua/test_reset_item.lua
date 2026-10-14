local args=...
local H=assert(loadfile(args.harness))({sim=args.sim})
local function settle()for _=1,240 do H.sim.tick(0.1);H.layer:tick(0.1)end end
local function first_numeric(o,skip)
    for _,r in ipairs(o.rows)do
        if r.editable and not r.kind and not r.info and type(r.vanilla)=='number'and r~=skip and r.max and r.min
            and r.max>r.vanilla then return r end
    end
end
-- A weapon: one applied and one pending change; RESET ITEM asks, then both go back now; another item is untouched.
local list=H.catalog:objects('primary')
local w=list[1];H.catalog:open(w)
local other=list[2];H.catalog:open(other)
local a=assert(first_numeric(w));local b=assert(first_numeric(w,a))
local c=assert(first_numeric(other))
assert(H.app:stage(a,a.vanilla+1));assert(H.app:stage(c,c.vanilla+1));H.app:apply();settle()
assert(H.sim.value(a)==a.vanilla+1 and H.sim.value(c)==c.vanilla+1)
assert(H.app:stage(b,b.vanilla+1))
H.app:goto_object(w);local f=H.frame({});assert(#f.refused==0)
assert(#H.app:item_changes(w)==2,#H.app:item_changes(w))
H.app.btn_reset_item.click()
assert(H.app.confirm and H.app.confirm.kind=='reset_item'and H.app.confirm.data.count==2)
assert(#H.frame({}).refused==0)
H.app:confirm_yes();settle()
assert(H.sim.value(a)==a.vanilla and H.app.pending[b.key]==nil,'both back')
assert(H.sim.value(c)==c.vanilla+1,'another item is untouched')
assert(#H.app:item_changes(w)==0)
H.app.btn_reset_item.click();assert(not H.app.confirm,'nothing to reset: no dialog')
-- A shared value (a mission timer source shared by several missions): the dialog names the other items.
local m=assert(H.catalog:object('mi|automatons/19e3e290'));H.catalog:open(m)
local n=assert(H.catalog:object('mi|automatons/c8859069'));H.catalog:open(n)
assert(H.app:stage(m.rows[1],1800))
local rows=H.app:item_changes(m);assert(#rows==1)
local shared=H.app:item_shared_names(m,rows);assert(shared and#shared>0,'the sharing missions are named')
-- (mission pages are unlisted: the dialog is asked for directly, as the button does)
H.app:ask('reset_item',{object=m,count=#rows,shared=shared})
assert(#H.frame({}).refused==0)
H.app:confirm_yes()
assert(H.app.pending[m.rows[1].key]==nil and#H.app:item_changes(n)==0,'the shared value reset on every item')
return 'reset item ok'

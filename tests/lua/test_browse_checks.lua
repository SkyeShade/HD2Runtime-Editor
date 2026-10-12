local args=...
local H=assert(loadfile(args.harness))({sim=args.sim})
local app,cat=H.app,H.catalog
local requests={}
local real=cat.real_hd2
cat.real_hd2=setmetatable({inspect=function(req)
    local job={status='running',request=req}
    function job.cancel()job.status='cancelled'end
    requests[#requests+1]=job
    return job
end},{__index=real})
-- This test isolates page browsing from the unrelated whole-catalogue shared-field index.
cat.indexed=true
local tank=assert(cat:object('ve|TD-110 Maelstrom'))
assert(app:goto_object(tank));app.view='browse'
local d
for _=1,25 do
    d=H.frame({})
    assert(#d.refused==0 and#d.items<=1024)
end
assert(#tank.rows==272 and#requests==1,'tank page did not display while checks were outstanding')
local shown={}
for _,item in ipairs(d.items)do if item.k=='t'then shown[#shown+1]=item.s end end
assert(table.concat(shown,'\n'):find('Checking live values 0/',1,true),'no progress shown')
local other=assert(cat:object('ve|EXO-45 Patriot Exosuit'))
assert(app:goto_object(other));H.frame({})
assert(requests[1].status=='cancelled','navigation left the tank inspection running')
local before=tank.owner_scan.done
requests[1].request.on_result({fields={{state='foreign',owner='unknown',value=0}}})
assert(tank.owner_scan.done==before,'late tank callback changed a different page')
assert(app:object()==other and#H.frame({}).refused==0,'navigation was blocked')
cat:pause_owners()
return 'Maelstrom fields immediate progress and navigation responsive'

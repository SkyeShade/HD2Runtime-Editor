local Catalog=require('mods/skyeshade/hd2runtime_editor/editor/catalog')
local requests,cancelled={},0
local function inspect(req)
    local job={status='running',request=req}
    function job.cancel()cancelled=cancelled+1;job.status='cancelled'end
    function job.finish(state)
        local fields={}
        for i,f in ipairs(req.fields)do fields[i]={field=f.field,state=state or'vanilla',value=2,owner='unknown'}end
        req.on_result({fields=fields});job.status='complete'
    end
    requests[#requests+1]=job
    return job
end
local cat=Catalog.new({inspect=inspect})
local function object(name,n)
    local o={key=name,rows={}}
    for i=1,n do
        o.rows[i]={key=name..i,editable=true,field='field.'..i,vanilla=1,
            target=function()return{resource='vehicle',vehicle=name}end}
    end
    return o
end
local a,b=object('tank',130),object('other',2)
cat:check_owners(a)
assert(#requests==0,'opening a page must not start every inspection in its draw callback')
for _=1,4 do cat:owners_step(a)end
assert(#requests==0,'request preparation must be incremental')
for _=1,20 do cat:owners_step(a)end
assert(#requests==1 and#requests[1].request.fields==64,'only one target batch may run')
requests[1].finish()
cat:pause_owners()
assert(a.owner_scan.done==64 and not a.owners_checked,'completed batch was not retained')
for _=1,3 do cat:owners_step(b)end
assert(#requests==2)
cat:owners_step(a)
assert(requests[2].status=='cancelled','leaving page did not cancel its request')
requests[2].finish('foreign')
assert(b.rows[1].editable and b.owner_scan.done==0,'late completion changed an abandoned page')
assert(#requests==3 and requests[3].request.fields[1].field=='field.65','revisit repeated completed fields')
requests[3].finish();cat:owners_step(a)
assert(#requests==4 and#requests[4].request.fields==2,'fields past the 64-field limit were dropped')
requests[4].finish('foreign');cat:owners_step(a)
assert(a.owners_checked and a.owner_scan.done==130 and a.rows[130].foreign)
assert(a.rows[1].editable and not a.rows[1].foreign)
for _=1,100 do cat:owners_step(a)end
assert(#requests==4,'a cached page started new inspections')
cat:owners_step(b);local n=#requests
cat:pause_owners()
assert(requests[n].status=='cancelled','closing the editor must stop read-only page checks')
assert(a.owner_scan.done==130 and cancelled>=2)
return 'incremental owners cancellation cache overflow stale callbacks ok'

-- Offline contract check: every editable row the catalogue builds must pass the Runtime's own validator
-- (hd2runtime/domains/patches.validate) with a changed value and the acknowledgements the row carries.
-- Returns a report: totals per category and the first failures grouped by error.
local hd2=require('hd2runtime/api/hd2')
local patches=require('hd2runtime/domains/patches')
local catalog=require('mods/skyeshade/hd2runtime_editor/editor/catalog')
local util=require('mods/skyeshade/hd2runtime_editor/editor/util')
local cat=catalog.new(hd2)
local CATEGORIES=...
local out,groups,order={}, {},{}
local total,passed,rows_total=0,0,0
local function test_value(row)
    local v=row.held_vanilla
    local step=row.integer and 1 or math.max(0.5,math.abs(v)*0.1)
    local up=v+step
    if row.integer then up=math.floor(up+0.5)else up=util.round(up)end
    if row.max and up>row.max then
        up=v-step
        if row.integer then up=math.floor(up+0.5)else up=util.round(up)end
    end
    if row.min and up<row.min then up=v end
    return up
end
for _,group in ipairs(catalog.GROUPS)do
    for _,item in ipairs(group.items)do
        if not CATEGORIES or CATEGORIES[item.id]then
            local objects,why=cat:objects(item.id)
            local c_total,c_pass,c_rows=0,0,0
            if why then out[#out+1]='CATEGORY '..item.id..' unavailable: '..why end
            for _,object in ipairs(objects)do
                cat:open(object)
                if object.error then out[#out+1]='OBJECT '..object.key..' failed: '..object.error end
                for _,row in ipairs(object.rows)do
                    c_rows=c_rows+1
                    if row.editable then
                        c_total=c_total+1
                        local request={id='editor-contract',field=row.field,expect=row.vanilla,value=test_value(row)}
                        for k,v in pairs(row.acks)do request[k]=v end
                        local ok,err=pcall(function()
                            request.target=row.target()
                            return patches.validate(request)
                        end)
                        if ok then c_pass=c_pass+1 else
                            local e=tostring(err):gsub('^[^:]+:%d+: ','')
                            local sig=item.id..' | '..e:gsub('[%d%.]+','#'):sub(1,110)
                            local g=groups[sig]
                            if not g then g={n=0,example=row.key..' ['..tostring(row.field)..'] '..e:sub(1,200)};groups[sig]=g;order[#order+1]=sig end
                            g.n=g.n+1
                        end
                    end
                end
            end
            total,passed,rows_total=total+c_total,passed+c_pass,rows_total+c_rows
            out[#out+1]=string.format('%-16s objects=%4d rows=%5d editable=%5d valid=%5d',item.id,#objects,c_rows,c_total,c_pass)
        end
    end
end
out[#out+1]=string.format('TOTAL rows=%d editable=%d valid=%d',rows_total,total,passed)
table.sort(order,function(a,b)return groups[a].n>groups[b].n end)
for i=1,math.min(#order,60)do
    local g=groups[order[i]]
    out[#out+1]=string.format('%5d x %s\n        e.g. %s',g.n,order[i],g.example)
end
return table.concat(out,'\n')

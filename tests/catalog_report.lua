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
local values,refs_total,refs_ok
local DONORS=select(2,...)
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
    -- a field with a disable sentinel takes it or a value above 0, nothing between
    if row.disabled_value~=nil and up~=row.disabled_value and up<=0 then up=1 end
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
                    if row.editable and row.kind then
                        -- value rows: the vanilla value and one other value pass the validator (acknowledgements added
                        -- as the validator asks, as the editor does)
                        c_total=c_total+1
                        local other
                        if row.kind=='code'then
                            other={}
                            for i,d in ipairs(row.vanilla)do other[i]=d end
                            other[#other]=other[#other]=='up'and'down'or'up'
                        elseif row.kind=='uses'then
                            other=row.vanilla=='unlimited'and 3 or(row.unlimited and'unlimited'or math.max(row.min,(row.vanilla or 1)-1))
                        elseif row.kind=='modes'then
                            other={}
                            for _,m in ipairs(row.modes)do
                                local present=false
                                for _,v in ipairs(row.vanilla)do if v==m then present=true end end
                                if not present and#row.vanilla<row.max_modes then other={unpack(row.vanilla)};other[#other+1]=m;break end
                            end
                            if#other==0 then other={row.vanilla[1]}end
                        elseif row.kind=='rates'then
                            other={unpack(row.vanilla)}
                            for i=1,3 do if other[i]>0 then other[i]=math.min(row.max,other[i]+50);break end end
                        elseif row.kind=='traits'then
                            other={unpack(row.vanilla)}
                            if#other<(row.max_traits or 5)then
                                for _,t in ipairs(row.traits)do
                                    local present=false
                                    for _,v in ipairs(other)do if v==t.value then present=true end end
                                    if not present then other[#other+1]=t.value;break end
                                end
                            else table.remove(other)end
                        elseif row.options and row.kind=='choice'then
                            for _,o in ipairs(row.options(row))do if not util.same(o.value,row.vanilla)then other=o.value;break end end
                        end
                        local ok,err=catalog.probe(row,catalog.expect(row))
                        if ok and other~=nil then ok,err=catalog.probe(row,other)end
                        if row.kind=='reference'and DONORS then
                            for _,o in ipairs(row.options(row))do
                                refs_total=(refs_total or 0)+1
                                if catalog.probe(row,o.value)then refs_ok=(refs_ok or 0)+1 end
                            end
                        end
                        values=(values or 0)+1
                        if ok then c_pass=c_pass+1 else
                            local sig=item.id..' | '..row.kind..' | '..tostring(err):gsub('[%d%.]+','#'):sub(1,100)
                            local g=groups[sig]
                            if not g then g={n=0,example=row.key..' ['..tostring(row.field)..'] '..tostring(err):sub(1,200)};groups[sig]=g;order[#order+1]=sig end
                            g.n=g.n+1
                        end
                    elseif row.editable then
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
out[#out+1]='VALUE ROWS '..tostring(values or 0)..(DONORS and('  reference donors valid '..tostring(refs_ok)..' of '..tostring(refs_total))or'')
table.sort(order,function(a,b)return groups[a].n>groups[b].n end)
for i=1,math.min(#order,60)do
    local g=groups[order[i]]
    out[#out+1]=string.format('%5d x %s\n        e.g. %s',g.n,order[i],g.example)
end
return table.concat(out,'\n')

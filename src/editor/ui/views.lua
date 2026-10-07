-- The editor's other tabs, installed onto the app (ui/app.lua):
--   CHANGES   every value the editor applied or has pending (never a mod's own values), with revert;
--   MODS      every deployed mod: HD2Runtime mods with the values they applied and their in-game options, and the
--             mods the mod manager deployed that are not HD2Runtime mods (what those change cannot be read);
--   CUSTOM    custom stratagems registered by mods, with their cooldown and uses tunable on this machine;
--   SETTINGS  restore session, the cursor, menu sounds and the language.
local theme=require('mods/skyeshade/hd2runtime_editor/editor/ui/theme')
local util=require('mods/skyeshade/hd2runtime_editor/editor/util')
local i18n=require('mods/skyeshade/hd2runtime_editor/editor/i18n')
local installed=require('mods/skyeshade/hd2runtime_editor/editor/installed')
local C,SZ=theme.colour,theme.size
local L=i18n.L
local M={}

local function clamp_index(i,n)if n<=0 then return 1 end return math.max(1,math.min(n,i))end
local LIST_W=430

-- Words of `text` in lines no wider than `w` (canvas units).
local function wrap(cv,text,w,size,max_lines)
    local lines,line={},''
    for word in tostring(text or''):gsub('%s+',' '):gmatch('%S+')do
        local test=line==''and word or(line..' '..word)
        if cv:measure(test,size)>w and line~=''then
            lines[#lines+1]=line;line=word
            if max_lines and#lines>=max_lines then break end
        else line=test end
    end
    if line~=''and(not max_lines or#lines<max_lines)then lines[#lines+1]=line end
    return lines
end
M.wrap=wrap

local function toggle_row(self,cv,x,y,w,on,label,action)
    cv:rect(x,y-9,34,18,on and C.gold or C.line_strong,3)
    cv:rect(on and x+18 or x+2,y-7,14,14,on and C.inverse or C.dim,4)
    cv:text(label,x+46,y,{size=SZ.small,colour=self.hover==action and C.text or C.dim,max=w-60})
    cv:hit(x,y-12,w,24,action)
end

local function selected_row(self,cv,x,y,w,rh,selected,action)
    if selected then cv:rect(x+8,y+2,w-16,rh-4,C.select,2);cv:rect(x+8,y+2,3,rh-4,C.gold,3)
    elseif self.hover==action then cv:rect(x+8,y+2,w-16,rh-4,C.hover,2)end
end

function M.install(App)
    local chip=App.chip_fn
    local button=App.button_fn

    ------------------------------------------------------------------------------------------- CHANGES --
    -- Every editor value: pending first, then applied and failed ones, by object and field.
    function App:changes()
        local key=self.layer.version..':'..self.pending_n
        if self.changes_key==key then return self.changes_cache end
        local list,seen={},{}
        for _,p in pairs(self.pending)do
            list[#list+1]={row=p.row,value=p.value,state='pending'}
            seen[p.row.key]=true
        end
        for _,slot in pairs(self.layer.slots)do
            local row=slot.row
            if row and not row.mirror and not seen[row.key]and(slot.user or slot.error)then
                local state,why=self.layer:state(row)
                list[#list+1]={row=row,value=slot.target~=nil and slot.target or slot.held,state=state,error=why}
            end
        end
        table.sort(list,function(a,b)
            local an,bn=a.row.object.name..'\0'..a.row.label,b.row.object.name..'\0'..b.row.label
            if a.state=='pending'and b.state~='pending'then return true end
            if b.state=='pending'and a.state~='pending'then return false end
            return util.natural_less(an,bn)
        end)
        self.changes_key,self.changes_cache=key,list
        return list
    end
    function App:revert_change(entry)
        if not entry then return end
        if entry.state=='pending'then self:unstage(entry.row);self:toast(L('Pending change removed'),C.dim);return end
        local base=self.layer:base(entry.row)
        self:stage(entry.row,base)
        self:toast(L('Staged: back to %s (press Apply)'):format(self:text(entry.row,base)),C.pending)
    end
    function App:handle_changes_keys(f)
        local k=f.keys
        local list=self:changes()
        self.change_index=self.change_index or 1
        if k.UP then self.change_index=clamp_index(self.change_index-1,#list)end
        if k.DOWN then self.change_index=clamp_index(self.change_index+1,#list)end
        if k.PAGEUP then self.change_index=clamp_index(self.change_index-12,#list)end
        if k.PAGEDOWN then self.change_index=clamp_index(self.change_index+12,#list)end
        if(k.ENTER or k.RIGHT)and list[self.change_index]then self:sound('open');self:reveal(list[self.change_index].row)end
        if k.DELETE then self:revert_change(list[self.change_index])end
    end
    function App:draw_changes(y0,h)
        local cv=self.canvas
        local W=theme.panel.w
        local list=self:changes()
        self.change_index=clamp_index(self.change_index or 1,#list)
        cv:rect(0,y0,W,h,C.panel,1)
        cv:text(L('CHANGES'),20,y0+24,{size=20,font='title',colour=C.text})
        local active,applying,errors=self.layer:counts()
        cv:text(L('Values the editor applied or has pending (your mods\' own values are in Mods).')..'   '
            ..L('%d active, %d pending, %d applying, %d failed'):format(active,self.pending_n,applying,errors),
            20,y0+47,{size=SZ.small,colour=C.faint,max=W-300})
        self.btn_revert_all=self.btn_revert_all or{click=function()self:ask('reset')end}
        button(self,L('REVERT ALL'),W-216,y0+16,196,34,(#list>0)and'danger'or'disabled',self.btn_revert_all)
        local hy=y0+66
        cv:rect(0,hy,W,22,C.header,2)
        cv:text(L('OBJECT'),20,hy+11,{size=SZ.tiny,font='title',colour=C.faint})
        cv:text(L('FIELD'),330,hy+11,{size=SZ.tiny,font='title',colour=C.faint})
        cv:text(L('DEFAULT'),W-420,hy+11,{size=SZ.tiny,font='title',colour=C.faint,align='right'})
        cv:text(L('VALUE'),W-250,hy+11,{size=SZ.tiny,font='title',colour=C.faint,align='right'})
        cv:text(L('STATE'),W-20,hy+11,{size=SZ.tiny,font='title',colour=C.faint,align='right'})
        if#list==0 then
            cv:text(L('No editor changes. Edit a field in Browse, then Apply.'),20,hy+44,{size=SZ.small,colour=C.faint})
        end
        self.change_actions=self.change_actions or{}
        if self.change_actions_key~=self.changes_key then self.change_actions,self.change_actions_key={},self.changes_key end
        self:list({x=0,y=hy+24,w=W,h=y0+h-hy-28,count=#list,row_h=32,selected=self.change_index,
            scroll_key='change_scroll',focused=true,actions=self.change_actions,
            click=function(i)
                if self.change_index==i then self:sound('open');self:reveal(list[i].row)else self.change_index=i end
            end,
            draw=function(i,x,y,lw,rh)
                local e=list[i]
                local action=self.change_actions[i]
                if action and not action.rclick then action.rclick=function()self:revert_change(list[i])end end
                selected_row(self,cv,x,y,lw,rh,i==self.change_index,action)
                local cy=y+rh/2
                self:draw_icon(e.row.object,x+18,y+4,rh-8)
                cv:text(e.row.object.name,x+18+rh,cy,{size=SZ.small,colour=C.dim,max=300-rh})
                cv:text(L(e.row.label),x+330,cy,{size=SZ.small,colour=C.text,max=lw-330-450})
                local base=self.layer:base(e.row)
                cv:text(self:text(e.row,base),x+lw-420,cy,{size=SZ.small,colour=C.faint,align='right',max=150})
                cv:text(self:text(e.row,e.value),x+lw-250,cy,{size=SZ.label,colour=C.gold,align='right',max=160})
                local fg,bg,label=C.gold,C.gold_wash,L('EDITED')
                if e.state=='pending'then fg,bg,label=C.pending,C.pending_soft,L('PENDING')
                elseif e.state=='applying'then fg,bg,label={255,199,44,255},C.gold_soft,L('APPLYING')
                elseif e.state=='error'or e.error then fg,bg,label=C.error,C.error_soft,L('ERROR')end
                chip(cv,label,x+lw-20,cy,fg,bg,'right')
            end})
    end

    ---------------------------------------------------------------------------------------------- MODS --
    -- Every mod: the mod manager's list (when readable), the HD2Runtime mods the Runtime knows, their options.
    function App:installed_mods()
        if not self.installed_reader then
            local known={}
            for _,m in ipairs(self.ledger:mods())do known[m.id]=true end
            for key in pairs(_G)do
                local id=type(key)=='string'and key:match('^HD2RuntimeMod:(.+)$')
                if id then known[id]=true end
            end
            self.installed_reader=(self.ctx.installed or installed.start)(function(id)return known[id]==true end)
        end
        if not self.installed_reader.done then self.installed_reader.step(0.004)end
        return self.installed_reader.done and self.installed_reader.result()or nil
    end
    function App:option_pages()
        if self.options_cache and self.time-(self.options_time or 0)<1 then return self.options_cache end
        local pages={}
        local diag=type(self.hd2.diagnostics)=='table'and self.hd2.diagnostics.options
        if type(diag)=='function'then
            local ok,list=pcall(diag)
            if ok and type(list)=='table'then pages=list end
        end
        self.options_cache,self.options_time=pages,self.time
        return pages
    end
    function App:mods_list()
        local inst=self:installed_mods()
        local key=tostring(self.ledger.version)..':'..tostring(inst~=nil)
        if self.mods_cache and self.mods_cache_key==key and self.time-(self.mods_cache_time or 0)<2 then
            return self.mods_cache
        end
        local runtime={}
        for _,m in ipairs(self.ledger:mods())do runtime[m.id]=m end
        local by_owner={}
        for _,page in ipairs(self:option_pages())do
            local owner=page.owner or'unknown'
            if owner~=self.ctx.id and page.kind=='menu'then
                by_owner[owner]=by_owner[owner]or{}
                table.insert(by_owner[owner],page)
            end
        end
        local out,used={},{}
        local function runtime_entry(id,base)
            local r=runtime[id]
            local e=base or{key='runtime:'..id,name=self.pretty_mod(id)}
            e.runtime,e.resource=true,id
            e.writes,e.operations=r and r.writes or{},r and r.operations or{}
            e.applied,e.refused=r and r.applied or 0,r and r.refused or 0
            e.pages=by_owner[id]or{}
            used[id]=true
            return e
        end
        for _,m in ipairs(inst and inst.mods or{})do
            local e={key=m.key,name=m.name,description=m.description,version=m.version,manager=m,
                source=inst.source,addons=m.addons,writes={},operations={},pages={},applied=0,refused=0}
            if m.resource and m.resource~=self.ctx.id then runtime_entry(m.resource,e)
            elseif m.resource==self.ctx.id then e.self=true;e.runtime=true end
            out[#out+1]=e
        end
        for id in pairs(runtime)do if not used[id]and id~='unknown'then out[#out+1]=runtime_entry(id)end end
        for id in pairs(by_owner)do if not used[id]and id~='unknown'then out[#out+1]=runtime_entry(id)end end
        table.sort(out,function(a,b)
            local ar,br=(a.runtime and not a.self)and 0 or 1,(b.runtime and not b.self)and 0 or 1
            if ar~=br then return ar<br end
            return tostring(a.name):lower()<tostring(b.name):lower()
        end)
        self.mods_cache,self.mods_cache_key,self.mods_cache_time=out,key,self.time
        return out
    end
    function App:handle_mods_keys(f)
        local k=f.keys
        local mods=self:mods_list()
        if k.UP then self.mod_index=clamp_index(self.mod_index-1,#mods);self.write_scroll=0 end
        if k.DOWN then self.mod_index=clamp_index(self.mod_index+1,#mods);self.write_scroll=0 end
        if k.PAGEUP then self.mod_index=clamp_index(self.mod_index-12,#mods);self.write_scroll=0 end
        if k.PAGEDOWN then self.mod_index=clamp_index(self.mod_index+12,#mods);self.write_scroll=0 end
        local mod=mods[self.mod_index]
        if(k.RIGHT or k.ENTER)and mod and mod.writes and mod.writes[1]then self:sound('open');self:open_mod_write(mod,1)end
    end
    -- A mod's icon: its own picture (tools/mod_icons.py layers) or the universal mod icon.
    function App:draw_mod_icon(mod,x,y,size)
        local icons=self.ctx.mod_icons
        local entry=icons and(icons[mod.key]or(mod.manager and mod.manager.guid and icons['guid:'..mod.manager.guid])
            or(mod.resource and icons['resource:'..mod.resource]))
        if entry and type(self.canvas.d.image)=='function'then
            for _,layer in ipairs(entry)do
                self.canvas:image(layer.handle,x,y,size,size,{colours=layer.colours,z=4})
            end
            return
        end
        local colour=mod.runtime and C.mod or C.faint
        if not self:draw_ui_icon('mod',x+size*0.1,y+size*0.1,size*0.8,colour)then
            self.canvas:rect(x+size*0.3,y+size*0.3,size*0.4,size*0.4,colour,4)
        end
    end
    function App:draw_mods(y0,h)
        local cv=self.canvas
        local W=theme.panel.w
        local mods=self:mods_list()
        self.mod_index=clamp_index(self.mod_index,#mods)
        cv:rect(0,y0,LIST_W,h,C.panel_alt,1)
        cv:rect(LIST_W-1,y0,1,h,C.line,2)
        local inst=self:installed_mods()
        local nrt=0
        for _,m in ipairs(mods)do if m.runtime and not m.self then nrt=nrt+1 end end
        cv:text(L('INSTALLED MODS'),18,y0+20,{size=SZ.heading,font='title',colour=C.faint})
        local note=inst==nil and L('reading the mod manager...')
            or(inst.source and L('%d mods, %d HD2Runtime (from %s)'):format(#mods,nrt,inst.source=='echelon'and'Echelon'or'HD2 Arsenal')
            or L('%d HD2Runtime mods (no mod manager state found)'):format(nrt))
        cv:text(note,LIST_W-18,y0+20,{size=SZ.tiny,colour=C.faint,align='right',max=LIST_W-170})
        self.mod_actions=self.mod_actions or{}
        self:list({x=0,y=y0+36,w=LIST_W-1,h=h-40,count=#mods,row_h=56,selected=self.mod_index,scroll_key='mod_scroll',
            focused=true,actions=self.mod_actions,click=function(i)self.mod_index=i;self.write_scroll=0 end,
            draw=function(i,x,y,w,rh)
                local mod=mods[i]
                selected_row(self,cv,x,y,w,rh,i==self.mod_index,self.mod_actions[i])
                self:draw_mod_icon(mod,x+16,y+8,rh-16)
                local tx=x+16+rh
                cv:text(mod.name,tx,y+19,{size=SZ.label,colour=i==self.mod_index and C.text or C.dim,max=w-(tx-x)-110})
                local sub=mod.self and L('this editor')or(mod.runtime and(mod.resource or'')or
                    (#(mod.addons or{})>0 and L('Lua mod (not HD2Runtime)')or L('asset mod')))
                cv:text(sub,tx,y+38,{size=SZ.tiny,colour=C.faint,max=w-(tx-x)-110})
                local rx=x+w-18
                if mod.refused>0 then rx=rx-chip(cv,mod.refused..' '..L('REFUSED'),rx,y+19,C.error,C.error_soft,'right')-6 end
                if mod.applied>0 then
                    chip(cv,mod.applied..' '..(mod.applied==1 and L('VALUE')or L('VALUES')),x+w-18,y+39,C.mod,C.mod_soft,'right')
                elseif#(mod.pages or{})>0 then chip(cv,L('OPTIONS'),x+w-18,y+39,C.gold,C.gold_wash,'right')end
            end})
        -- detail
        local mod=mods[self.mod_index]
        local x0=LIST_W
        local w=W-x0
        cv:rect(x0,y0,w,h,C.panel,1)
        if not mod then return end
        self:draw_mod_icon(mod,x0+20,y0+14,46)
        cv:text(mod.name..(mod.version and('  '..mod.version)or''),x0+78,y0+28,{size=20,font='title',colour=C.text,max=w-100})
        local sub
        if mod.self then sub=L('HD2Runtime Editor itself')
        elseif mod.runtime then
            sub=mod.resource..'   '..L('%d operations, %d values applied'):format(#mod.operations,mod.applied)
                ..(mod.refused>0 and('   '..L('%d refused'):format(mod.refused))or'')
        else sub=(#(mod.addons or{})>0 and L('A Lua mod that does not use HD2Runtime')or L('An asset mod (it replaces game files)'))end
        cv:text(sub,x0+78,y0+50,{size=SZ.small,colour=C.faint,max=w-100})
        -- rows: description, options, writes, refused operations
        local rows={}
        for _,line in ipairs(wrap(cv,mod.description,w-60,SZ.small,4))do rows[#rows+1]={text=line}end
        if not mod.runtime then
            rows[#rows+1]={text=L('HD2Runtime cannot read what this mod changes: it replaces game files directly.'),faint=true}
            if#(mod.addons or{})>0 then rows[#rows+1]={text=L('Lua addons: %s'):format(table.concat(mod.addons,', ')),faint=true}end
        end
        for _,page in ipairs(mod.pages or{})do
            rows[#rows+1]={heading=L('IN-GAME OPTIONS: %s'):format(page.title or page.id)}
            for _,o in ipairs(page.options or{})do rows[#rows+1]={option=o,page=page}end
            if#(page.operations or{})>0 then
                rows[#rows+1]={text=L('Drives: %s'):format(table.concat(page.operations,', ')),faint=true}
            end
        end
        if#(mod.writes or{})>0 then rows[#rows+1]={heading=L('VALUES APPLIED')}end
        for index,claim in ipairs(mod.writes or{})do rows[#rows+1]={claim=claim,index=index}end
        for _,op in ipairs(mod.operations or{})do
            if op.status=='rejected'or op.status=='blocked'then rows[#rows+1]={op=op}end
        end
        if self.write_actions_mod~=mod.key then self.write_actions,self.write_actions_mod={},mod.key end
        self:list({x=x0,y=y0+76,w=w,h=h-80,count=#rows,row_h=28,scroll_key='write_scroll',focused=false,
            actions=self.write_actions,click=function(i)if rows[i].claim then self:open_mod_write(mod,rows[i].index)end end,
            draw=function(i,x,y,lw,rh)
                local item=rows[i]
                local cy=y+rh/2
                if item.heading then
                    cv:text(item.heading,x+18,cy+3,{size=SZ.heading,font='title',colour=C.gold})
                    cv:rect(x+18,y+rh-3,lw-36,1,C.line,2)
                elseif item.text then
                    cv:text(item.text,x+18,cy,{size=SZ.small,colour=item.faint and C.faint or C.dim,max=lw-36})
                elseif item.option then
                    local o=item.option
                    cv:text(L(o.label or o.option),x+30,cy,{size=SZ.small,colour=C.text,max=lw-360})
                    local value=o.value
                    if o.kind=='choice'and o.choices and o.values then
                        for k,v in ipairs(o.values)do if util.same(v,value)then value=o.choices[k]end end
                    end
                    local range=o.kind=='slider'and(o.min and o.max and(util.format(o.min)..' – '..util.format(o.max)))
                        or(o.kind=='choice'and o.choices and L('%d choices'):format(#o.choices))or''
                    cv:text(range,x+lw-200,cy,{size=SZ.tiny,colour=C.faint,align='right',max=140})
                    local text=type(value)=='boolean'and(value and L('On')or L('Off'))or util.value_text(value)
                    local fg=o.state=='ready'and C.gold or C.faint
                    chip(cv,util.plain(text,28),x+lw-18,cy,fg,o.state=='ready'and C.gold_wash or C.line,'right')
                elseif item.claim then
                    if self.hover==self.write_actions[i]then cv:rect(x+6,y+1,lw-12,rh-2,C.hover,2)end
                    local claim=item.claim
                    cv:text(claim.text,x+30,cy,{size=SZ.small,colour=C.dim,max=lw-340})
                    cv:text(util.value_text(claim.value),x+lw-210,cy,{size=SZ.label,colour=C.mod,align='right',max=150})
                    local slot=self.layer.slots[claim.loc]
                    if slot and slot.user then
                        chip(cv,L('EDITOR')..' '..util.plain(util.value_text(slot.target),24),x+lw-18,cy,C.gold,C.gold_wash,'right')
                    elseif slot and slot.watch then chip(cv,L('HELD BY EDITOR'),x+lw-18,cy,C.faint,C.line,'right')
                    else chip(cv,L('ACTIVE'),x+lw-18,cy,C.mod,C.mod_soft,'right')end
                elseif item.op then
                    local op=item.op
                    cv:text((op.kind or'op')..' '..tostring(op.id)..': '..tostring(op.error or op.code or op.status),x+18,cy,
                        {size=SZ.small,colour=C.error,max=lw-140})
                    chip(cv,L('REFUSED'),x+lw-18,cy,C.error,C.error_soft,'right')
                end
            end})
    end

    -------------------------------------------------------------------------------------------- CUSTOM --
    local function custom_api(self)
        local api=type(self.hd2.custom_stratagem)=='table'and self.hd2.custom_stratagem
        return api and type(api.status)=='function'and api or nil
    end
    function App:custom_list()
        if self.custom_cache and self.time-(self.custom_time or 0)<1 then return self.custom_cache end
        local api=custom_api(self)
        local out={}
        if api then
            local ok,list=pcall(api.status)
            for _,s in ipairs(ok and type(list)=='table'and list or{})do
                local dok,d=pcall(api.describe,s.id)
                local e=dok and type(d)=='table'and d or{id=s.id,owner=s.owner}
                e.state=s.state or e.state
                e.calls=s.calls
                out[#out+1]=e
            end
        end
        table.sort(out,function(a,b)return tostring(a.label or a.id)<tostring(b.label or b.id)end)
        self.custom_cache,self.custom_time=out,self.time
        return out
    end
    local CUSTOM_FIELDS={{key='cooldown',label='Cooldown',unit='s',step=5},{key='uses',label='Uses per mission',step=1}}
    function App:custom_tune(entry,field,value)
        local api=custom_api(self)
        if not api or type(api.tune)~='function'then
            self:toast(L('Tuning custom stratagems needs HD2Runtime r51'),C.error);self:sound('error');return
        end
        local ok,why=api.tune(entry.id,{[field]=value})
        if ok then
            self:toast(L('%s: %s set to %s (from the next call)'):format(entry.label or entry.id,L(field),util.format(value)),C.ok)
            self:sound('apply')
        else self:toast(tostring(why),C.error);self:sound('error')end
        self.custom_cache=nil
    end
    function App:custom_untune(entry)
        local api=custom_api(self)
        if api and type(api.untune)=='function'then
            api.untune(entry.id)
            self:toast(L('%s: back to its own cooldown and uses'):format(entry.label or entry.id),C.dim)
            self.custom_cache=nil
        end
    end
    function App:handle_custom_keys(f)
        local k=f.keys
        local list=self:custom_list()
        self.custom_index=clamp_index(self.custom_index or 1,#list)
        self.custom_field=self.custom_field or 0
        local entry=list[self.custom_index]
        local edit=self.custom_edit
        if edit then
            for _,ch in ipairs(f.chars)do if ch:match('[%d%.]')and#edit.buffer<8 then edit.buffer=edit.buffer..ch end end
            if k.BACKSPACE then edit.buffer=edit.buffer:sub(1,-2)end
            if k.ESCAPE or k.DELETE then self.custom_edit=nil
            elseif k.ENTER or k.TAB then
                local v=tonumber(edit.buffer)
                self.custom_edit=nil
                if v and entry then self:custom_tune(entry,edit.field,v)end
            end
            return
        end
        if self.custom_field==0 then
            if k.UP then self.custom_index=clamp_index(self.custom_index-1,#list)end
            if k.DOWN then self.custom_index=clamp_index(self.custom_index+1,#list)end
            if(k.RIGHT or k.ENTER)and entry then self.custom_field=1 end
        else
            local field=CUSTOM_FIELDS[self.custom_field]
            if k.UP then self.custom_field=math.max(1,self.custom_field-1)end
            if k.DOWN then self.custom_field=math.min(#CUSTOM_FIELDS,self.custom_field+1)end
            if k.ESCAPE then self.custom_field=0 end
            if entry and field then
                local current=entry[field.key]
                if(k.LEFT or k.RIGHT)and type(current)=='number'then
                    local step=field.step*(f.shift and 10 or 1)
                    self:custom_tune(entry,field.key,math.max(field.key=='uses'and 1 or step,current+(k.LEFT and-step or step)))
                elseif k.LEFT and current==nil then self.custom_field=0 end
                if k.ENTER then self.custom_edit={field=field.key,buffer=''}end
                if#f.chars>0 then
                    self.custom_edit={field=field.key,buffer=''}
                    for _,ch in ipairs(f.chars)do if ch:match('[%d%.]')then self.custom_edit.buffer=self.custom_edit.buffer..ch end end
                end
                if k.DELETE then self:custom_untune(entry)end
            end
        end
    end
    function App:draw_custom(y0,h)
        local cv=self.canvas
        local W=theme.panel.w
        local list=self:custom_list()
        self.custom_index=clamp_index(self.custom_index or 1,#list)
        cv:rect(0,y0,LIST_W,h,C.panel_alt,1)
        cv:rect(LIST_W-1,y0,1,h,C.line,2)
        cv:text(L('CUSTOM STRATAGEMS'),18,y0+20,{size=SZ.heading,font='title',colour=C.faint})
        if not custom_api(self)then
            cv:text(L('This HD2Runtime has no custom stratagems.'),18,y0+52,{size=SZ.small,colour=C.faint,max=LIST_W-36})
        elseif#list==0 then
            cv:text(L('No mod has registered a custom stratagem.'),18,y0+52,{size=SZ.small,colour=C.faint,max=LIST_W-36})
        end
        self.custom_actions=self.custom_actions or{}
        self:list({x=0,y=y0+36,w=LIST_W-1,h=h-40,count=#list,row_h=56,selected=self.custom_index,scroll_key='custom_scroll',
            focused=(self.custom_field or 0)==0,actions=self.custom_actions,
            click=function(i)self.custom_index=i;self.custom_field=0;self.custom_edit=nil end,
            draw=function(i,x,y,w,rh)
                local e=list[i]
                selected_row(self,cv,x,y,w,rh,i==self.custom_index,self.custom_actions[i])
                local drew=false
                if type(e.icon)=='table'and type(cv.d.image)=='function'then
                    drew=pcall(cv.image,cv,e.icon,x+16,y+8,rh-16,rh-16,{z=4})
                end
                if not drew then cv:rect(x+16+(rh-16)*0.2,y+8+(rh-16)*0.2,(rh-16)*0.6,(rh-16)*0.6,C.gold,4)end
                local tx=x+16+rh
                cv:text(e.label or e.id,tx,y+19,{size=SZ.label,colour=i==self.custom_index and C.text or C.dim,max=w-(tx-x)-90})
                cv:text(self.pretty_mod(e.owner or'?')..'   '..tostring(e.kind or''),tx,y+38,{size=SZ.tiny,colour=C.faint,max=w-(tx-x)-90})
                if e.tuned then chip(cv,L('TUNED'),x+w-18,y+rh/2,C.gold,C.gold_wash,'right')end
            end})
        local e=list[self.custom_index]
        local x0=LIST_W
        local w=W-x0
        cv:rect(x0,y0,w,h,C.panel,1)
        if not e then return end
        cv:text(e.label or e.id,x0+20,y0+24,{size=20,font='title',colour=C.text,max=w-40})
        cv:text(tostring(e.id)..'   '..L('by %s'):format(tostring(e.owner)),x0+20,y0+47,{size=SZ.small,colour=C.faint,max=w-40})
        -- editable rows
        local y=y0+80
        cv:rect(x0,y,w,22,C.header,2)
        cv:text(L('FIELD'),x0+18,y+11,{size=SZ.tiny,font='title',colour=C.faint})
        cv:text(L('REGISTERED'),x0+w-200,y+11,{size=SZ.tiny,font='title',colour=C.faint,align='right'})
        cv:text(L('VALUE'),x0+w-18,y+11,{size=SZ.tiny,font='title',colour=C.faint,align='right'})
        y=y+26
        self.custom_field_actions=self.custom_field_actions or{}
        for index,field in ipairs(CUSTOM_FIELDS)do
            local action=self.custom_field_actions[index]
            if not action then
                local fi=index
                action={click=function()self.custom_field=fi end}
                self.custom_field_actions[index]=action
            end
            local focused=self.custom_field==index
            if focused then cv:rect(x0+8,y,w-16,30,C.select,2);cv:rect(x0+8,y,3,30,C.gold,3)
            elseif self.hover==action then cv:rect(x0+8,y,w-16,30,C.hover,2)end
            local value=e[field.key]
            local registered=e.registered and e.registered[field.key]
            local disabled=field.key=='uses'and e.eagle_uses~=nil
            cv:text(L(field.label)..(disabled and('  ('..L('an Eagle: %d per rearm'):format(e.eagle_uses)..')')or''),x0+22,y+15,
                {size=SZ.label,colour=C.text,max=w-320})
            cv:text(registered and util.format(registered)or L('unlimited'),x0+w-200,y+15,{size=SZ.small,colour=C.faint,align='right'})
            local text=self.custom_edit and focused and(self.custom_edit.buffer..'_')
                or(value and(util.format(value)..(field.unit and(' '..field.unit)or''))or L('unlimited'))
            cv:rect(x0+w-150,y+3,132,24,C.box,3)
            cv:frame(x0+w-150,y+3,132,24,focused and C.box_focus or C.box_edge,4)
            cv:text(text,x0+w-26,y+15,{size=SZ.label,colour=(value~=registered)and C.gold or C.text,align='right',z=6,max=120})
            cv:hit(x0+8,y,w-16,30,action)
            y=y+34
        end
        cv:text(L('←→ adjust (Shift ×10)   digits type   Enter set   Del back to the registered values. Applies from the next call, on this machine only.'),
            x0+22,y+8,{size=SZ.tiny,colour=C.faint,max=w-44})
        self.btn_untune=self.btn_untune or{}
        self.btn_untune.click=function()self:custom_untune(e)end
        button(self,L('RESET TO REGISTERED'),x0+w-240,y+24,220,32,e.tuned and'danger'or'disabled',self.btn_untune)
        -- details
        y=y+76
        local details={
            {L('Calldown code'),(function()
                local names,dirs={},{'up','right','down','left'}
                for i,v in ipairs(e.code_values or{})do names[i]=dirs[v]or tostring(v)end
                return#names>0 and util.code_text(names)or tostring(e.code or'-')
            end)()},
            {L('Kind'),tostring(e.kind or'-')},
            {L('Carrier group'),tostring(e.group or'-')},
            {L('Carrier'),e.carrier and e.carrier.name or L('not allocated yet')},
            {L('State'),tostring(e.state or'-')..(e.calls and e.calls>0 and('   '..L('%d calls this mission'):format(e.calls))or'')},
        }
        if e.pod and e.pod.items then
            local items={}
            for _,it in ipairs(e.pod.items)do items[#items+1]=tostring(it.item)..(it.count and(' ×'..it.count)or'')end
            details[#details+1]={L('Pod'),table.concat(items,', ')}
        end
        for _,d in ipairs(details)do
            cv:text(d[1],x0+22,y,{size=SZ.small,colour=C.faint})
            cv:text(d[2],x0+220,y,{size=SZ.small,colour=C.dim,max=w-240})
            y=y+24
        end
    end

    ------------------------------------------------------------------------------------------ SETTINGS --
    function App:languages()
        if not self.language_cache then self.language_cache=i18n.languages()end
        return self.language_cache
    end
    function App:handle_settings_keys(f)
        local k=f.keys
        local langs=self:languages()
        self.settings_index=clamp_index(self.settings_index or 1,3+#langs)
        if k.UP then self.settings_index=clamp_index(self.settings_index-1,3+#langs)end
        if k.DOWN then self.settings_index=clamp_index(self.settings_index+1,3+#langs)end
        if k.ENTER or k.RIGHT or k.LEFT then
            local i=self.settings_index
            if i<=3 then
                local action=(self.settings_toggles or{})[i]
                if action then action.click()end
            else self:use_language(langs[i-3].name)end
        end
    end
    function App:use_language(name)
        local ok,why=i18n.use(name)
        if ok then
            self.presets:set_setting('language',name)
            self:toast(L('Language: %s'):format(i18n.language()),C.ok)
            self.tab_actions=nil
        else self:toast(tostring(why),C.error)end
        self.mods_cache,self.changes_key=nil,nil
    end
    function App:draw_settings(y0,h)
        local cv=self.canvas
        local W=theme.panel.w
        cv:rect(0,y0,W,h,C.panel,1)
        cv:text(L('SETTINGS'),20,y0+24,{size=20,font='title',colour=C.text})
        self.settings_index=self.settings_index or 1
        local x,y=24,y0+64
        self.settings_toggles=self.settings_toggles or{
            {click=function()self.presets:set_setting('restore_session',not self.presets:setting('restore_session',true))end},
            {click=function()
                local on=not self.presets:setting('free_cursor',true)
                self.presets:set_setting('free_cursor',on)
                if self.ctx.set_free_cursor then self.ctx.set_free_cursor(on)end
            end},
            {click=function()self.presets:set_setting('ui_sounds',not self.presets:setting('ui_sounds',true))end}}
        local labels={L('Restore my last applied values when the game starts'),
            L('Free the mouse from the camera while open (experimental)'),L('Menu sounds on buttons')}
        local values={self.presets:setting('restore_session',true),self.presets:setting('free_cursor',true),
            self.presets:setting('ui_sounds',true)}
        for i=1,3 do
            if self.settings_index==i then cv:rect(x-8,y-14,560,28,C.select,1)end
            toggle_row(self,cv,x,y,540,values[i],labels[i],self.settings_toggles[i])
            y=y+34
        end
        cv:text(L('Open the editor with %s. Edits apply live through HD2Runtime\'s guarded writes.'):format(tostring(self.ctx.hotkey or'F8')),
            x,y+4,{size=SZ.tiny,colour=C.faint,max=W-48})
        -- language
        y=y+40
        cv:text(L('LANGUAGE'),x,y,{size=SZ.heading,font='title',colour=C.gold})
        y=y+24
        local langs=self:languages()
        self.language_actions=self.language_actions or{}
        for i,lang in ipairs(langs)do
            local action=self.language_actions[lang.name]
            if not action then
                local name=lang.name
                action={click=function()self:use_language(name)end}
                self.language_actions[lang.name]=action
            end
            local current=i18n.language()==lang.name
            if self.settings_index==3+i then cv:rect(x-8,y-2,560,28,C.select,1)
            elseif self.hover==action then cv:rect(x-8,y-2,560,28,C.hover,1)end
            cv:rect(x,y+6,14,14,current and C.gold or C.line_strong,3)
            cv:text(lang.name,x+26,y+13,{size=SZ.label,colour=current and C.text or C.dim})
            cv:text(lang.file and L('%d texts, %s'):format(lang.count,lang.file)or L('built in'),x+540,y+13,
                {size=SZ.tiny,colour=C.faint,align='right'})
            cv:hit(x-8,y-2,560,28,action)
            y=y+30
        end
        local folder=i18n.folder()
        y=y+8
        cv:text(L('Language files are read from:'),x,y,{size=SZ.small,colour=C.faint})
        cv:text(folder or L('(no %LOCALAPPDATA%)'),x,y+20,{size=SZ.small,colour=C.dim,max=W-48})
        self.btn_reload_lang=self.btn_reload_lang or{click=function()
            self.language_cache=nil
            local n=#self:languages()-1
            self:toast(L('Found %d language files'):format(n),C.ok)
        end}
        self.btn_template=self.btn_template or{click=function()
            local path,why=i18n.write_template(self.ctx.strings or{})
            if path then self:toast(L('Wrote %s'):format(path),C.ok)else self:toast(tostring(why),C.error)end
        end}
        button(self,L('RELOAD LANGUAGES'),x,y+40,200,34,'normal',self.btn_reload_lang)
        button(self,L('WRITE TEMPLATE'),x+212,y+40,200,34,'normal',self.btn_template)
        cv:text(L('A language file has one line per text: the English text, " = ", the translation.'),
            x,y+94,{size=SZ.tiny,colour=C.faint,max=W-48})
    end
end

return M

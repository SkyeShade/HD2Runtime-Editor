-- The editor window: Browse (categories -> objects -> fields), Mods (what each installed mod writes) and Presets.
-- Edits are staged as pending values and applied together; Reset to defaults gives every field back to the mods'
-- values (or vanilla). Keyboard first (the cursor is the game's while playing), mouse where the cursor is free.
local theme=require('mods/skyeshade/hd2runtime_editor/editor/ui/theme')
local canvas_module=require('mods/skyeshade/hd2runtime_editor/editor/ui/canvas')
local input_module=require('mods/skyeshade/hd2runtime_editor/editor/ui/input')
local catalog_module=require('mods/skyeshade/hd2runtime_editor/editor/catalog')
local util=require('mods/skyeshade/hd2runtime_editor/editor/util')
local C,SZ=theme.colour,theme.size
local M={}
local App={};App.__index=App

local VIEWS={{id='browse',label='BROWSE'},{id='mods',label='MODS'},{id='presets',label='PRESETS'}}
local CAT_W,OBJ_W=224,334
local MODS_W,PRESETS_W=430,470

function M.new(ctx)
    local self=setmetatable({ctx=ctx,hd2=ctx.hd2,catalog=ctx.catalog,layer=ctx.layer,ledger=ctx.ledger,
        presets=ctx.presets,canvas=canvas_module.new(),input=input_module.new(ctx.hd2),
        view='browse',focus='categories',cat=1,obj=1,obj_scroll=0,field=1,field_scroll=0,cat_scroll=0,
        pending={},pending_n=0,time=0,mod_index=1,mod_scroll=0,write_scroll=0,preset_index=1,preset_scroll=0,
        preset_action=1,detail_scroll=0},App)
    self.categories={}
    for _,group in ipairs(catalog_module.GROUPS)do
        self.categories[#self.categories+1]={group=true,label=group.label}
        for _,item in ipairs(group.items)do
            self.categories[#self.categories+1]={id=item.id,label=item.label}
        end
    end
    self.cat=2
    return self
end

------------------------------------------------------------------------------------------------- helpers --
function App:toast(text,colour)self.toast_msg={text=util.plain(text,150),colour=colour or C.text,time=self.time}end
local function pretty_mod(id)
    local last=tostring(id):match('([^/]+)$')or tostring(id)
    return util.humanize(last)
end
M.pretty_mod=pretty_mod
local function category_item(self)return self.categories[self.cat]end

-- The objects of the selected category, filtered by the search text.
function App:objects()
    local item=category_item(self)
    if not item or item.group then return {}end
    local list,why=self.catalog:objects(item.id)
    self.objects_error=why
    local q=self.search and self.search.text~=''and self.search.text:lower()
    if not q then return list end
    local key=item.id..'\0'..q
    if self.filter_key==key then return self.filtered end
    local out={}
    for _,object in ipairs(list)do
        local hay=(object.name..' '..(object.subtitle or'')):lower()
        if hay:find(q,1,true)then out[#out+1]=object end
    end
    self.filter_key,self.filtered=key,out
    return out
end
function App:object()
    local list=self:objects()
    local object=list[self.obj]
    if object then self.catalog:open(object)end
    return object
end
-- The selected object's flat field list: {{section=label} | {row=row}}, and the indices of rows.
function App:field_items(object)
    if not object then return {},{}end
    if object.items then return object.items,object.selectable end
    local items,selectable={},{}
    for _,section in ipairs(object.sections or{})do
        items[#items+1]={section=section.label,count=#section.rows}
        for _,row in ipairs(section.rows)do
            items[#items+1]={row=row}
            selectable[#selectable+1]=#items
        end
    end
    object.items,object.selectable=items,selectable
    return items,selectable
end
function App:focused_row()
    if self.view~='browse'then return nil end
    local object=self:object()
    local items,selectable=self:field_items(object)
    local index=selectable[self.field]
    return index and items[index].row or nil
end

-- What a row shows: value, kind ('pending' | 'editor' | 'mod' | 'vanilla'), state, holder, error.
function App:row_view(row)
    local pending=self.pending[row.key]
    local value,source,holder,slot=self.layer:value(row)
    local state,err=self.layer:state(row)
    if pending then return pending.value,'pending',state,holder,err end
    return value,source,state,holder,err
end

-- Objects with pending, active or mod-written fields (refreshed when the layer or ledger change).
function App:markers()
    local key=self.layer.version..':'..self.ledger.version..':'..self.pending_n
    if self.marker_key==key then return self.marker_cache end
    local m={pending={},editor={},mod={}}
    for _,p in pairs(self.pending)do m.pending[p.row.object.key]=true end
    for _,slot in pairs(self.layer.slots)do
        if slot.user and slot.row and slot.row.object then m.editor[slot.row.object.key]=true end
    end
    for _,claims in pairs(self.ledger.by_loc)do
        for _,claim in ipairs(claims)do if claim.object then m.mod[claim.object]=true end end
    end
    self.marker_key,self.marker_cache=key,m
    return m
end

---------------------------------------------------------------------------------------------- staging --
function App:stage(row,value)
    if not row.editable then self:toast(row.label..': '..tostring(row.reason or'not editable'),C.error);return false end
    local held=util.representable(value,row.integer,row.storage)
    if held==nil then
        self:toast(row.integer and'Whole numbers only'or'At most 3 decimals',C.error);return false
    end
    if row.min and held<row.min then held=row.min;self:toast('Clamped to the minimum '..util.format(row.min),C.pending)end
    if row.max and held>row.max then held=row.max;self:toast('Clamped to the maximum '..util.format(row.max),C.pending)end
    local current=self.layer:value(row)
    local existing=self.pending[row.key]
    if util.representable(current,row.integer,row.storage)==held then
        if existing then self.pending[row.key]=nil;self.pending_n=self.pending_n-1 end
        return true
    end
    if not existing then self.pending_n=self.pending_n+1 end
    self.pending[row.key]={row=row,value=held}
    return true
end
function App:unstage(row)
    if self.pending[row.key]then self.pending[row.key]=nil;self.pending_n=self.pending_n-1;return true end
    return false
end
function App:stage_map(map)
    local missing=0
    for key,value in pairs(map)do
        local row=self.catalog:row(key)
        if row and row.editable then self:stage(row,value)else missing=missing+1 end
    end
    return missing
end
function App:apply()
    if self.pending_n==0 then self:toast('Nothing to apply',C.dim);return end
    local n,failed=0,0
    for key,p in pairs(self.pending)do
        local ok,why=self.layer:set(p.row,p.value)
        if ok then self.pending[key]=nil;n=n+1 else failed=failed+1;self:toast(p.row.label..': '..tostring(why),C.error)end
    end
    self.pending_n=failed
    if failed==0 then self:toast('Applying '..n..(n==1 and' change'or' changes'),C.gold)end
    self.save_session=true
end
function App:discard()
    local n=self.pending_n
    self.pending,self.pending_n={},0
    self:toast(n>0 and('Discarded '..n..' pending '..(n==1 and'change'or'changes'))or'Nothing pending',C.dim)
end
function App:reset_defaults()
    local n=self.layer:reset_all()
    self.pending,self.pending_n={},0
    self.save_session=true
    self:toast(n>0 and('Returning '..n..(n==1 and' field'or' fields')..' to the mods\' and game values')
        or'Nothing to reset: no editor values are active',n>0 and C.gold or C.dim)
end
-- Step for nudging a value: integers by 1, decimals by a tenth of their magnitude.
local function nudge_step(row,value,shift,ctrl)
    local step
    if row.integer then step=1
    else
        local mag=math.abs(value)
        step=mag>0 and 10^(math.floor(math.log10(mag))-1)or 0.1
        step=math.max(step,util.STEP)
    end
    if shift then step=step*10 end
    if ctrl then step=math.max(row.integer and 1 or util.STEP,step/10)end
    return step
end
function App:nudge(row,direction,shift,ctrl)
    if not row or not row.editable then return end
    local value=self:row_view(row)
    local step=nudge_step(row,value,shift,ctrl)
    local v=value+direction*step
    if row.integer then v=math.floor(v+0.5)else v=util.round(v)end
    self:stage(row,util.clamp(v,row.min,row.max))
end

---------------------------------------------------------------------------------------------- editing --
function App:begin_edit(row,text,fresh)
    if not row or not row.editable then
        if row then self:toast(row.label..': '..tostring(row.reason or'not editable'),C.error)end
        return
    end
    self.edit={row=row,buffer=text or util.format((self:row_view(row))),fresh=fresh}
end
function App:commit_edit()
    local e=self.edit
    self.edit=nil
    if not e then return end
    local v=tonumber(e.buffer)
    if e.buffer==''then return end
    if not v then self:toast('"'..e.buffer..'" is not a number',C.error);return end
    self:stage(e.row,v)
end
function App:edit_chars(chars)
    local e=self.edit
    for _,ch in ipairs(chars)do
        if e.fresh then e.buffer='';e.fresh=false end
        if ch=='-'then
            if e.buffer:sub(1,1)=='-'then e.buffer=e.buffer:sub(2)else e.buffer='-'..e.buffer end
        elseif ch=='.'then
            if not e.buffer:find('.',1,true)and not e.row.integer then e.buffer=(e.buffer==''and'0'or e.buffer)..'.'end
        elseif ch:match('%d')and#e.buffer<16 then
            e.buffer=e.buffer..ch
        end
    end
end

---------------------------------------------------------------------------------------------- input --
local function clamp_index(i,n)if n<=0 then return 1 end return math.max(1,math.min(n,i))end
function App:move_category(delta)
    local i=self.cat
    repeat
        i=i+(delta>0 and 1 or-1)
        if i<1 or i>#self.categories then return end
    until not self.categories[i].group
    if self.categories[i]then
        self.cat,self.obj,self.obj_scroll,self.field,self.field_scroll=i,1,0,1,0
        self.filter_key=nil
    end
end
function App:select_category(i)
    if self.categories[i]and not self.categories[i].group and i~=self.cat then
        self.cat,self.obj,self.obj_scroll,self.field,self.field_scroll=i,1,0,1,0
        self.filter_key=nil
    end
end
function App:select_object(i)
    if i~=self.obj then self.obj,self.field,self.field_scroll=i,1,0 end
end
function App:next_view(delta)
    local index=1
    for i,v in ipairs(VIEWS)do if v.id==self.view then index=i end end
    index=(index-1+delta)%#VIEWS+1
    self:set_view(VIEWS[index].id)
end
function App:set_view(id)
    self.view,self.edit,self.rename=id,nil,nil
    if self.search then self.search.active=false end
    if id=='mods'then self.mods_cache=nil end
end

function App:handle_browse_keys(f)
    local k=f.keys
    local objects=self:objects()
    local object=self:object()
    local items,selectable=self:field_items(object)
    local row=self:focused_row()
    local page=12
    if self.focus=='categories'then
        if k.UP then self:move_category(-1)end
        if k.DOWN then self:move_category(1)end
        if k.RIGHT or k.ENTER then self.focus='objects'end
    elseif self.focus=='objects'then
        if k.UP then self:select_object(clamp_index(self.obj-1,#objects))end
        if k.DOWN then self:select_object(clamp_index(self.obj+1,#objects))end
        if k.PAGEUP then self:select_object(clamp_index(self.obj-page,#objects))end
        if k.PAGEDOWN then self:select_object(clamp_index(self.obj+page,#objects))end
        if k.HOME then self:select_object(1)end
        if k.END then self:select_object(#objects)end
        if k.LEFT then self.focus='categories'end
        if(k.RIGHT or k.ENTER)and object then self.focus='fields'end
    elseif self.focus=='fields'then
        if k.UP then self.field=clamp_index(self.field-1,#selectable)end
        if k.DOWN then self.field=clamp_index(self.field+1,#selectable)end
        if k.PAGEUP then self.field=clamp_index(self.field-page,#selectable)end
        if k.PAGEDOWN then self.field=clamp_index(self.field+page,#selectable)end
        if k.HOME then self.field=1 end
        if k.END then self.field=#selectable end
        if row then
            if k.LEFT then self:nudge(row,-1,f.shift,f.ctrl)end
            if k.RIGHT then self:nudge(row,1,f.shift,f.ctrl)end
            if k.ENTER then self:begin_edit(row,nil,true)end
            if k.BACKSPACE then
                local text=util.format((self:row_view(row)))
                self:begin_edit(row,text:sub(1,-2))
            end
            if k.DELETE then
                if self:unstage(row)then self:toast('Pending change removed',C.dim)
                else
                    local _,source=self.layer:value(row)
                    if source=='editor'then
                        local base=self.layer:base(row)
                        self:stage(row,base)
                        self:toast('Staged: back to '..util.format(base)..' (press Apply)',C.pending)
                    end
                end
            end
            if#f.chars>0 then
                self:begin_edit(row,'',false)
                if self.edit then self:edit_chars(f.chars)end
            end
        end
        if k.ESCAPE then self.focus='objects'end
    end
end

function App:handle_keys(f)
    local k=f.keys
    if self.confirm then
        if k.ENTER or k.F10 and self.confirm.kind=='reset'or k.INSERT then self:confirm_yes()
        elseif k.ESCAPE or k.BACKSPACE or k.DELETE then self.confirm=nil end
        return
    end
    if self.edit then
        if#f.chars>0 then self:edit_chars(f.chars)end
        if k.BACKSPACE then
            if self.edit.fresh then self.edit.buffer='';self.edit.fresh=false
            else self.edit.buffer=self.edit.buffer:sub(1,-2)end
        end
        if k.ESCAPE or k.DELETE then self.edit=nil
        elseif k.ENTER or k.TAB then self:commit_edit()
        elseif k.UP or k.DOWN then
            self:commit_edit()
            local _,selectable=self:field_items(self:object())
            self.field=clamp_index(self.field+(k.UP and-1 or 1),#selectable)
        end
        return
    end
    if self.search and self.search.active then
        for _,ch in ipairs(f.chars)do
            if#self.search.text<32 then self.search.text=self.search.text..ch;self.obj=1;self.obj_scroll=0 end
        end
        if k.BACKSPACE then self.search.text=self.search.text:sub(1,-2);self.obj=1;self.obj_scroll=0 end
        if k.ESCAPE or k.DELETE then self.search=nil;self.obj=1;self.obj_scroll=0;self.filter_key=nil end
        if k.ENTER or k.TAB or k.DOWN then if self.search then self.search.active=false end;self.focus='objects'end
        return
    end
    if self.rename then
        local r=self.rename
        for _,ch in ipairs(f.chars)do if#r.text<40 then r.text=r.text..ch end end
        if k.BACKSPACE then r.text=r.text:sub(1,-2)end
        if k.ESCAPE or k.DELETE then self.rename=nil
        elseif k.ENTER or k.TAB then self:finish_rename()end
        return
    end
    if k.TAB then
        if f.shift then self:next_view(1)
        elseif self.view=='browse'then
            self.focus=({categories='objects',objects='fields',fields='categories'})[self.focus]
        end
        return
    end
    if k.F9 then self:apply()end
    if k.F10 then self:ask('reset')end
    if f.ctrl and self:key_down_once('F')and self.view=='browse'then
        self.search=self.search or{text=''}
        self.search.active=true
        self.focus='objects'
        return
    end
    if self.view=='browse'then self:handle_browse_keys(f)
    elseif self.view=='mods'then self:handle_mods_keys(f)
    elseif self.view=='presets'then self:handle_presets_keys(f)end
end
function App:key_down_once(name)return self.input:query('pressed',name)end

function App:ask(kind,data)
    if kind=='reset'then
        local active=self.layer:counts()
        if active==0 and self.pending_n==0 then self:toast('Nothing to reset: no editor values are active',C.dim);return end
    end
    self.confirm={kind=kind,data=data}
end
function App:confirm_yes()
    local c=self.confirm
    self.confirm=nil
    if not c then return end
    if c.kind=='reset'then self:reset_defaults()
    elseif c.kind=='delete_preset'then
        self.presets:delete(c.data)
        self:toast('Deleted preset '..c.data,C.dim)
        self.preset_index=clamp_index(self.preset_index-1,#self.presets:list()+1)
    elseif c.kind=='overwrite_preset'then self:save_preset(c.data,true)end
end

------------------------------------------------------------------------------------------------ mouse --
function App:handle_mouse(f)
    local m=f.mouse
    if not m then self.hover=nil;return end
    local ux,uy=self.canvas:to_units(m.x,m.y)
    local action=self.canvas:hit_at(ux,uy)
    self.hover=action and action.hover
    self.mouse_units={x=ux,y=uy,moved=m.moved}
    if f.wheel~=0 then
        local scroller=self.canvas:scroll_at(ux,uy)
        if scroller then scroller.scroll(-f.wheel)end
    end
    if m.clicked and action and action.click then action.click(ux,uy)end
end

------------------------------------------------------------------------------------------------- frame --
function App:frame(d,dt)
    self.time=self.time+(dt or 0)
    local layout=theme.panel
    self.canvas:begin(d,layout.x,layout.y)
    local typing=self.edit~=nil or(self.view=='browse'and self.focus=='fields')
    local letters=(self.search and self.search.active)or self.rename~=nil
    local f=self.input:poll(dt or 0,{typing=typing,letters=letters,mouse=self.ctx.mouse})
    self.frame_input=f
    self:handle_keys(f)
    if f.mouse then self:handle_mouse(f)end
    self:draw()
    if self.toast_msg and self.time-self.toast_msg.time>3.2 then self.toast_msg=nil end
end

----------------------------------------------------------------------------------------------- drawing --
local function chip(cv,text,x,cy,fg,bg,align,z)
    local size=SZ.tiny
    local w=cv:measure(text,size,'title')+14
    if align=='right'then x=x-w end
    cv:rect(x,cy-10,w,20,bg,z or 3)
    cv:text(text,x+7,cy,{size=size,colour=fg,font='title',z=(z or 3)+2})
    return w
end
M.chip=chip
local function button(self,label,x,y,w,h,style,action,hint)
    local cv=self.canvas
    local hovered=self.hover==action
    local bg,fg,edge
    if style=='primary'then bg,fg,edge=C.gold,C.inverse,C.gold
    elseif style=='danger'then bg,fg,edge=hovered and C.error_soft or C.panel,C.error,C.error
    elseif style=='disabled'then bg,fg,edge=C.panel,C.faint,C.line_strong
    else bg,fg,edge=hovered and C.hover or C.panel,C.text,C.line_strong end
    if style=='primary'and hovered then bg={255,214,92,255}end
    cv:rect(x,y,w,h,bg,3)
    cv:frame(x,y,w,h,edge,4)
    cv:text(label,x+w/2,y+h/2,{size=SZ.tab,colour=fg,font='title',align='center',z=6})
    if hint then cv:text(hint,x+w/2,y+h+11,{size=SZ.tiny,colour=C.faint,align='center',z=6})end
    cv:hit(x,y,w,h,action)
end

-- The icon's mark: four corner brackets and three slider bars.
local function logo(cv,x,y,s)
    local g,k=C.gold,C.gold
    local t=math.max(2,s*0.13)
    local l=s*0.36
    cv:rect(x,y,l,t,g,4);cv:rect(x,y,t,l,g,4)
    cv:rect(x+s-l,y,l,t,g,4);cv:rect(x+s-t,y,t,l,g,4)
    cv:rect(x,y+s-t,l,t,g,4);cv:rect(x,y+s-l,t,l,g,4)
    cv:rect(x+s-l,y+s-t,l,t,g,4);cv:rect(x+s-t,y+s-l,t,l,g,4)
    local bw,bh=s*0.5,math.max(1.5,s*0.06)
    local bx=x+s*0.25
    for i,knob in ipairs({0.62,0.18,0.48})do
        local by=y+s*(0.3+0.2*(i-1))
        cv:rect(bx,by-bh/2,bw,bh,g,4)
        cv:rect(bx+bw*knob-s*0.06,by-s*0.07,s*0.12,s*0.14,k,5)
    end
end

function App:draw_header()
    local cv,L=self.canvas,theme.panel
    local h=theme.header_h
    cv:rect(0,0,L.w,h,C.header,1)
    cv:rect(0,h-1,L.w,1,C.line_strong,2)
    logo(cv,18,15,28)
    local x=60
    x=x+cv:text('HD2RUNTIME',x,h/2,{size=SZ.title,font='title',colour=C.text})
    cv:text('EDITOR',x+8,h/2,{size=SZ.title,font='title',colour=C.gold})
    -- tabs
    local tx=330
    for _,v in ipairs(VIEWS)do
        local label=v.label
        if v.id=='mods'then
            local n=#(self:mods_list())
            if n>0 then label=label..'  '..n end
        elseif v.id=='presets'then
            local n=#self.presets:list()
            if n>0 then label=label..'  '..n end
        end
        local w=cv:measure(label,SZ.tab,'title')+28
        local selected=self.view==v.id
        local action=self.tab_actions and self.tab_actions[v.id]
        if not action then
            self.tab_actions=self.tab_actions or{}
            local id=v.id
            action={click=function()self:set_view(id)end}
            self.tab_actions[id]=action
        end
        if selected then
            cv:rect(tx,h-3,w,3,C.gold,4)
            cv:rect(tx,8,w,h-11,C.gold_wash,2)
        elseif self.hover==action then cv:rect(tx,8,w,h-11,C.hover,2)end
        cv:text(label,tx+14,h/2+1,{size=SZ.tab,font='title',colour=selected and C.gold or C.dim})
        cv:hit(tx,6,w,h-6,action)
        tx=tx+w+4
    end
    -- status chips, right to left
    local rx=L.w-18
    local active,applying,errors=self.layer:counts()
    if errors>0 then rx=rx-chip(cv,errors..(errors==1 and' ERROR'or' ERRORS'),rx,h/2,C.error,C.error_soft,'right')-8 end
    if applying>0 then
        local pulse=0.55+0.45*math.abs(math.sin(self.time*4))
        rx=rx-chip(cv,'APPLYING '..applying,rx,h/2,{255,199,44,math.floor(255*pulse)},C.gold_soft,'right')-8
    end
    if active>0 then rx=rx-chip(cv,active..' ACTIVE',rx,h/2,C.gold,C.gold_wash,'right')-8 end
    if self.pending_n>0 then rx=rx-chip(cv,self.pending_n..' PENDING',rx,h/2,C.pending,C.pending_soft,'right')-8 end
    if active==0 and applying==0 and errors==0 and self.pending_n==0 and self.ctx.label then
        cv:text(self.ctx.label,rx,h/2,{size=SZ.small,colour=C.faint,align='right'})
    end
end

-- A vertical list with virtual scrolling. opts: {x, y, w, h, count, row_h, selected, scroll_key, draw(i, x, y, w, h),
-- click(i), focused}. Returns nothing; keeps the selection in view.
function App:list(opts)
    local cv=self.canvas
    local rows=math.max(1,math.floor(opts.h/opts.row_h))
    local scroll=self[opts.scroll_key]or 0
    -- keep the selection in view when it moves (the wheel may scroll it out of view in between)
    local seen=opts.scroll_key..'_selected'
    if opts.selected and self[seen]~=opts.selected then
        self[seen]=opts.selected
        if opts.selected<scroll+1 then scroll=opts.selected-1 end
        if opts.selected>scroll+rows then scroll=opts.selected-rows end
    end
    scroll=math.max(0,math.min(scroll,math.max(0,opts.count-rows)))
    self[opts.scroll_key]=scroll
    for i=scroll+1,math.min(opts.count,scroll+rows)do
        local y=opts.y+(i-scroll-1)*opts.row_h
        opts.draw(i,opts.x,y,opts.w,opts.row_h)
        if opts.click then
            local action=opts.actions and opts.actions[i]
            if not action then
                action={click=function()opts.click(i)end}
                if opts.actions then opts.actions[i]=action end
            end
            action.scroll=nil
            cv:hit(opts.x,y,opts.w,opts.row_h,action)
        end
    end
    -- scrollbar
    if opts.count>rows then
        local track_h=opts.h-4
        local thumb_h=math.max(24,track_h*rows/opts.count)
        local t=scroll/math.max(1,opts.count-rows)
        cv:rect(opts.x+opts.w-4,opts.y+2,3,track_h,C.line,3)
        cv:rect(opts.x+opts.w-4,opts.y+2+(track_h-thumb_h)*t,3,thumb_h,opts.focused and C.gold or C.line_strong,4)
    end
    -- wheel over the list
    local key=opts.scroll_key
    cv:hit(opts.x,opts.y,opts.w,opts.h,{scroll=function(delta)
        self[key]=math.max(0,math.min((self[key]or 0)+delta*3,math.max(0,opts.count-rows)))
        self.wheel_scrolled=key
    end,passthrough=true})
    -- row hits must win over the wheel region: move it to the front
    local hits=cv.hits
    table.insert(hits,1,table.remove(hits))
    return rows,scroll
end

function App:draw_categories(y0,h)
    local cv=self.canvas
    cv:rect(0,y0,CAT_W,h,C.panel_alt,1)
    cv:rect(CAT_W-1,y0,1,h,C.line,2)
    self.cat_actions=self.cat_actions or{}
    local focused=self.focus=='categories'
    local y=y0+10
    for i,item in ipairs(self.categories)do
        if item.group then
            y=y+(i>1 and 10 or 0)
            cv:text(item.label,18,y+11,{size=SZ.heading,font='title',colour=C.faint})
            y=y+24
        else
            local rh=31
            local selected=i==self.cat
            local action=self.cat_actions[i]
            if not action then
                local index=i
                action={click=function()self:select_category(index);self.focus='categories'end}
                self.cat_actions[i]=action
            end
            if selected then
                cv:rect(8,y,CAT_W-16,rh,focused and C.select or C.gold_wash,2)
                cv:rect(8,y,3,rh,focused and C.gold or C.gold_dim,3)
            elseif self.hover==action then cv:rect(8,y,CAT_W-16,rh,C.hover,2)end
            cv:text(item.label,22,y+rh/2,{size=SZ.label,colour=selected and C.text or C.dim,max=CAT_W-80})
            local count=self.catalog:count(item.id)
            cv:text(tostring(count),CAT_W-20,y+rh/2,{size=SZ.small,colour=C.faint,align='right'})
            cv:hit(8,y,CAT_W-16,rh,action)
            y=y+rh
        end
    end
end

function App:draw_objects(y0,h)
    local cv=self.canvas
    local x0=CAT_W
    cv:rect(x0,y0,OBJ_W,h,C.panel,1)
    cv:rect(x0+OBJ_W-1,y0,1,h,C.line,2)
    -- search
    local sy=y0+10
    local searching=self.search and self.search.active
    cv:rect(x0+12,sy,OBJ_W-24,32,C.box,3)
    cv:frame(x0+12,sy,OBJ_W-24,32,searching and C.box_focus or C.box_edge,4)
    local text=self.search and self.search.text or''
    if text==''and not searching then
        cv:text('Search   Ctrl+F',x0+24,sy+16,{size=SZ.small,colour=C.faint})
    else
        local w=cv:text(text,x0+24,sy+16,{size=SZ.label,colour=C.text,max=OBJ_W-60})
        if searching and math.floor(self.time*2)%2==0 then cv:rect(x0+26+w,sy+7,2,18,C.gold,6)end
    end
    self.search_action=self.search_action or{click=function()
        self.search=self.search or{text=''};self.search.active=true;self.focus='objects'end}
    cv:hit(x0+12,sy,OBJ_W-24,32,self.search_action)
    local objects=self:objects()
    self.obj=clamp_index(self.obj,#objects)
    local markers=self:markers()
    local focused=self.focus=='objects'
    local ly=sy+44
    self.obj_actions_key=self.obj_actions_key or''
    local akey=tostring(self.cat)..'\0'..(self.search and self.search.text or'')
    if self.obj_actions_key~=akey then self.obj_actions,self.obj_actions_key={},akey end
    if#objects==0 then
        local msg=self.objects_error and('Unavailable on this Runtime: '..self.objects_error)
            or(self.search and'No match'or'Nothing here')
        cv:text(msg,x0+20,ly+20,{size=SZ.small,colour=C.faint,max=OBJ_W-40})
    end
    self:list({x=x0,y=ly,w=OBJ_W-1,h=y0+h-ly-6,count=#objects,row_h=theme.list_row_h+8,selected=self.obj,
        scroll_key='obj_scroll',focused=focused,actions=self.obj_actions,
        click=function(i)self:select_object(i);self.focus='objects'end,
        draw=function(i,x,y,w,rh)
            local object=objects[i]
            local selected=i==self.obj
            if selected then
                cv:rect(x+8,y+2,w-16,rh-4,focused and C.select or C.gold_wash,2)
                cv:rect(x+8,y+2,3,rh-4,focused and C.gold or C.gold_dim,3)
            elseif self.hover==(self.obj_actions[i])then cv:rect(x+8,y+2,w-16,rh-4,C.hover,2)end
            cv:text(object.name,x+22,y+15,{size=SZ.label,colour=selected and C.text or C.dim,max=w-74})
            cv:text(object.subtitle or'',x+22,y+31,{size=SZ.tiny,colour=C.faint,max=w-74})
            local mx=x+w-20
            if markers.pending[object.key]then cv:rect(mx-7,y+rh/2-4,8,8,C.pending,4);mx=mx-14 end
            if markers.editor[object.key]then cv:rect(mx-7,y+rh/2-4,8,8,C.gold,4);mx=mx-14 end
            if markers.mod[object.key]then cv:rect(mx-7,y+rh/2-4,8,8,C.mod,4)end
        end})
end

-- Column positions of the field rows (relative to the fields pane).
local FX={label=18,default_right=404,box=416,box_w=120,unit=544,badge_right=-14}
function App:draw_fields(y0,h)
    local cv=self.canvas
    local x0=CAT_W+OBJ_W
    local w=theme.panel.w-x0
    cv:rect(x0,y0,w,h,C.panel_alt,1)
    local object=self:object()
    if not object then
        cv:text('Select a category and an object',x0+24,y0+40,{size=SZ.label,colour=C.faint})
        return
    end
    -- object header
    cv:text(object.name,x0+20,y0+24,{size=20,font='title',colour=C.text,max=w-40})
    local items,selectable=self:field_items(object)
    local edited=0
    for _,row in ipairs(object.rows)do
        local _,source=self:row_view(row)
        if source=='pending'or source=='editor'then edited=edited+1 end
    end
    local sub=(object.subtitle and(object.subtitle..'   ')or'')..#object.rows..' fields'
        ..(edited>0 and('   '..edited..' edited')or'')
    cv:text(sub,x0+20,y0+47,{size=SZ.small,colour=C.faint,max=w-40})
    if object.error then cv:text('Could not read: '..object.error,x0+20,y0+70,{size=SZ.small,colour=C.error,max=w-40})end
    -- column titles
    local hy=y0+66
    cv:rect(x0,hy,w,22,C.header,2)
    cv:text('FIELD',x0+FX.label,hy+11,{size=SZ.tiny,font='title',colour=C.faint})
    cv:text('DEFAULT',x0+FX.default_right,hy+11,{size=SZ.tiny,font='title',colour=C.faint,align='right'})
    cv:text('VALUE',x0+FX.box+FX.box_w-8,hy+11,{size=SZ.tiny,font='title',colour=C.faint,align='right'})
    cv:text('SOURCE',x0+w+FX.badge_right,hy+11,{size=SZ.tiny,font='title',colour=C.faint,align='right'})
    self.field=clamp_index(self.field,#selectable)
    local selected_item=selectable[self.field]
    local focused=self.focus=='fields'
    local ly=hy+24
    local rh=theme.row_h
    if self.fields_actions_object~=object then self.fields_actions,self.fields_actions_object={},object end
    local actions=self.fields_actions
    self:list({x=x0,y=ly,w=w,h=y0+h-ly-4,count=#items,row_h=rh,selected=selected_item,scroll_key='field_scroll',
        focused=focused,actions=nil,
        draw=function(i,x,y,lw)
            local item=items[i]
            if item.section then
                cv:text(string.upper(item.section),x+FX.label,y+rh/2+3,{size=SZ.tiny,font='title',colour=C.gold_dim,max=lw-120})
                local tw=math.min(cv:measure(string.upper(item.section),SZ.tiny,'title'),lw-120)
                cv:rect(x+FX.label+tw+10,y+rh/2+3,lw-FX.label-tw-24,1,C.line,2)
                return
            end
            local row=item.row
            local selected=i==selected_item
            local action=actions[i]
            if not action then
                local index=i
                action={click=function(ux)
                    for s,idx in ipairs(selectable)do if idx==index then self.field=s end end
                    self.focus='fields'
                    local r=items[index].row
                    if ux>=x0+FX.box and ux<=x0+FX.box+FX.box_w then self:begin_edit(r,nil,true)end
                end}
                actions[i]=action
            end
            cv:hit(x,y,lw,rh,action)
            if selected then
                cv:rect(x+6,y+1,lw-12,rh-2,focused and C.select or C.gold_wash,2)
                cv:rect(x+6,y+1,3,rh-2,focused and C.gold or C.gold_dim,3)
            elseif self.hover==action then cv:rect(x+6,y+1,lw-12,rh-2,C.hover,2)end
            local cy=y+rh/2
            cv:text(row.label,x+FX.label,cy,{size=SZ.label,colour=row.editable and(selected and C.text or C.dim)or C.faint,
                max=FX.default_right-FX.label-90})
            cv:text(util.format(row.vanilla),x+FX.default_right,cy,{size=SZ.small,colour=C.faint,align='right',max=84})
            -- value box
            local value,source,state,holder,err=self:row_view(row)
            local editing=self.edit and self.edit.row==row
            local bx,bw=x+FX.box,FX.box_w
            local edge=C.box_edge
            local colour=C.text
            if editing then edge=C.box_focus
            elseif source=='pending'then edge,colour=C.pending,C.pending
            elseif source=='editor'then edge,colour=C.gold_dim,C.gold
            elseif source=='mod'then colour=C.mod end
            cv:rect(bx,y+4,bw,rh-8,C.box,3)
            cv:frame(bx,y+4,bw,rh-8,edge,4)
            if editing then
                local text=self.edit.buffer
                local tw=cv:text(text,bx+bw-10,cy,{size=SZ.label,colour=C.text,align='right',max=bw-16})
                if self.edit.fresh and text~=''then cv:rect(bx+bw-12-tw,y+7,tw+4,rh-14,C.gold_soft,4)end
                if math.floor(self.time*2.2)%2==0 then cv:rect(bx+bw-8,y+8,2,rh-16,C.gold,6)end
            else
                cv:text(util.format(value),bx+bw-10,cy,{size=SZ.label,colour=row.editable and colour or C.faint,
                    align='right',max=bw-16})
            end
            local unit=util.unit(row.unit)
            if unit then cv:text(unit,x+FX.unit,cy,{size=SZ.tiny,colour=C.faint,max=56})end
            -- source badge
            local bxr=x+lw+FX.badge_right
            if not row.editable then chip(cv,'LOCKED',bxr,cy,C.faint,C.line,'right')
            elseif state=='error'then chip(cv,'ERROR',bxr,cy,C.error,C.error_soft,'right')
            elseif source=='pending'then chip(cv,'PENDING',bxr,cy,C.pending,C.pending_soft,'right')
            elseif state=='applying'then chip(cv,'APPLYING',bxr,cy,C.gold,C.gold_soft,'right')
            elseif source=='editor'then chip(cv,'EDITED',bxr,cy,C.gold,C.gold_wash,'right')
            elseif source=='mod'then chip(cv,'MOD',bxr,cy,C.mod,C.mod_soft,'right')end
        end})
end

function App:draw_status(y,h)
    local cv=self.canvas
    local L=theme.panel
    cv:rect(0,y,L.w,h,C.header,1)
    cv:rect(0,y,L.w,1,C.line,2)
    local cy=y+h/2
    if self.toast_msg then
        cv:text(self.toast_msg.text,L.w-18,cy,{size=SZ.small,colour=self.toast_msg.colour,align='right',max=520})
    end
    local maxw=self.toast_msg and L.w-580 or L.w-40
    if self.view=='browse'then
        local row=self:focused_row()
        if not row then
            cv:text('Pick a field: ↑↓ to move, → to go deeper, Tab to switch panes',18,cy,{size=SZ.small,colour=C.faint,max=maxw})
            return
        end
        local value,source,state,holder,err=self:row_view(row)
        local parts={}
        local x=18
        if err then
            cv:text('Error: '..err,x,cy,{size=SZ.small,colour=C.error,max=maxw})
            return
        end
        if not row.editable then
            cv:text('Locked: '..tostring(row.reason),x,cy,{size=SZ.small,colour=C.faint,max=maxw})
            return
        end
        local range=(row.min or row.max)and('range '..util.format(row.min or-math.huge)..' to '..util.format(row.max))or'no published range'
        x=x+cv:text(tostring(row.field),x,cy,{size=SZ.small,colour=C.dim,max=260})+16
        x=x+cv:text(range..(row.integer and', whole numbers'or''),x,cy,{size=SZ.small,colour=C.faint,max=240})+14
        if row.shared then x=x+chip(cv,'SHARED',x,cy,C.pending,C.pending_soft)+6 end
        if row.unverified then x=x+chip(cv,'UNVERIFIED EFFECT',x,cy,C.faint,C.line)+6 end
        local _,base_holder=self.layer:base(row)
        if base_holder then
            x=x+10
            cv:text('Mod: '..pretty_mod(base_holder.mod)..' = '..util.format(base_holder.value),x,cy,
                {size=SZ.small,colour=C.mod,max=math.max(40,maxw-x)})
        end
    elseif self.view=='mods'then
        cv:text('Values each installed HD2Runtime mod applied this session. The editor overrides them only when you apply an edit.',
            18,cy,{size=SZ.small,colour=C.faint,max=maxw})
    else
        cv:text('Presets store field values by name; loading one stages them as pending changes.',
            18,cy,{size=SZ.small,colour=C.faint,max=maxw})
    end
end

function App:draw_footer(y,h)
    local cv=self.canvas
    local L=theme.panel
    cv:rect(0,y,L.w,h,C.footer,1)
    cv:rect(0,y,L.w,1,C.line_strong,2)
    local hint
    if self.edit then hint='Type a number   Backspace erase   Tab / ↑↓ confirm   Del cancel'
    elseif self.search and self.search.active then hint='Type to filter   Backspace erase   Tab done   Del clear'
    elseif self.rename then hint='Type a name   Tab save   Del cancel'
    elseif self.view=='browse'and self.focus=='fields'then
        hint='F8 close   ←→ adjust (Shift x10, Ctrl ÷10)   digits type a value   Del revert   F9 apply'
    else hint='F8 close   ↑↓ select   ←→ panes   Tab next pane   Shift+Tab next tab   F9 apply' end
    cv:text(hint,18,y+h/2,{size=SZ.small,colour=C.faint,max=L.w-560})
    local bh=34
    local by=y+(h-bh)/2
    local bx=L.w-14
    local active=self.layer:counts()
    self.btn_reset=self.btn_reset or{click=function()self:ask('reset')end}
    self.btn_discard=self.btn_discard or{click=function()self:discard()end}
    self.btn_apply=self.btn_apply or{click=function()self:apply()end}
    local w=196
    bx=bx-w
    button(self,'RESET TO DEFAULTS',bx,by,w,bh,(active>0 or self.pending_n>0)and'danger'or'disabled',self.btn_reset)
    w=110;bx=bx-w-10
    button(self,'DISCARD',bx,by,w,bh,self.pending_n>0 and'normal'or'disabled',self.btn_discard)
    w=150;bx=bx-w-10
    button(self,self.pending_n>0 and('APPLY  '..self.pending_n)or'APPLY',bx,by,w,bh,
        self.pending_n>0 and'primary'or'disabled',self.btn_apply)
end

function App:draw_confirm()
    local c=self.confirm
    if not c then return end
    local cv=self.canvas
    local L=theme.panel
    cv:rect(0,0,L.w,L.h,C.scrim,8)
    local w,h=560,190
    local x,y=(L.w-w)/2,(L.h-h)/2-40
    cv:rect(x,y,w,h,C.panel_alt,9)
    cv:frame(x,y,w,h,C.line_strong,10)
    cv:rect(x,y,w,3,c.kind=='reset'and C.error or C.gold,10)
    local title,body
    if c.kind=='reset'then
        local active=self.layer:counts()
        title='RESET TO DEFAULTS?'
        body={'Every field the editor changed goes back to the value its mod applies,',
            'or to the game\'s own value. '..active..' active, '..self.pending_n..' pending.'}
    elseif c.kind=='delete_preset'then
        title='DELETE PRESET?';body={'"'..tostring(c.data)..'" will be removed from your saved presets.'}
    elseif c.kind=='overwrite_preset'then
        title='OVERWRITE PRESET?';body={'"'..tostring(c.data)..'" will be replaced with the current values.'}
    end
    cv:text(title,x+24,y+34,{size=19,font='title',colour=C.text,z=11})
    for i,line in ipairs(body)do cv:text(line,x+24,y+62+(i-1)*22,{size=SZ.small,colour=C.dim,max=w-48,z=11})end
    self.btn_confirm=self.btn_confirm or{click=function()self:confirm_yes()end}
    self.btn_cancel=self.btn_cancel or{click=function()self.confirm=nil end}
    local bw,bh=150,34
    local by=y+h-bh-20
    -- swallow clicks outside the dialog (added before its buttons, so they stay on top)
    cv:hit(-10000,-10000,20000,20000,{})
    local function modal_button(label,bx,style,action)
        local hovered=self.hover==action
        local bg=style=='danger'and(hovered and{255,96,84,90}or C.error_soft)or(hovered and C.hover or C.panel)
        cv:rect(bx,by,bw,bh,bg,10)
        cv:frame(bx,by,bw,bh,style=='danger'and C.error or C.line_strong,11)
        cv:text(label,bx+bw/2,by+bh/2,{size=SZ.tab,font='title',colour=style=='danger'and C.error or C.text,align='center',z=12})
        cv:hit(bx,by,bw,bh,action)
    end
    modal_button('CANCEL',x+w-24-bw*2-12,'normal',self.btn_cancel)
    modal_button('CONFIRM',x+w-24-bw,'danger',self.btn_confirm)
    cv:text('Enter / Ins confirm   Esc / Del cancel',x+24,by+bh/2,{size=SZ.tiny,colour=C.faint,z=11})
end

------------------------------------------------------------------------------------------------- mods view --
function App:mods_list()
    local key=self.ledger.version
    if self.mods_cache and self.mods_cache_key==key and self.time-(self.mods_cache_time or 0)<2 then return self.mods_cache end
    self.mods_cache,self.mods_cache_key,self.mods_cache_time=self.ledger:mods(),key,self.time
    return self.mods_cache
end
function App:handle_mods_keys(f)
    local k=f.keys
    local mods=self:mods_list()
    if k.UP then self.mod_index=clamp_index(self.mod_index-1,#mods);self.write_scroll=0 end
    if k.DOWN then self.mod_index=clamp_index(self.mod_index+1,#mods);self.write_scroll=0 end
    if k.PAGEUP then self.write_scroll=math.max(0,self.write_scroll-10)end
    if k.PAGEDOWN then self.write_scroll=self.write_scroll+10 end
    if k.RIGHT or k.ENTER then self:open_mod_write(mods[self.mod_index],1)end
end
-- Jump to the field of a mod's write in Browse.
function App:open_mod_write(mod,index)
    local claim=mod and mod.writes[index]
    if not claim or not claim.object then return end
    local row=self.catalog:find(claim.object,claim.loc,claim.descriptor)
    if not row then self:toast('That field is not in the editor catalogue',C.dim);return end
    self:reveal(row)
end
function App:reveal(row)
    local object=row.object
    for i,item in ipairs(self.categories)do
        if item.id==object.category then self.cat=i end
    end
    self.search,self.filter_key=nil,nil
    for i,o in ipairs(self:objects())do if o==object then self.obj=i end end
    local items,selectable=self:field_items(self.catalog:open(object))
    for s,index in ipairs(selectable)do if items[index].row==row then self.field=s end end
    self.view,self.focus='browse','fields'
end
function App:draw_mods(y0,h)
    local cv=self.canvas
    local L=theme.panel
    local mods=self:mods_list()
    self.mod_index=clamp_index(self.mod_index,#mods)
    cv:rect(0,y0,MODS_W,h,C.panel_alt,1)
    cv:rect(MODS_W-1,y0,1,h,C.line,2)
    cv:text('INSTALLED HD2RUNTIME MODS',18,y0+20,{size=SZ.heading,font='title',colour=C.faint})
    if#mods==0 then
        cv:text('No other HD2Runtime mod has registered an operation.',18,y0+52,{size=SZ.small,colour=C.faint,max=MODS_W-36})
    end
    self.mod_actions=self.mod_actions or{}
    self:list({x=0,y=y0+36,w=MODS_W-1,h=h-40,count=#mods,row_h=52,selected=self.mod_index,scroll_key='mod_scroll',
        focused=true,actions=self.mod_actions,click=function(i)self.mod_index=i;self.write_scroll=0 end,
        draw=function(i,x,y,w,rh)
            local mod=mods[i]
            local selected=i==self.mod_index
            if selected then cv:rect(x+8,y+2,w-16,rh-4,C.select,2);cv:rect(x+8,y+2,3,rh-4,C.gold,3)
            elseif self.hover==self.mod_actions[i]then cv:rect(x+8,y+2,w-16,rh-4,C.hover,2)end
            cv:text(pretty_mod(mod.id),x+22,y+17,{size=SZ.label,colour=selected and C.text or C.dim,max=w-150})
            cv:text(mod.id,x+22,y+36,{size=SZ.tiny,colour=C.faint,max=w-150})
            local rx=x+w-18
            if mod.refused>0 then rx=rx-chip(cv,mod.refused..' REFUSED',rx,y+17,C.error,C.error_soft,'right')-6 end
            chip(cv,mod.applied..(mod.applied==1 and' VALUE'or' VALUES'),x+w-18,y+37,C.mod,C.mod_soft,'right')
        end})
    -- detail
    local mod=mods[self.mod_index]
    local x0=MODS_W
    local w=L.w-x0
    cv:rect(x0,y0,w,h,C.panel,1)
    if not mod then return end
    cv:text(pretty_mod(mod.id),x0+20,y0+24,{size=20,font='title',colour=C.text,max=w-40})
    local summary=#mod.operations..(#mod.operations==1 and' operation'or' operations')..'   '..mod.applied
        ..(mod.applied==1 and' value applied'or' values applied')..(mod.refused>0 and('   '..mod.refused..' refused')or'')
    cv:text(mod.id..'   '..summary,x0+20,y0+47,{size=SZ.small,colour=C.faint,max=w-40})
    -- rows: writes then refused operations
    local rows={}
    for _,claim in ipairs(mod.writes)do rows[#rows+1]={claim=claim}end
    for _,op in ipairs(mod.operations)do
        if op.status=='rejected'or op.status=='blocked'then rows[#rows+1]={op=op}end
    end
    local hy=y0+66
    cv:rect(x0,hy,w,22,C.header,2)
    cv:text('FIELD',x0+18,hy+11,{size=SZ.tiny,font='title',colour=C.faint})
    cv:text('MOD VALUE',x0+w-210,hy+11,{size=SZ.tiny,font='title',colour=C.faint,align='right'})
    cv:text('NOW',x0+w-18,hy+11,{size=SZ.tiny,font='title',colour=C.faint,align='right'})
    if self.write_actions_mod~=mod.id then self.write_actions,self.write_actions_mod={},mod.id end
    self:list({x=x0,y=hy+24,w=w,h=y0+h-hy-28,count=#rows,row_h=30,scroll_key='write_scroll',focused=false,
        actions=self.write_actions,click=function(i)if rows[i].claim then self:open_mod_write(mod,i)end end,
        draw=function(i,x,y,lw,rh)
            local item=rows[i]
            local cy=y+rh/2
            if self.hover==self.write_actions[i]then cv:rect(x+6,y+1,lw-12,rh-2,C.hover,2)end
            if item.claim then
                local claim=item.claim
                local label=claim.text
                cv:text(label,x+18,cy,{size=SZ.small,colour=C.dim,max=lw-330})
                cv:text(util.format(claim.value),x+lw-210,cy,{size=SZ.label,colour=C.mod,align='right',max=100})
                local slot=self.layer.slots[claim.loc]
                if slot and slot.user then
                    chip(cv,'EDITOR '..util.format(slot.target),x+lw-18,cy,C.gold,C.gold_wash,'right')
                elseif slot and slot.watch then
                    chip(cv,'HELD BY EDITOR',x+lw-18,cy,C.faint,C.line,'right')
                else
                    chip(cv,'ACTIVE',x+lw-18,cy,C.mod,C.mod_soft,'right')
                end
            else
                local op=item.op
                cv:text((op.kind or'op')..' '..tostring(op.id)..': '..tostring(op.error or op.code or op.status),x+18,cy,
                    {size=SZ.small,colour=C.error,max=lw-140})
                chip(cv,'REFUSED',x+lw-18,cy,C.error,C.error_soft,'right')
            end
        end})
end

---------------------------------------------------------------------------------------------- presets view --
function App:current_values()
    local values=self.layer:overrides()
    for key,p in pairs(self.pending)do values[key]=p.value end
    return values
end
function App:save_preset(name,confirmed)
    local values=self:current_values()
    if next(values)==nil then self:toast('Nothing to save: edit a field first',C.dim);return end
    if not confirmed and self.presets:find(name)then self:ask('overwrite_preset',name);return end
    local ok,why=self.presets:save(name,values)
    if ok then self:toast('Saved preset '..name..' ('..util.count(values)..' fields)',C.ok)
    else self:toast('Could not save: '..tostring(why),C.error)end
end
function App:load_preset(name)
    local values=self.presets:load(name)
    if not values then return end
    local missing=self:stage_map(values)
    self:toast('Loaded '..name..': '..self.pending_n..' pending'..(missing>0 and(', '..missing..' unknown fields skipped')or'')
        ..'. Press Apply.',missing>0 and C.pending or C.ok)
end
function App:finish_rename()
    local r=self.rename
    self.rename=nil
    if not r then return end
    if r.create then
        local name=self.presets:unique_name(r.text~=''and r.text or'Preset')
        self:save_preset(name,true)
        local list=self.presets:list()
        self.preset_index=#list+1
        return
    end
    local ok,why=self.presets:rename(r.old,r.text)
    if ok then self:toast('Renamed to '..r.text,C.ok)else self:toast(tostring(why),C.error)end
end
local PRESET_ACTIONS={'LOAD','SAVE OVER','RENAME','DELETE'}
function App:preset_action_run(index,preset)
    if not preset then return end
    local a=PRESET_ACTIONS[index]
    if a=='LOAD'then self:load_preset(preset.name)
    elseif a=='SAVE OVER'then self:save_preset(preset.name)
    elseif a=='RENAME'then self.rename={old=preset.name,text=preset.name}
    elseif a=='DELETE'then self:ask('delete_preset',preset.name)end
end
function App:new_preset()
    if next(self:current_values())==nil then self:toast('Nothing to save: edit a field first',C.dim);return end
    self.rename={create=true,text=self.presets:unique_name('Preset')}
end
function App:handle_presets_keys(f)
    local k=f.keys
    local list=self.presets:list()
    local n=#list+1
    if k.UP then self.preset_index=clamp_index(self.preset_index-1,n)end
    if k.DOWN then self.preset_index=clamp_index(self.preset_index+1,n)end
    if k.LEFT then self.preset_action=clamp_index(self.preset_action-1,#PRESET_ACTIONS)end
    if k.RIGHT then self.preset_action=clamp_index(self.preset_action+1,#PRESET_ACTIONS)end
    if k.INSERT then self:new_preset()end
    if k.ENTER then
        if self.preset_index==1 then self:new_preset()
        else self:preset_action_run(self.preset_action,list[self.preset_index-1])end
    end
    if k.DELETE and self.preset_index>1 then self:ask('delete_preset',list[self.preset_index-1].name)end
end
function App:draw_presets(y0,h)
    local cv=self.canvas
    local L=theme.panel
    local list=self.presets:list()
    local n=#list+1
    self.preset_index=clamp_index(self.preset_index,n)
    cv:rect(0,y0,PRESETS_W,h,C.panel_alt,1)
    cv:rect(PRESETS_W-1,y0,1,h,C.line,2)
    cv:text('PRESETS',18,y0+20,{size=SZ.heading,font='title',colour=C.faint})
    if not self.presets:available()then
        cv:text('Saved data needs a newer HD2Runtime (hd2.store).',18,y0+52,{size=SZ.small,colour=C.error,max=PRESETS_W-36})
        return
    end
    self.preset_actions=self.preset_actions or{}
    local bottom=y0+h-96
    self:list({x=0,y=y0+36,w=PRESETS_W-1,h=bottom-y0-40,count=n,row_h=48,selected=self.preset_index,
        scroll_key='preset_scroll',focused=true,actions=self.preset_actions,
        click=function(i)
            if i==1 and self.preset_index==1 then self:new_preset()end
            self.preset_index=i
        end,
        draw=function(i,x,y,w,rh)
            local selected=i==self.preset_index
            if selected then cv:rect(x+8,y+2,w-16,rh-4,C.select,2);cv:rect(x+8,y+2,3,rh-4,C.gold,3)
            elseif self.hover==self.preset_actions[i]then cv:rect(x+8,y+2,w-16,rh-4,C.hover,2)end
            if i==1 then
                local renaming=self.rename and self.rename.create
                if renaming then
                    local tw=cv:text(self.rename.text,x+22,y+rh/2,{size=SZ.label,colour=C.text,max=w-60})
                    if math.floor(self.time*2)%2==0 then cv:rect(x+24+tw,y+14,2,20,C.gold,6)end
                else
                    cv:text('+  NEW PRESET FROM CURRENT VALUES',x+22,y+rh/2,{size=SZ.tab,font='title',colour=C.gold,max=w-44})
                end
                return
            end
            local p=list[i-1]
            local renaming=self.rename and not self.rename.create and self.rename.old==p.name
            if renaming then
                local tw=cv:text(self.rename.text,x+22,y+17,{size=SZ.label,colour=C.text,max=w-60})
                if math.floor(self.time*2)%2==0 then cv:rect(x+24+tw,y+7,2,20,C.gold,6)end
            else
                cv:text(p.name,x+22,y+17,{size=SZ.label,colour=selected and C.text or C.dim,max=w-60})
            end
            local when=p.created and p.created>0 and os.date and os.date('%Y-%m-%d %H:%M',p.created)or''
            cv:text(p.count..(p.count==1 and' field'or' fields')..(when~=''and('   '..when)or''),x+22,y+35,
                {size=SZ.tiny,colour=C.faint,max=w-44})
        end})
    -- settings
    local sy=bottom+8
    cv:rect(0,sy-8,PRESETS_W-1,1,C.line,2)
    local restore=self.presets:setting('restore_session',true)
    self.toggle_restore=self.toggle_restore or{click=function()
        self.presets:set_setting('restore_session',not self.presets:setting('restore_session',true))end}
    local tx,ty=18,sy+14
    cv:rect(tx,ty-9,34,18,restore and C.gold or C.line_strong,3)
    cv:rect(restore and tx+18 or tx+2,ty-7,14,14,restore and C.inverse or C.dim,4)
    cv:text('Restore my last applied values when the game starts',tx+46,ty,{size=SZ.small,colour=C.dim,max=PRESETS_W-80})
    cv:hit(tx,ty-12,PRESETS_W-36,24,self.toggle_restore)
    cv:text('Open the editor with '..tostring(self.ctx.hotkey or'F8')..'. Edits apply live through HD2Runtime\'s guarded writes.',
        18,sy+48,{size=SZ.tiny,colour=C.faint,max=PRESETS_W-36})
    -- detail
    local x0=PRESETS_W
    local w=L.w-x0
    cv:rect(x0,y0,w,h,C.panel,1)
    if self.preset_index==1 then
        local values=self:current_values()
        cv:text('NEW PRESET',x0+20,y0+24,{size=20,font='title',colour=C.text})
        cv:text(util.count(values)..' fields would be saved: every applied editor value and every pending change.',
            x0+20,y0+47,{size=SZ.small,colour=C.faint,max=w-40})
        self.btn_new=self.btn_new or{click=function()self:new_preset()end}
        button(self,'SAVE AS NEW PRESET',x0+20,y0+72,230,34,next(values)and'primary'or'disabled',self.btn_new)
        self:draw_value_list(values,x0,y0+124,w,y0+h-y0-128)
        return
    end
    local p=list[self.preset_index-1]
    cv:text(p.name,x0+20,y0+24,{size=20,font='title',colour=C.text,max=w-40})
    cv:text(p.count..' fields',x0+20,y0+47,{size=SZ.small,colour=C.faint})
    self.preset_btns=self.preset_btns or{}
    local bx=x0+20
    for i,label in ipairs(PRESET_ACTIONS)do
        local action=self.preset_btns[i]
        if not action then
            local index=i
            action={click=function()self.preset_action=index;self:preset_action_run(index,self.presets:list()[self.preset_index-1])end}
            self.preset_btns[i]=action
        end
        local bw=cv:measure(label,SZ.tab,'title')+40
        local style=(i==1 and'primary')or(label=='DELETE'and'danger')or'normal'
        button(self,label,bx,y0+72,bw,34,style,action)
        if i==self.preset_action then cv:rect(bx,y0+108,bw,2,C.gold,5)end
        bx=bx+bw+10
    end
    local values={}
    for _,item in ipairs(p.fields or{})do values[item.k]=item.v end
    self:draw_value_list(values,x0,y0+124,w,y0+h-y0-128)
end
-- Field values by key: resolved names where the catalogue has the field.
function App:draw_value_list(values,x0,y,w,h)
    local cv=self.canvas
    local keys=util.sorted_keys(values)
    local rows={}
    for _,key in ipairs(keys)do
        local row=self.catalog:row(key)
        rows[#rows+1]={key=key,row=row,value=values[key]}
    end
    table.sort(rows,function(a,b)
        local an=a.row and(a.row.object.name..' '..a.row.label)or a.key
        local bn=b.row and(b.row.object.name..' '..b.row.label)or b.key
        return util.natural_less(an,bn)
    end)
    cv:rect(x0,y,w,22,C.header,2)
    cv:text('FIELD',x0+18,y+11,{size=SZ.tiny,font='title',colour=C.faint})
    cv:text('VALUE',x0+w-18,y+11,{size=SZ.tiny,font='title',colour=C.faint,align='right'})
    self:list({x=x0,y=y+24,w=w,h=h-24,count=#rows,row_h=28,scroll_key='detail_scroll',focused=false,
        draw=function(i,x,ry,lw,rh)
            local item=rows[i]
            local cy=ry+rh/2
            if item.row then
                local name=item.row.object.name
                local nw=cv:text(name,x+18,cy,{size=SZ.small,colour=C.faint,max=(lw-140)*0.45})
                cv:text(item.row.label,x+30+nw,cy,{size=SZ.small,colour=C.dim,max=lw-170-nw})
            else
                cv:text('Unknown field: '..item.key,x+18,cy,{size=SZ.small,colour=C.faint,max=lw-140})
            end
            cv:text(util.format(item.value),x+lw-18,cy,{size=SZ.label,colour=C.gold,align='right',max=110})
        end})
end

---------------------------------------------------------------------------------------------- main draw --
function App:draw()
    local cv=self.canvas
    local L=theme.panel
    -- frame and shadow
    cv:rect(-4,-4,L.w+8,L.h+8,C.shadow,0)
    cv:rect(0,0,L.w,L.h,C.panel,0)
    self:draw_header()
    local body_y=theme.header_h
    local body_h=L.h-theme.header_h-theme.footer_h-theme.status_h
    if self.view=='browse'then
        self:draw_categories(body_y,body_h)
        self:draw_objects(body_y,body_h)
        self:draw_fields(body_y,body_h)
    elseif self.view=='mods'then self:draw_mods(body_y,body_h)
    else self:draw_presets(body_y,body_h)end
    self:draw_status(body_y+body_h,theme.status_h)
    self:draw_footer(L.h-theme.footer_h,theme.footer_h)
    cv:rect(0,0,3,L.h,C.rail,7)
    self:draw_confirm()
end

return M

-- HD2R Editor (c) 2026 SkyeShade. All rights reserved except as granted in LICENSE
-- (https://github.com/SkyeShade/HD2Runtime-Editor). Do not redistribute or reuse without the credit it requires.
-- The two value editors that open over the window: a searchable picker (choices, mission uses, projectile and
-- explosion donors) and a calldown code editor. Installed onto the app (ui/app.lua).
local theme=require('mods/skyeshade/hd2runtime_editor/editor/ui/theme')
local catalog_module=require('mods/skyeshade/hd2runtime_editor/editor/catalog')
local util=require('mods/skyeshade/hd2runtime_editor/editor/util')
local L=require('mods/skyeshade/hd2runtime_editor/editor/i18n').L
local C,SZ=theme.colour,theme.size
local M={}

local DIRECTIONS={UP='up',DOWN='down',LEFT='left',RIGHT='right'}

-- Native codes of every catalogued stratagem (for clash and prefix notes in the code editor).
local native_codes
local function natives()
    if native_codes then return native_codes end
    native_codes={}
    local ok,ST=pcall(require,'hd2runtime/domains/stratagem_authoring')
    if ok and type(ST)=='table'then
        for name,s in pairs(ST.stratagems or{})do
            for _,f in ipairs(s.fields or{})do
                if f.type=='calldown_code'and type(f.currentDefault)=='table'then
                    native_codes[#native_codes+1]={name=name,code=f.currentDefault}
                end
            end
        end
    end
    return native_codes
end
local function code_key(code)return table.concat(code,',')end

-- A popup's close button (top-right) and a plain text button; both register their click region.
local function close_button(self,cv,x,y,w,on_close)
    local action=self.popup_close or{}
    self.popup_close=action
    action.click=on_close
    local hovered=self.hover==action
    cv:rect(x+w-44,y+12,30,30,hovered and C.error_soft or C.panel_alt,10)
    cv:frame(x+w-44,y+12,30,30,hovered and C.error or C.line_strong,11)
    cv:text('×',x+w-29,y+27,{size=22,colour=hovered and C.error or C.dim,align='center',z=12})
    cv:hit(x+w-44,y+12,30,30,action)
end
local function text_button(self,cv,label,x,y,w,h,action,style)
    local hovered=self.hover==action
    local bg=style=='primary'and C.gold or(hovered and C.hover or C.panel)
    cv:rect(x,y,w,h,bg,10)
    if style~='primary'then cv:frame(x,y,w,h,C.line_strong,11)end
    cv:text(label,x+w/2,y+h/2,{size=SZ.tab,font='title',colour=style=='primary'and C.inverse or C.text,align='center',z=12})
    cv:hit(x,y,w,h,action)
end
M.close_button,M.text_button=close_button,text_button

function M.install(App)
    ------------------------------------------------------------------------------------------------ picker --
    -- The picker's items for a row: static choices, mission uses, or donors (each checked with the Runtime's own
    -- validator; refused donors are not offered).
    function App:picker_items(row)
        local items={}
        if row.kind=='uses'then
            if row.unlimited or row.vanilla=='unlimited'then
                items[#items+1]={value='unlimited',label='Unlimited',sub='type 0 or -1'}
            end
            for n=row.min or 1,row.max or 100 do items[#items+1]={value=n,label=tostring(n)}end
            return items
        end
        local options=row.options and row.options(row)or{}
        for _,o in ipairs(options)do
            if row.kind~='reference'or catalog_module.probe(row,o.value)then items[#items+1]=o end
        end
        return items
    end
    function App:open_picker(row,filter)
        local ok,items=pcall(self.picker_items,self,row)
        if not ok then self:toast(L('Could not list values: ')..tostring(items),C.error);return end
        if#items==0 then self:toast(L('No values are available for this field'),C.dim);return end
        local current=self:row_view(row)
        local index=1
        for i,item in ipairs(items)do if util.same(item.value,current)then index=i end end
        self.picker={row=row,items=items,index=index,filter=filter or'',scroll=0,current=current}
        self:picker_filter()
    end
    function App:picker_filter()
        local p=self.picker
        local q=p.filter:lower()
        p.shown={}
        local typed=p.row.kind=='uses'and tonumber(q)
        if typed and typed<=0 then
            -- mission uses: 0 or -1 means unlimited (where the stratagem can be unlimited)
            for i,item in ipairs(p.items)do if item.value=='unlimited'then p.shown[1]=i end end
            p.cursor=1
            return
        end
        for i,item in ipairs(p.items)do
            local hay=(item.label..' '..(item.sub or'')):lower()
            if q==''or hay:find(q,1,true)then p.shown[#p.shown+1]=i end
        end
        p.cursor=1
        for s,i in ipairs(p.shown)do if i==p.index then p.cursor=s end end
        -- a typed count selects that count itself (typing 5 picks 5, not the first of 5, 15, 25)
        if typed then
            for s,i in ipairs(p.shown)do if p.items[i].value==typed then p.cursor=s end end
        end
    end
    function App:picker_choose()
        local p=self.picker
        self.picker=nil
        local index=p and p.shown[p.cursor]
        if not index then return end
        self:stage(p.row,p.items[index].value)
    end
    function App:handle_picker_keys(f)
        local p,k=self.picker,f.keys
        for _,ch in ipairs(f.chars)do if#p.filter<32 then p.filter=p.filter..ch;self:picker_filter()end end
        if k.BACKSPACE and#p.filter>0 then p.filter=p.filter:sub(1,-2);self:picker_filter()end
        local n=#p.shown
        local function move(d)if n>0 then p.cursor=math.max(1,math.min(n,p.cursor+d))end end
        if k.UP then move(-1)end
        if k.DOWN then move(1)end
        if k.PAGEUP then move(-10)end
        if k.PAGEDOWN then move(10)end
        if k.HOME then p.cursor=1 end
        if k.END and n>0 then p.cursor=n end
        if k.ESCAPE or k.DELETE then self.picker=nil;return end
        if k.ENTER or k.TAB then self:picker_choose()end
    end
    function App:draw_picker()
        local p=self.picker
        if not p then return end
        local cv=self.canvas
        local P=theme.panel
        cv:rect(0,0,P.w,P.h,C.scrim,8)
        cv:hit(-10000,-10000,20000,20000,{click=function()self.picker=nil end})
        local w,h=680,600
        local x,y=(P.w-w)/2,(P.h-h)/2
        cv:rect(x,y,w,h,C.panel_alt,9)
        cv:frame(x,y,w,h,C.line_strong,10)
        cv:rect(x,y,w,3,C.gold,10)
        cv:hit(x,y,w,h,{})
        cv:text(string.upper(p.row.label),x+24,y+30,{size=18,font='title',colour=C.text,max=w-90,z=11})
        cv:text(p.row.object.name,x+24,y+54,{size=SZ.small,colour=C.faint,max=w-90,z=11})
        close_button(self,cv,x,y,w,function()self.picker=nil end)
        -- filter
        local fy=y+74
        cv:rect(x+20,fy,w-40,32,C.box,10)
        cv:frame(x+20,fy,w-40,32,C.box_focus,11)
        if p.filter==''then
            cv:text(L('Type to filter'),x+32,fy+16,{size=SZ.small,colour=C.faint,z=12})
        else
            local tw=cv:text(p.filter,x+32,fy+16,{size=SZ.label,colour=C.text,z=12,max=w-80})
            if math.floor(self.time*2)%2==0 then cv:rect(x+34+tw,fy+7,2,18,C.gold,12)end
        end
        -- list
        local ly,rh=fy+44,40
        local rows=math.floor((y+h-56-ly)/rh)
        local n=#p.shown
        -- the cursor pulls the view along only when it moves (the wheel scrolls freely in between)
        if p.seen_cursor~=p.cursor then
            p.seen_cursor=p.cursor
            if p.cursor<p.scroll+1 then p.scroll=p.cursor-1 end
            if p.cursor>p.scroll+rows then p.scroll=p.cursor-rows end
        end
        p.scroll=math.max(0,math.min(p.scroll,math.max(0,n-rows)))
        p.wheel=p.wheel or{passthrough=true}
        p.wheel.scroll=function(delta)p.scroll=math.max(0,math.min(p.scroll+delta*3,math.max(0,n-rows)))end
        cv:hit(x+12,ly,w-24,rows*rh,p.wheel)
        for s=p.scroll+1,math.min(n,p.scroll+rows)do
            local item=p.items[p.shown[s]]
            local ry=ly+(s-p.scroll-1)*rh
            local selected=s==p.cursor
            local action={click=function()p.cursor=s;self:picker_choose()end}
            if selected then cv:rect(x+12,ry+2,w-24,rh-4,C.select,10);cv:rect(x+12,ry+2,3,rh-4,C.gold,11)end
            cv:text(item.label,x+28,ry+(item.sub and 14 or rh/2),{size=SZ.label,colour=selected and C.text or C.dim,
                max=w-180,z=12})
            if item.sub then cv:text(item.sub,x+28,ry+30,{size=SZ.tiny,colour=C.faint,max=w-180,z=12})end
            if util.same(item.value,p.current)then
                self.chip_fn(cv,L('CURRENT'),x+w-28,ry+rh/2,C.gold,C.gold_wash,'right',10)
            elseif util.same(item.value,p.row.vanilla)then
                self.chip_fn(cv,L('DEFAULT'),x+w-28,ry+rh/2,C.faint,C.line,'right',10)
            end
            cv:hit(x+12,ry,w-24,rh,action)
        end
        if n==0 then cv:text(L('No match'),x+28,ly+20,{size=SZ.small,colour=C.faint,z=12})end
        if n>rows then
            local th=math.max(24,(rows*rh)*rows/n)
            local t=p.scroll/math.max(1,n-rows)
            cv:rect(x+w-10,ly,3,rows*rh,C.line,11)
            cv:rect(x+w-10,ly+(rows*rh-th)*t,3,th,C.gold,12)
        end
        cv:text(L('↑↓ choose   Enter / Tab select   Type to filter   Esc / Del close   ')..n..' of '..#p.items,
            x+24,y+h-26,{size=SZ.tiny,colour=C.faint,max=w-48,z=11})
    end

    ------------------------------------------------------------------------------------------- code editor --
    function App:open_code(row)
        local current=self:row_view(row)
        self.coder={row=row,code=util.copy(type(current)=='table'and current or{})}
    end
    function App:code_notes(code)
        local key=code_key(code)
        local notes={}
        for _,n in ipairs(natives())do
            local other=code_key(n.code)
            if n.name~=self.coder.row.object.name then
                if other==key then notes[#notes+1]={'Same code as '..n.name..' (written with the unverified acknowledgement)',C.pending}
                elseif #key>0 and(other:sub(1,#key+1)==key..','or key:sub(1,#other+1)==other..',')then
                    if#notes<3 then notes[#notes+1]={'Overlaps '..n.name..' ('..util.code_text(n.code)..')',C.faint}end
                end
            end
        end
        return notes
    end
    function App:code_save()
        local c=self.coder
        self.coder=nil
        if not c then return end
        if#c.code<(c.row.min_length or 1)then self:toast(L('A code needs at least ')..(c.row.min_length or 1)..' direction',C.error);return end
        self:stage(c.row,c.code)
    end
    function App:handle_code_keys(f)
        local c,k=self.coder,f.keys
        for name,d in pairs(DIRECTIONS)do
            if k[name]and#c.code<(c.row.max_length or 9)then c.code[#c.code+1]=d end
        end
        if k.BACKSPACE then c.code[#c.code]=nil end
        if k.DELETE then c.code={}end
        if k.ESCAPE then self.coder=nil;return end
        if k.ENTER or k.TAB then self:code_save()end
    end
    function App:draw_code()
        local c=self.coder
        if not c then return end
        local cv=self.canvas
        local P=theme.panel
        cv:rect(0,0,P.w,P.h,C.scrim,8)
        cv:hit(-10000,-10000,20000,20000,{click=function()self.coder=nil end})
        local w,h=640,330
        local x,y=(P.w-w)/2,(P.h-h)/2-30
        cv:rect(x,y,w,h,C.panel_alt,9)
        cv:frame(x,y,w,h,C.line_strong,10)
        cv:rect(x,y,w,3,C.gold,10)
        cv:hit(x,y,w,h,{})
        cv:text(L('CALLDOWN CODE'),x+24,y+30,{size=18,font='title',colour=C.text,z=11})
        cv:text(c.row.object.name,x+24,y+54,{size=SZ.small,colour=C.faint,max=w-120,z=11})
        close_button(self,cv,x,y,w,function()self.coder=nil end)
        -- the code as arrow tiles
        local max=c.row.max_length or 9
        local tile,gap=52,8
        local total=max*tile+(max-1)*gap
        local tx=x+(w-total)/2
        local ty=y+80
        self.code_tiles=self.code_tiles or{}
        for i=1,max do
            local d=c.code[i]
            local bx=tx+(i-1)*(tile+gap)
            local action=self.code_tiles[i]or{}
            self.code_tiles[i]=action
            local index=i
            -- right click removes this arrow
            action.rclick=function()if c.code[index]then table.remove(c.code,index)end end
            local hovered=d and self.hover==action
            cv:rect(bx,ty,tile,tile,hovered and C.error_soft or(d and C.gold_wash or C.box),10)
            cv:frame(bx,ty,tile,tile,hovered and C.error or(d and C.gold_dim or C.line),11)
            if d then cv:text(util.ARROWS[d],bx+tile/2,ty+tile/2,{size=30,font='title',colour=C.gold,align='center',z=12})end
            cv:hit(bx,ty,tile,tile,action)
        end
        cv:text(#c.code..' / '..max,x+w-60,y+54,{size=SZ.small,colour=C.faint,align='right',z=11})
        -- arrow buttons for the mouse
        local bw=48
        local bx=x+24
        local by=ty+tile+22
        for i,d in ipairs({'up','down','left','right'})do
            local action={click=function()if#c.code<max then c.code[#c.code+1]=d end end}
            cv:rect(bx+(i-1)*(bw+8),by,bw,36,self.hover==action and C.hover or C.panel,10)
            cv:frame(bx+(i-1)*(bw+8),by,bw,36,C.line_strong,11)
            cv:text(util.ARROWS[d],bx+(i-1)*(bw+8)+bw/2,by+18,{size=20,colour=C.text,align='center',z=12})
            cv:hit(bx+(i-1)*(bw+8),by,bw,36,action)
        end
        self.code_undo=self.code_undo or{}
        self.code_undo.click=function()c.code[#c.code]=nil end
        text_button(self,cv,L('UNDO'),bx+4*(bw+8),by,84,36,self.code_undo)
        self.code_reset=self.code_reset or{}
        self.code_reset.click=function()c.code=util.copy(c.row.vanilla)end
        text_button(self,cv,L('DEFAULT'),bx+4*(bw+8)+92,by,100,36,self.code_reset)
        self.code_save_btn=self.code_save_btn or{}
        self.code_save_btn.click=function()self:code_save()end
        text_button(self,cv,L('SAVE'),x+w-24-110,by,110,36,self.code_save_btn,'primary')
        -- notes
        local ny=by+56
        for i,note in ipairs(self:code_notes(c.code))do
            cv:text(note[1],x+24,ny+(i-1)*20,{size=SZ.small,colour=note[2],max=w-48,z=11})
        end
        cv:text(L('Arrow keys add   Right-click an arrow to remove it   Backspace undo   Del clear   Enter save'),x+24,y+h-22,
            {size=SZ.tiny,colour=C.faint,max=w-48,z=11})
    end

    ------------------------------------------------------------------------------------------- fire modes --
    function App:open_modes(row)
        local current=self:row_view(row)
        self.moder={row=row,list=util.copy(type(current)=='table'and current or{}),cursor=1}
    end
    local function has(list,m)for i,v in ipairs(list)do if v==m then return i end end end
    function App:mode_toggle(m)
        local e=self.moder
        local at=has(e.list,m)
        if at then
            if#e.list>1 then table.remove(e.list,at)else self:toast(L('A weapon keeps at least one fire mode'),C.dim)end
        elseif#e.list<(e.row.max_modes or 4)then e.list[#e.list+1]=m
        else self:toast(L('At most ')..(e.row.max_modes or 4)..' fire modes',C.dim)end
    end
    function App:modes_save()
        local e=self.moder
        self.moder=nil
        if e then self:stage(e.row,e.list)end
    end
    function App:handle_modes_keys(f)
        local e,k=self.moder,f.keys
        local n=#e.row.modes
        if k.UP then e.cursor=math.max(1,e.cursor-1)end
        if k.DOWN then e.cursor=math.min(n,e.cursor+1)end
        if k.LEFT or k.RIGHT then self:mode_toggle(e.row.modes[e.cursor])end
        if k.DELETE then e.list=util.copy(e.row.vanilla)end
        if k.ESCAPE then self.moder=nil;return end
        if k.ENTER or k.TAB then self:modes_save()end
    end
    function App:draw_modes()
        local e=self.moder
        if not e then return end
        local cv=self.canvas
        local P=theme.panel
        cv:rect(0,0,P.w,P.h,C.scrim,8)
        cv:hit(-10000,-10000,20000,20000,{click=function()self.moder=nil end})
        local n=#e.row.modes
        local w,h=560,190+n*44
        local x,y=(P.w-w)/2,(P.h-h)/2-30
        cv:rect(x,y,w,h,C.panel_alt,9);cv:frame(x,y,w,h,C.line_strong,10);cv:rect(x,y,w,3,C.gold,10)
        cv:hit(x,y,w,h,{})
        cv:text(L('FIRE MODES'),x+24,y+30,{size=18,font='title',colour=C.text,z=11})
        cv:text(e.row.object.name..'   '..#e.list..' of at most '..(e.row.max_modes or 4),x+24,y+54,
            {size=SZ.small,colour=C.faint,max=w-90,z=11})
        close_button(self,cv,x,y,w,function()self.moder=nil end)
        self.mode_rows=self.mode_rows or{}
        for i,m in ipairs(e.row.modes)do
            local ry=y+76+(i-1)*44
            local at=has(e.list,m)
            local action=self.mode_rows[i]or{}
            self.mode_rows[i]=action
            local index=i
            action.click=function()e.cursor=index;self:mode_toggle(m)end
            local selected=i==e.cursor
            if selected then cv:rect(x+12,ry,w-24,40,C.select,10);cv:rect(x+12,ry,3,40,C.gold,11)
            elseif self.hover==action then cv:rect(x+12,ry,w-24,40,C.hover,10)end
            cv:rect(x+28,ry+11,18,18,at and C.gold or C.box,11)
            cv:frame(x+28,ry+11,18,18,at and C.gold or C.line_strong,11)
            if at then cv:text(tostring(at),x+37,ry+20,{size=SZ.tiny,font='title',colour=C.inverse,align='center',z=12})end
            cv:text(util.humanize(m),x+60,ry+20,{size=SZ.label,colour=at and C.text or C.dim,z=12})
            if has(e.row.vanilla,m)then cv:text(L('default'),x+w-28,ry+20,{size=SZ.tiny,colour=C.faint,align='right',z=12})end
            cv:hit(x+12,ry,w-24,40,action)
        end
        local by=y+h-56
        self.modes_reset=self.modes_reset or{}
        self.modes_reset.click=function()e.list=util.copy(e.row.vanilla)end
        text_button(self,cv,L('DEFAULT'),x+24,by,110,36,self.modes_reset)
        self.modes_save_btn=self.modes_save_btn or{}
        self.modes_save_btn.click=function()self:modes_save()end
        text_button(self,cv,L('SAVE'),x+w-24-110,by,110,36,self.modes_save_btn,'primary')
        cv:text(L('↑↓ choose   ←→ toggle   numbers = selector order'),x+150,by+18,{size=SZ.tiny,colour=C.faint,max=w-300,z=11})
    end

    ------------------------------------------------------------------------------------- armory traits --
    -- The displayed traits of a weapon: up to five labels in the order the armory lists them (presentation only).
    function App:open_traits(row)
        local current=self:row_view(row)
        self.traiter={row=row,list=util.copy(type(current)=='table'and current or{}),cursor=1}
    end
    function App:trait_toggle(id)
        local e=self.traiter
        local at=has(e.list,id)
        if at then table.remove(e.list,at)
        elseif#e.list<(e.row.max_traits or 5)then e.list[#e.list+1]=id
        else self:toast(L('At most %d traits'):format(e.row.max_traits or 5),C.dim)end
    end
    function App:traits_save()
        local e=self.traiter
        self.traiter=nil
        if e then self:stage(e.row,e.list)end
    end
    local TRAIT_COLUMNS=2
    function App:handle_traits_keys(f)
        local e,k=self.traiter,f.keys
        local n=#e.row.traits
        local rows=math.ceil(n/TRAIT_COLUMNS)
        if k.UP then e.cursor=math.max(1,e.cursor-1)end
        if k.DOWN then e.cursor=math.min(n,e.cursor+1)end
        if k.LEFT and e.cursor>rows then e.cursor=e.cursor-rows end
        if k.RIGHT and e.cursor+rows<=n then e.cursor=e.cursor+rows end
        if k.SPACE or k.INSERT then self:trait_toggle(e.row.traits[e.cursor].value)end
        if k.BACKSPACE and#e.list>0 then table.remove(e.list)end
        if k.ESCAPE then self.traiter=nil;return end
        if k.ENTER then
            -- Enter toggles the focused trait; Tab saves
            self:trait_toggle(e.row.traits[e.cursor].value)
        end
        if k.TAB then self:traits_save()end
    end
    function App:draw_traits()
        local e=self.traiter
        if not e then return end
        local cv=self.canvas
        local P=theme.panel
        cv:rect(0,0,P.w,P.h,C.scrim,8)
        cv:hit(-10000,-10000,20000,20000,{click=function()self.traiter=nil end})
        local traits=e.row.traits
        local rows=math.ceil(#traits/TRAIT_COLUMNS)
        local w,h=760,214+rows*36
        local x,y=(P.w-w)/2,math.max(10,(P.h-h)/2-30)
        cv:rect(x,y,w,h,C.panel_alt,9);cv:frame(x,y,w,h,C.line_strong,10);cv:rect(x,y,w,3,C.gold,10)
        cv:hit(x,y,w,h,{})
        cv:text(L('DISPLAYED TRAITS'),x+24,y+30,{size=18,font='title',colour=C.text,z=11})
        cv:text(e.row.object.name..'   '..L('%d of at most %d, in this order: %s'):format(#e.list,e.row.max_traits or 5,
            catalog_module.text(e.row,e.list)),x+24,y+54,{size=SZ.small,colour=C.faint,max=w-90,z=11})
        close_button(self,cv,x,y,w,function()self.traiter=nil end)
        self.trait_rows=self.trait_rows or{}
        local cw=(w-36)/TRAIT_COLUMNS
        for i,t in ipairs(traits)do
            local col,line=math.floor((i-1)/rows),(i-1)%rows
            local rx,ry=x+12+col*cw,y+76+line*36
            local at=has(e.list,t.value)
            local action=self.trait_rows[i]or{}
            self.trait_rows[i]=action
            local index,id=i,t.value
            action.click=function()e.cursor=index;self:trait_toggle(id)end
            if i==e.cursor then cv:rect(rx,ry,cw-6,32,C.select,10);cv:rect(rx,ry,3,32,C.gold,11)
            elseif self.hover==action then cv:rect(rx,ry,cw-6,32,C.hover,10)end
            cv:rect(rx+14,ry+7,18,18,at and C.gold or C.box,11)
            cv:frame(rx+14,ry+7,18,18,at and C.gold or C.line_strong,11)
            if at then cv:text(tostring(at),rx+23,ry+16,{size=SZ.tiny,font='title',colour=C.inverse,align='center',z=12})end
            cv:text(L(t.label),rx+44,ry+16,{size=SZ.label,colour=at and C.text or C.dim,max=cw-110,z=12})
            if has(e.row.vanilla,t.value)then cv:text(L('default'),rx+cw-18,ry+16,{size=SZ.tiny,colour=C.faint,align='right',z=12})end
            cv:hit(rx,ry,cw-6,32,action)
        end
        local by=y+h-56
        self.traits_reset=self.traits_reset or{}
        self.traits_reset.click=function()e.list=util.copy(e.row.vanilla)end
        text_button(self,cv,L('DEFAULT'),x+24,by,110,36,self.traits_reset)
        self.traits_clear=self.traits_clear or{}
        self.traits_clear.click=function()e.list={}end
        text_button(self,cv,L('NONE'),x+142,by,90,36,self.traits_clear)
        self.traits_save_btn=self.traits_save_btn or{}
        self.traits_save_btn.click=function()self:traits_save()end
        text_button(self,cv,L('SAVE'),x+w-24-110,by,110,36,self.traits_save_btn,'primary')
        cv:text(L('Enter / click toggle   numbers = order   Backspace remove last   Tab save'),x+246,by+18,
            {size=SZ.tiny,colour=C.faint,max=w-390,z=11})
    end

    --------------------------------------------------------------------------------------- rate-of-fire modes --
    function App:open_rates(row)
        local current=self:row_view(row)
        self.rater={row=row,slots=util.copy(type(current)=='table'and current or{0,0,0}),cursor=1}
        for i=1,3 do if(self.rater.slots[i]or 0)>0 then self.rater.cursor=i;break end end
    end
    function App:rates_commit()
        local e=self.rater
        if not e or not e.buffer then return true end
        local v=tonumber(e.buffer)
        e.buffer=nil
        if v==nil then return true end
        v=math.floor(v+0.5)
        if v~=0 and(v<(e.row.min or 1)or v>(e.row.max or 3000))then
            self:toast(L('A rate is 0 (unused) or ')..(e.row.min or 1)..' to '..(e.row.max or 3000)..' rpm',C.error)
            return false
        end
        e.slots[e.cursor]=v
        return true
    end
    function App:rates_save()
        if not self:rates_commit()then return end
        local e=self.rater
        self.rater=nil
        if e then self:stage(e.row,e.slots)end
    end
    function App:handle_rates_keys(f)
        local e,k=self.rater,f.keys
        for _,ch in ipairs(f.chars)do
            if ch:match('%d')then e.buffer=(e.buffer or'')..ch;if#e.buffer>5 then e.buffer=e.buffer:sub(1,5)end end
        end
        if k.BACKSPACE then e.buffer=(e.buffer or tostring(e.slots[e.cursor])):sub(1,-2)end
        if k.DELETE then e.buffer=nil;e.slots[e.cursor]=0 end
        if k.UP or k.DOWN then
            if self:rates_commit()then e.cursor=math.max(1,math.min(3,e.cursor+(k.UP and-1 or 1)))end
        end
        if k.ESCAPE then self.rater=nil;return end
        if k.ENTER or k.TAB then self:rates_save()end
    end
    function App:draw_rates()
        local e=self.rater
        if not e then return end
        local cv=self.canvas
        local P=theme.panel
        cv:rect(0,0,P.w,P.h,C.scrim,8)
        cv:hit(-10000,-10000,20000,20000,{click=function()self.rater=nil end})
        local w,h=560,330
        local x,y=(P.w-w)/2,(P.h-h)/2-30
        cv:rect(x,y,w,h,C.panel_alt,9);cv:frame(x,y,w,h,C.line_strong,10);cv:rect(x,y,w,3,C.gold,10)
        cv:hit(x,y,w,h,{})
        cv:text(L('RATE-OF-FIRE MODES'),x+24,y+30,{size=18,font='title',colour=C.text,z=11})
        cv:text(e.row.object.name..'   0 = unused slot',x+24,y+54,{size=SZ.small,colour=C.faint,max=w-90,z=11})
        close_button(self,cv,x,y,w,function()self.rater=nil end)
        self.rate_rows=self.rate_rows or{}
        for i=1,3 do
            local ry=y+76+(i-1)*48
            local action=self.rate_rows[i]or{}
            self.rate_rows[i]=action
            local index=i
            action.click=function()if self:rates_commit()then e.cursor=index end end
            local selected=i==e.cursor
            if selected then cv:rect(x+12,ry,w-24,44,C.select,10);cv:rect(x+12,ry,3,44,C.gold,11)
            elseif self.hover==action then cv:rect(x+12,ry,w-24,44,C.hover,10)end
            local slot=e.row.slots and e.row.slots[i]or tostring(i)
            cv:text(L('Slot ')..string.upper(slot),x+28,ry+22,{size=SZ.label,colour=C.dim,z=12})
            local text=(selected and e.buffer)or(e.slots[i]==0 and'unused'or util.format(e.slots[i]))
            cv:rect(x+w-200,ry+8,150,28,C.box,11)
            cv:frame(x+w-200,ry+8,150,28,selected and C.box_focus or C.box_edge,11)
            cv:text(text,x+w-60,ry+22,{size=SZ.label,colour=e.slots[i]==0 and not(selected and e.buffer)and C.faint or C.text,
                align='right',z=12})
            cv:text(L('rpm'),x+w-40,ry+22,{size=SZ.tiny,colour=C.faint,z=12})
            cv:hit(x+12,ry,w-24,44,action)
        end
        local by=y+h-56
        self.rates_reset=self.rates_reset or{}
        self.rates_reset.click=function()e.slots=util.copy(e.row.vanilla);e.buffer=nil end
        text_button(self,cv,L('DEFAULT'),x+24,by,110,36,self.rates_reset)
        self.rates_save_btn=self.rates_save_btn or{}
        self.rates_save_btn.click=function()self:rates_save()end
        text_button(self,cv,L('SAVE'),x+w-24-110,by,110,36,self.rates_save_btn,'primary')
        cv:text(L('↑↓ slot   digits type   Del unused'),x+150,by+18,{size=SZ.tiny,colour=C.faint,max=w-300,z=11})
    end
end

return M

-- The two value editors that open over the window: a searchable picker (choices, mission uses, projectile and
-- explosion donors) and a calldown code editor. Installed onto the app (ui/app.lua).
local theme=require('mods/skyeshade/hd2runtime_editor/editor/ui/theme')
local catalog_module=require('mods/skyeshade/hd2runtime_editor/editor/catalog')
local util=require('mods/skyeshade/hd2runtime_editor/editor/util')
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

function M.install(App)
    ------------------------------------------------------------------------------------------------ picker --
    -- The picker's items for a row: static choices, mission uses, or donors (each checked with the Runtime's own
    -- validator; refused donors are not offered).
    function App:picker_items(row)
        local items={}
        if row.kind=='uses'then
            if row.unlimited or row.vanilla=='unlimited'then items[#items+1]={value='unlimited',label='Unlimited'}end
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
        if not ok then self:toast('Could not list values: '..tostring(items),C.error);return end
        if#items==0 then self:toast('No values are available for this field',C.dim);return end
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
        for i,item in ipairs(p.items)do
            local hay=(item.label..' '..(item.sub or'')):lower()
            if q==''or hay:find(q,1,true)then p.shown[#p.shown+1]=i end
        end
        p.cursor=1
        for s,i in ipairs(p.shown)do if i==p.index then p.cursor=s end end
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
        local L=theme.panel
        cv:rect(0,0,L.w,L.h,C.scrim,8)
        cv:hit(-10000,-10000,20000,20000,{click=function()self.picker=nil end})
        local w,h=680,600
        local x,y=(L.w-w)/2,(L.h-h)/2
        cv:rect(x,y,w,h,C.panel_alt,9)
        cv:frame(x,y,w,h,C.line_strong,10)
        cv:rect(x,y,w,3,C.gold,10)
        cv:hit(x,y,w,h,{})
        cv:text(string.upper(p.row.label),x+24,y+30,{size=18,font='title',colour=C.text,max=w-48,z=11})
        cv:text(p.row.object.name,x+24,y+54,{size=SZ.small,colour=C.faint,max=w-48,z=11})
        -- filter
        local fy=y+74
        cv:rect(x+20,fy,w-40,32,C.box,10)
        cv:frame(x+20,fy,w-40,32,C.box_focus,11)
        if p.filter==''then
            cv:text('Type to filter',x+32,fy+16,{size=SZ.small,colour=C.faint,z=12})
        else
            local tw=cv:text(p.filter,x+32,fy+16,{size=SZ.label,colour=C.text,z=12,max=w-80})
            if math.floor(self.time*2)%2==0 then cv:rect(x+34+tw,fy+7,2,18,C.gold,12)end
        end
        -- list
        local ly,rh=fy+44,40
        local rows=math.floor((y+h-56-ly)/rh)
        local n=#p.shown
        if p.cursor<p.scroll+1 then p.scroll=p.cursor-1 end
        if p.cursor>p.scroll+rows then p.scroll=p.cursor-rows end
        p.scroll=math.max(0,math.min(p.scroll,math.max(0,n-rows)))
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
                self.chip_fn(cv,'CURRENT',x+w-28,ry+rh/2,C.gold,C.gold_wash,'right',10)
            elseif util.same(item.value,p.row.vanilla)then
                self.chip_fn(cv,'DEFAULT',x+w-28,ry+rh/2,C.faint,C.line,'right',10)
            end
            cv:hit(x+12,ry,w-24,rh,action)
        end
        if n==0 then cv:text('No match',x+28,ly+20,{size=SZ.small,colour=C.faint,z=12})end
        if n>rows then
            local th=math.max(24,(rows*rh)*rows/n)
            local t=p.scroll/math.max(1,n-rows)
            cv:rect(x+w-10,ly,3,rows*rh,C.line,11)
            cv:rect(x+w-10,ly+(rows*rh-th)*t,3,th,C.gold,12)
        end
        cv:text('↑↓ choose   Enter / Tab select   Type to filter   Esc / Del close   '..n..' of '..#p.items,
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
        if#c.code<(c.row.min_length or 1)then self:toast('A code needs at least '..(c.row.min_length or 1)..' direction',C.error);return end
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
        local L=theme.panel
        cv:rect(0,0,L.w,L.h,C.scrim,8)
        cv:hit(-10000,-10000,20000,20000,{click=function()self.coder=nil end})
        local w,h=640,330
        local x,y=(L.w-w)/2,(L.h-h)/2-30
        cv:rect(x,y,w,h,C.panel_alt,9)
        cv:frame(x,y,w,h,C.line_strong,10)
        cv:rect(x,y,w,3,C.gold,10)
        cv:hit(x,y,w,h,{})
        cv:text('CALLDOWN CODE',x+24,y+30,{size=18,font='title',colour=C.text,z=11})
        cv:text(c.row.object.name,x+24,y+54,{size=SZ.small,colour=C.faint,max=w-48,z=11})
        -- the code as arrow tiles
        local max=c.row.max_length or 9
        local tile,gap=52,8
        local total=max*tile+(max-1)*gap
        local tx=x+(w-total)/2
        local ty=y+80
        for i=1,max do
            local d=c.code[i]
            local bx=tx+(i-1)*(tile+gap)
            cv:rect(bx,ty,tile,tile,d and C.gold_wash or C.box,10)
            cv:frame(bx,ty,tile,tile,d and C.gold_dim or C.line,11)
            if d then cv:text(util.ARROWS[d],bx+tile/2,ty+tile/2,{size=30,font='title',colour=C.gold,align='center',z=12})end
        end
        cv:text(#c.code..' / '..max,x+w-24,y+54,{size=SZ.small,colour=C.faint,align='right',z=11})
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
        local undo={click=function()c.code[#c.code]=nil end}
        cv:rect(bx+4*(bw+8),by,90,36,C.panel,10);cv:frame(bx+4*(bw+8),by,90,36,C.line_strong,11)
        cv:text('UNDO',bx+4*(bw+8)+45,by+18,{size=SZ.tab,font='title',colour=C.text,align='center',z=12})
        cv:hit(bx+4*(bw+8),by,90,36,undo)
        local save={click=function()self:code_save()end}
        cv:rect(x+w-24-120,by,120,36,C.gold,10)
        cv:text('SAVE',x+w-24-60,by+18,{size=SZ.tab,font='title',colour=C.inverse,align='center',z=12})
        cv:hit(x+w-24-120,by,120,36,save)
        -- notes
        local ny=by+56
        for i,note in ipairs(self:code_notes(c.code))do
            cv:text(note[1],x+24,ny+(i-1)*20,{size=SZ.small,colour=note[2],max=w-48,z=11})
        end
        cv:text('Arrow keys add   Backspace undo   Del clear   Enter / Tab save   Esc cancel',x+24,y+h-22,
            {size=SZ.tiny,colour=C.faint,max=w-48,z=11})
    end
end

return M

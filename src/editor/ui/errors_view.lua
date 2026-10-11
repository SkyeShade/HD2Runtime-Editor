-- HD2R Editor (c) 2026 SkyeShade. All rights reserved except as granted in LICENSE
-- (https://github.com/SkyeShade/HD2Runtime-Editor). Do not redistribute or reuse without the credit it requires.
-- The errors list: every field whose value was refused or failed (the header's ERRORS badge, or Ctrl+E), with the
-- object, the field, the value asked for, the Runtime's code and reason, and where the value came from (your edit, a
-- preset, the saved session, or a mod's value the editor took over). Enter or a click opens the field in BROWSE (its
-- group and section opened, the row selected); Ins writes the list to HD2Runtime.log and shows it in LOGS.
local theme=require('mods/skyeshade/hd2runtime_editor/editor/ui/theme')
local util=require('mods/skyeshade/hd2runtime_editor/editor/util')
local i18n=require('mods/skyeshade/hd2runtime_editor/editor/i18n')
local C,SZ=theme.colour,theme.size
local L=i18n.L
local Lf=i18n.Lf
local M={}

-- The code a reason starts with or names (STATUS_SLOT_GAP, CONFLICT, REARM_POOL_UNLIMITED ...), when the Runtime gave
-- none: an upper-case word with an underscore, or one of the Runtime's one-word codes.
local ONE_WORD={CONFLICT=true,REJECTED=true,BLOCKED=true,UNAVAILABLE=true,CANCELLED=true}
function M.code(entry)
    if entry.code then return entry.code end
    for word in tostring(entry.reason or''):gmatch('[%u][%u%d_]+')do
        if#word>=4 and(word:find('_',1,true)or ONE_WORD[word])then return word end
    end
    return nil
end

function M.install(App)
    local chip=App.chip_fn
    local wrap=function(cv,text,w,size,lines)return App.wrap(cv,text,w,size,lines)end

    -- Where a failed value came from, as shown.
    function App:origin_text(origin)
        local kind=type(origin)=='table'and origin.kind or'edit'
        if kind=='preset'then return Lf('Preset: %s',tostring(origin.name or'?'))end
        if kind=='session'then return L('Saved session')end
        if kind=='mod'then return Lf('Mod: %s (taken over)',self.pretty_mod(origin.name or'unknown'))end
        if kind=='reset'then return L('Your reset (the value is still in the game)')end
        return L('Your edit')
    end
    -- Every failed field, by object and field (cached per layer state).
    function App:error_list()
        local key=self.layer.version
        if self.errors_key==key and self.errors_cache then return self.errors_cache end
        local list=self.layer:errors()
        for _,e in ipairs(list)do
            e.object_name=e.row.object and util.display_name(e.row.object)or'?'
            e.code=M.code(e)
            -- (the reason without the code it starts with: the code is shown on its own)
            local reason=tostring(e.reason)
            if e.code and reason:sub(1,#e.code+2)==e.code..': 'then reason=reason:sub(#e.code+3)end
            e.text=reason
            e.sort=(e.row.object and e.row.object.name or'')..'\0'..tostring(e.row.label)..'\0'..tostring(e.row.key)
        end
        table.sort(list,function(a,b)return util.natural_less(a.sort,b.sort)end)
        self.errors_key,self.errors_cache=key,list
        return list
    end
    function App:open_errors()
        self.errors_popup={index=1,scroll=0}
        self:sound('open')
    end
    function App:close_errors()
        self.errors_popup=nil
        self:sound('back')
    end
    -- Opens a failed field in BROWSE (the popup closes).
    function App:goto_error(entry)
        if not entry then return end
        self.errors_popup=nil
        self:sound('open')
        if not self:reveal(entry.row)then
            self:toast(Lf('%s is not shown on its page now',L(entry.row.label)),C.dim)
        end
    end
    -- One line of the log per failed field, then the LOGS tab on its Errors filter.
    function App:errors_to_log()
        local list=self:error_list()
        local log=self.ctx.log
        if not log then self:toast(L('The log is not available'),C.error);return end
        log(Lf('%d fields failed:',#list))
        for _,e in ipairs(list)do
            log('error: '..e.object_name..' · '..tostring(e.row.label)..' = '..self:text(e.row,e.value)
                ..(e.code and(' ['..e.code..']')or'')..': '..tostring(e.reason)..' ('..self:origin_text(e.origin)..'; '
                ..tostring(e.row.key)..')')
        end
        self.errors_popup=nil
        self:set_view('logs')
        self.log_filter,self.log_follow,self.log_key='error',true,nil
    end
    function App:handle_errors_keys(f)
        local p,k=self.errors_popup,f.keys
        local list=self:error_list()
        local n=#list
        local function move(d)if n>0 then p.index=math.max(1,math.min(n,p.index+d))end end
        if k.UP then move(-1)end
        if k.DOWN then move(1)end
        if k.PAGEUP then move(-8)end
        if k.PAGEDOWN then move(8)end
        if k.HOME then p.index=1 end
        if k.END and n>0 then p.index=n end
        if k.ESCAPE or k.DELETE or k.BACKSPACE then self:close_errors();return end
        if k.INSERT then self:errors_to_log();return end
        if k.ENTER then self:goto_error(list[p.index])end
    end

    local function modal_button(self,cv,label,x,y,w,h,action,style)
        local hovered=self.hover==action
        local danger=style=='danger'
        cv:rect(x,y,w,h,hovered and(danger and C.error_soft or C.hover)or C.panel,10)
        cv:frame(x,y,w,h,danger and C.error or C.line_strong,11)
        cv:text(label,x+w/2,y+h/2,{size=SZ.tab,font='title',colour=danger and C.error or C.text,align='center',z=12})
        cv:hit(x,y,w,h,action)
    end
    function App:draw_errors()
        local p=self.errors_popup
        if not p then return end
        local cv=self.canvas
        local P=theme.panel
        local list=self:error_list()
        local n=#list
        p.index=math.max(1,math.min(p.index,math.max(1,n)))
        cv:rect(0,0,P.w,P.h,C.scrim,8)
        self.errors_outside=self.errors_outside or{click=function()self:close_errors()end}
        cv:hit(-10000,-10000,20000,20000,self.errors_outside)
        local w=math.min(1120,P.w-60)
        local h=math.min(640,P.h-80)
        local x,y=math.floor((P.w-w)/2),math.floor((P.h-h)/2)
        cv:rect(x,y,w,h,C.panel_alt,9)
        cv:frame(x,y,w,h,C.line_strong,10)
        cv:rect(x,y,w,3,C.error,10)
        cv:hit(x,y,w,h,{})
        local tw=cv:text(L('ERRORS'),x+24,y+30,{size=18,font='title',colour=C.error,z=11})
        cv:text(n==1 and L('1 field was refused or failed')or Lf('%d fields were refused or failed',n),x+36+tw,y+31,
            {size=SZ.small,colour=C.faint,max=w-300,z=11})
        -- the close button
        self.errors_close=self.errors_close or{click=function()self:close_errors()end}
        local hovered=self.hover==self.errors_close
        cv:rect(x+w-44,y+12,30,30,hovered and C.error_soft or C.panel_alt,10)
        cv:frame(x+w-44,y+12,30,30,hovered and C.error or C.line_strong,11)
        cv:text('×',x+w-29,y+27,{size=22,colour=hovered and C.error or C.dim,align='center',z=12})
        cv:hit(x+w-44,y+12,30,30,self.errors_close)
        -- column titles
        local hy=y+52
        cv:rect(x+1,hy,w-2,22,C.header,10)
        local col_value,col_source=x+w-250,x+w-24
        cv:text(L('OBJECT · FIELD'),x+24,hy+11,{size=SZ.tiny,font='title',colour=C.faint,z=11})
        cv:text(L('VALUE'),col_value,hy+11,{size=SZ.tiny,font='title',colour=C.faint,align='right',z=11})
        cv:text(L('SOURCE'),col_source,hy+11,{size=SZ.tiny,font='title',colour=C.faint,align='right',z=11})
        -- the list: two lines a field (what failed, then the Runtime's code and reason)
        local ly,rh=hy+26,50
        local detail_h=78
        local rows=math.max(1,math.floor((y+h-ly-detail_h-60)/rh))
        if p.seen~=p.index then
            p.seen=p.index
            if p.index<p.scroll+1 then p.scroll=p.index-1 end
            if p.index>p.scroll+rows then p.scroll=p.index-rows end
        end
        p.scroll=math.max(0,math.min(p.scroll,math.max(0,n-rows)))
        p.wheel=p.wheel or{passthrough=true}
        p.wheel.scroll=function(delta)p.scroll=math.max(0,math.min(p.scroll+delta*3,math.max(0,n-rows)))end
        cv:hit(x+12,ly,w-24,rows*rh,p.wheel)
        p.actions=p.actions or{}
        for s=p.scroll+1,math.min(n,p.scroll+rows)do
            local e=list[s]
            local ry=ly+(s-p.scroll-1)*rh
            local action=p.actions[s]
            if not action then
                local index=s
                action={click=function()p.index=index;self:goto_error(self:error_list()[index])end}
                p.actions[s]=action
            end
            local selected=s==p.index
            if selected then cv:rect(x+12,ry+2,w-24,rh-4,C.error_soft,10);cv:rect(x+12,ry+2,3,rh-4,C.error,11)
            elseif self.hover==action then cv:rect(x+12,ry+2,w-24,rh-4,C.hover,10)end
            local lx=x+24
            if e.row.object and self:draw_icon(e.row.object,x+22,ry+7,rh-14,12)then lx=x+28+rh-14 end
            local nw=cv:text(e.object_name,lx,ry+16,{size=SZ.small,colour=C.dim,max=math.floor((col_value-160-lx)*0.45),z=12})
            cv:text(L(e.row.label),lx+nw+12,ry+16,{size=SZ.label,colour=selected and C.text or C.dim,
                max=col_value-160-lx-nw-12,z=12})
            cv:text(self:text(e.row,e.value),col_value,ry+16,{size=SZ.label,colour=C.error,align='right',max=150,z=12})
            cv:text(self:origin_text(e.origin),col_source,ry+16,{size=SZ.tiny,colour=e.origin and e.origin.kind=='mod'
                and C.mod or C.faint,align='right',max=220,z=12})
            local rx=lx
            if e.code then rx=rx+chip(cv,e.code,rx,ry+35,C.error,C.error_soft,nil,10)+8 end
            cv:text(e.text,rx,ry+35,{size=SZ.tiny,colour=C.faint,max=x+w-36-rx,z=12})
            cv:hit(x+12,ry,w-24,rh,action)
        end
        if n==0 then cv:text(L('No errors: every value the editor applied was accepted.'),x+28,ly+22,
            {size=SZ.small,colour=C.faint,z=12})end
        if n>rows then
            local th=math.max(24,(rows*rh)*rows/n)
            local t=p.scroll/math.max(1,n-rows)
            cv:rect(x+w-10,ly,3,rows*rh,C.line,11)
            cv:rect(x+w-10,ly+(rows*rh-th)*t,3,th,C.error,12)
        end
        -- the selected field's whole reason
        local e=list[p.index]
        local dy=ly+rows*rh+8
        cv:rect(x+12,dy,w-24,1,C.line,10)
        if e then
            local lines=wrap(cv,(e.code and(e.code..': ')or'')..e.text,w-48,SZ.small,3)
            for i,line in ipairs(lines)do
                cv:text(line,x+24,dy+16+(i-1)*19,{size=SZ.small,colour=C.dim,max=w-48,z=11})
            end
        end
        -- buttons and keys
        local by=y+h-50
        self.errors_log=self.errors_log or{click=function()self:errors_to_log()end}
        self.errors_close_button=self.errors_close_button or{click=function()self:close_errors()end}
        modal_button(self,cv,L('SHOW IN LOGS'),x+w-24-180-12-150,by,180,34,self.errors_log)
        modal_button(self,cv,L('CLOSE'),x+w-24-150,by,150,34,self.errors_close_button)
        cv:text(L('↑↓ select   Enter / click go to the field   Ins show in LOGS   Esc / Del close'),x+24,by+17,
            {size=SZ.tiny,colour=C.faint,max=w-420,z=11})
    end
end

return M

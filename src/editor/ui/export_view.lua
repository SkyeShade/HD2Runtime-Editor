-- HD2R Editor (c) 2026 SkyeShade. All rights reserved except as granted in LICENSE
-- (https://github.com/SkyeShade/HD2Runtime-Editor). Do not redistribute or reuse without the credit it requires.
-- EXPORT: a three-step wizard that turns the editor's changes into an HD2Runtime mod (editor/export.lua):
--   1. pick the changes to export;
--   2. the mod's name, version, author, description and its HD2 Arsenal image (a file from your PC, picked in the
--      Windows open-file dialog over the game; an in-game browser of your folders when the dialog cannot open);
--   3. done: the folder it was written to (the mod ZIP and its project), opened with one click, and a preset with the
--      exported values saved in Presets.
local theme=require('mods/skyeshade/hd2runtime_editor/editor/ui/theme')
local util=require('mods/skyeshade/hd2runtime_editor/editor/util')
local i18n=require('mods/skyeshade/hd2runtime_editor/editor/i18n')
local export=require('mods/skyeshade/hd2runtime_editor/editor/export')
local win=require('mods/skyeshade/hd2runtime_editor/editor/win')
local catalog_module=require('mods/skyeshade/hd2runtime_editor/editor/catalog')
local C,SZ=theme.colour,theme.size
local L=i18n.L
local M={}

local FIELDS={{key='name',label='Name',limit=40},{key='version',label='Version',limit=16},
    {key='author',label='Author',limit=24},{key='description',label='Description',limit=300},
    {key='image',label='Arsenal image'}}
local IMAGE_TYPES={png=true,jpg=true,jpeg=true}

function M.install(App)
    local button=App.button_fn
    local chip=App.chip_fn

    local function state(self)
        if not self.exporter then
            local author=self.presets:setting('export_author',nil)
                or(win.env('USERNAME')or'player'):gsub('[^%w ]','')
            self.exporter={step='pick',selected=nil,cursor=1,field=1,
                meta={name='My Mod',version='1.0.0',author=author,description='',image=nil}}
        end
        return self.exporter
    end
    -- The changes the wizard offers: every editor change that is applied or pending.
    function App:export_changes()
        local list=self:changes()
        local x=state(self)
        if not x.selected then
            x.selected={}
            for _,e in ipairs(list)do x.selected[e.row.key]=true end
        end
        return list,x
    end
    function App:export_typing()
        local x=self.exporter
        return self.view=='export'and x and x.step=='details'and not x.browser and FIELDS[x.field]and FIELDS[x.field].limit~=nil
    end
    function App:export_next()
        local list,x=self:export_changes()
        local n=0
        for _,e in ipairs(list)do if x.selected[e.row.key]then n=n+1 end end
        if n==0 then self:toast(L('Pick at least one change to export'),C.error);return end
        x.step,x.field='details',1
        self:sound('open')
    end
    function App:export_run()
        local list,x=self:export_changes()
        local entries,values={},{}
        for _,e in ipairs(list)do
            if x.selected[e.row.key]then entries[#entries+1]={row=e.row,value=e.value};values[e.row.key]=e.value end
        end
        local meta={}
        for k,v in pairs(x.meta)do meta[k]=v end
        meta.minimum=tostring(self.ctx.minimum or'0.30.0-dev')
        meta.editor_version=self.ctx.version
        local ok,result=pcall(export.build,catalog_module,entries,meta)
        if not ok then self:toast(L('Export failed: %s'):format(tostring(result)),C.error);return end
        local base=export.folder()
        if not base then self:toast(L('Export failed: %s'):format('no %USERPROFILE%'),C.error);return end
        local folder=base..'\\'..export.safe_name(meta.name)..'-'..meta.version
        local okw,zip=pcall(export.write,result,folder,win.mkdir)
        if not okw then self:toast(L('Export failed: %s'):format(tostring(zip)),C.error);return end
        -- a preset with exactly the exported values, to load them again later
        local preset=self.presets:unique_name(meta.name..' '..meta.version)
        local saved=self.presets:available()and self.presets:save(preset,self:encode_values(values))
        self.presets:set_setting('export_author',meta.author)
        x.done={folder=folder,zip=zip,resource=result.resource,count=#entries-#result.skipped,
            skipped=result.skipped,preset=saved and preset or nil}
        x.step='done'
        self:sound('apply')
    end
    -- the image browser: a folder's sub-folders and images
    function App:export_browse(path)
        local x=state(self)
        local entries,why=win.list(path)
        if not entries then self:toast(L('Cannot list %s: %s'):format(path,tostring(why)),C.error);return end
        local shown={}
        for _,e in ipairs(entries)do
            local ext=(e.name:match('%.(%w+)$')or''):lower()
            if e.folder or IMAGE_TYPES[ext]then shown[#shown+1]=e end
        end
        x.browser={path=path,entries=shown,cursor=1,scroll=0}
    end
    -- The image: the Windows open-file dialog, on top of the game (editor/win.lua pick_file); the in-game browser only
    -- when the dialog cannot open.
    function App:export_pick_image()
        local x=state(self)
        if x.picking then return end
        local job,why=win.pick_file({title=L('Choose the HD2 Arsenal image'),
            filter=L('Images')..' (*.png, *.jpg)|*.png;*.jpg;*.jpeg|',folder=(win.places()[1]or{}).path})
        if job then x.picking=job;return end
        self:toast(L('The Windows file dialog did not open (%s); browsing in game'):format(tostring(why)),C.dim)
        self:export_browse((win.places()[1]or{}).path or'C:\\')
    end
    -- Picks up the dialog's answer (called every frame while it is open).
    function App:export_poll_image()
        local x=self.exporter
        local job=x and x.picking
        if not job then return end
        local result=job.poll()
        if result==nil then return end
        x.picking=nil
        if result then
            local ext=(result:match('%.(%w+)$')or''):lower()
            if not IMAGE_TYPES[ext]then self:toast(L('Not a PNG or JPEG image: %s'):format(result),C.error);return end
            x.meta.image=result
            self:toast(L('Arsenal image: %s'):format(result:match('([^\\]+)$')or result),C.ok)
        end
    end
    function App:export_browser_pick(e)
        local x=self.exporter
        local b=x.browser
        if e.folder then
            self:export_browse(b.path..'\\'..e.name)
        else
            x.meta.image=b.path..'\\'..e.name
            x.browser=nil
            self:toast(L('Arsenal image: %s'):format(e.name),C.ok)
        end
    end
    local function parent(path)return path:match('^(.*)\\[^\\]+$')end

    function App:handle_export_keys(f)
        local k=f.keys
        local list,x=self:export_changes()
        if x.step=='pick'then
            if k.UP then x.cursor=math.max(1,x.cursor-1)end
            if k.DOWN then x.cursor=math.min(#list,x.cursor+1)end
            if k.ENTER and list[x.cursor]then
                local key=list[x.cursor].row.key
                x.selected[key]=not x.selected[key]
            end
            if k.RIGHT then self:export_next()end
        elseif x.step=='details'then
            if x.browser then
                local b=x.browser
                if k.UP then b.cursor=math.max(1,b.cursor-1)end
                if k.DOWN then b.cursor=math.min(#b.entries,b.cursor+1)end
                if k.ENTER and b.entries[b.cursor]then self:export_browser_pick(b.entries[b.cursor])end
                if k.BACKSPACE and parent(b.path)then self:export_browse(parent(b.path))end
                if k.ESCAPE then x.browser=nil end
                return
            end
            local field=FIELDS[x.field]
            if k.UP then x.field=math.max(1,x.field-1)end
            if k.DOWN or k.TAB then x.field=math.min(#FIELDS,x.field+1)end
            if field.limit then
                local text=x.meta[field.key]or''
                for _,ch in ipairs(f.chars)do if#text<field.limit then text=text..ch end end
                if k.BACKSPACE then text=text:sub(1,-2)end
                x.meta[field.key]=text
            elseif k.ENTER then
                self:export_pick_image()
            elseif k.DELETE then x.meta.image=nil end
        elseif x.step=='done'then
            if k.ENTER then win.open(x.done.folder)end
        end
    end

    function App:draw_export(y0,h)
        self:export_poll_image()
        local cv=self.canvas
        local W=theme.panel.w
        local list,x=self:export_changes()
        cv:rect(0,y0,W,h,C.panel,1)
        -- the steps
        local steps={L('1  CHANGES'),L('2  DETAILS'),L('3  DONE')}
        local at=({pick=1,details=2,done=3})[x.step]
        local sx=20
        for i,label in ipairs(steps)do
            local w=cv:measure(label,SZ.small,'title')+28
            cv:rect(sx,y0+16,w,28,i==at and C.gold or(i<at and C.gold_wash or C.box),3)
            cv:text(label,sx+w/2,y0+30,{size=SZ.small,font='title',colour=i==at and C.inverse or(i<at and C.gold or C.faint),
                align='center',z=5})
            sx=sx+w+8
        end
        cv:text(L('EXPORT AS A MOD'),W-20,y0+30,{size=18,font='title',colour=C.text,align='right'})
        local top=y0+60
        if x.step=='pick'then self:draw_export_pick(list,x,top,y0+h-top)
        elseif x.step=='details'then self:draw_export_details(list,x,top,y0+h-top)
        else self:draw_export_done(x,top,y0+h-top)end
    end

    function App:draw_export_pick(list,x,top,h)
        local cv=self.canvas
        local W=theme.panel.w
        local n=0
        for _,e in ipairs(list)do if x.selected[e.row.key]then n=n+1 end end
        cv:text(L('Pick the changes the mod will make. Applied and pending editor values are listed; mods\' own values are not.'),
            20,top+10,{size=SZ.small,colour=C.faint,max=W-480})
        self.export_all=self.export_all or{click=function()for _,e in ipairs(self:changes())do self.exporter.selected[e.row.key]=true end end}
        self.export_none=self.export_none or{click=function()self.exporter.selected={}end}
        self.export_next_btn=self.export_next_btn or{click=function()self:export_next()end}
        button(self,L('ALL'),W-452,top-6,90,32,'normal',self.export_all)
        button(self,L('NONE'),W-352,top-6,90,32,'normal',self.export_none)
        button(self,L('NEXT  %d'):format(n),W-252,top-6,232,32,n>0 and'primary'or'disabled',self.export_next_btn)
        if#list==0 then
            cv:text(L('No editor changes yet. Edit fields in Browse first.'),20,top+50,{size=SZ.label,colour=C.dim})
            return
        end
        self.export_rows=self.export_rows or{}
        self:list({x=0,y=top+34,w=W,h=h-38,count=#list,row_h=34,selected=x.cursor,scroll_key='export_scroll',focused=true,
            actions=self.export_rows,click=function(i)
                x.cursor=i
                local key=list[i].row.key
                x.selected[key]=not x.selected[key]
            end,
            draw=function(i,rx,ry,lw,rh)
                local e=list[i]
                local on=x.selected[e.row.key]
                if i==x.cursor then cv:rect(rx+8,ry+2,lw-16,rh-4,C.select,2)
                elseif self.hover==self.export_rows[i]then cv:rect(rx+8,ry+2,lw-16,rh-4,C.hover,2)end
                cv:rect(rx+22,ry+9,16,16,on and C.gold or C.box,3)
                cv:frame(rx+22,ry+9,16,16,on and C.gold or C.line_strong,4)
                if on then cv:rect(rx+26,ry+13,8,8,C.inverse,6)end
                self:draw_icon(e.row.object,rx+48,ry+4,rh-8)
                cv:text(e.row.object.name,rx+48+rh,ry+rh/2,{size=SZ.small,colour=on and C.text or C.faint,max=280})
                cv:text(L(e.row.label),rx+360,ry+rh/2,{size=SZ.small,colour=on and C.dim or C.faint,max=lw-700})
                cv:text(self:text(e.row,e.value),rx+lw-130,ry+rh/2,{size=SZ.label,colour=on and C.gold or C.faint,
                    align='right',max=200})
                if e.state=='pending'then chip(cv,L('PENDING'),rx+lw-20,ry+rh/2,C.pending,C.pending_soft,'right')end
            end})
    end

    function App:draw_export_details(list,x,top,h)
        local cv=self.canvas
        local W=theme.panel.w
        local n=0
        for _,e in ipairs(list)do if x.selected[e.row.key]then n=n+1 end end
        cv:text(L('How the mod appears in your mod manager. %d changes will be exported.'):format(n),20,top+10,
            {size=SZ.small,colour=C.faint,max=W-40})
        self.export_field_actions=self.export_field_actions or{}
        local y=top+40
        for i,field in ipairs(FIELDS)do
            local action=self.export_field_actions[i]
            if not action then
                local index=i
                action={click=function()
                    self.exporter.field=index
                    if FIELDS[index].key=='image'then self:export_pick_image()end
                end}
                self.export_field_actions[i]=action
            end
            local focused=x.field==i and not x.browser
            local fh=field.key=='description'and 64 or 36
            cv:text(L(field.label),24,y+fh/2,{size=SZ.label,colour=focused and C.text or C.dim})
            cv:rect(200,y,W-440,fh,C.box,3)
            cv:frame(200,y,W-440,fh,focused and C.box_focus or C.box_edge,4)
            if field.key=='image'then
                local text=x.picking and L('Choose the image in the Windows dialog...')
                    or x.meta.image or L('none (click or Enter to pick an image from your PC)')
                cv:text(text,212,y+fh/2,{size=SZ.small,colour=(x.meta.image and not x.picking)and C.text or C.faint,
                    max=W-470,z=6})
            elseif field.key=='description'then
                local lines=self.wrap and self.wrap(cv,x.meta.description,W-470,SZ.small,3)or{x.meta.description}
                if#lines==0 then lines={''}end
                for li,line in ipairs(lines)do
                    cv:text(line..((focused and li==#lines and math.floor(self.time*2)%2==0)and'_'or''),212,y+14+(li-1)*18,
                        {size=SZ.small,colour=C.text,max=W-470,z=6})
                end
            else
                local text=(x.meta[field.key]or'')..((focused and math.floor(self.time*2)%2==0)and'_'or'')
                cv:text(text,212,y+fh/2,{size=SZ.label,colour=C.text,max=W-470,z=6})
            end
            cv:hit(24,y,W-264,fh,action)
            y=y+fh+12
        end
        local version_ok=tostring(x.meta.version):match('^%d+%.%d+%.%d+$')~=nil
        if not version_ok then cv:text(L('The version must look like 1.0.0'),200,y+4,{size=SZ.small,colour=C.error})end
        cv:text(L('Resource id: %s'):format('mods/'..export.slug(x.meta.author)..'/'..export.slug(x.meta.name)),200,y+26,
            {size=SZ.small,colour=C.faint,max=W-440})
        cv:text(L('Saved to: %s'):format((export.folder()or'?')..'\\'..export.safe_name(x.meta.name)..'-'..x.meta.version),
            200,y+46,{size=SZ.small,colour=C.faint,max=W-440})
        self.export_back=self.export_back or{click=function()self.exporter.step='pick'end}
        self.export_go=self.export_go or{click=function()self:export_run()end}
        button(self,L('BACK'),W-452,top+h-50,120,36,'normal',self.export_back)
        button(self,L('EXPORT'),W-320,top+h-50,300,36,version_ok and x.meta.name~=''and'primary'or'disabled',self.export_go)
        if x.browser then self:draw_export_browser(x)end
    end

    function App:draw_export_browser(x)
        local cv=self.canvas
        local P=theme.panel
        local b=x.browser
        cv:rect(0,0,P.w,P.h,C.scrim,8)
        cv:hit(-10000,-10000,20000,20000,{click=function()x.browser=nil end})
        local w,h=820,620
        local bx,by=(P.w-w)/2,(P.h-h)/2
        cv:rect(bx,by,w,h,C.panel_alt,9);cv:frame(bx,by,w,h,C.line_strong,10);cv:rect(bx,by,w,3,C.gold,10)
        cv:hit(bx,by,w,h,{})
        cv:text(L('PICK AN ARSENAL IMAGE'),bx+24,by+30,{size=18,font='title',colour=C.text,z=11})
        cv:text(b.path,bx+24,by+54,{size=SZ.small,colour=C.faint,max=w-90,z=11})
        self.browser_close=self.browser_close or{}
        self.browser_close.click=function()x.browser=nil end
        cv:rect(bx+w-44,by+12,30,30,self.hover==self.browser_close and C.error_soft or C.panel_alt,10)
        cv:text('×',bx+w-29,by+27,{size=22,colour=C.dim,align='center',z=12})
        cv:hit(bx+w-44,by+12,30,30,self.browser_close)
        -- places
        self.browser_places=self.browser_places or{}
        local py=by+80
        for i,place in ipairs(win.places())do
            local action=self.browser_places[i]
            if not action then
                local path=place.path
                action={click=function()self:export_browse(path)end}
                self.browser_places[i]=action
            end
            local on=b.path:sub(1,#place.path)==place.path
            cv:rect(bx+16,py,150,30,on and C.gold_wash or(self.hover==action and C.hover or C.panel_alt),10)
            cv:text(L(place.label),bx+28,py+15,{size=SZ.small,colour=on and C.gold or C.dim,z=11})
            cv:hit(bx+16,py,150,30,action)
            py=py+34
        end
        self.browser_up=self.browser_up or{}
        self.browser_up.click=function()local p=parent(x.browser.path);if p then self:export_browse(p)end end
        cv:rect(bx+16,py+10,150,30,self.hover==self.browser_up and C.hover or C.panel_alt,10)
        cv:text(L('Up a folder'),bx+28,py+25,{size=SZ.small,colour=C.dim,z=11})
        cv:hit(bx+16,py+10,150,30,self.browser_up)
        -- entries
        local lx,ly,lw=bx+180,by+80,w-200
        local rows=math.floor((h-130)/30)
        local n=#b.entries
        if b.cursor<b.scroll+1 then b.scroll=b.cursor-1 end
        if b.cursor>b.scroll+rows then b.scroll=b.cursor-rows end
        b.scroll=math.max(0,math.min(b.scroll,math.max(0,n-rows)))
        b.wheel=b.wheel or{passthrough=true}
        b.wheel.scroll=function(d)b.scroll=math.max(0,math.min(b.scroll+d*3,math.max(0,n-rows)))end
        cv:hit(lx,ly,lw,rows*30,b.wheel)
        if n==0 then cv:text(L('No folders or images here'),lx+12,ly+16,{size=SZ.small,colour=C.faint,z=11})end
        for s=b.scroll+1,math.min(n,b.scroll+rows)do
            local e=b.entries[s]
            local ry=ly+(s-b.scroll-1)*30
            local action={click=function()b.cursor=s;self:export_browser_pick(e)end}
            if s==b.cursor then cv:rect(lx,ry,lw,28,C.select,10)end
            cv:text(e.name..(e.folder and'\\'or''),lx+12,ry+14,{size=SZ.small,colour=e.folder and C.gold or C.text,
                max=lw-140,z=11})
            if not e.folder then
                cv:text(string.format('%.0f KB',e.size/1024),lx+lw-12,ry+14,{size=SZ.tiny,colour=C.faint,align='right',z=11})
            end
            cv:hit(lx,ry,lw,28,action)
        end
        cv:text(L('Click a folder to open it, an image to use it. Backspace goes up a folder, Esc closes.'),bx+24,by+h-24,
            {size=SZ.tiny,colour=C.faint,max=w-48,z=11})
    end

    function App:draw_export_done(x,top,h)
        local cv=self.canvas
        local W=theme.panel.w
        local d=x.done
        cv:text(L('EXPORT SUCCESSFUL!'),W/2,top+80,{size=30,font='title',colour=C.ok,align='center'})
        cv:text(L('%d changes exported as %s'):format(d.count,d.resource),W/2,top+124,{size=SZ.label,colour=C.text,align='center'})
        cv:text(d.zip,W/2,top+152,{size=SZ.small,colour=C.dim,align='center',max=W-80})
        if d.preset then
            cv:text(L('Saved as the preset "%s" too, to load these values again later.'):format(d.preset),W/2,top+176,
                {size=SZ.small,colour=C.faint,align='center',max=W-80})
        end
        if#d.skipped>0 then
            cv:text(L('%d changes could not be exported: %s'):format(#d.skipped,tostring(d.skipped[1].why)),W/2,top+200,
                {size=SZ.small,colour=C.error,align='center',max=W-80})
        end
        self.export_open=self.export_open or{click=function()
            local ok,why=win.open(self.exporter.done.folder)
            if not ok then self:toast(L('Could not open it: %s'):format(tostring(why)),C.error)end
        end}
        self.export_reveal=self.export_reveal or{click=function()win.reveal(self.exporter.done.zip)end}
        self.export_again=self.export_again or{click=function()self.exporter.step,self.exporter.done='pick',nil end}
        button(self,L('OPEN EXPORT FOLDER'),W/2-310,top+240,300,40,'primary',self.export_open)
        button(self,L('SHOW THE ZIP'),W/2+10,top+240,300,40,'normal',self.export_reveal)
        button(self,L('EXPORT ANOTHER'),W/2-150,top+296,300,36,'normal',self.export_again)
        cv:text(L('Install the ZIP with your mod manager next to HD2Runtime. The project folder beside it builds with the HD2Runtime SDK.'),
            W/2,top+356,{size=SZ.small,colour=C.faint,align='center',max=W-80})
    end
end

return M

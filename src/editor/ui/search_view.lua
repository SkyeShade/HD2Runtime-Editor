-- HD2R Editor (c) 2026 SkyeShade. All rights reserved except as granted in LICENSE
-- (https://github.com/SkyeShade/HD2Runtime-Editor). Do not redistribute or reuse without the credit it requires.
-- SEARCH: one box over everything the editor can edit. Objects (weapons, stratagems, sentries, vehicles, backpacks,
-- boosters, armor, enemies ...) match by name and subtitle in every category; from three letters, fields match too,
-- by object, section and label (over the objects the background index has opened: all of them within seconds).
-- Every word must appear, in any order. Enter or a click opens the object in BROWSE, or goes to the field.
local theme=require('mods/skyeshade/hd2runtime_editor/editor/ui/theme')
local i18n=require('mods/skyeshade/hd2runtime_editor/editor/i18n')
local catalog_module=require('mods/skyeshade/hd2runtime_editor/editor/catalog')
local C,SZ=theme.colour,theme.size
local L=i18n.L
local M={}

local LIMIT_OBJECTS,LIMIT_FIELDS=200,300

-- The words of a query, lower case.
local function words(text)
    local out={}
    for w in tostring(text or''):lower():gmatch('%S+')do out[#out+1]=w end
    return out
end
-- Whether every word is in the text (plain find).
local function matches(haystack,list)
    for _,w in ipairs(list)do if not haystack:find(w,1,true)then return false end end
    return true
end

function M.install(App)
    local chip=App.chip_fn

    local function state(self)
        self.gsearch=self.gsearch or{text='',index=1}
        return self.gsearch
    end
    -- Every category: {id, label} in catalogue order.
    local function categories()
        local out={}
        for _,group in ipairs(catalog_module.GROUPS)do
            for _,item in ipairs(group.items)do out[#out+1]={id=item.id,label=item.label,group=group.label}end
        end
        return out
    end
    -- The results for a query: {{kind='object'|'field', object, row, label, sub}}, objects first.
    function App:search_results(text)
        local s=state(self)
        local key=tostring(text)..'|'..tostring(self.catalog.indexed)
        -- again while the index grows (it opens a few objects each frame)
        if s.key==key and(self.catalog.indexed or self.time-(s.at or 0)<1)then return s.results end
        local list=words(text)
        local results={}
        if#list>0 then
            local objects,fields={},{}
            for _,c in ipairs(categories())do
                for _,object in ipairs((self.catalog:objects(c.id))or{})do
                    object.search_text=object.search_text
                        or(object.name..' '..tostring(object.subtitle or'')..' '..c.label..' '..c.group):lower()
                    if#objects<LIMIT_OBJECTS and matches(object.search_text,list)then
                        objects[#objects+1]={kind='object',object=object,label=object.name,
                            sub=c.label..(object.subtitle and('  ·  '..object.subtitle)or''),
                            prefix=object.name:lower():sub(1,#list[1])==list[1]}
                    end
                    if#table.concat(list,' ')>=3 and object.rows and#fields<LIMIT_FIELDS then
                        for _,row in ipairs(object.rows)do
                            row.search_text=row.search_text
                                or(object.name..' '..tostring(row.section or'')..' '..tostring(row.group or'')..' '
                                ..tostring(row.label)..' '..tostring(row.field or'')):lower()
                            if matches(row.search_text,list)then
                                fields[#fields+1]={kind='field',object=object,row=row,label=row.label,
                                    sub=object.name..'  ·  '..tostring(row.group and(row.group..'  ·  ')or'')..tostring(row.section or'')}
                                if#fields>=LIMIT_FIELDS then break end
                            end
                        end
                    end
                end
            end
            -- names that start with the first word first, then by name
            table.sort(objects,function(a,b)
                if a.prefix~=b.prefix then return a.prefix end
                return a.label:lower()<b.label:lower()
            end)
            for _,r in ipairs(objects)do results[#results+1]=r end
            for _,r in ipairs(fields)do results[#results+1]=r end
        end
        s.key,s.results,s.at=key,results,self.time
        return results
    end
    -- Opens a result in BROWSE: the object (fields pane on its first field), or the field itself.
    function App:search_open(result)
        if not result then return end
        if result.kind=='field'then self:reveal(result.row)
        else
            local object=result.object
            for i,item in ipairs(self.categories)do if item.id==object.category then self.cat=i end end
            self.search,self.filter_key=nil,nil
            for i,o in ipairs(self:objects())do if o==object then self.obj=i end end
            self.field,self.field_scroll=1,0
            self.view,self.focus='browse','objects'
        end
        self:sound('open')
    end
    function App:handle_search_keys(f)
        local s=state(self)
        local k=f.keys
        for _,ch in ipairs(f.chars)do
            if#s.text<40 then s.text=s.text..ch;s.index,s.scroll_to=1,true end
        end
        if k.BACKSPACE then s.text=s.text:sub(1,-2);s.index=1 end
        if k.DELETE then s.text='';s.index=1 end
        local results=self:search_results(s.text)
        if k.UP then s.index=math.max(1,s.index-1)end
        if k.DOWN then s.index=math.min(math.max(1,#results),s.index+1)end
        if k.PAGEUP then s.index=math.max(1,s.index-10)end
        if k.PAGEDOWN then s.index=math.min(math.max(1,#results),s.index+10)end
        if k.ENTER then self:search_open(results[s.index])end
    end
    -- Escape: a query is cleared first (the window closes on the next Escape).
    function App:search_escape()
        local s=state(self)
        if s.text~=''then s.text='';s.index=1;return true end
        return false
    end
    function App:draw_search(y0,h)
        local cv=self.canvas
        local W=theme.panel.w
        local s=state(self)
        cv:rect(0,y0,W,h,C.panel,1)
        -- the box
        local bx,by,bw,bh=20,y0+18,W-40,40
        cv:rect(bx,by,bw,bh,C.box,3)
        cv:frame(bx,by,bw,bh,C.box_focus,4)
        local shown=s.text~=''and s.text or L('Search every weapon, stratagem, sentry, vehicle, armor, enemy and field...')
        local tw=cv:text(shown,bx+14,by+bh/2,{size=SZ.label,colour=s.text~=''and C.text or C.faint,max=bw-28,z=6})
        if s.text~=''and math.floor(self.time*2)%2==0 then cv:rect(bx+16+tw,by+10,2,bh-20,C.gold,6)end
        local results=self:search_results(s.text)
        s.index=math.max(1,math.min(s.index,math.max(1,#results)))
        local n_obj,n_field=0,0
        for _,r in ipairs(results)do if r.kind=='object'then n_obj=n_obj+1 else n_field=n_field+1 end end
        local info
        if s.text==''then info=L('Type to search. Every word must match, in any order. Fields match from three letters.')
        elseif#results==0 then info=L('Nothing matches "%s".'):format(s.text)
        else
            info=L('%d objects, %d fields'):format(n_obj,n_field)
            if not self.catalog.indexed then info=info..'   '..L('(still indexing every field...)')end
        end
        cv:text(info,bx,by+bh+18,{size=SZ.small,colour=C.faint,max=bw})
        -- the results
        local ly=by+bh+34
        self.search_actions=self.search_actions or{}
        self:list({x=0,y=ly,w=W,h=y0+h-ly-6,count=#results,row_h=40,selected=s.index,scroll_key='gsearch_scroll',
            focused=true,actions=self.search_actions,
            click=function(i)
                if s.index==i then self:search_open(results[i])else s.index=i end
            end,
            draw=function(i,x,y,w,rh)
                local r=results[i]
                local selected=i==s.index
                if selected then cv:rect(x+8,y+2,w-16,rh-4,C.select,2);cv:rect(x+8,y+2,3,rh-4,C.gold,3)
                elseif self.hover==self.search_actions[i]then cv:rect(x+8,y+2,w-16,rh-4,C.hover,2)end
                local tx=x+24
                if r.kind=='object'then
                    if self:draw_icon(r.object,x+20,y+5,rh-10)then tx=x+20+rh end
                else
                    chip(cv,L('FIELD'),x+20,y+rh/2,C.faint,C.line)
                    tx=x+80
                end
                cv:text(r.kind=='field'and L(r.label)or r.label,tx,y+14,{size=SZ.label,colour=selected and C.text or C.dim,max=w*0.5})
                cv:text(r.sub or'',tx,y+30,{size=SZ.tiny,colour=C.faint,max=w*0.6})
                if r.kind=='field'then
                    local value=self:row_view(r.row)
                    cv:text(r.row.editable and self:text(r.row,value)or L('locked'),x+w-24,y+rh/2,
                        {size=SZ.label,colour=r.row.editable and C.gold or C.faint,align='right',max=220})
                end
            end})
    end
end

return M

-- HD2R Editor (c) 2026 SkyeShade. All rights reserved except as granted in LICENSE
-- (https://github.com/SkyeShade/HD2Runtime-Editor). Do not redistribute or reuse without the credit it requires.
-- SEARCH: one box over everything the editor can edit, by object: weapons (primary, secondary, support), grenades,
-- stratagems of every kind, sentries, vehicles, backpacks, boosters, armor, enemies ... match by name and subtitle in
-- every category; a word of four letters or more also matches the start of a category's name ("boost" lists every
-- booster). Individual fields are not listed. Every word must appear, in any order. Enter or a click opens the object
-- in BROWSE.
local theme=require('mods/skyeshade/hd2runtime_editor/editor/ui/theme')
local i18n=require('mods/skyeshade/hd2runtime_editor/editor/i18n')
local catalog_module=require('mods/skyeshade/hd2runtime_editor/editor/catalog')
local util=require('mods/skyeshade/hd2runtime_editor/editor/util')
local C,SZ=theme.colour,theme.size
local L=i18n.L
local M={}

local LIMIT_OBJECTS=300

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
    -- Whether a query word names a category: four letters or more, the start of one of its words ("boost", "prim").
    local function names_category(word,label)
        -- (a CJK word has no letters %a finds: a translated category matches by its start, from two characters)
        if#word<4 then return false end
        for part in label:lower():gmatch('%a+')do if part:sub(1,#word)==word then return true end end
        if word:byte(1)>=0xC0 and label:lower():find(word,1,true)then return true end
        return false
    end
    -- The results for a query: {{kind='object', object, label, sub}}, names that start with the first word first.
    function App:search_results(text)
        local s=state(self)
        -- (a language switch, or the game's names, change the names shown and matched)
        local names=util.names_key()
        local key=tostring(text)..'\0'..names
        if s.key==key then return s.results end
        local list=words(text)
        local results,seen={},{}
        if#list>0 then
            for _,c in ipairs(categories())do
                local clabel,cgroup=L(c.label),L(c.group)
                for _,object in ipairs((self.catalog:objects(c.id))or{})do
                    -- the English name and subtitle, and the ones shown (translated): either matches
                    local name,sub=util.display_name(object),util.display_subtitle(object)
                    if object.search_language~=names then
                        object.search_language=names
                        object.search_text=(object.name..' '..tostring(object.subtitle or'')..' '..name..' '
                            ..tostring(sub or'')..' '..tostring(object.search_terms or'')):lower()
                    end
                    local ok=not seen[object.key]
                    for _,w in ipairs(list)do
                        if not ok then break end
                        ok=object.search_text:find(w,1,true)~=nil or names_category(w,c.label)
                            or names_category(w,c.group)or names_category(w,clabel)or names_category(w,cgroup)
                    end
                    if ok and#results<LIMIT_OBJECTS then
                        seen[object.key]=true
                        results[#results+1]={kind='object',object=object,label=name,
                            sub=clabel..(sub and('  ·  '..sub)or''),
                            prefix=name:lower():sub(1,#list[1])==list[1]
                                or object.name:lower():sub(1,#list[1])==list[1]}
                    end
                end
            end
            table.sort(results,function(a,b)
                if a.prefix~=b.prefix then return a.prefix end
                return a.label:lower()<b.label:lower()
            end)
        end
        s.key,s.results=key,results
        return results
    end
    -- Opens a result in BROWSE: its category (filters cleared) with the object selected.
    function App:search_open(result)
        if not result then return end
        if not self:goto_object(result.object)and self.ctx.log then
            self.ctx.log('search: '..tostring(result.object.key)..' is not listed in its category')
        end
        self.field,self.field_scroll=1,0
        self.view,self.focus='browse','objects'
        self:sound('open')
    end
    function App:handle_search_keys(f)
        local s=state(self)
        local k=f.keys
        for _,ch in ipairs(f.chars)do
            if#s.text<40 then s.text=s.text..ch;s.index,s.scroll_to=1,true end
        end
        if k.BACKSPACE then s.text=util.drop_last(s.text);s.index=1 end
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
        local shown=s.text~=''and s.text or L('Search every weapon, grenade, stratagem, booster, vehicle, armor and enemy...')
        local tw=cv:text(shown,bx+14,by+bh/2,{size=SZ.label,colour=s.text~=''and C.text or C.faint,max=bw-28,z=6})
        if s.text~=''and math.floor(self.time*2)%2==0 then cv:rect(bx+16+tw,by+10,2,bh-20,C.gold,6)end
        local results=self:search_results(s.text)
        s.index=math.max(1,math.min(s.index,math.max(1,#results)))
        local info
        if s.text==''then info=L('Type to search. Every word must match, in any order.')
        elseif#results==0 then info=i18n.Lf('Nothing matches "%s".',s.text)
        else info=i18n.Lf('%d results',#results)end
        cv:text(info,bx,by+bh+18,{size=SZ.small,colour=C.faint,max=bw})
        -- the results
        local ly=by+bh+34
        self.search_actions=self.search_actions or{}
        self:list({x=0,y=ly,w=W,h=y0+h-ly-6,count=#results,row_h=40,selected=s.index,scroll_key='gsearch_scroll',
            focused=true,actions=self.search_actions,
            click=function(i)
                -- one click opens it (a first click that only selected looked like it did nothing)
                s.index=i
                self:search_open(results[i])
            end,
            draw=function(i,x,y,w,rh)
                local r=results[i]
                local selected=i==s.index
                if selected then cv:rect(x+8,y+2,w-16,rh-4,C.select,2);cv:rect(x+8,y+2,3,rh-4,C.gold,3)
                elseif self.hover==self.search_actions[i]then cv:rect(x+8,y+2,w-16,rh-4,C.hover,2)end
                local tx=x+24
                if self:draw_icon(r.object,x+20,y+5,rh-10)then tx=x+20+rh end
                cv:text(r.label,tx,y+14,{size=SZ.label,colour=selected and C.text or C.dim,max=w*0.6})
                cv:text(r.sub or'',tx,y+30,{size=SZ.tiny,colour=C.faint,max=w*0.7})
            end})
    end
end

return M

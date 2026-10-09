-- HD2R Editor (c) 2026 SkyeShade. All rights reserved except as granted in LICENSE
-- (https://github.com/SkyeShade/HD2Runtime-Editor). Do not redistribute or reuse without the credit it requires.
-- The editor window: Browse (categories -> objects -> fields), Changes, Mods, Custom stratagems, Presets, Settings.
-- Edits are staged as pending values and applied together; Reset to defaults gives every field back to the mods'
-- values (or vanilla). Keyboard first (the cursor is the game's while playing), mouse where the cursor is free.
local theme=require('mods/skyeshade/hd2runtime_editor/editor/ui/theme')
local canvas_module=require('mods/skyeshade/hd2runtime_editor/editor/ui/canvas')
local input_module=require('mods/skyeshade/hd2runtime_editor/editor/ui/input')
local catalog_module=require('mods/skyeshade/hd2runtime_editor/editor/catalog')
local util=require('mods/skyeshade/hd2runtime_editor/editor/util')
local pickers=require('mods/skyeshade/hd2runtime_editor/editor/ui/pickers')
local views=require('mods/skyeshade/hd2runtime_editor/editor/ui/views')
local export_view=require('mods/skyeshade/hd2runtime_editor/editor/ui/export_view')
local i18n=require('mods/skyeshade/hd2runtime_editor/editor/i18n')
local modbuilder=require('mods/skyeshade/hd2runtime_editor/editor/modbuilder')
local preset_files=require('mods/skyeshade/hd2runtime_editor/editor/preset_files')
local win=require('mods/skyeshade/hd2runtime_editor/editor/win')
local L=i18n.L
local C,SZ=theme.colour,theme.size
local M={}
local App={};App.__index=App

local VIEWS={{id='browse',label='BROWSE'},{id='changes',label='CHANGES'},{id='export',label='EXPORT'},{id='mods',label='MODS'},
    {id='custom',label='CUSTOM'},{id='presets',label='PRESETS'},{id='logs',label='LOGS'},{id='settings',label='SETTINGS'}}
local CAT_W,OBJ_W=224,334
local PRESETS_W=470

function M.new(ctx)
    local self=setmetatable({ctx=ctx,hd2=ctx.hd2,catalog=ctx.catalog,layer=ctx.layer,ledger=ctx.ledger,
        presets=ctx.presets,canvas=canvas_module.new(),input=input_module.new(ctx.hd2),
        view='browse',focus='categories',cat=1,obj=1,obj_scroll=0,field=1,field_scroll=0,cat_scroll=0,
        pending={},pending_n=0,time=0,mod_index=1,mod_scroll=0,write_scroll=0,preset_index=1,preset_scroll=0,
        preset_action=1,detail_scroll=0,expanded={},expand_version=0},App)
    self.categories={}
    for _,group in ipairs(catalog_module.GROUPS)do
        self.categories[#self.categories+1]={group=true,label=group.label}
        for _,item in ipairs(group.items)do
            self.categories[#self.categories+1]={id=item.id,label=item.label,tone=item.tone}
        end
    end
    self.cat=2
    return self
end

pickers.install(App)

------------------------------------------------------------------------------------------------- helpers --
function App:toast(text,colour)
    self.toast_msg={text=util.plain(text,150),colour=colour or C.text,time=self.time}
    if colour==C.error then self:sound('error')end
end
-- The options page (hd2.diagnostics.options, HD2Runtime r51) whose options drive a mod's operation, or nil.
function App:option_page_of(op_id)
    if op_id==nil or type(self.option_pages)~='function'then return nil end
    for _,page in ipairs(self:option_pages())do
        for _,id in ipairs(page.operations or{})do if id==op_id then return page end end
    end
    return nil
end
-- One of the game's menu sounds (editor/sounds.lua), when the setting is on.
function App:sound(kind)
    local s=self.ctx.sounds
    if s and s.play then pcall(s.play,kind)end
end
local function pretty_mod(id)
    local last=tostring(id):match('([^/]+)$')or tostring(id)
    return util.humanize(last)
end
M.pretty_mod=pretty_mod
App.pretty_mod=pretty_mod
local function category_item(self)return self.categories[self.cat]end

-- The game's weapon groups, in the armory's order, with the short chip labels the filter shows.
local WEAPON_GROUPS={
    primary={'Assault Rifle','Marksman Rifle','Submachine Gun','Shotgun','Explosive','Energy-Based','Special'},
    secondary={'Pistol','Melee','Special'}}
local GROUP_LABELS={['Assault Rifle']='Assault',['Marksman Rifle']='Marksman',['Submachine Gun']='SMG',
    ['Energy-Based']='Energy'}
-- The weapon groups present in a weapon category (nil for every other category): {'All', groups...}.
function App:weapon_groups(category)
    local order=WEAPON_GROUPS[category]
    if not order then return nil end
    local present={}
    for _,object in ipairs(self.catalog:objects(category))do present[object.subtitle or'']=true end
    local out={'All'}
    for _,g in ipairs(order)do if present[g]then out[#out+1]=g end end
    for g in pairs(present)do
        local known=false
        for _,o in ipairs(out)do if o==g then known=true end end
        if not known and g~=''then out[#out+1]=g end
    end
    return out
end
function App:set_weapon_group(category,group)
    self.weapon_group=self.weapon_group or{}
    if self.weapon_group[category]~=group then
        self.weapon_group[category]=group
        self.obj,self.obj_scroll,self.field,self.field_scroll,self.filter_key=1,0,1,0,nil
    end
end
-- The objects of the selected category, filtered by the weapon group and the search text.
function App:objects()
    local item=category_item(self)
    if not item or item.group then return {}end
    local list,why=self.catalog:objects(item.id)
    self.objects_error=why
    local group=self.weapon_group and self.weapon_group[item.id]
    if group=='All'then group=nil end
    local q=self.search and self.search.text~=''and self.search.text:lower()
    if not q and not group then return list end
    local key=item.id..'\0'..(q or'')..'\0'..(group or'')
    if self.filter_key==key then return self.filtered end
    local out={}
    for _,object in ipairs(list)do
        local hay=(object.name..' '..(object.subtitle or'')):lower()
        if(not q or hay:find(q,1,true))and(not group or object.subtitle==group)then out[#out+1]=object end
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
function App:is_open(object,key)return self.expanded[object.key..'\0'..key]==true end
function App:toggle(object,key,open)
    local id=object.key..'\0'..key
    if open==nil then open=not self.expanded[id]end
    if(self.expanded[id]==true)==open then return end
    self.expanded[id]=open or nil
    self.expand_version=self.expand_version+1
end
-- An object's sections as shown: a mount that holds another weapon shows THAT weapon's rows (its own catalogued
-- vehicle weapon, edited through its home vehicle) instead of the slot's original weapon, whose records the Runtime
-- refuses to write while the slot holds something else. Returns sections and a signature of the swaps.
function App:effective_sections(object)
    local swapped,sig={},{}
    for _,row in ipairs(object.rows or{})do
        if row.mount_slot then
            local value=self:row_view(row)
            if value~=nil and value~=row.vanilla then swapped[row.mount_slot]=value;sig[#sig+1]=row.mount_slot..'='..value end
        end
    end
    if#sig==0 then return object.sections or{},''end
    table.sort(sig)
    local out,done={},{}
    for _,section in ipairs(object.sections or{})do
        local slot=section.rows[1]and section.rows[1].home_slot
        local id=slot and swapped[slot]
        if not id then out[#out+1]=section
        elseif not done[slot]then
            done[slot]=true
            local name=catalog_module.mounted_weapon_name(id)
            local key=catalog_module.mounted_weapon_entry(id)
            local role=section.group and section.group:match('^Weapon · (.+)$')or util.humanize(slot)
            local group=role..' · now '..name
            local rows,home=key and self.catalog:weapon_rows(key)or{},nil
            if key then _,home=self.catalog:weapon_rows(key)end
            if#rows==0 then
                out[#out+1]={label='No editable stats for this weapon',group=group,rows={}}
            else
                local by,order={},{}
                for _,r in ipairs(rows)do
                    local label=(home and home~=object and(r.section..' · shared with '..home.name))or r.section
                    if not by[label]then by[label]={label=label,group=group,rows={}};order[#order+1]=by[label]end
                    local list=by[label].rows
                    list[#list+1]=r
                end
                for _,sec in ipairs(order)do out[#out+1]=sec end
            end
        end
    end
    return out,table.concat(sig,';')
end
function App:field_items(object)
    if not object then return {},{}end
    local sections,sig=self:effective_sections(object)
    if object.items and object.items_version==self.expand_version and object.items_swaps==sig then
        return object.items,object.selectable
    end
    local items,selectable={},{}
    local function add(item,pick)
        items[#items+1]=item
        if pick then selectable[#selectable+1]=#items end
    end
    local groups,order={},{}
    for _,section in ipairs(sections)do
        if section.group then
            if not groups[section.group]then groups[section.group]={};order[#order+1]=section.group end
            local list=groups[section.group]
            list[#list+1]=section
        end
    end
    local emitted={}
    for _,section in ipairs(sections)do
        if not section.group then
            add({section=section.label,count=#section.rows})
            for _,row in ipairs(section.rows)do add({row=row,depth=0},true)end
        elseif not emitted[section.group]then
            emitted[section.group]=true
            local g=section.group
            local count,rows=0,{}
            for _,sec in ipairs(groups[g])do
                count=count+#sec.rows
                for _,row in ipairs(sec.rows)do rows[#rows+1]=row end
            end
            local gkey='g|'..g
            local open=self:is_open(object,gkey)
            add({header=g,key=gkey,open=open,count=count,subs=#groups[g],depth=0,rows=rows},true)
            if open then
                for _,sec in ipairs(groups[g])do
                    local skey='s|'..g..'|'..sec.label
                    local sopen=self:is_open(object,skey)
                    add({header=sec.label,key=skey,open=sopen,count=#sec.rows,depth=1,parent=gkey,rows=sec.rows},true)
                    if sopen then
                        for _,row in ipairs(sec.rows)do add({row=row,depth=2,parent=skey},true)end
                    end
                end
            end
        end
    end
    object.items,object.selectable,object.items_version,object.items_swaps=items,selectable,self.expand_version,sig
    return items,selectable
end
-- The focused field-list item (a row or a collapsible header), or nil.
function App:focused_item()
    if self.view~='browse'then return nil end
    local object=self:object()
    local items,selectable=self:field_items(object)
    local index=selectable[self.field]
    return index and items[index]or nil,object
end
-- Opens or closes a header, keeping it selected.
function App:toggle_item(item,object,open)
    if not(item and item.header)then return end
    self:toggle(object,item.key,open)
    local items,selectable=self:field_items(object)
    for s,index in ipairs(selectable)do if items[index].key==item.key then self.field=s end end
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
    if not pending then
        -- the same bytes staged through another object's row (a shared value): shown here too
        for _,other in ipairs(self.catalog:siblings(row))do
            if other~=row and self.pending[other.key]then pending=self.pending[other.key];break end
        end
    end
    local value,source,holder,slot=self.layer:value(row)
    local state,err=self.layer:state(row)
    if pending then return pending.value,'pending',state,holder,err end
    return value,source,state,holder,err
end

-- Objects with pending, active or mod-written fields (refreshed when the layer or ledger change).
function App:markers()
    local key=self.layer.version..':'..self.ledger.version..':'..self.pending_n
    if self.marker_key==key then return self.marker_cache end
    local m={pending={},editor={},mod={},row_pending={},loc_editor={},loc_mod={},category={}}
    local function in_category(object,kind)
        local category=object and object.category
        if not category then return end
        local c=m.category[category]
        if not c then c={};m.category[category]=c end
        c[kind]=true
    end
    -- a value shared by several objects marks every one of them (the rows on the same native bytes)
    for _,p in pairs(self.pending)do
        for _,r in ipairs(self.catalog:siblings(p.row))do
            if r.object then
                m.pending[r.object.key]=true
                in_category(r.object,'pending')
            end
            m.row_pending[r.key]=true
        end
        m.pending[p.row.object.key]=true
        m.row_pending[p.row.key]=true
        in_category(p.row.object,'pending')
    end
    for loc,slot in pairs(self.layer.slots)do
        if slot.user and slot.row and slot.row.object then
            m.loc_editor[loc]=true
            for _,r in ipairs(self.catalog:siblings(slot.row))do
                if r.object then m.editor[r.object.key]=true;in_category(r.object,'editor')end
            end
            m.editor[slot.row.object.key]=true
            in_category(slot.row.object,'editor')
        end
    end
    for loc,claims in pairs(self.ledger.by_loc)do
        for _,claim in ipairs(claims)do
            m.loc_mod[loc]=true
            if claim.object then
                local object=self.catalog:object(claim.object)
                m.mod[object and object.key or claim.object]=true
                in_category(object,'mod')
            end
        end
        -- every object whose rows write those bytes
        for _,r in ipairs(self.catalog.by_loc[loc]or{})do
            if r.object then m.mod[r.object.key]=true;in_category(r.object,'mod')end
        end
    end
    m.key=key
    self.marker_key,self.marker_cache=key,m
    return m
end
-- What a collapsible header's rows hold: {pending, editor, mod} (cached on the item per marker state).
function App:header_marks(item,m)
    if item.marks_key==m.key then return item.marks end
    local marks={}
    for _,row in ipairs(item.rows or{})do
        if m.row_pending[row.key]then marks.pending=true end
        if m.loc_editor[row.loc]then marks.editor=true end
        if m.loc_mod[row.loc]then marks.mod=true end
    end
    item.marks,item.marks_key=marks,m.key
    return marks
end
-- Draws the markers right to left from x (pending orange hourglass piece, edited by you yellow pencil piece, set by a
-- mod blue piece), centred on cy; returns the x left of them. The glyphs fill about half of their square (x 25% to
-- 76%), so the squares overlap: one glyph width and a small gap apart.
function App:draw_marks(marks,x,cy,size)
    local cv=self.canvas
    local step=math.floor(size*0.62+0.5)
    local first=true
    local function mark(name,colour)
        local left=x-size+(first and math.floor(size*0.22)or 0)
        if not self:draw_ui_icon(name,left,cy-size/2,size,colour)then
            local dot=math.floor(size*0.4)
            cv:rect(left+(size-dot)/2,cy-dot/2,dot,dot,colour,4)
        end
        x=left+size-step
        first=false
    end
    if marks.pending then mark('pending',C.pending)end
    if marks.editor then mark('edited',C.gold)end
    if marks.mod then mark('mod',C.mod)end
    x=first and x or x-math.floor(size*0.2)
    return x
end

---------------------------------------------------------------------------------------------- staging --
-- Drops pending values staged on other rows of the same native bytes (one value per location).
function App:unstage_siblings(row)
    for _,other in ipairs(self.catalog:siblings(row))do
        if other~=row and self.pending[other.key]then self.pending[other.key]=nil;self.pending_n=self.pending_n-1 end
    end
end
-- 'AR-23 Liberator, AR-23P Liberator Penetrator (+2)': the other objects a shared row's value also changes.
function App:shared_names(row,limit)
    local names,seen={},{}
    for _,other in ipairs(self.catalog:shared_with(row))do
        local name=other.object and other.object.name
        if name and not seen[name]then seen[name]=true;names[#names+1]=name end
    end
    if#names==0 then return nil,0 end
    table.sort(names,util.natural_less)
    limit=limit or 3
    local shown={}
    for i=1,math.min(limit,#names)do shown[i]=names[i]end
    return table.concat(shown,', ')..(#names>limit and(' (+'..(#names-limit)..')')or''),#names
end
function App:stage(row,value)
    if not row.editable then self:toast(row.label..': '..tostring(row.reason or'not editable'),C.error);return false end
    local staged=self:stage_value(row,value)
    -- accepted: any value staged on another row of the same bytes gives way to it
    if staged then self:unstage_siblings(row)end
    if staged and self.pending[row.key]then
        local names=self:shared_names(row)
        if names then self:toast(L('Shared value: this also changes %s'):format(names),C.pending)end
        -- once a session: the edits GameGuard was reported to react to
        if row.risk=='gameguard'and not self.gameguard_warned then
            self.gameguard_warned=true
            self:toast(L('Careful: ')..L(catalog_module.GAMEGUARD_RISK),C.error)
        end
    end
    return staged
end
function App:stage_value(row,value)
    if row.kind then
        if self.ctx.choices==false then
            self:toast(L('Editing ')..row.label..' needs HD2Runtime r50 (script choices)',C.error);return false
        end
        local current=self.layer:value(row)
        local existing=self.pending[row.key]
        if not util.same(current,value)then
            local ok,why=catalog_module.probe(row,value)
            if not ok then self:toast(row.label..': '..tostring(why),C.error);return false end
        end
        if util.same(current,value)then
            if existing then self.pending[row.key]=nil;self.pending_n=self.pending_n-1 end
            return true
        end
        if not existing then self.pending_n=self.pending_n+1 end
        self.pending[row.key]={row=row,value=value}
        return true
    end
    local held=util.representable(value,row.integer,row.storage)
    if held==nil then
        self:toast(row.integer and'Whole numbers only'or'At most 3 decimals',C.error);return false
    end
    if row.min and held<row.min then held=row.min;self:toast(L('Clamped to the minimum ')..util.format(row.min),C.pending)end
    if row.max and held>row.max then held=row.max;self:toast(L('Clamped to the maximum ')..util.format(row.max),C.pending)end
    if row.disabled_value~=nil and held~=row.disabled_value and held<=0 then
        -- nothing between the disable value and 0 is valid: zero or below means disabled
        held=row.disabled_value
        self:toast(L('%s disables it (a value above 0 enables it)'):format(util.format(row.disabled_value)),C.pending)
    end
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
    for key,stored in pairs(map)do
        local row,value=self:decode_value(key,stored)
        if row and value~=nil then self:stage(row,value)else missing=missing+1 end
    end
    return missing
end
function App:apply()
    if self.pending_n==0 then self:toast(L('Nothing to apply'),C.dim);return end
    local n,failed=0,0
    for key,p in pairs(self.pending)do
        local ok,why=self.layer:set(p.row,p.value)
        if ok then self.pending[key]=nil;n=n+1 else failed=failed+1;self:toast(p.row.label..': '..tostring(why),C.error)end
    end
    self.pending_n=failed
    if failed==0 then self:toast(L('Applying ')..n..(n==1 and' change'or' changes'),C.gold)end
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
    if row.kind=='choice'and row.options then
        -- step through the choices (On / Off, statuses, enums)
        local options=row.options(row)
        local value=self:row_view(row)
        local index=1
        for i,o in ipairs(options)do if util.same(o.value,value)then index=i end end
        local next_index=(index-1+direction)%#options+1
        if options[next_index]then self:stage(row,options[next_index].value)end
        return
    elseif row.kind=='uses'then
        local value=self:row_view(row)
        if value=='unlimited'then if direction<0 then self:stage(row,row.max or 100)end return end
        -- below the lowest count is unlimited (0 or -1 typed means the same), where the stratagem allows it
        if direction<0 and value<=(row.min or 1)and(row.unlimited or row.vanilla=='unlimited')then
            self:stage(row,'unlimited')
            return
        end
        local n=util.clamp(value+direction*(shift and 10 or 1),row.min or 1,row.max or 100)
        self:stage(row,n)
        return
    elseif row.kind then return end
    local value=self:row_view(row)
    if row.disabled_value~=nil and value==row.disabled_value then
        -- stepping up from disabled enables it at the smallest step
        if direction>0 then self:stage(row,row.integer and 1 or util.STEP*100)end
        return
    end
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
    if row.kind=='code'then return self:open_code(row)end
    if row.kind=='modes'then return self:open_modes(row)end
    if row.kind=='rates'then return self:open_rates(row)end
    if row.kind=='traits'then return self:open_traits(row)end
    if row.kind then return self:open_picker(row,row.kind=='uses'and text or nil)end
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
    if self.view~=id then self:sound('click')end
    self.view,self.edit,self.rename=id,nil,nil
    if self.search then self.search.active=false end
    if id=='mods'then self.mods_cache,self.options_cache=nil,nil end
    if id=='custom'then self.custom_cache=nil end
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
        local groups=f.ctrl and(k.LEFT or k.RIGHT)and self:weapon_groups(category_item(self).id)
        if groups then
            local id=category_item(self).id
            local current=self.weapon_group and self.weapon_group[id]or'All'
            local index=1
            for i,g in ipairs(groups)do if g==current then index=i end end
            index=(index-1+(k.LEFT and-1 or 1))%#groups+1
            self:set_weapon_group(id,groups[index])
            return
        end
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
        local item=self:focused_item()
        if item and item.header then
            if k.RIGHT or k.ENTER then self:toggle_item(item,object,true)end
            if k.LEFT then
                if item.open then self:toggle_item(item,object,false)
                elseif item.parent then
                    for s,index in ipairs(selectable)do if items[index].key==item.parent then self.field=s end end
                end
            end
        end
        if row then
            if k.LEFT then self:nudge(row,-1,f.shift,f.ctrl)end
            if k.RIGHT then self:nudge(row,1,f.shift,f.ctrl)end
            if k.ENTER then self:begin_edit(row,nil,true)end
            if k.BACKSPACE and not row.kind then
                local text=util.format((self:row_view(row)))
                self:begin_edit(row,text:sub(1,-2))
            end
            if k.DELETE then
                if self:unstage(row)then self:toast(L('Pending change removed'),C.dim)
                else
                    local _,source=self.layer:value(row)
                    if source=='editor'then
                        local base=self.layer:base(row)
                        self:stage(row,base)
                        self:toast(L('Staged: back to ')..self:text(row,base)..' (press Apply)',C.pending)
                    end
                end
            end
            if#f.chars>0 then
                if row.kind=='uses'then self:open_picker(row,table.concat(f.chars))
                elseif not row.kind then
                    self:begin_edit(row,'',false)
                    if self.edit then self:edit_chars(f.chars)end
                end
            end
        end
    end
end

function App:handle_keys(f)
    local k=f.keys
    if self.key_capture then return self:handle_key_capture(f)end
    if self.picker then return self:handle_picker_keys(f)end
    if self.coder then return self:handle_code_keys(f)end
    if self.moder then return self:handle_modes_keys(f)end
    if self.rater then return self:handle_rates_keys(f)end
    if self.traiter then return self:handle_traits_keys(f)end
    if self.confirm then
        if k.ENTER or k.INSERT then self:confirm_yes()
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
    -- Escape closes the window (inside a dialog, a typed value, the search or a name it cancels that first)
    if k.ESCAPE then
        if self.view=='custom'and((self.custom_field or 0)>0 or self.custom_edit)then
            self.custom_edit,self.custom_field=nil,0
            return
        end
        if self.view=='export'and self.exporter and self.exporter.browser then
            self.exporter.browser=nil
            return
        end
        self:sound('back')
        if self.ctx.close then self.ctx.close()end
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
    if k.ENTER then self:sound('click')end
    if f.ctrl and self:key_down_once('F')and self.view=='browse'then
        self.search=self.search or{text=''}
        self.search.active=true
        self.focus='objects'
        return
    end
    if self.view=='browse'then self:handle_browse_keys(f)
    elseif self.view=='changes'then self:handle_changes_keys(f)
    elseif self.view=='mods'then self:handle_mods_keys(f)
    elseif self.view=='custom'then self:handle_custom_keys(f)
    elseif self.view=='settings'then self:handle_settings_keys(f)
    elseif self.view=='logs'then self:handle_logs_keys(f)
    elseif self.view=='export'then self:handle_export_keys(f)
    elseif self.view=='presets'then self:handle_presets_keys(f)end
end
function App:key_down_once(name)return self.input:query('pressed',name)end

----------------------------------------------------------------------------------------- the open key --
-- HD2Runtime 0.30.2: the wheel hook is the player's install choice. With "Mouse wheel hook off" the wheel only scrolls
-- over a game menu: the Runtime's notice (wheel_status().notice), or nil when the wheel works. Read every few seconds.
function App:wheel_notice()
    if not self.wheel_checked or self.time-self.wheel_checked>2 then
        self.wheel_checked=self.time
        local fn=type(self.hd2.input)=='table'and self.hd2.input.wheel_status
        local status
        if type(fn)=='function'then
            local ok,v=pcall(fn)
            status=ok and type(v)=='table'and v or nil
        end
        self.wheel_off=status and status.install_option=='hook_off'and(status.notice or true)or nil
    end
    return self.wheel_off
end
App.DEFAULT_HOTKEY='F8'
M.DEFAULT_HOTKEY=App.DEFAULT_HOTKEY
function App:hotkey()return tostring(self.ctx.hotkey or App.DEFAULT_HOTKEY)end
-- Why a chord cannot open and close the editor, or nil: the keys the editor reads while open (with any modifier),
-- the keys it types with (unless Ctrl or Alt is held), Ctrl+F (search) and Alt+F4. name: an hd2.input key name.
function App.hotkey_refusal_fn(...)return M.hotkey_refusal(...)end
function M.hotkey_refusal(name,ctrl,shift,alt)
    for _,nav in ipairs(input_module.NAV)do
        if nav==name then return L('The editor already uses %s'):format(name)end
    end
    if not ctrl and not alt and(input_module.CHARS[name]or name:match('^%u$'))then
        return L('%s types text in the editor: hold Ctrl or Alt with it'):format(name)
    end
    if ctrl and not alt and not shift and name=='F'then return L('Ctrl+F searches in the editor')end
    if name=='F10'and not ctrl and not alt and not shift then return L('F10 opens the HD2Runtime settings')end
    if alt and name=='F4'then return L('Alt+F4 closes the game')end
    return nil
end
-- Every key a binding accepts (hd2.input.keys); F1-F12 without it.
function App:bindable_keys()
    if not self.key_list then
        local list={}
        local fn=type(self.hd2.input)=='table'and self.hd2.input.keys
        if type(fn)=='function'then
            local ok,names=pcall(fn)
            if ok and type(names)=='table'then for _,name in ipairs(names)do list[#list+1]=name end end
        end
        if#list==0 then for i=1,12 do list[i]='F'..i end end
        table.sort(list)
        self.key_list=list
    end
    return self.key_list
end
-- Moves the open key to a chord ('Ctrl+F7'): main.lua rebinds it (the Runtime refuses one another binding holds).
function App:set_hotkey(chord)
    if not self.ctx.set_hotkey then self:toast(L('This HD2Runtime cannot rebind the key'),C.error);return false end
    local ok,why,holder=self.ctx.set_hotkey(chord)
    if ok then
        self:toast(L('The editor now opens and closes with %s'):format(self:hotkey()),C.ok)
    elseif why=='conflict'then
        self:toast(L('%s is already used by %s'):format(chord,tostring(holder or L('another mod'))),C.error)
    else
        self:toast(tostring(why),C.error)
    end
    return ok
end
-- Waiting for the new key: the current one is held off meanwhile, so pressing it does not close the window.
function App:start_key_capture()
    if not self.ctx.set_hotkey then self:toast(L('This HD2Runtime cannot rebind the key'),C.error);return end
    self.key_capture={}
    if self.ctx.hold_hotkey then self.ctx.hold_hotkey(true)end
end
function App:end_key_capture()
    if not self.key_capture then return end
    self.key_capture=nil
    if self.ctx.hold_hotkey then self.ctx.hold_hotkey(false)end
end
function App:handle_key_capture(f)
    local cap=self.key_capture
    if self.view~='settings'then return self:end_key_capture()end
    if cap.chord then
        -- taken once the key is up: a binding that found its key already held would close the window at once
        if not self.input:query('down',cap.main)then
            local chord=cap.chord
            self:end_key_capture()
            if self:set_hotkey(chord)then self:sound('click')end
        end
        return
    end
    if f.keys.ESCAPE then self:end_key_capture();self:sound('back');return end
    for _,name in ipairs(self:bindable_keys())do
        if name~='ESCAPE'and self.input:query('pressed',name)then
            local why=M.hotkey_refusal(name,f.ctrl,f.shift,f.alt)
            if why then self:toast(why,C.error);return end
            cap.main=name
            cap.chord=(f.ctrl and'Ctrl+'or'')..(f.shift and'Shift+'or'')..(f.alt and'Alt+'or'')..name
            return
        end
    end
end

function App:ask(kind,data)
    if kind=='reset'then
        local active=self.layer:counts()
        if active==0 and self.pending_n==0 then self:toast(L('Nothing to reset: no editor values are active'),C.dim);return end
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
        self:toast(L('Deleted preset ')..c.data,C.dim)
        self.preset_index=clamp_index(self.preset_index-1,#self.presets:list()+1)
    elseif c.kind=='overwrite_preset'then self:save_preset(c.data,true)end
end

------------------------------------------------------------------------------------------------ mouse --
function App:handle_mouse(f)
    local m=f.mouse
    if not m then self.hover=nil;return end
    local ux,uy=self.canvas:to_units(m.x,m.y)
    local action=self.canvas:hit_at(ux,uy)
    self.hover=action
    self.mouse_units={x=ux,y=uy,moved=m.moved}
    if self.drag then
        if m.left then self.drag.move(uy)else self.drag=nil end
        return
    end
    if f.wheel~=0 then
        local scroller=self.canvas:scroll_at(ux,uy)
        if scroller then scroller.scroll(-f.wheel)end
    end
    if m.clicked and action and action.click then
        if action.sound~=false then self:sound(action.scroll and'click'or'click')end
        action.click(ux,uy)
    end
    if m.rclicked and action and action.rclick then action.rclick(ux,uy)end
end

-- The interface size the Settings chose (one of theme.UI_SCALES; 1 by default).
function App:ui_scale()
    local v=self.presets and self.presets:setting('ui_scale',1)or 1
    for _,s in ipairs(theme.UI_SCALES)do if s==v then return v end end
    return 1
end
-- Steps the interface size one choice up (+1) or down (-1).
function App:step_ui_scale(direction)
    local list=theme.UI_SCALES
    local now,index=self:ui_scale(),1
    for i,s in ipairs(list)do if s==now then index=i end end
    local next_index=math.max(1,math.min(#list,index+direction))
    if next_index==index then return end
    self.presets:set_setting('ui_scale',list[next_index])
    self:sound('click')
end

------------------------------------------------------------------------------------------------- frame --
function App:frame(d,dt)
    self.time=self.time+(dt or 0)
    -- the native-bytes index of the whole catalogue, a few objects a frame (shared values, markers)
    if not self.catalog.indexed then
        local before=self.catalog.indexed
        if self.catalog:index_step(6,0.003)and not before then self.marker_key=nil end
    end
    self.frame_dt=dt or 0
    if self.ctx.sounds and self.ctx.sounds.tick then self.ctx.sounds.tick(dt or 0)end
    -- centred on the screen (1080p units), at the chosen interface size: the overlay's scale times the setting, as
    -- large as still fits (the panel keeps its full width and at least PANEL_MIN_H units of height)
    local layout=theme.panel
    local base=d.scale or 1
    local sw,sh=(d.width or 1920)/base,(d.height or 1080)/base
    local k=math.min(self:ui_scale(),sw/(layout.w+24),sh/(theme.PANEL_MIN_H+24))
    k=math.max(k,0.5)
    self.ui_scale_now=k
    local W,H=sw/k,sh/k
    layout.h=math.floor(math.min(theme.PANEL_H,H-24))
    local ox=math.floor((W-layout.w)/2+0.5)
    local oy=math.floor((H-layout.h)/2+0.5)
    self.canvas:begin(d,math.max(0,ox),math.max(0,oy),base*k)
    local typing=self.edit~=nil or(self.view=='browse'and self.focus=='fields')
    local letters=(self.search and self.search.active)or self.rename~=nil or self.picker~=nil
    if self.coder or self.moder or self.traiter then typing=false end
    if self.rater then typing=true end
    if self.view=='custom'and(self.custom_field or 0)>0 then typing=true end
    if self:export_typing()then typing,letters=true,true end
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
App.chip_fn=chip
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

App.button_fn=button

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
    local cv,P=self.canvas,theme.panel
    local h=theme.header_h
    cv:rect(0,0,P.w,h,C.header,1)
    cv:rect(0,h-1,P.w,1,C.line_strong,2)
    logo(cv,18,15,28)
    local x=60
    x=x+cv:text('HD2R',x,h/2,{size=SZ.title,font='title',colour=C.text})
    cv:text('EDITOR',x+8,h/2,{size=SZ.title,font='title',colour=C.gold})
    -- tabs
    local tx=300
    for _,v in ipairs(VIEWS)do
        local label=L(v.label)
        local n=0
        if v.id=='mods'then n=#(self:mods_list())
        elseif v.id=='presets'then n=#self.presets:list()
        elseif v.id=='changes'then n=#self:changes()
        elseif v.id=='custom'then n=#self:custom_list()end
        if n>0 then label=label..'  '..n end
        local w=cv:measure(label,SZ.tab,'title')+22
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
        cv:text(label,tx+11,h/2+1,{size=SZ.tab,font='title',colour=selected and C.gold or C.dim})
        cv:hit(tx,6,w,h-6,action)
        tx=tx+w+2
    end
    local tabs_end=tx+8
    -- the close button, then the status chips, right to left
    -- the window's X closes it with the same sound as Escape
    self.btn_close=self.btn_close or{sound=false,click=function()
        self:sound('back')
        if self.ctx.close then self.ctx.close()end
    end}
    local hovered=self.hover==self.btn_close
    cv:rect(P.w-50,12,36,34,hovered and C.error_soft or C.panel,3)
    cv:frame(P.w-50,12,36,34,hovered and C.error or C.line_strong,4)
    cv:text('×',P.w-32,29,{size=24,colour=hovered and C.error or C.dim,align='center',z=6})
    cv:hit(P.w-50,12,36,34,self.btn_close)
    local rx=P.w-62
    local active,applying,errors=self.layer:counts()
    -- status chips right to left, each only while it clears the tabs
    local function status(text,fg,bg)
        local w=cv:measure(text,SZ.tiny,'title')+14
        if rx-w<tabs_end then return end
        rx=rx-chip(cv,text,rx,h/2,fg,bg,'right')-8
    end
    if errors>0 then status(errors..' '..(errors==1 and L('ERROR')or L('ERRORS')),C.error,C.error_soft)end
    if applying>0 then
        local pulse=0.55+0.45*math.abs(math.sin(self.time*4))
        status(L('APPLYING')..' '..applying,{255,199,44,math.floor(255*pulse)},C.gold_soft)
    end
    if active>0 then status(active..' '..L('ACTIVE'),C.gold,C.gold_wash)end
    if self.pending_n>0 then status(self.pending_n..' '..L('PENDING'),C.pending,C.pending_soft)end
end

-- A vertical list with virtual scrolling. opts: {x, y, w, h, count, row_h, selected, scroll_key, draw(i, x, y, w, h),
-- click(i), focused, after(i, x, y, w, h) (controls drawn over the row's click region)}. Returns nothing; keeps the
-- selection in view.
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
        -- controls inside the row (a button) register after the row, so they take its clicks
        if opts.after then opts.after(i,opts.x,y,opts.w,opts.row_h)end
    end
    -- scrollbar: drawn thin, grabbed wide; click the track to jump, drag to scroll
    if opts.count>rows then
        local track_y,track_h=opts.y+2,opts.h-4
        local thumb_h=math.max(24,track_h*rows/opts.count)
        local t=scroll/math.max(1,opts.count-rows)
        local dragging=self.drag and self.drag.key==opts.scroll_key
        cv:rect(opts.x+opts.w-4,track_y,3,track_h,C.line,3)
        cv:rect(opts.x+opts.w-(dragging and 6 or 4),track_y+(track_h-thumb_h)*t,dragging and 5 or 3,thumb_h,
            (opts.focused or dragging)and C.gold or C.line_strong,4)
        local key,count=opts.scroll_key,opts.count
        local function move(uy)
            local f=(uy-track_y-thumb_h/2)/math.max(1,track_h-thumb_h)
            f=math.max(0,math.min(1,f))
            self[key]=math.floor(f*math.max(0,count-rows)+0.5)
        end
        self.scrollbars=self.scrollbars or{}
        local bar=self.scrollbars[key]or{}
        self.scrollbars[key]=bar
        bar.click=function(_,uy)move(uy);self.drag={key=key,move=move}end
        bar.scroll=function(delta)self[key]=math.max(0,math.min((self[key]or 0)+delta*3,math.max(0,count-rows)))end
        bar.after_list=true
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
    -- the scrollbar above the rows
    if opts.count>rows and self.scrollbars and self.scrollbars[opts.scroll_key]then
        cv:hit(opts.x+opts.w-14,opts.y,14,opts.h,self.scrollbars[opts.scroll_key])
    end
    return rows,scroll
end

function App:draw_categories(y0,h)
    local cv=self.canvas
    cv:rect(0,y0,CAT_W,h,C.panel_alt,1)
    cv:rect(CAT_W-1,y0,1,h,C.line,2)
    self.cat_actions=self.cat_actions or{}
    local cat_marks=self:markers().category
    local focused=self.focus=='categories'
    -- the column's layout; it scrolls when it is taller than the pane (a larger interface size gives the panel less
    -- height): the wheel scrolls it, the selected category stays in view, and only whole rows are drawn
    local pos,yy={},10
    for i,item in ipairs(self.categories)do
        if item.group then yy=yy+(i>1 and 10 or 0);pos[i]={y=yy,h=24};yy=yy+24
        else pos[i]={y=yy,h=31};yy=yy+31 end
    end
    local max_scroll=math.max(0,yy+10-h)
    local scroll=self.cat_scroll or 0
    local sel=pos[self.cat]
    if sel and self.cat_seen~=self.cat then
        self.cat_seen=self.cat
        if sel.y-scroll<10 then scroll=sel.y-10 elseif sel.y+sel.h-scroll>h-10 then scroll=sel.y+sel.h-h+10 end
    end
    scroll=math.max(0,math.min(max_scroll,scroll))
    self.cat_scroll=scroll
    if max_scroll>0 then
        self.cat_scroller=self.cat_scroller or{scroll=function(d)self.cat_scroll=(self.cat_scroll or 0)+d*62 end}
        cv:hit(0,y0,CAT_W,h,self.cat_scroller)
        local track=h-8
        local thumb=math.max(24,track*h/(yy+10))
        cv:rect(CAT_W-5,y0+4+(track-thumb)*scroll/max_scroll,3,thumb,C.line_strong,3)
    end
    for i,item in ipairs(self.categories)do
        local y=y0+pos[i].y-scroll
        local shown=y>=y0 and y+pos[i].h<=y0+h
        if not shown then
            -- outside the pane: not drawn
        elseif item.group then
            cv:text(L(item.label),18,y+11,{size=SZ.heading,font='title',colour=C.faint})
        else
            local rh=31
            local selected=i==self.cat
            local action=self.cat_actions[i]
            if not action then
                local index=i
                action={click=function()self:select_category(index);self.focus='categories'end}
                self.cat_actions[i]=action
            end
            local tone=item.tone and theme.tone[item.tone]
            if selected then
                cv:rect(8,y,CAT_W-16,rh,tone and theme.tone_soft[item.tone]or(focused and C.select or C.gold_wash),2)
                cv:rect(8,y,3,rh,tone or(focused and C.gold or C.gold_dim),3)
            elseif self.hover==action then cv:rect(8,y,CAT_W-16,rh,C.hover,2)end
            if tone and not selected then cv:rect(8,y+9,3,rh-18,tone,3)end
            local count=self.catalog:count(item.id)
            local cw=cv:text(tostring(count),CAT_W-20,y+rh/2,{size=SZ.small,colour=C.faint,align='right'})
            local mx=self:draw_marks(cat_marks[item.id]or{},CAT_W-28-(tonumber(cw)or 24),y+rh/2,26)
            cv:text(L(item.label),22,y+rh/2,{size=SZ.label,colour=selected and C.text or C.dim,
                max=math.min(CAT_W-80,mx-30)})
            cv:hit(8,y,CAT_W-16,rh,action)
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
        cv:text(L('Search   Ctrl+F'),x0+24,sy+16,{size=SZ.small,colour=C.faint})
    else
        local w=cv:text(text,x0+24,sy+16,{size=SZ.label,colour=C.text,max=OBJ_W-60})
        if searching and math.floor(self.time*2)%2==0 then cv:rect(x0+26+w,sy+7,2,18,C.gold,6)end
    end
    self.search_action=self.search_action or{click=function()
        self.search=self.search or{text=''};self.search.active=true;self.focus='objects'end}
    cv:hit(x0+12,sy,OBJ_W-24,32,self.search_action)
    -- the weapon-group filter (Primary and Secondary only), wrapped onto as many rows as it needs
    local ly=sy+44
    local item=category_item(self)
    local groups=item and not item.group and self:weapon_groups(item.id)
    if groups then
        self.group_actions=self.group_actions or{}
        local current=self.weapon_group and self.weapon_group[item.id]or'All'
        local cx,cy=x0+12,sy+40
        for _,g in ipairs(groups)do
            local label=GROUP_LABELS[g]or g
            label=L(label)
            local w=cv:measure(label,SZ.tiny,'title')+18
            if cx+w>x0+OBJ_W-12 then cx,cy=x0+12,cy+28 end
            local key=item.id..'|'..g
            local action=self.group_actions[key]
            if not action then
                local id,group=item.id,g
                action={click=function()self:set_weapon_group(id,group);self.focus='objects'end}
                self.group_actions[key]=action
            end
            local on=g==current
            cv:rect(cx,cy,w,22,on and C.gold or(self.hover==action and C.hover or C.box),3)
            if not on then cv:frame(cx,cy,w,22,C.line_strong,4)end
            cv:text(label,cx+w/2,cy+11,{size=SZ.tiny,font='title',colour=on and C.inverse or C.dim,align='center',z=5})
            cv:hit(cx,cy,w,22,action)
            cx=cx+w+6
        end
        ly=cy+32
    end
    local objects=self:objects()
    self.obj=clamp_index(self.obj,#objects)
    local markers=self:markers()
    local focused=self.focus=='objects'
    self.obj_actions_key=self.obj_actions_key or''
    local akey=tostring(self.cat)..'\0'..(self.search and self.search.text or'')..'\0'
        ..tostring(item and self.weapon_group and self.weapon_group[item.id]or'')
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
            local tone=object.tone and theme.tone[object.tone]
            if selected then
                cv:rect(x+8,y+2,w-16,rh-4,tone and theme.tone_soft[object.tone]or(focused and C.select or C.gold_wash),2)
                cv:rect(x+8,y+2,3,rh-4,tone or(focused and C.gold or C.gold_dim),3)
            elseif self.hover==(self.obj_actions[i])then cv:rect(x+8,y+2,w-16,rh-4,C.hover,2)end
            local tx=x+22
            if self:draw_icon(object,x+18,y+5,rh-10)then tx=x+18+rh end
            cv:text(object.name,tx,y+15,{size=SZ.label,colour=selected and C.text or C.dim,max=w-56-(tx-x)})
            cv:text(object.subtitle or'',tx,y+31,{size=SZ.tiny,colour=C.faint,max=w-56-(tx-x)})
            -- markers, right to left: pending (orange hourglass piece), edited by you (yellow pencil piece), set by
            -- a mod (blue piece)
            self:draw_marks({pending=markers.pending[object.key],editor=markers.editor[object.key],
                mod=markers.mod[object.key]},x+w-10,y+rh/2,34)
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
        cv:text(L('Select a category and an object'),x0+24,y0+40,{size=SZ.label,colour=C.faint})
        return
    end
    -- object header
    local hx=x0+20
    if self:draw_icon(object,x0+20,y0+8,48)then hx=x0+80 end
    cv:text(object.name,hx,y0+24,{size=20,font='title',colour=C.text,max=w-40-(hx-x0)})
    local items,selectable=self:field_items(object)
    local markers=self:markers()
    local edited=0
    for _,row in ipairs(object.rows)do
        local _,source=self:row_view(row)
        if source=='pending'or source=='editor'then edited=edited+1 end
    end
    local sub=(object.subtitle and(object.subtitle..'   ')or'')..(object.detail and object.detail~=''and(object.detail..'   ')or'')
        ..#object.rows..' fields'
        ..(edited>0 and('   '..edited..' edited')or'')
    cv:text(sub,hx,y0+47,{size=SZ.small,colour=C.faint,max=w-40-(hx-x0)})
    if object.error then cv:text(L('Could not read: ')..object.error,x0+20,y0+70,{size=SZ.small,colour=C.error,max=w-40})end
    -- column titles
    local hy=y0+66
    cv:rect(x0,hy,w,22,C.header,2)
    cv:text(L('FIELD'),x0+FX.label,hy+11,{size=SZ.tiny,font='title',colour=C.faint})
    cv:text(L('DEFAULT'),x0+FX.default_right,hy+11,{size=SZ.tiny,font='title',colour=C.faint,align='right'})
    cv:text(L('VALUE'),x0+FX.box+FX.box_w-8,hy+11,{size=SZ.tiny,font='title',colour=C.faint,align='right'})
    cv:text(L('SOURCE'),x0+w+FX.badge_right,hy+11,{size=SZ.tiny,font='title',colour=C.faint,align='right'})
    self.field=clamp_index(self.field,#selectable)
    local selected_item=selectable[self.field]
    local focused=self.focus=='fields'
    local ly=hy+24
    local rh=theme.row_h
    if self.fields_actions_object~=object or self.fields_actions_version~=self.expand_version then
        self.fields_actions,self.fields_actions_object,self.fields_actions_version={},object,self.expand_version
    end
    local actions=self.fields_actions
    self:list({x=x0,y=ly,w=w,h=y0+h-ly-4,count=#items,row_h=rh,selected=selected_item,scroll_key='field_scroll',
        focused=focused,actions=nil,
        draw=function(i,x,y,lw)
            local item=items[i]
            if item.section then
                cv:text(string.upper(L(item.section)),x+FX.label,y+rh/2+3,{size=SZ.tiny,font='title',colour=C.gold_dim,max=lw-120})
                local tw=math.min(cv:measure(string.upper(L(item.section)),SZ.tiny,'title'),lw-120)
                cv:rect(x+FX.label+tw+10,y+rh/2+3,lw-FX.label-tw-24,1,C.line,2)
                return
            end
            if item.header then
                -- a collapsible group (Damage Zones, Attacks, Magazines, a vehicle weapon) or one of its sections
                local selected=i==selected_item
                local action=actions[i]
                if not action then
                    local index,it=i,item
                    action={click=function()
                        for s2,idx in ipairs(selectable)do if idx==index then self.field=s2 end end
                        self.focus='fields'
                        self:toggle_item(it,object)
                    end}
                    actions[i]=action
                end
                cv:hit(x,y,lw,rh,action)
                local indent=FX.label+(item.depth or 0)*20
                if item.depth==0 then cv:rect(x+6,y+2,lw-12,rh-4,C.header,1)end
                if selected then
                    cv:rect(x+6,y+1,lw-12,rh-2,focused and C.select or C.gold_wash,2)
                    cv:rect(x+6,y+1,3,rh-2,focused and C.gold or C.gold_dim,3)
                elseif self.hover==action then cv:rect(x+6,y+1,lw-12,rh-2,C.hover,2)end
                local cy=y+rh/2
                cv:text(item.open and'↓'or'→',x+indent,cy,{size=SZ.small,colour=C.gold,font='title'})
                -- what its fields hold, so an edit inside a closed group is visible without opening it
                local mx=self:draw_marks(self:header_marks(item,markers),x+lw-14,cy,28)
                local right=mx<x+lw-14 and mx-8 or x+lw-18
                local reserve=x+lw-right
                if item.depth==0 then
                    cv:text(string.upper(L(item.header)),x+indent+20,cy,{size=SZ.small,font='title',colour=C.gold,
                        max=lw-indent-170-reserve})
                    cv:text(L('%d parts · %d fields'):format(item.subs,item.count),right,cy,
                        {size=SZ.tiny,colour=C.faint,align='right'})
                else
                    cv:text(L(item.header),x+indent+20,cy,{size=SZ.label,colour=selected and C.text or C.dim,
                        max=lw-indent-150-reserve})
                    cv:text(L('%d fields'):format(item.count),right,cy,{size=SZ.tiny,colour=C.faint,align='right'})
                end
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
            local indent=(item.depth or 0)*20
            cv:text(L(row.label),x+FX.label+indent,cy,{size=SZ.label,colour=row.editable and(selected and C.text or C.dim)or C.faint,
                max=FX.default_right-FX.label-90-indent})
            cv:text(self:text(row,row.vanilla),x+FX.default_right,cy,{size=SZ.small,colour=C.faint,align='right',max=84})
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
                cv:text(self:text(row,value),bx+bw-10,cy,{size=SZ.label,colour=row.editable and colour or C.faint,
                    align='right',max=bw-16})
            end
            local unit=util.unit(row.unit)
            if unit then cv:text(unit,x+FX.unit,cy,{size=SZ.tiny,colour=C.faint,max=56})end
            -- source badge
            local bxr=x+lw+FX.badge_right
            if not row.editable then chip(cv,L('LOCKED'),bxr,cy,C.faint,C.line,'right')
            elseif state=='error'then chip(cv,L('ERROR'),bxr,cy,C.error,C.error_soft,'right')
            elseif source=='pending'then chip(cv,L('PENDING'),bxr,cy,C.pending,C.pending_soft,'right')
            elseif state=='applying'then chip(cv,L('APPLYING'),bxr,cy,C.gold,C.gold_soft,'right')
            elseif source=='editor'then chip(cv,L('EDITED'),bxr,cy,C.gold,C.gold_wash,'right')
            elseif source=='mod'then chip(cv,L('MOD'),bxr,cy,C.mod,C.mod_soft,'right')end
        end})
end

function App:draw_status(y,h)
    local cv=self.canvas
    local P=theme.panel
    cv:rect(0,y,P.w,h,C.header,1)
    cv:rect(0,y,P.w,1,C.line,2)
    local cy=y+h/2
    if self.toast_msg then
        cv:text(self.toast_msg.text,P.w-18,cy,{size=SZ.small,colour=self.toast_msg.colour,align='right',max=520})
    end
    local maxw=self.toast_msg and P.w-580 or P.w-40
    if self.view=='browse'then
        local row=self:focused_row()
        if not row then
            cv:text(L('Pick a field: ↑↓ to move, → to go deeper, Tab to switch panes'),18,cy,{size=SZ.small,colour=C.faint,max=maxw})
            return
        end
        local value,source,state,holder,err=self:row_view(row)
        local parts={}
        local x=18
        if err then
            cv:text(L('Error: ')..err,x,cy,{size=SZ.small,colour=C.error,max=maxw})
            return
        end
        if not row.editable then
            cv:text(L('Locked: ')..tostring(row.reason),x,cy,{size=SZ.small,colour=C.faint,max=maxw})
            return
        end
        local range
        if row.kind=='code'then range=(row.min_length or 1)..' to '..(row.max_length or 9)..' directions'
        elseif row.kind=='uses'then range=(row.unlimited and'unlimited, or 'or'')..(row.min or 1)..' to '..(row.max or 100)
        elseif row.kind=='reference'then range='Enter to pick a donor'
        elseif row.kind then range='Enter to choose, ←→ to step'
        else range=(row.min or row.max)and('range '..util.format(row.min or-math.huge)..' to '..util.format(row.max))or'no published range'end
        x=x+cv:text(tostring(row.field),x,cy,{size=SZ.small,colour=C.dim,max=260})+16
        x=x+cv:text(range..(row.integer and', whole numbers'or''),x,cy,{size=SZ.small,colour=C.faint,max=240})+14
        local shared_names,shared_n=self:shared_names(row,2)
        if row.shared or shared_n>0 then x=x+chip(cv,L('SHARED'),x,cy,C.pending,C.pending_soft)+6 end
        if row.risk=='gameguard'then x=x+chip(cv,L('GAMEGUARD RISK'),x,cy,C.error,C.error_soft)+6 end
        if row.unverified then x=x+chip(cv,L('UNVERIFIED EFFECT'),x,cy,C.faint,C.line)+6 end
        local _,base_holder=self.layer:base(row)
        if row.risk=='gameguard'and not base_holder then
            cv:text(L(catalog_module.GAMEGUARD_RISK),x+10,cy,{size=SZ.small,colour=C.error,max=math.max(40,maxw-x-10)})
            return
        end
        if shared_names and not base_holder then
            x=x+10+cv:text(L('also changes %s'):format(shared_names),x+10,cy,
                {size=SZ.small,colour=C.pending,max=math.max(40,maxw-x-10)})
        end
        if row.note and not base_holder and not shared_names then
            cv:text(L(row.note),x+10,cy,{size=SZ.small,colour=C.faint,max=math.max(40,maxw-x-10)})
        end
        if base_holder then
            x=x+10
            local page=self:option_page_of(base_holder.op)
            cv:text(L('Mod: ')..pretty_mod(base_holder.mod)..' = '..self:text(row,base_holder.value)
                ..(page and('   '..L('set by its in-game options "%s"'):format(page.title or page.id))or''),x,cy,
                {size=SZ.small,colour=C.mod,max=math.max(40,maxw-x)})
        end
    elseif self.view=='mods'then
        cv:text(L('Every deployed mod. HD2Runtime mods show their in-game options and the values they applied; the editor overrides them only when you apply an edit.'),
            18,cy,{size=SZ.small,colour=C.faint,max=maxw})
    elseif self.view=='changes'then
        cv:text(L('Enter jumps to the field. RESET or Backspace resets a change now; Del or right-click stages it (Apply to write it).'),
            18,cy,{size=SZ.small,colour=C.faint,max=maxw})
    elseif self.view=='custom'then
        cv:text(L('Custom stratagems other mods registered. Cooldown and uses can be tuned on this machine.'),
            18,cy,{size=SZ.small,colour=C.faint,max=maxw})
    elseif self.view=='export'then
        cv:text(L('Turns your changes into a mod for your mod manager, in Documents\\HD2R Editor\\Exports.'),
            18,cy,{size=SZ.small,colour=C.faint,max=maxw})
    elseif self.view=='logs'then
        cv:text(L('HD2Runtime.log, live. ←→ filter, ↑↓ select (scrolling up stops following; End follows again).'),
            18,cy,{size=SZ.small,colour=C.faint,max=maxw})
    elseif self.view=='settings'then
        cv:text(L('Settings are saved with the editor\'s data and apply at once.'),
            18,cy,{size=SZ.small,colour=C.faint,max=maxw})
    else
        cv:text(L('Presets store field values by name; loading one stages them as pending changes.'),
            18,cy,{size=SZ.small,colour=C.faint,max=maxw})
    end
end

function App:draw_footer(y,h)
    local cv=self.canvas
    local P=theme.panel
    cv:rect(0,y,P.w,h,C.footer,1)
    cv:rect(0,y,P.w,1,C.line_strong,2)
    local hint
    if self.edit then hint=L('Type a number   Backspace erase   Tab / ↑↓ confirm   Del cancel')
    elseif self.search and self.search.active then hint=L('Type to filter   Backspace erase   Tab done   Del clear')
    elseif self.rename then hint=L('Type a name   Tab save   Del cancel')
    elseif self.view=='browse'and self.focus=='fields'then
        hint=L('F8 close   ←→ adjust (Shift x10, Ctrl ÷10)   digits type a value   Del revert   F9 apply')
    else hint=L('F8 close   ↑↓ select   ←→ panes   Tab next pane   Shift+Tab next tab   F9 apply') end
    -- the key chosen in Settings (the translated hints keep naming F8)
    if self:hotkey()~='F8'then hint=hint:gsub('F8',(self:hotkey():gsub('%%','%%%%')),1)end
    local hw=cv:text(hint,18,y+h/2,{size=SZ.small,colour=C.faint,max=P.w-560})
    -- the wheel is off (the player's HD2Runtime install choice): say how to scroll, after the hints
    if self:wheel_notice()then
        cv:text(L('Wheel off: PgUp / PgDn or the scrollbar'),18+hw+18,y+h/2,
            {size=SZ.small,colour=C.pending,max=math.max(40,P.w-560-hw-18)})
    end
    local bh=34
    local by=y+(h-bh)/2
    local bx=P.w-14
    local active=self.layer:counts()
    self.btn_reset=self.btn_reset or{click=function()self:ask('reset')end}
    self.btn_discard=self.btn_discard or{click=function()self:discard()end}
    self.btn_apply=self.btn_apply or{click=function()self:apply()end}
    local w=196
    bx=bx-w
    button(self,L('RESET TO DEFAULTS'),bx,by,w,bh,(active>0 or self.pending_n>0)and'danger'or'disabled',self.btn_reset)
    w=110;bx=bx-w-10
    button(self,L('DISCARD'),bx,by,w,bh,self.pending_n>0 and'normal'or'disabled',self.btn_discard)
    w=150;bx=bx-w-10
    button(self,self.pending_n>0 and('APPLY  '..self.pending_n)or'APPLY',bx,by,w,bh,
        self.pending_n>0 and'primary'or'disabled',self.btn_apply)
end

function App:draw_confirm()
    local c=self.confirm
    if not c then return end
    local cv=self.canvas
    local P=theme.panel
    cv:rect(0,0,P.w,P.h,C.scrim,8)
    local w,h=560,190
    local x,y=(P.w-w)/2,(P.h-h)/2-40
    cv:rect(x,y,w,h,C.panel_alt,9)
    cv:frame(x,y,w,h,C.line_strong,10)
    cv:rect(x,y,w,3,c.kind=='reset'and C.error or C.gold,10)
    local title,body
    if c.kind=='reset'then
        local active=self.layer:counts()
        title=L('RESET TO DEFAULTS?')
        body={L('Every field the editor changed goes back to the value its mod applies,'),
            L('or to the game\'s own value.')..' '..L('%d active, %d pending.'):format(active,self.pending_n)}
    elseif c.kind=='delete_preset'then
        title=L('DELETE PRESET?');body={L('"%s" will be removed from your saved presets.'):format(tostring(c.data))}
    elseif c.kind=='overwrite_preset'then
        title=L('OVERWRITE PRESET?');body={L('"%s" will be replaced with the current values.'):format(tostring(c.data))}
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
    modal_button(L('CANCEL'),x+w-24-bw*2-12,'normal',self.btn_cancel)
    modal_button(L('CONFIRM'),x+w-24-bw,'danger',self.btn_confirm)
    cv:text(L('Enter / Ins confirm   Esc / Del cancel'),x+24,by+bh/2,{size=SZ.tiny,colour=C.faint,z=11})
end

------------------------------------------------------------------------------------------------- mods view --
-- (the list and the view are in ui/views.lua)
-- Jump to the field of a mod's write in Browse.
function App:open_mod_write(mod,index)
    local claim=mod and mod.writes[index]
    if not claim or not claim.object then return end
    local row=self.catalog:find(claim.object,claim.loc,claim.descriptor)
    if not row then self:toast(L('That field is not in the editor catalogue'),C.dim);return end
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
---------------------------------------------------------------------------------------------- presets view --
function App:current_values()
    local values=self.layer:overrides()
    for key,p in pairs(self.pending)do values[key]=p.value end
    return values
end
-- The game's own icon of a stratagem or booster (tools/game_icons.py; HD2Runtime r50 d:image), coloured as the
-- loadout screen colours it. False when there is none (the layout keeps its text-only form).
local STRATAGEM_FAMILIES={st=true,sp=true,sb=true,ve=true,rs=true}
function App:draw_icon(object,x,y,size)
    if type(self.canvas.d.image)~='function'then return false end
    local icons=self.ctx.icons
    local family=tostring(object.key):match('^(%a+)|')
    local entry
    if icons and STRATAGEM_FAMILIES[family]then entry=icons.stratagems[object.stratagem or object.name]
    elseif icons and family=='bo'then entry=icons.boosters[object.name]end
    if entry and entry.game then
        -- the game's own HUD icon through HD2Runtime: a stratagem's category layer in its category colour, the white
        -- layer white; a booster as the Runtime draws it (its yellow plate)
        if family=='bo'then self.canvas:image(entry.handle,x,y,size,size,{z=4})
        else
            local tone=object.tone and theme.tone[object.tone]or C.gold
            self.canvas:image(entry.handle,x,y,size,size,{colours={r=tone,g={255,255,238,255},b={0,0,0,0}},z=4})
        end
        return true
    end
    if entry then
        -- the game's HUD sprite: R in its accent, G white, B (a booster's glyph) in its own measured colour
        self.canvas:image(entry.handle,x,y,size,size,
            {colours={r=entry.accent,g={255,255,238,255},b=entry.dark or{0,0,0,0}},z=4})
        return true
    end
    -- a stratagem or booster the game has no icon for: a plain square in its category colour (never made-up art)
    if (icons and STRATAGEM_FAMILIES[family])or family=='bo'then
        local tone=object.tone and theme.tone[object.tone]or(family=='bo'and{255,221,31,255})or C.gold
        self.canvas:rect(x+size*0.18,y+size*0.18,size*0.64,size*0.64,tone,4)
        return true
    end
    return false
end
-- One of the editor's own mask icons (images/ui_<name>.png) in a colour; false when it is not available.
function App:draw_ui_icon(name,x,y,size,colour)
    local ui=self.ctx.ui_icons
    local handle=ui and ui[name]
    if not handle or type(self.canvas.d.image)~='function'then return false end
    self.canvas:image(handle,x,y,size,size,{colours={r=colour,g=colour},z=5})
    return true
end
-- A value's text for a row (its labels, arrows for codes, names for references).
function App:text(row,value)return catalog_module.text(row,value)end
-- Values by key as presets and the saved session store them (reference handles by what names them).
function App:encode_values(values)
    local out={}
    for key,value in pairs(values)do
        local row=self.catalog:row(key)
        local stored=row and catalog_module.encode(row,value)
        if stored~=nil then out[key]=stored end
    end
    return out
end
function App:decode_value(key,stored)
    local row=self.catalog:row(key)
    if not row or not row.editable then return nil end
    return row,catalog_module.decode(self.catalog,row,stored)
end
function App:save_preset(name,confirmed)
    local values=self:current_values()
    if next(values)==nil then self:toast(L('Nothing to save: edit a field first'),C.dim);return end
    if not confirmed and self.presets:find(name)then self:ask('overwrite_preset',name);return end
    local ok,why=self.presets:save(name,self:encode_values(values))
    if ok then self:toast(L('Saved preset ')..name..' ('..util.count(values)..' fields)',C.ok)
    else self:toast(L('Could not save: ')..tostring(why),C.error)end
end
function App:load_preset(name)
    local values=self.presets:load(name)
    if not values then return end
    local missing=self:stage_map(values)
    self:toast(L('Loaded ')..name..': '..self.pending_n..' pending'..(missing>0 and(', '..missing..' unknown fields skipped')or'')
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
    if ok then self:toast(L('Renamed to ')..r.text,C.ok)else self:toast(tostring(why),C.error)end
end
local PRESET_ACTIONS={'LOAD','SAVE OVER','RENAME','SHARE','DELETE'}
function App:preset_action_run(index,preset)
    if not preset then return end
    local a=PRESET_ACTIONS[index]
    if a=='LOAD'then self:load_preset(preset.name)
    elseif a=='SAVE OVER'then self:save_preset(preset.name)
    elseif a=='RENAME'then self.rename={old=preset.name,text=preset.name}
    elseif a=='SHARE'then self:share_preset(preset)
    elseif a=='DELETE'then self:ask('delete_preset',preset.name)end
end
--------------------------------------------------------------------------------------- shared preset files --
-- The shared folder's preset files (editor/preset_files.lua), listed again every few seconds while the tab shows
-- them, so a file dropped into the folder appears by itself.
function App:preset_files()
    if not self.pf_list or self.time-(self.pf_time or-99)>3 then
        self.pf_list=preset_files.list(preset_files.folder(),win.list)
        self.pf_time=self.time
    end
    return self.pf_list
end
-- A preset as a file in the shared folder, with each field's name for people reading it.
function App:share_preset(preset)
    local folder=preset_files.folder()
    if not folder then self:toast(L('No Documents folder (%USERPROFILE%)'),C.error);return end
    local values,labels={},{}
    for _,item in ipairs(preset.fields or{})do
        values[item.k]=item.v
        local row=self.catalog:row(item.k)
        if row then labels[item.k]=row.object.name..' · '..row.label end
    end
    local ok,path=pcall(preset_files.save,folder,preset.name,values,labels,
        {editor=self.ctx.version,runtime=self.ctx.minimum},win.mkdir)
    if not ok then self:toast(L('Not shared: %s'):format(tostring(path)),C.error);return end
    self.pf_list=nil
    self:toast(L('Shared as %s'):format(path),C.ok)
    if self.ctx.log then self.ctx.log('shared the preset '..preset.name..' as '..path)end
end
-- A file's preset, read once per size: {preset, error}.
function App:preset_file_open(f)
    local key=f.path..'@'..tostring(f.size)
    if self.pf_key~=key then
        local preset,why=preset_files.load(f.path)
        self.pf_open,self.pf_key,self.detail_scroll={preset=preset,error=preset==nil and tostring(why)or nil},key,0
    end
    return self.pf_open
end
local FILE_ACTIONS={'LOAD','SAVE AS PRESET'}
function App:preset_file_action_run(index,f)
    local open=self:preset_file_open(f)
    if not open.preset then self:toast(tostring(open.error),C.error);return end
    local p=open.preset
    if FILE_ACTIONS[index]=='LOAD'then
        local missing=self:stage_map(p.values)
        self:toast(L('Loaded ')..p.name..': '..self.pending_n..' pending'..(missing>0 and(', '..missing..' unknown fields skipped')or'')
            ..'. Press Apply.',missing>0 and C.pending or C.ok)
    else
        local name=self.presets:unique_name(p.name)
        local ok,why=self.presets:save(name,p.values)
        if ok then self:toast(L('Saved preset ')..name..' ('..util.count(p.values)..' fields)',C.ok)
        else self:toast(L('Could not save: ')..tostring(why),C.error)end
    end
end
-- A preset file from anywhere: the Windows open-file dialog, then a copy into the shared folder.
function App:preset_file_pick()
    if self.pf_picking then return end
    local job,why=win.pick_file({title=L('Choose a preset file'),
        filter=L('HD2R Editor presets')..' (*.hd2rpreset.json)|*.hd2rpreset.json;*.json|',folder=preset_files.folder()})
    if not job then self:toast(L('The Windows file dialog did not open (%s)'):format(tostring(why)),C.error);return end
    self.pf_picking=job
end
function App:preset_file_poll()
    local job=self.pf_picking
    if not job then return end
    local result=job.poll()
    if result==nil then return end
    self.pf_picking=nil
    if not result then return end
    local path,preset=preset_files.import(result,preset_files.folder(),win.mkdir)
    if not path then self:toast(L('Not imported: %s'):format(tostring(preset)),C.error);return end
    self.pf_list=nil
    self:toast(L('Imported %s into the shared folder'):format(path:match('([^\\]+)$')or path),C.ok)
end
function App:new_preset()
    if next(self:current_values())==nil then self:toast(L('Nothing to save: edit a field first'),C.dim);return end
    self.rename={create=true,text=self.presets:unique_name('Preset')}
end
------------------------------------------------------------------------------------- ModBuilder projects --
-- ModBuilder's library (editor/modbuilder.lua), read when the Presets tab first lists it and on REFRESH.
function App:mb_projects()
    if not self.mb_list then
        local list,why=modbuilder.projects()
        self.mb_list,self.mb_error=list or{},why
    end
    return self.mb_list
end
-- A project's edits, read once per saved version: {items, error}.
function App:mb_open_project(p)
    local key=p.id..'@'..p.modified
    if self.mb_key~=key then
        local project,why=modbuilder.read(p.id)
        local open={items={},error=project==nil and tostring(why)or nil}
        if project then
            local ok,items=pcall(modbuilder.items,self.catalog,project)
            if ok then open.items=items else open.error=tostring(items)end
        end
        self.mb_open,self.mb_key,self.mb_scroll=open,key,0
    end
    return self.mb_open
end
function App:mb_select(open,on)
    for _,it in ipairs(open.items)do if it.row and not it.why then it.selected=on end end
end
-- Stages the chosen edits like any other change (Apply writes them).
function App:mb_stage(open,name)
    local n,failed=0,0
    for _,it in ipairs(open.items)do
        if it.selected and it.row and not it.why then
            if self:stage_value(it.row,it.value)then n=n+1 else failed=failed+1 end
        end
    end
    if n==0 and failed==0 then self:toast(L('Nothing chosen to stage'),C.dim);return end
    self:toast(L('Staged %d values from %s. Press Apply.'):format(n,name)..(failed>0 and(' '..L('%d refused'):format(failed))or''),
        failed>0 and C.pending or C.ok)
    self:sound('click')
end
-- The Presets list: the new preset, the presets, the shared files (under their header), ModBuilder's projects (under
-- theirs). Built again when a frame passes or any of the lists changes.
function App:preset_entries()
    local presets,files,projects=self.presets:list(),self:preset_files(),self:mb_projects()
    local key=tostring(self.time)..'|'..#presets
    if not self.pe_list or self.pe_key~=key or self.pe_files~=files or self.pe_projects~=projects then
        local out={{kind='new'}}
        for _,p in ipairs(presets)do out[#out+1]={kind='preset',preset=p}end
        out[#out+1]={kind='file_header'}
        for _,f in ipairs(files)do out[#out+1]={kind='file',file=f}end
        out[#out+1]={kind='mb_header'}
        for _,p in ipairs(projects)do out[#out+1]={kind='mb',project=p}end
        self.pe_list,self.pe_key,self.pe_files,self.pe_projects=out,key,files,projects
    end
    return self.pe_list
end
-- The list index of the first entry of a kind ('file_header', 'mb_header', ...), or nil.
function App:preset_index_of(kind)
    for i,e in ipairs(self:preset_entries())do if e.kind==kind then return i end end
    return nil
end
function App:preset_entry(i)return self:preset_entries()[i]or{kind='new'}end
function App:preset_count()return #self:preset_entries()end
local MB_ACTIONS={'STAGE CHOSEN','CHOOSE ALL','CHOOSE NONE'}
function App:mb_action_run(index,p)
    local open=self:mb_open_project(p)
    local a=MB_ACTIONS[index]
    if a=='STAGE CHOSEN'then self:mb_stage(open,p.name)
    elseif a=='CHOOSE ALL'then self:mb_select(open,true)
    else self:mb_select(open,false)end
end
function App:handle_presets_keys(f)
    local k=f.keys
    local list=self.presets:list()
    local n=self:preset_count()
    if k.UP then self.preset_index=clamp_index(self.preset_index-1,n)end
    if k.DOWN then self.preset_index=clamp_index(self.preset_index+1,n)end
    local entry=self:preset_entry(self.preset_index)
    local actions=entry.kind=='mb'and MB_ACTIONS or entry.kind=='file'and FILE_ACTIONS or PRESET_ACTIONS
    if k.LEFT then self.preset_action=clamp_index(self.preset_action-1,#actions)end
    if k.RIGHT then self.preset_action=clamp_index(self.preset_action+1,#actions)end
    self.preset_action=clamp_index(self.preset_action,#actions)
    if k.INSERT then self:new_preset()end
    if k.ENTER then
        if entry.kind=='new'then self:new_preset()
        elseif entry.kind=='preset'then self:preset_action_run(self.preset_action,entry.preset)
        elseif entry.kind=='mb'then self:mb_action_run(self.preset_action,entry.project)
        elseif entry.kind=='file'then self:preset_file_action_run(self.preset_action,entry.file)
        elseif entry.kind=='file_header'then self:preset_file_pick()
        else self.mb_list=nil end
    end
    if k.DELETE and entry.kind=='preset'then self:ask('delete_preset',entry.preset.name)end
end
function App:draw_presets(y0,h)
    local cv=self.canvas
    local P=theme.panel
    local n=self:preset_count()
    self.preset_index=clamp_index(self.preset_index,n)
    self:preset_file_poll()
    cv:rect(0,y0,PRESETS_W,h,C.panel_alt,1)
    cv:rect(PRESETS_W-1,y0,1,h,C.line,2)
    cv:text(L('PRESETS'),18,y0+20,{size=SZ.heading,font='title',colour=C.faint})
    if not self.presets:available()then
        cv:text(L('Saved data needs a newer HD2Runtime (hd2.store).'),18,y0+52,{size=SZ.small,colour=C.error,max=PRESETS_W-36})
        return
    end
    self.preset_actions=self.preset_actions or{}
    local bottom=y0+h-118
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
                    cv:text(L('+  NEW PRESET FROM CURRENT VALUES'),x+22,y+rh/2,{size=SZ.tab,font='title',colour=C.gold,max=w-44})
                end
                return
            end
            local entry=self:preset_entry(i)
            if entry.kind=='file_header'then
                cv:text(L('SHARED PRESET FILES'),x+22,y+rh/2,{size=SZ.tab,font='title',colour=C.faint,max=w-120})
                cv:text(tostring(#self:preset_files()),x+w-22,y+rh/2,{size=SZ.small,colour=C.faint,align='right'})
                return
            elseif entry.kind=='file'then
                local f=entry.file
                cv:text(f.name,x+22,y+17,{size=SZ.label,colour=selected and C.text or C.dim,max=w-60})
                cv:text(L('file')..'   '..string.format('%.1f KB',(f.size or 0)/1024),x+22,y+35,{size=SZ.tiny,colour=C.faint,max=w-44})
                return
            elseif entry.kind=='mb_header'then
                cv:text(L('MODBUILDER PROJECTS'),x+22,y+rh/2,{size=SZ.tab,font='title',colour=C.faint,max=w-120})
                cv:text(tostring(#self:mb_projects()),x+w-22,y+rh/2,{size=SZ.small,colour=C.faint,align='right'})
                return
            elseif entry.kind=='mb'then
                local mp=entry.project
                cv:text(mp.name,x+22,y+17,{size=SZ.label,colour=selected and C.text or C.dim,max=w-60})
                cv:text(tostring(mp.resource or'')..'   '..mp.modified:sub(1,10),x+22,y+35,{size=SZ.tiny,colour=C.faint,max=w-44})
                return
            end
            local p=entry.preset
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
    cv:text(L('Restore my last applied values when the game starts'),tx+46,ty,{size=SZ.small,colour=C.dim,max=PRESETS_W-80})
    cv:hit(tx,ty-12,PRESETS_W-36,24,self.toggle_restore)
    -- the cursor capture (HD2Runtime r50, experimental)
    if self.ctx.set_free_cursor then
        local free=self.presets:setting('free_cursor',true)
        self.toggle_cursor=self.toggle_cursor or{click=function()
            local on=not self.presets:setting('free_cursor',true)
            self.presets:set_setting('free_cursor',on)
            self.ctx.set_free_cursor(on)
        end}
        local cy2=ty+28
        cv:rect(tx,cy2-9,34,18,free and C.gold or C.line_strong,3)
        cv:rect(free and tx+18 or tx+2,cy2-7,14,14,free and C.inverse or C.dim,4)
        cv:text(L('Free the mouse from the camera while open (experimental)'),tx+46,cy2,{size=SZ.small,colour=C.dim,max=PRESETS_W-80})
        cv:hit(tx,cy2-12,PRESETS_W-36,24,self.toggle_cursor)
    end
    cv:text(L('Open the editor with ')..self:hotkey()..'. Edits apply live through HD2Runtime\'s guarded writes.',
        18,sy+70,{size=SZ.tiny,colour=C.faint,max=PRESETS_W-36})
    -- detail
    local x0=PRESETS_W
    local w=P.w-x0
    cv:rect(x0,y0,w,h,C.panel,1)
    if self.preset_index==1 then
        local values=self:current_values()
        cv:text(L('NEW PRESET'),x0+20,y0+24,{size=20,font='title',colour=C.text})
        cv:text(util.count(values)..' fields would be saved: every applied editor value and every pending change.',
            x0+20,y0+47,{size=SZ.small,colour=C.faint,max=w-40})
        self.btn_new=self.btn_new or{click=function()self:new_preset()end}
        button(self,L('SAVE AS NEW PRESET'),x0+20,y0+72,230,34,next(values)and'primary'or'disabled',self.btn_new)
        self:draw_value_list(values,x0,y0+124,w,y0+h-y0-128)
        return
    end
    local entry=self:preset_entry(self.preset_index)
    if entry.kind=='file_header'then return self:draw_files_header(x0,y0,w,h)end
    if entry.kind=='file'then return self:draw_preset_file(entry.file,x0,y0,w,h)end
    if entry.kind=='mb_header'then return self:draw_mb_header(x0,y0,w,h)end
    if entry.kind=='mb'then return self:draw_mb_project(entry.project,x0,y0,w,h)end
    local p=entry.preset
    cv:text(p.name,x0+20,y0+24,{size=20,font='title',colour=C.text,max=w-40})
    cv:text(p.count..' fields',x0+20,y0+47,{size=SZ.small,colour=C.faint})
    self.preset_btns=self.preset_btns or{}
    local bx=x0+20
    for i,label in ipairs(PRESET_ACTIONS)do
        local action=self.preset_btns[i]
        if not action then
            local index=i
            action={click=function()
                self.preset_action=index
                local e=self:preset_entry(self.preset_index)
                if e.kind=='preset'then self:preset_action_run(index,e.preset)end
            end}
            self.preset_btns[i]=action
        end
        local bw=cv:measure(L(label),SZ.tab,'title')+40
        local style=(i==1 and'primary')or(label=='DELETE'and'danger')or'normal'
        button(self,L(label),bx,y0+72,bw,34,style,action)
        if i==self.preset_action then cv:rect(bx,y0+108,bw,2,C.gold,5)end
        bx=bx+bw+10
    end
    local values={}
    for _,item in ipairs(p.fields or{})do values[item.k]=item.v end
    self:draw_value_list(values,x0,y0+124,w,y0+h-y0-128)
end
function App:draw_files_header(x0,y0,w,h)
    local cv=self.canvas
    cv:text(L('SHARED PRESET FILES'),x0+20,y0+24,{size=20,font='title',colour=C.text})
    local lines={L('Presets as files, to share with other players. The editor lists this folder:'),
        tostring(preset_files.folder()or L('(no %USERPROFILE%)')),'',
        L('SHARE on a preset writes it here. Put a file someone sent you here (or use IMPORT A FILE) and it shows up.'),
        L('Pick a file to see its values; LOAD stages them, SAVE AS PRESET keeps them with your presets.')}
    for i,line in ipairs(lines)do
        cv:text(line,x0+20,y0+56+(i-1)*22,{size=SZ.small,colour=i==2 and C.dim or C.faint,max=w-40})
    end
    self.btn_pf_import=self.btn_pf_import or{click=function()self:preset_file_pick()end}
    self.btn_pf_open=self.btn_pf_open or{click=function()
        local folder=preset_files.folder()
        if folder then win.mkdir(folder)end
        local ok,why=win.open(folder or'')
        if not ok then self:toast(L('Could not open it: %s'):format(tostring(why)),C.error)end
    end}
    button(self,self.pf_picking and L('CHOOSE IN THE WINDOWS DIALOG...')or L('IMPORT A FILE'),x0+20,y0+200,300,34,
        'primary',self.btn_pf_import)
    button(self,L('OPEN THE FOLDER'),x0+332,y0+200,220,34,'normal',self.btn_pf_open)
end
function App:draw_preset_file(f,x0,y0,w,h)
    local cv=self.canvas
    local open=self:preset_file_open(f)
    local p=open.preset
    cv:text(p and p.name or f.name,x0+20,y0+24,{size=20,font='title',colour=C.text,max=w-40})
    if not p then
        cv:text(L('Could not read this file: %s'):format(tostring(open.error)),x0+20,y0+47,{size=SZ.small,colour=C.error,max=w-40})
        return
    end
    local info=f.name..'   '..util.count(p.values)..' fields'..(p.editor and('   '..L('from editor %s'):format(p.editor))or'')
        ..(p.skipped>0 and('   '..L('%d unreadable fields skipped'):format(p.skipped))or'')
    cv:text(info,x0+20,y0+47,{size=SZ.small,colour=C.faint,max=w-40})
    self.pf_btns=self.pf_btns or{}
    local bx=x0+20
    for i,label in ipairs(FILE_ACTIONS)do
        local action=self.pf_btns[i]
        if not action then
            local index=i
            action={click=function()
                self.preset_action=index
                local e=self:preset_entry(self.preset_index)
                if e.kind=='file'then self:preset_file_action_run(index,e.file)end
            end}
            self.pf_btns[i]=action
        end
        local bw=cv:measure(L(label),SZ.tab,'title')+40
        button(self,L(label),bx,y0+72,bw,34,i==1 and'primary'or'normal',action)
        if i==self.preset_action then cv:rect(bx,y0+108,bw,2,C.gold,5)end
        bx=bx+bw+10
    end
    self:draw_value_list(p.values,x0,y0+124,w,y0+h-y0-128)
end
function App:draw_mb_header(x0,y0,w,h)
    local cv=self.canvas
    cv:text(L('MODBUILDER PROJECTS'),x0+20,y0+24,{size=20,font='title',colour=C.text})
    local lines={L('Your HD2Runtime ModBuilder projects, read from its library on this PC:'),
        tostring(modbuilder.root()or L('(no %LOCALAPPDATA%)')),'',
        L('Pick one to see its edits as editor fields, choose which to stage, then Apply.'),
        L('Edits the editor cannot take are listed with the reason (scripts and custom content stay in ModBuilder).'),'',
        L('To send your changes to ModBuilder: Export tab, then SAVE TO MODBUILDER.')}
    for i,line in ipairs(lines)do
        cv:text(line,x0+20,y0+56+(i-1)*22,{size=SZ.small,colour=i==2 and C.dim or C.faint,max=w-40})
    end
    if self.mb_error then cv:text(tostring(self.mb_error),x0+20,y0+230,{size=SZ.small,colour=C.error,max=w-40})end
    self.btn_mb_refresh=self.btn_mb_refresh or{click=function()self.mb_list,self.mb_key=nil,nil end}
    button(self,L('REFRESH'),x0+20,y0+260,160,34,'normal',self.btn_mb_refresh)
end
function App:draw_mb_project(p,x0,y0,w,h)
    local cv=self.canvas
    local open=self:mb_open_project(p)
    local ok_n,chosen=0,0
    for _,it in ipairs(open.items)do
        if it.row and not it.why then ok_n=ok_n+1 end
        if it.selected and it.row and not it.why then chosen=chosen+1 end
    end
    cv:text(p.name,x0+20,y0+24,{size=20,font='title',colour=C.text,max=w-40})
    cv:text(L('%s   ModBuilder project, SDK %s   %d of %d edits can be staged'):format(tostring(p.resource or''),
        tostring(p.sdk or'?'),ok_n,#open.items),x0+20,y0+47,{size=SZ.small,colour=C.faint,max=w-40})
    self.mb_btns=self.mb_btns or{}
    local bx=x0+20
    for i,label in ipairs(MB_ACTIONS)do
        local action=self.mb_btns[i]
        if not action then
            local index=i
            action={click=function()
                self.preset_action=index
                local e=self:preset_entry(self.preset_index)
                if e.kind=='mb'then self:mb_action_run(index,e.project)end
            end}
            self.mb_btns[i]=action
        end
        local text=i==1 and(L(label)..'  ('..chosen..')')or L(label)
        local bw=cv:measure(text,SZ.tab,'title')+40
        button(self,text,bx,y0+72,bw,34,i==1 and(chosen>0 and'primary'or'disabled')or'normal',action)
        if i==self.preset_action then cv:rect(bx,y0+108,bw,2,C.gold,5)end
        bx=bx+bw+10
    end
    local y=y0+124
    if open.error then
        cv:text(L('Could not read this project: %s'):format(open.error),x0+20,y+12,{size=SZ.small,colour=C.error,max=w-40})
        return
    end
    cv:rect(x0,y,w,22,C.header,2)
    cv:text(L('EDIT'),x0+46,y+11,{size=SZ.tiny,font='title',colour=C.faint})
    cv:text(L('VALUE'),x0+w-18,y+11,{size=SZ.tiny,font='title',colour=C.faint,align='right'})
    self.mb_item_actions=self.mb_item_actions or{}
    self:list({x=x0,y=y+24,w=w,h=y0+h-y-28,count=#open.items,row_h=28,scroll_key='mb_scroll',focused=false,
        actions=self.mb_item_actions,
        click=function(i)
            local it=self.mb_open.items[i]
            if it and it.row and not it.why then it.selected=not it.selected end
        end,
        draw=function(i,x,ry,lw,rh)
            local it=open.items[i]
            local cy=ry+rh/2
            local usable=it.row and not it.why
            if usable then
                cv:rect(x+18,cy-7,14,14,it.selected and C.gold or C.line_strong,3)
                if not it.selected then cv:rect(x+20,cy-5,10,10,C.panel,4)end
            end
            local tx=x+46
            if it.row then
                local nw=cv:text(it.row.object.name,tx,cy,{size=SZ.small,colour=C.faint,max=(lw-260)*0.45})
                cv:text(L(it.row.label),tx+12+nw,cy,{size=SZ.small,colour=usable and C.dim or C.faint,max=lw-330-nw})
            else
                cv:text(it.label,tx,cy,{size=SZ.small,colour=C.faint,max=lw-330})
            end
            if usable then
                cv:text(self:text(it.row,it.value),x+lw-18,cy,{size=SZ.label,colour=C.gold,align='right',max=260})
            else
                cv:text(tostring(it.why),x+lw-18,cy,{size=SZ.tiny,colour=C.error,align='right',max=300})
            end
        end})
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
    cv:text(L('FIELD'),x0+18,y+11,{size=SZ.tiny,font='title',colour=C.faint})
    cv:text(L('VALUE'),x0+w-18,y+11,{size=SZ.tiny,font='title',colour=C.faint,align='right'})
    self:list({x=x0,y=y+24,w=w,h=h-24,count=#rows,row_h=28,scroll_key='detail_scroll',focused=false,
        draw=function(i,x,ry,lw,rh)
            local item=rows[i]
            local cy=ry+rh/2
            if item.row then
                local name=item.row.object.name
                local nw=cv:text(name,x+18,cy,{size=SZ.small,colour=C.faint,max=(lw-140)*0.45})
                cv:text(L(item.row.label),x+30+nw,cy,{size=SZ.small,colour=C.dim,max=lw-170-nw})
            else
                cv:text(L('Unknown field: ')..item.key,x+18,cy,{size=SZ.small,colour=C.faint,max=lw-140})
            end
            cv:text(item.row and self:text(item.row,item.value)or util.value_text(item.value),x+lw-18,cy,
                {size=SZ.label,colour=C.gold,align='right',max=170})
        end})
end

---------------------------------------------------------------------------------------------- main draw --
function App:draw()
    local cv=self.canvas
    local P=theme.panel
    -- frame and shadow
    cv:rect(-4,-4,P.w+8,P.h+8,C.shadow,0)
    cv:rect(0,0,P.w,P.h,C.panel,0)
    self:draw_header()
    local body_y=theme.header_h
    local body_h=P.h-theme.header_h-theme.footer_h-theme.status_h
    if self.view=='browse'then
        self:draw_categories(body_y,body_h)
        self:draw_objects(body_y,body_h)
        self:draw_fields(body_y,body_h)
    elseif self.view=='changes'then self:draw_changes(body_y,body_h)
    elseif self.view=='mods'then self:draw_mods(body_y,body_h)
    elseif self.view=='custom'then self:draw_custom(body_y,body_h)
    elseif self.view=='settings'then self:draw_settings(body_y,body_h)
    elseif self.view=='logs'then self:draw_logs(body_y,body_h)
    elseif self.view=='export'then self:draw_export(body_y,body_h)
    else self:draw_presets(body_y,body_h)end
    self:draw_status(body_y+body_h,theme.status_h)
    self:draw_footer(P.h-theme.footer_h,theme.footer_h)
    cv:rect(0,0,3,P.h,C.rail,7)
    self:draw_confirm()
    self:draw_picker()
    self:draw_code()
    self:draw_modes()
    self:draw_rates()
    self:draw_traits()
end

views.install(App)
export_view.install(App)

return M

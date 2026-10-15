-- Enumerate display text from the configured public Runtime, without a running game.
local root='mods/skyeshade/hd2runtime_editor/editor/'
local hd2=require('hd2runtime/api/hd2')
local module=require(root..'catalog')
local names=require(root..'game_names')
local sections=require(root..'ui/sections')
local i=require(root..'i18n')
local builtin=require(root..'locale').cn
local catalog=module.new(hd2)
while not catalog:index_step(500)do end
assert(i.use('简体中文',{}))
local rows={}
local function add(text,role,object,field)
    if type(text)~='string'then return end
    text=text:gsub('^%s+',''):gsub('%s+$','')
    if text==''or text:find('[\r\n]')or not text:find('%a')then return end
    local r=rows[text]
    if not r then r={text=text,roles={},contexts={},exact=builtin[text]~=nil,display=i.L(text)};rows[text]=r end
    r.roles[role]=true
    if object then
        local family=object.key:match('^([^|]+)|')
        if family=='dm'and(role=='object_name'or role=='subtitle')then r.native_model=true end
        if role=='object_name'and names.KINDS[family]then r.game_api=names.KINDS[family]end
        local context=object.key..(field and('|'..field)or'')
        if #r.contexts<3 and r.contexts[#r.contexts]~=context then r.contexts[#r.contexts+1]=context end
    end
end
local function parts(text,role,object)
    add(text,role,object)
    if type(text)=='string'and text:find(' · ',1,true)then
        for s in(text..' · '):gmatch('(.-) · ')do add(s,role..'_part',object)end
    end
end
for _,group in ipairs(module.GROUPS)do
    add(group.label,'category_group')
    for _,item in ipairs(group.items)do
        add(item.label,'category')
        local objects,why=catalog:objects(item.id)
        assert(not why,tostring(why))
        for _,object in ipairs(objects)do
            assert(not object.error,tostring(object.error))
            add(object.name,'object_name',object)
            add(object.subtitle,'subtitle',object)
            add(object.detail,'detail',object)
            for _,section in ipairs(object.sections or{})do
                parts(section.label,'section',object)
                parts(section.group,'group',object)
                for _,t in ipairs(sections.titles(section.label))do parts(t,'title',object)end
            end
            for _,row in ipairs(object.rows or{})do
                add(row.label,'field_label',object,row.field)
                add(row.note,'field_note',object,row.field)
                add(row.reason,'field_reason',object,row.field)
                for _,l in ipairs(row.labels or{})do add(l.label,'value_label',object,row.field)end
                for _,t in ipairs(row.traits or{})do add(t.label,'trait_label',object,row.field)end
            end
        end
    end
end
local out={}
for _,text in ipairs(catalog:texts())do assert(rows[text],text);out[#out+1]=rows[text]end
local function encode(v)
    if type(v)=='string'then return '"'..v:gsub('[%z\1-\31\\"]',function(c)
        if c=='\\'then return'\\\\'elseif c=='"'then return'\\"'end
        return string.format('\\u%04x',c:byte())end)..'"'end
    if type(v)~='table'then return tostring(v)end
    local pieces={}
    if #v>0 then for _,x in ipairs(v)do pieces[#pieces+1]=encode(x)end;return'['..table.concat(pieces,',')..']'end
    for k,x in pairs(v)do pieces[#pieces+1]=encode(k)..':'..encode(x)end
    return'{'..table.concat(pieces,',')..'}'
end
return encode(out)

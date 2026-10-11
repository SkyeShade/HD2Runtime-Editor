-- HD2R Editor (c) 2026 SkyeShade. All rights reserved except as granted in LICENSE
-- (https://github.com/SkyeShade/HD2Runtime-Editor). Do not redistribute or reuse without the credit it requires.
-- Presets as files, to share: one JSON file per preset (<name>.hd2rpreset.json) in a shared folder
-- (Documents\HD2R Editor\Presets). The Presets tab lists the folder, so a file dropped there shows up by itself.
--   { "format": "hd2r-editor-preset", "version": 1, "name", "editor", "runtime", "created", "icon",
--     "fields": [ { "key", "value", "label" } ] }
-- key is the editor's field key, value its stored form (numbers, booleans, strings, codes and lists as they are;
-- references as {ref, ...}, editor/catalog.lua encode), label only for people reading the file. icon (optional, 0.9.3)
-- is {kind = 'stratagem' | 'booster' | 'picture', name}: a game icon by its stratagem or booster name, or a picture
-- built into the editor (tools/preset_icons.py). An editor that does not know it reads the file as before.
--
-- Reading a file is a job (M.job) that a caller steps a few milliseconds a frame: read in slices, decode in slices,
-- check the fields in slices, so a preset of thousands of fields never stalls a frame. Every failure has a reason a
-- person can act on (where a JSON error is: line and column).
local json=require('mods/skyeshade/hd2runtime_editor/editor/json')
local export=require('mods/skyeshade/hd2runtime_editor/editor/export')
local util=require('mods/skyeshade/hd2runtime_editor/editor/util')
local M={}

M.FORMAT='hd2r-editor-preset'
M.EXTENSION='.hd2rpreset.json'
M.LIMIT=16*1024*1024   -- bytes: a preset file larger than this is not read
M.CHUNK=256*1024       -- bytes read per slice
M.ICON_KINDS={stratagem=true,booster=true,picture=true}

M.base=nil   -- tests: another folder in place of Documents\HD2R Editor\Presets
function M.folder()
    if M.base then return M.base end
    local ok,home=pcall(os.getenv,'USERPROFILE')
    if not ok or not home then return nil end
    return home..'\\Documents\\HD2R Editor\\Presets'
end

-- A value a preset may hold: plain data only, nothing deeper than a few levels.
local function storable(v,depth)
    depth=depth or 0
    local t=type(v)
    if t=='number'then return v==v and v>-math.huge and v<math.huge end
    if t=='string'then return#v<=200 end
    if t=='boolean'then return true end
    if t~='table'or depth>3 then return false end
    for k,x in pairs(v)do
        if type(k)~='string'and type(k)~='number'then return false end
        if not storable(x,depth+1)then return false end
    end
    return true
end
M.storable=storable

-- A preset icon as stored, or nil: {kind, name} with a known kind and a printable name.
function M.icon(v)
    if type(v)~='table'or not M.ICON_KINDS[v.kind]or type(v.name)~='string'then return nil end
    local name=v.name:gsub('[%c]','')
    if name==''or#name>120 then return nil end
    return {kind=v.kind,name=name}
end

-- The file's text for a preset: name, {key = stored value}, labels {key = text} (optional), meta {editor, runtime,
-- icon, created} (optional).
function M.encode(name,values,labels,meta)
    meta=meta or{}
    local fields={__array=true}
    local keys={}
    for key in pairs(values)do keys[#keys+1]=key end
    table.sort(keys)
    for _,key in ipairs(keys)do
        fields[#fields+1]={__order={'key','value','label'},key=key,value=values[key],label=labels and labels[key]or nil}
    end
    local icon=M.icon(meta.icon)
    return export.json({__order={'format','version','name','editor','runtime','created','icon','fields'},
        format=M.FORMAT,version=1,name=name,editor=meta.editor,runtime=meta.runtime,
        created=type(meta.created)=='string'and meta.created or os.date('!%Y-%m-%dT%H:%M:%SZ'),
        icon=icon and{__order={'kind','name'},kind=icon.kind,name=icon.name}or nil,fields=fields})..'\n'
end

-- Whether decoded JSON is a ModBuilder project (project.hd2mod.json): the importer converts those.
function M.is_modbuilder(data)
    return type(data)=='table'and type(data.formatVersion)=='number'and data.format==nil
        and(type(data.resourceId)=='string'or type(data.weaponChanges)=='table'or type(data.customLua)=='table')
end

-- Checks decoded JSON as a preset; yield_every: coroutine.yield() after that many fields (inside a job).
-- Returns the preset {name, values = {key = stored value}, labels, count, editor, runtime, created, icon, skipped,
-- skipped_keys}, or nil, why and extra ({modbuilder = data} for a ModBuilder project).
local function check(data,fallback_name,yield_every)
    if type(data)~='table'then return nil,'not a preset file (its JSON is not an object)'end
    if M.is_modbuilder(data)then return nil,'a ModBuilder project, not a preset file',{modbuilder=data}end
    if data.format~=M.FORMAT then
        return nil,'not an HD2R Editor preset file (no "format": "'..M.FORMAT..'" in it)'
    end
    if type(data.version)~='number'or data.version>1 then return nil,'a newer preset format: update the editor'end
    if type(data.fields)~='table'then return nil,'the file has no "fields" list'end
    local values,labels,skipped,skipped_keys,count={},{},0,{},0
    for i,f in ipairs(data.fields)do
        if type(f)=='table'and type(f.key)=='string'and#f.key>0 and#f.key<=300 and f.value~=nil and storable(f.value)then
            if values[f.key]==nil then count=count+1 end
            values[f.key]=f.value
            if type(f.label)=='string'and#f.label<=300 then labels[f.key]=f.label end
        else
            skipped=skipped+1
            if#skipped_keys<5 then
                skipped_keys[#skipped_keys+1]=type(f)=='table'and type(f.key)=='string'and f.key or('field '..i)
            end
        end
        if yield_every and i%yield_every==0 then coroutine.yield()end
    end
    if count==0 then
        if skipped>0 then return nil,'none of its '..skipped..' fields can be read'end
        return nil,'the preset has no fields'
    end
    local name=type(data.name)=='string'and util.utf8_cut((data.name:gsub('[%c]',''):gsub('^%s+',''):gsub('%s+$','')),40)or''
    if name==''then name=fallback_name or'Shared preset'end
    return {name=name,values=values,labels=labels,count=count,editor=data.editor,runtime=data.runtime,
        created=type(data.created)=='string'and data.created or nil,icon=M.icon(data.icon),skipped=skipped,
        skipped_keys=skipped_keys}
end

-- A preset from a file's text, or nil, why and extra (see check).
function M.decode(text,fallback_name)
    if type(text)~='string'or#text==0 then return nil,'the file is empty'end
    if#text>M.LIMIT then return nil,M.too_large(#text)end
    if text:sub(1,3)=='\239\187\191'then text=text:sub(4)end
    local ok,data=pcall(json.decode,text,nil,true)
    if not ok then return nil,'not valid JSON: '..json.explain(text,data)end
    return check(data,fallback_name)
end
function M.too_large(size)
    return ('the file is too large: %.1f MB (a preset file can be at most %d MB)'):format(size/1048576,M.LIMIT/1048576)
end

-- A file's name without the folder and the preset extension.
function M.base_name(path)
    local base=tostring(path):match('([^\\/]+)$')or'Shared preset'
    return (base:gsub('%.hd2rpreset%.json$',''):gsub('%.hd2mod%.json$',''):gsub('%.json$',''))
end

-- Opens a file for reading: io.open, then (a path with characters the game's io cannot open, from the Windows
-- dialog) the wide-character reader of editor/win.lua when given. A handle with read(n), seek(), close(), or nil and
-- why.
local function open(path,wide)
    local ok,f=pcall(io.open,path,'rb')
    if ok and f then return f end
    if wide then
        local r,why=wide(path)
        if r then return r end
        return nil,why
    end
    return nil,'it does not exist or cannot be opened'
end

-- The whole file (at most LIMIT bytes), or nil and why.
function M.read_file(path,wide)
    local f,why=open(path,wide)
    if not f then return nil,why end
    local data=f:read(M.LIMIT+1)
    f:close()
    return data or''
end
local function write(path,data)
    local f,why=io.open(path,'wb')
    if not f then error('cannot write '..path..': '..tostring(why),0)end
    local ok,err=f:write(data)
    f:close()
    if not ok then error('cannot write '..path..': '..tostring(err),0)end
end

-- The file name for a preset name, without a folder.
function M.file_name(name)return export.safe_name(name)..M.EXTENSION end

-- Writes a preset into the folder (made when missing) and returns the path.
function M.save(folder,name,values,labels,meta,mkdir)
    mkdir(folder)
    local path=folder..'\\'..M.file_name(name)
    write(path,M.encode(name,values,labels,meta))
    return path
end

-- Reads a preset file at once: the decoded preset, or nil, why and extra.
function M.load(path,wide)
    local text,why=M.read_file(path,wide)
    if not text then return nil,'cannot read '..tostring(path)..': '..tostring(why)end
    return M.decode(text,M.base_name(path))
end

-- Copies a checked preset file's text into the folder; returns the new path (the same path when it is there already).
function M.copy_into(path,text,preset,folder,mkdir)
    local target=folder..'\\'..M.file_name(preset.name)
    if target:lower()==tostring(path):lower()then return target end
    mkdir(folder)
    write(target,text)
    return target
end

-- Copies a preset file from anywhere into the folder (checked first); returns the new path and the preset, or nil,
-- why and extra.
function M.import(path,folder,mkdir,wide)
    local text,why=M.read_file(path,wide)
    if not text then return nil,'cannot read '..tostring(path)..': '..tostring(why)end
    local preset,why2,extra=M.decode(text,M.base_name(path))
    if not preset then return nil,why2,extra end
    return M.copy_into(path,text,preset,folder,mkdir),preset
end

-- A file's icon (the first few KB hold it: encode writes it before the fields), or nil.
function M.peek(path)
    local ok,f=pcall(io.open,path,'rb')
    if not ok or not f then return nil end
    local head=f:read(4096)or''
    f:close()
    local object=head:match('"icon"%s*:%s*(%b{})')
    if not object then return nil end
    local okj,data=pcall(json.decode,object)
    return okj and M.icon(data)or nil
end

-- Writes a new icon into a preset file (nil removes it); everything else in the file stays. True, or nil and why.
function M.set_icon(path,icon)
    local text,why=M.read_file(path)
    if not text then return nil,why end
    local preset,why2=M.decode(text,M.base_name(path))
    if not preset then return nil,why2 end
    local ok,err=pcall(write,path,M.encode(preset.name,preset.values,preset.labels,
        {editor=preset.editor,runtime=preset.runtime,created=preset.created,icon=icon}))
    if not ok then return nil,tostring(err)end
    return true
end

-------------------------------------------------------------------------------------------------- reading job --
-- A file read, decoded and checked over several frames. job:step(seconds) works for about that long and returns true
-- once finished; then job.preset (and job.text, the file's text) or job.why (and job.extra: {modbuilder = data}).
-- job.phase is 'reading', 'decoding', 'checking', then 'done' or 'failed'; job.progress goes from 0 to 1. opts.wide:
-- the wide-character reader (editor/win.lua reader).
local Job={};Job.__index=Job
function M.job(path,opts)
    opts=opts or{}
    local self=setmetatable({path=path,phase='reading',progress=0,size=0},Job)
    self.co=coroutine.create(function()
        local f,why=open(path,opts.wide)
        if not f then return self:fail('cannot open '..tostring(path)..': '..tostring(why))end
        local size=f:seek('end')or 0
        f:seek('set',0)
        self.size=size
        if size==0 then f:close();return self:fail('the file is empty')end
        if size>M.LIMIT then f:close();return self:fail(M.too_large(size))end
        local parts,got={},0
        while got<size do
            local chunk=f:read(math.min(M.CHUNK,size-got))
            if not chunk or#chunk==0 then break end
            parts[#parts+1]=chunk
            got=got+#chunk
            self.progress=0.25*got/size
            coroutine.yield()
        end
        f:close()
        local text=table.concat(parts)
        if#text==0 then return self:fail('the file is empty')end
        if text:sub(1,3)=='\239\187\191'then text=text:sub(4)end
        self.phase='decoding'
        local ok,data=pcall(json.decode,text,opts.yield_every or 1000,true)
        if not ok then return self:fail('not valid JSON: '..json.explain(text,data))end
        self.phase,self.progress='checking',0.9
        local preset,why2,extra=check(data,M.base_name(path),opts.check_every or 2000)
        if not preset then self.extra=extra;return self:fail(why2)end
        self.preset,self.text,self.phase,self.progress=preset,text,'done',1
    end)
    return self
end
function Job:fail(why)self.why,self.phase=why,'failed'end
function Job:finished()return self.phase=='done'or self.phase=='failed'end
function Job:step(seconds)
    if self:finished()then return true end
    local clock=os.clock
    local stop=clock()+(seconds or 0.004)
    repeat
        local ok,pos,len=coroutine.resume(self.co)
        if not ok then self:fail('the reader stopped: '..tostring(pos));break end
        if self.phase=='decoding'and type(pos)=='number'and type(len)=='number'and len>0 then
            self.progress=0.25+0.65*pos/len
        end
        if coroutine.status(self.co)=='dead'then
            if not self:finished()then self:fail('the reader stopped')end
            break
        end
    until clock()>=stop
    return self:finished()
end

-- The preset files in the folder: {{name, path, size}}, sorted by name, and why when the folder could not be listed
-- (a folder that does not exist yet lists empty). list(folder, pattern) lists a folder (editor/win.lua list).
function M.list(folder,list)
    if not folder then return {},'no Documents folder (%USERPROFILE%)'end
    local entries,why=list(folder,'*.json')
    if not entries then return {},tostring(why or'the folder cannot be listed')end
    local out={}
    for _,e in ipairs(entries)do
        if not e.folder and e.name:lower():match('%.json$')then
            out[#out+1]={name=M.base_name(e.name),file=e.name,path=folder..'\\'..e.name,size=e.size}
        end
    end
    table.sort(out,function(a,b)return a.name:lower()<b.name:lower()end)
    return out
end

return M

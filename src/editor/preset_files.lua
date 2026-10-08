-- HD2R Editor (c) 2026 SkyeShade. All rights reserved except as granted in LICENSE
-- (https://github.com/SkyeShade/HD2Runtime-Editor). Do not redistribute or reuse without the credit it requires.
-- Presets as files, to share: one JSON file per preset (<name>.hd2rpreset.json) in a shared folder
-- (Documents\HD2R Editor\Presets). The Presets tab lists the folder, so a file dropped there shows up by itself.
--   { "format": "hd2r-editor-preset", "version": 1, "name", "editor", "runtime", "created",
--     "fields": [ { "key", "value", "label" } ] }
-- key is the editor's field key, value its stored form (numbers, booleans, strings, codes and lists as they are;
-- references as {ref, ...}, editor/catalog.lua encode), label only for people reading the file.
local json=require('mods/skyeshade/hd2runtime_editor/editor/json')
local export=require('mods/skyeshade/hd2runtime_editor/editor/export')
local M={}

M.FORMAT='hd2r-editor-preset'
M.EXTENSION='.hd2rpreset.json'
M.LIMIT=4*1024*1024   -- bytes: a preset file larger than this is not read

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

-- The file's text for a preset: name, {key = stored value}, labels {key = text} (optional), meta {editor, runtime}.
function M.encode(name,values,labels,meta)
    local fields={__array=true}
    local keys={}
    for key in pairs(values)do keys[#keys+1]=key end
    table.sort(keys)
    for _,key in ipairs(keys)do
        fields[#fields+1]={__order={'key','value','label'},key=key,value=values[key],label=labels and labels[key]or nil}
    end
    return export.json({__order={'format','version','name','editor','runtime','created','fields'},format=M.FORMAT,
        version=1,name=name,editor=meta and meta.editor,runtime=meta and meta.runtime,
        created=os.date('!%Y-%m-%dT%H:%M:%SZ'),fields=fields})..'\n'
end

-- A preset from a file's text: {name, values = {key = stored value}, editor, runtime, skipped}, or nil and why.
function M.decode(text,fallback_name)
    if type(text)~='string'or#text==0 then return nil,'the file is empty'end
    if#text>M.LIMIT then return nil,'the file is too large for a preset'end
    if text:sub(1,3)=='\239\187\191'then text=text:sub(4)end
    local ok,data=pcall(json.decode,text)
    if not ok or type(data)~='table'then return nil,'not a preset file (not JSON)'end
    if data.format~=M.FORMAT then return nil,'not an HD2R Editor preset file'end
    if type(data.version)~='number'or data.version>1 then return nil,'a newer preset format: update the editor'end
    local values,skipped={},0
    for _,f in ipairs(type(data.fields)=='table'and data.fields or{})do
        if type(f)=='table'and type(f.key)=='string'and#f.key<=300 and f.value~=nil and storable(f.value)then
            values[f.key]=f.value
        else skipped=skipped+1 end
    end
    local name=type(data.name)=='string'and data.name:gsub('[%c]',''):sub(1,40)or''
    if name==''then name=fallback_name or'Shared preset'end
    return {name=name,values=values,editor=data.editor,runtime=data.runtime,skipped=skipped}
end

local function read(path)
    local ok,f=pcall(io.open,path,'rb')
    if not ok or not f then return nil end
    local data=f:read(M.LIMIT+1);f:close()
    return data
end
M.read_file=read
local function write(path,data)
    local f,why=io.open(path,'wb')
    if not f then error('cannot write '..path..': '..tostring(why),0)end
    f:write(data);f:close()
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

-- Reads a preset file: the decoded preset, or nil and why.
function M.load(path)
    local text=read(path)
    if not text then return nil,'cannot read '..tostring(path)end
    local base=tostring(path):match('([^\\/]+)$')or'Shared preset'
    return M.decode(text,(base:gsub('%.hd2rpreset%.json$',''):gsub('%.json$','')))
end

-- Copies a preset file from anywhere into the folder (checked first); returns the new path, or nil and why.
function M.import(path,folder,mkdir)
    local preset,why=M.load(path)
    if not preset then return nil,why end
    local target=folder..'\\'..M.file_name(preset.name)
    if target:lower()==tostring(path):lower()then return target end
    mkdir(folder)
    write(target,read(path))
    return target,preset
end

-- The preset files in the folder: {{name, path, size}}, sorted by name. list(folder, pattern) lists a folder
-- (editor/win.lua list).
function M.list(folder,list)
    if not folder then return {}end
    local entries=list(folder,'*.json')or{}
    local out={}
    for _,e in ipairs(entries)do
        if not e.folder and e.name:lower():match('%.json$')then
            out[#out+1]={name=(e.name:gsub('%.hd2rpreset%.json$',''):gsub('%.json$','')),path=folder..'\\'..e.name,
                size=e.size}
        end
    end
    table.sort(out,function(a,b)return a.name:lower()<b.name:lower()end)
    return out
end

return M

-- HD2R Editor (c) 2026 SkyeShade. All rights reserved except as granted in LICENSE
-- (https://github.com/SkyeShade/HD2Runtime-Editor). Do not redistribute or reuse without the credit it requires.
-- HD2Runtime ModBuilder interop, through its own files (%LOCALAPPDATA%\HD2RuntimeGUI):
--   * projects(): ModBuilder's library (library.json), newest first; read(id): one project (project.hd2mod.json);
--   * items(catalog, project): a project's edits as editor rows and values, and the ones the editor cannot take with
--     why. Structured changes match by their identity (weapon + semantic field, instance keys, swaps); the project's
--     custom Lua runs against a recording hd2, so hd2.ensure patches in it (an editor export saved to ModBuilder, or
--     hand-written ones) match by their target code and field;
--   * save(...): the editor's changes as a ModBuilder project in its library: the editor's generated addon as the
--     project's custom Lua (format 11), which ModBuilder builds as it is. Never overwrites a project it did not write.
local json=require('mods/skyeshade/hd2runtime_editor/editor/json')
local export=require('mods/skyeshade/hd2runtime_editor/editor/export')
local catalog_module=require('mods/skyeshade/hd2runtime_editor/editor/catalog')
local util=require('mods/skyeshade/hd2runtime_editor/editor/util')
local M={}

-- The first line of the custom Lua the editor writes: how it knows a project is its own.
M.MARK='-- HD2R Editor values'
M.base=nil   -- tests: another folder in place of %LOCALAPPDATA%

function M.root()
    local base=M.base
    if not base then
        local ok,v=pcall(os.getenv,'LOCALAPPDATA')
        base=ok and v or nil
    end
    return base and(base..'\\HD2RuntimeGUI')or nil
end
local function read(path)
    local ok,f=pcall(io.open,path,'rb')
    if not ok or not f then return nil end
    local data=f:read('*a');f:close()
    if data:sub(1,3)=='\239\187\191'then data=data:sub(4)end
    return data
end
local function write(path,data)
    local f,why=io.open(path,'wb')
    if not f then error('cannot write '..path..': '..tostring(why),0)end
    f:write(data);f:close()
end
local function decode_file(path)
    local text=read(path)
    if not text then return nil,'cannot read '..path end
    local ok,value=pcall(json.decode,text)
    if not ok or type(value)~='table'then return nil,tostring(value)end
    return value
end

-- ModBuilder's projects: {{id, name, resource, sdk, modified}}, newest first ({} without a library); nil and why
-- without %LOCALAPPDATA%.
function M.projects()
    local root=M.root()
    if not root then return nil,'no %LOCALAPPDATA%'end
    local library=decode_file(root..'\\library.json')
    local list={}
    for _,p in ipairs(library and library.projects or{})do
        if type(p)=='table'and type(p.id)=='string'and p.id:match('^[%x%-]+$')then
            list[#list+1]={id=p.id,name=tostring(p.displayName or p.id),resource=p.resourceId,sdk=p.sdkVersion,
                modified=tostring(p.modifiedAt or'')}
        end
    end
    table.sort(list,function(a,b)return a.modified>b.modified end)
    return list
end
function M.read(id)
    local root=M.root()
    if not root then return nil,'no %LOCALAPPDATA%'end
    if not tostring(id):match('^[%x%-]+$')then return nil,'not a project id'end
    return decode_file(root..'\\Projects\\'..id..'\\project.hd2mod.json')
end

---------------------------------------------------------------------------------------------- values in --
-- The editor value for a ModBuilder value on a row, or nil and why.
local function fit(cat,row,v)
    if not row.editable then return nil,tostring(row.reason or'not editable in the editor')end
    local kind=row.kind
    if kind==nil then
        if type(v)~='number'then return nil,'not a number: '..tostring(v)end
        if row.integer and v%1~=0 then return nil,'not a whole number: '..tostring(v)end
        if row.min and v<row.min or row.max and v>row.max then
            return nil,('outside the editor range %s to %s'):format(util.format(row.min),util.format(row.max))
        end
        if row.disabled_value~=nil and v~=row.disabled_value and v<=0 then
            return nil,util.format(row.disabled_value)..' disables it; otherwise a value above 0'
        end
        return v
    elseif kind=='choice'then
        -- an enum by its name (ModBuilder) or its number (the editor)
        local d=type(row.descriptor)=='table'and row.descriptor or{}
        if type(v)=='string'and type(d.enumValues)=='table'and d.enumValues[v]~=nil then v=d.enumValues[v]end
        for _,o in ipairs(row.labels or{})do if util.same(o.value,v)then return o.value end end
        return nil,'not one of its choices: '..tostring(v)
    elseif kind=='uses'then
        if v=='unlimited'then
            if row.unlimited then return v end
            return nil,'this stratagem cannot be made unlimited'
        end
        if type(v)~='number'or v%1~=0 then return nil,'not a whole number: '..tostring(v)end
        if row.min and v<row.min or row.max and v>row.max then
            return nil,('outside the editor range %s to %s'):format(util.format(row.min),util.format(row.max))
        end
        return v
    elseif kind=='code'then
        if type(v)~='table'then return nil,'not a call-in code'end
        local allowed={}
        for _,d in ipairs(row.directions or{})do allowed[d]=true end
        for _,d in ipairs(v)do if not allowed[d]then return nil,'not a direction: '..tostring(d)end end
        if#v<(row.min_length or 1)or#v>(row.max_length or 16)then return nil,'a code of '..#v..' directions'end
        return util.copy(v)
    elseif kind=='modes'or kind=='traits'then
        -- fire mode names / displayed trait ids, each one the row offers
        if type(v)~='table'then return nil,'not a list'end
        local offered={}
        for _,o in ipairs((kind=='modes'and row.modes or row.traits)or{})do offered[type(o)=='table'and o.value or o]=true end
        for _,x in ipairs(v)do if not offered[x]then return nil,'not offered here: '..tostring(x)end end
        if kind=='modes'and(#v==0 or#v>(row.max_modes or 4))then return nil,#v..' fire modes'end
        return util.copy(v)
    elseif kind=='rates'then
        if type(v)~='table'or#v~=3 then return nil,'not three rates'end
        for _,x in ipairs(v)do if type(x)~='number'or x<0 then return nil,'not a rate: '..tostring(x)end end
        return util.copy(v)
    elseif kind=='reference'and type(v)=='table'and v.ref then
        local value=catalog_module.decode(cat,row,v)
        if value~=nil then return value end
        return nil,'the referenced '..tostring(v.ref)..' is not available'
    end
    return nil,'this kind of value is not imported yet'
end
M.fit=fit

-- A weapon field by ModBuilder's semantic id, with the role and phase qualified forms the catalogue may use
-- ('damage.alternate.stagger', 'explosion.primary.impact.damage.standard_damage').
local function weapon_row(lookup,weapon,sid,role,phase)
    local candidates={sid}
    local domain,rest=tostring(sid):match('^([%w_]+)%.(.+)$')
    if domain and role then
        candidates[#candidates+1]=domain..'.'..role..'.'..rest
        if phase then
            candidates[#candidates+1]=domain..'.'..role..'.'..phase..'.'..rest
            candidates[#candidates+1]='explosion.'..role..'.'..phase..'.'..sid
        end
    end
    for _,id in ipairs(candidates)do
        local row=lookup.weapon[weapon..'|'..id]
        if row then return row end
    end
    return nil
end

-- A reference value written as Lua (custom Lua): the stored form the catalogue decodes, or nil.
local function code_ref(code)
    local id=code:match('^hd2%.attack_output%("([^"]+)"%)$')
    if id then return {ref='output',id=id}end
    id=code:match('^hd2%.pickup%("([^"]+)"%)$')
    if id then return {ref='pickup',id=id}end
    if code:match(':no_explosion%(%)$')then return {ref='none'}end
    local w,a,p=code:match('^hd2%.weapon%("([^"]+)"%):attack%("([^"]+)"%):projectile%(%):terminal_action%("([^"]+)"%):explosion%(%)$')
    if w then return {ref='terminal',weapon=w,attack=a,phase=p}end
    w,a=code:match('^hd2%.weapon%("([^"]+)"%):attack%("([^"]+)"%):projectile%(%)$')
    if w then return {ref='projectile',weapon=w,attack=a}end
    return nil
end

-- A recording hd2 for running custom Lua: every name is a node that records the Lua that reaches it
-- ('hd2.weapon("X"):attack("primary")'); hd2.ensure records its patches instead.
local function literal(v)
    local ok,s=pcall(export.literal,v)
    return ok and s or'?'
end
local Node={}
local function node(code,parent,name)return setmetatable({__code=code,__parent=parent,__name=name},Node)end
Node.__index=function(self,k)
    if k=='__code'or k=='__parent'or k=='__name'then return rawget(self,k)end
    return node(rawget(self,'__code')..'.'..tostring(k),self,tostring(k))
end
Node.__call=function(self,first,...)
    local parent=rawget(self,'__parent')
    local args,code={},nil
    if parent~=nil and first==parent then
        -- a method call: parent:name(...)
        for i=1,select('#',...)do args[i]=literal((select(i,...)))end
        code=rawget(parent,'__code')..':'..rawget(self,'__name')..'('..table.concat(args,',')..')'
    else
        local all={first,...}
        for i=1,select('#',...)+1 do args[i]=literal(all[i])end
        if first==nil and select('#',...)==0 then args={}end
        code=rawget(self,'__code')..'('..table.concat(args,',')..')'
    end
    return node(code)
end
local function code_of(v)return type(v)=='table'and rawget(v,'__code')or nil end

-- The hd2.ensure patches a custom Lua source registers: {{target = code, field = id, value}}, or nil and why. Runs
-- sandboxed: only the recording hd2 and plain Lua libraries, a bounded number of instructions.
function M.lua_patches(source)
    local patches={}
    local function field_of(f)
        local code=code_of(f)
        if code then return(code:gsub('^hd2%.fields%.',''))end
        return f
    end
    local function value_of(v)
        local code=code_of(v)
        if code then return code_ref(code)or{ref='code',code=code}end
        return v
    end
    local fake=node('hd2')
    local real=setmetatable({},{__index=function(_,k)
        if k=='ensure'then
            return function(spec)
                spec=type(spec)=='table'and spec or{}
                local p=spec.patch
                if type(p)=='table'then
                    patches[#patches+1]={target=code_of(p.target),field=field_of(p.field),value=value_of(p.value)}
                elseif type(spec.transaction)=='table'then
                    local t=spec.transaction
                    for i,c in ipairs(t.changes or{})do
                        patches[#patches+1]={target=code_of(t.target),field=field_of(c.field),value=value_of(c.value),
                            follower=i>1}
                    end
                end
                return node('hd2.ensure()')
            end
        end
        if k=='api_version'then return 1 end
        if k=='version'or k=='version_label'then return'0.30.0'end
        return fake[k]
    end})
    local fn,why=loadstring(source,'=custom Lua')
    if not fn then return nil,'the custom Lua does not load: '..tostring(why)end
    local env={hd2=real,require=function(name)
            if name=='mods/skyeshade/hd2runtime'then return real end
            error('require('..tostring(name)..') is not available while importing',2)
        end,
        print=function()end,pairs=pairs,ipairs=ipairs,next=next,type=type,tostring=tostring,tonumber=tonumber,
        select=select,unpack=unpack,pcall=pcall,xpcall=xpcall,error=error,assert=assert,setmetatable=setmetatable,
        getmetatable=getmetatable,rawget=rawget,rawset=rawset,rawequal=rawequal,math=math,string=string,table=table,
        os={time=os.time,clock=os.clock,date=os.date}}
    env._G=env
    setfenv(fn,env)
    local hook=type(debug)=='table'and debug.sethook
    if hook then hook(function()error('the custom Lua runs too long',0)end,'',20000000)end
    local ok,err=pcall(fn)
    if hook then hook()end
    if not ok then return patches,'the custom Lua stopped: '..tostring(err)end
    return patches
end

-- A project's edits: {{label, row, value, why, selected}}, in project order; rows that take a value are selected.
function M.items(cat,project)
    local lookup=cat:import_index()
    local items={}
    local function add(label,row,value,why)
        items[#items+1]={label=label,row=row,value=value,why=why,selected=row~=nil and why==nil}
    end
    local function take(label,row,desired,enabled)
        if not row then return add(label,nil,nil,'no such field in this editor (a different HD2Runtime?)')end
        if enabled==false then return add(label,row,nil,'turned off in ModBuilder')end
        local value,why=fit(cat,row,desired)
        add(label,row,value,why)
    end
    for _,c in ipairs(project.weaponChanges or{})do
        local weapon=tostring(c.weapon)
        take(weapon..': '..tostring(c.semanticFieldId),lookup.weapon[weapon..'|'..tostring(c.semanticFieldId)],
            c.desiredValue,c.enabled)
    end
    for _,c in ipairs(project.compositionChanges or{})do
        local weapon,role=tostring(c.weapon),tostring(c.attackRole or'primary')
        if c.kind=='terminal'then
            local d=type(c.desiredExplosion)=='table'and c.desiredExplosion or{}
            local p=type(d.projectile)=='table'and d.projectile
            local stored=p and{ref='terminal',weapon=p.weapon,attack=p.attackRole,phase=d.phase}or{ref='none'}
            take(weapon..': '..tostring(c.phase)..' explosion',lookup.swap['terminal|'..weapon..'|'..role..'|'..tostring(c.phase)],
                stored,c.enabled)
        elseif type(c.scalar)=='table'then
            local s=c.scalar
            local enabled=c.enabled~=false and s.enabled~=false
            take(weapon..': '..tostring(c.kind)..' '..tostring(s.semanticFieldId),
                weapon_row(lookup,weapon,tostring(s.semanticFieldId),role,c.phase),s.desiredValue,enabled)
        else
            add(weapon..': '..tostring(c.kind),nil,nil,'this composition change is not imported yet')
        end
    end
    for _,c in ipairs(project.projectileChanges or{})do
        local weapon,role=tostring(c.weapon),tostring(c.attackRole or'primary')
        local r=type(c.replacementProjectile)=='table'and c.replacementProjectile or{}
        take(weapon..': projectile swap',lookup.swap['projectile|'..weapon..'|'..role],
            {ref='projectile',weapon=r.weapon,attack=r.attackRole},c.enabled)
    end
    -- by instance key; an older project's key (its build hash) by the identity fields it also stores
    local function keyed(c,kind)
        local row=lookup.instance[tostring(c.instanceKey)]
        if row then return row end
        local sid=tostring(c.semanticFieldId)
        if kind=='support'then return lookup.ident['support|'..tostring(c.weapon)..'|'..tostring(c.attackRole or'')..'|'..sid]end
        local resource=tostring(c.resource)
        if resource=='enemy'or resource=='structure'then
            return lookup.ident[resource..'|'..tostring(c.entity)..'|'..tostring(c.path)..'|'..tostring(c.zone or c.attack or'')..'|'..sid]
        elseif resource=='vehicle_weapon'then
            return lookup.ident['vehicle_weapon|'..tostring(c.entity)..'||'..sid]
        elseif resource=='pod_rack'then
            local rack=tostring(c.instanceKey):match('^pod_rack:(.-):slot%-%d+$')
            return rack and lookup.ident['pod_rack|'..rack..'|'..tostring(c.slot)]
        end
        return nil
    end
    for kind,list in pairs({support=project.supportChanges or{},stratagem=project.stratagemChanges or{},
            entity=project.entityChanges or{}})do
        for _,c in ipairs(list)do
            local label=tostring(c.weapon or c.stratagem or c.entity or c.instanceKey)..': '..tostring(c.semanticFieldId)
            local desired=c.desiredValue
            if c.fieldType=='pickup_reference'and type(desired)=='string'then desired={ref='pickup',id=desired}
            elseif c.fieldType=='mounted_weapon_reference'then
                add(label,keyed(c,kind),nil,'mounted weapon swaps are not imported yet')
                desired=nil
            end
            if desired~=nil then take(label,keyed(c,kind),desired,c.enabled)end
        end
    end
    for _,c in ipairs(project.attackOutputChanges or{})do
        add(tostring(c.weapon)..': fires '..tostring(c.output),nil,nil,'attack output changes are not imported yet')
    end
    for _,c in ipairs(project.outputRowChanges or{})do
        add(tostring(c.output)..': '..tostring(c.field),nil,nil,'output row changes are not imported yet')
    end
    for _,c in ipairs(project.changes or{})do
        add(tostring(c.target)..': '..tostring(c.field),nil,nil,'an old-format change: open and save the project in ModBuilder')
    end
    if project.playerArmor then add('Player armor',nil,nil,'player armor settings are not imported yet')end
    if project.customContent then add('Custom content',nil,nil,'custom stratagems and projectiles stay in ModBuilder')end
    -- the custom Lua: its hd2.ensure patches, matched by target code and field
    local lua=project.customLua
    if type(lua)=='table'and lua.enabled~=false and type(lua.source)=='string'and lua.source:find('%S')then
        local patches,why=M.lua_patches(lua.source)
        if not lookup.code then
            local code={}
            for _,row in ipairs(lookup.rows)do
                local ok,text=true,row.target_code
                if not text then ok,text=pcall(export.trace,row.target)end
                if ok and text and row.field then
                    local key=text..'|'..tostring(row.field)
                    if not code[key]then code[key]=row end
                end
            end
            lookup.code=code
        end
        for _,p in ipairs(patches or{})do
            local row=p.target and lookup.code[p.target..'|'..tostring(p.field)]
            if row or not p.follower then
                local label=tostring(p.target)..' '..tostring(p.field)
                if type(p.value)=='table'and p.value.ref=='code'then
                    add(label,row,nil,'a value written as Lua ('..p.value.code..') is not imported')
                else
                    take(label,row,p.value,true)
                end
            end
        end
        if why then add('Custom Lua',nil,nil,why)
        elseif#(patches or{})==0 then add('Custom Lua',nil,nil,'no hd2.ensure patches in it (scripts stay in ModBuilder)')end
    end
    return items
end

---------------------------------------------------------------------------------------------- values out --
local function guid4()
    local seed=tostring(os.time())..tostring(os.clock())..tostring(math.random())..tostring({})
    local b={export.sha256(seed):byte(1,16)}
    b[7]=bit.bor(bit.band(b[7],0x0F),0x40)
    b[9]=bit.bor(bit.band(b[9],0x3F),0x80)
    local hex={}
    for i=1,16 do hex[i]=string.format('%02x',b[i])end
    local s=table.concat(hex)
    return s:sub(1,8)..'-'..s:sub(9,12)..'-'..s:sub(13,16)..'-'..s:sub(17,20)..'-'..s:sub(21,32)
end
local CHANGE_LISTS={'changes','weaponChanges','projectileChanges','compositionChanges','supportChanges',
    'stratagemChanges','entityChanges','attackOutputChanges','outputRowChanges'}
-- Whether a project is one the editor wrote and nothing else changed: its custom Lua starts with MARK and it has
-- no ModBuilder changes of its own.
function M.editor_owned(project)
    local lua=type(project)=='table'and project.customLua
    if type(lua)~='table'or type(lua.source)~='string'or lua.source:sub(1,#M.MARK)~=M.MARK then return false end
    for _,key in ipairs(CHANGE_LISTS)do
        if type(project[key])=='table'and#project[key]>0 then return false end
    end
    return project.customContent==nil and project.playerArmor==nil
end

-- Saves changes {{row, value}} as a ModBuilder project. meta = {name, version, author, description, image, minimum,
-- sdk (the HD2Runtime version), editor_version}; mkdir(path) makes a folder. Returns {id, name, resource, path,
-- updated, count, skipped}; raises with why (a project of the same resource ModBuilder owns, a write failure).
function M.save(cat_module,entries,meta,mkdir)
    local root=M.root()
    if not root then error('no %LOCALAPPDATA%',0)end
    assert(tostring(meta.version):match('^%d+%.%d+%.%d+$'),'the version must look like 1.0.0')
    local author=meta.author~=''and meta.author or'player'
    local resource='mods/'..export.slug(author)..'/'..export.slug(meta.name)
    meta.resource=resource
    local source,skipped=export.addon(cat_module,entries,meta)
    if#entries<=#skipped then error('none of the chosen changes could be exported',0)end
    source=M.MARK..' ('..(#entries-#skipped)..' changes; the HD2R Editor imports them again from its Presets tab).\n'
        ..source
    local library=decode_file(root..'\\library.json')or{formatVersion=1,projects={}}
    if library.formatVersion~=1 or type(library.projects)~='table'then error('ModBuilder\'s library has a newer format',0)end
    local id,created,updated
    for _,p in ipairs(library.projects)do
        if type(p)=='table'and tostring(p.resourceId):lower()==resource:lower()then
            local old=M.read(p.id)
            if old and not M.editor_owned(old)then
                error(('ModBuilder already has the project "%s" (%s) with changes of its own: export under another name or author')
                    :format(tostring(p.displayName),resource),0)
            end
            id,created,updated=p.id,old and old.createdAt,true
        end
    end
    id=id or guid4()
    local now=os.date('!%Y-%m-%dT%H:%M:%SZ')
    local function list()return{__array=true}end
    local description=meta.description~=''and meta.description or meta.name
    local project={__order={'formatVersion','id','displayName','author','resourceId','managerGuid','version',
            'description','createdAt','modifiedAt','sdkVersion','runtimeApi','exportDirectory','changes','weaponChanges',
            'projectileChanges','compositionChanges','supportChanges','supportApprovals','stratagemChanges',
            'stratagemApprovals','entityChanges','entityApprovals','customLua','arsenal'},
        formatVersion=meta.image and 12 or 11,id=id,displayName=meta.name,author=author,resourceId=resource,
        managerGuid=export.guid(resource),version=meta.version,description=description,createdAt=created or now,
        modifiedAt=now,sdkVersion=tostring(meta.sdk or meta.minimum),runtimeApi=1,exportDirectory=root..'\\Exports',
        changes=list(),weaponChanges=list(),projectileChanges=list(),compositionChanges=list(),supportChanges=list(),
        supportApprovals={},stratagemChanges=list(),stratagemApprovals={},entityChanges=list(),entityApprovals={},
        customLua={__order={'enabled','source'},enabled=true,source=source},
        arsenal=meta.image and{__order={'description','icon'},description=description,icon=meta.image}or nil}
    local folder=root..'\\Projects\\'..id
    mkdir(folder)
    write(folder..'\\project.hd2mod.json',export.json(project)..'\n')
    -- ModBuilder's working copy of the custom Lua, when it has made one: kept the same so it sees no outside edit
    if read(folder..'\\src\\addon.lua')then write(folder..'\\src\\addon.lua',source)end
    -- the library entry (the others as they are)
    local projects={__array=true}
    for _,p in ipairs(library.projects)do
        if type(p)=='table'and p.id~=id then
            projects[#projects+1]={__order={'id','displayName','resourceId','sdkVersion','modifiedAt'},id=p.id,
                displayName=p.displayName,resourceId=p.resourceId,sdkVersion=p.sdkVersion,modifiedAt=p.modifiedAt}
        end
    end
    projects[#projects+1]={__order={'id','displayName','resourceId','sdkVersion','modifiedAt'},id=id,
        displayName=meta.name,resourceId=resource,sdkVersion=project.sdkVersion,modifiedAt=now}
    mkdir(root)
    write(root..'\\library.json',export.json({__order={'formatVersion','projects'},formatVersion=1,projects=projects})..'\n')
    return {id=id,name=meta.name,resource=resource,path=folder..'\\project.hd2mod.json',updated=updated==true,
        count=#entries-#skipped,skipped=skipped}
end

return M

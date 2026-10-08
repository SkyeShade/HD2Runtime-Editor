-- HD2R Editor (c) 2026 SkyeShade. All rights reserved except as granted in LICENSE
-- (https://github.com/SkyeShade/HD2Runtime-Editor). Do not redistribute or reuse without the credit it requires.
-- Exporting the editor's changes as an HD2Runtime mod, from inside the game, the way HD2Runtime ModBuilder builds one:
--   * src/addon.lua: one guarded hd2.ensure per changed field (expect = the field's original value; a rate list that
--     fills an empty slot as a transaction with the rate selector binding), written from each row's own target code;
--   * the mod ZIP (ModBuilder's layout): manifest.json (Arsenal: name, version, description, icon), hd2runtime.json,
--     build-report.json, README.md, src/addon.lua, the icon, and mod/9ba626afa44a3aa3.patch_0 (+ empty .stream and
--     .gpu_resources): the boot-package patch archive holding the addon wrapped like the SDK's wrap_addon;
--   * the unpacked project next to it (hd2runtime.json, src/addon.lua, the icon), which the HD2Runtime SDK can build.
-- Pure Lua (LuaJIT 64-bit cdata for MurmurHash64A); files are written with io.open in binary mode.
local M={}

------------------------------------------------------------------------------------------------- hashing --
local ffi_ok,ffi=pcall(require,'ffi')
local band,bxor,rshift,lshift,bor,bnot=bit.band,bit.bxor,bit.rshift,bit.lshift,bit.bor,bit.bnot

-- MurmurHash64A, seed 0 (the engine's resource names; hd2_archive.resource_hash). Returns the 16 hex digits.
function M.murmur64(text)
    assert(ffi_ok,'the FFI is needed for 64-bit hashing')
    local MIX=0xC6A4A7935BD1E995ULL
    local n=#text
    local h=ffi.new('uint64_t',n)*MIX
    local complete=n-n%8
    for i=1,complete,8 do
        local k=0ULL
        for j=7,0,-1 do k=k*256ULL+text:byte(i+j)end
        k=k*MIX
        k=bxor(k,rshift(k,47))
        k=k*MIX
        h=bxor(h,k)*MIX
    end
    if complete~=n then
        local t=0ULL
        for j=n,complete+1,-1 do t=t*256ULL+text:byte(j)end
        h=bxor(h,t)*MIX
    end
    h=bxor(h,rshift(h,47))
    h=h*MIX
    h=bxor(h,rshift(h,47))
    return bit.tohex(h,16)
end
local function u64_bytes(hex)
    local out={}
    for i=8,1,-1 do out[#out+1]=string.char(tonumber(hex:sub(i*2-1,i*2),16))end
    return table.concat(out)
end

local CRC
function M.crc32(data)
    if not CRC then
        CRC={}
        for i=0,255 do
            local c=i
            for _=1,8 do c=band(c,1)~=0 and bxor(0xEDB88320,rshift(c,1))or rshift(c,1)end
            CRC[i]=c
        end
    end
    local c=0xFFFFFFFF
    for i=1,#data do c=bxor(CRC[band(bxor(c,data:byte(i)),0xFF)],rshift(c,8))end
    c=bxor(c,0xFFFFFFFF)
    return c<0 and c+4294967296 or c
end

-- SHA-256 (the manager GUID, as ModBuilder derives it). Returns the 32 raw bytes.
local K={0x428a2f98,0x71374491,0xb5c0fbcf,0xe9b5dba5,0x3956c25b,0x59f111f1,0x923f82a4,0xab1c5ed5,0xd807aa98,
    0x12835b01,0x243185be,0x550c7dc3,0x72be5d74,0x80deb1fe,0x9bdc06a7,0xc19bf174,0xe49b69c1,0xefbe4786,0x0fc19dc6,
    0x240ca1cc,0x2de92c6f,0x4a7484aa,0x5cb0a9dc,0x76f988da,0x983e5152,0xa831c66d,0xb00327c8,0xbf597fc7,0xc6e00bf3,
    0xd5a79147,0x06ca6351,0x14292967,0x27b70a85,0x2e1b2138,0x4d2c6dfc,0x53380d13,0x650a7354,0x766a0abb,0x81c2c92e,
    0x92722c85,0xa2bfe8a1,0xa81a664b,0xc24b8b70,0xc76c51a3,0xd192e819,0xd6990624,0xf40e3585,0x106aa070,0x19a4c116,
    0x1e376c08,0x2748774c,0x34b0bcb5,0x391c0cb3,0x4ed8aa4a,0x5b9cca4f,0x682e6ff3,0x748f82ee,0x78a5636f,0x84c87814,
    0x8cc70208,0x90befffa,0xa4506ceb,0xbef9a3f7,0xc67178f2}
local function rrot(x,n)return bor(rshift(x,n),lshift(x,32-n))end
function M.sha256(msg)
    local h={0x6a09e667,0xbb67ae85,0x3c6ef372,0xa54ff53a,0x510e527f,0x9b05688c,0x1f83d9ab,0x5be0cd19}
    local len=#msg
    msg=msg..'\128'..string.rep('\0',(55-len)%64)
    local bits=len*8
    local tail={}
    for i=7,0,-1 do tail[#tail+1]=string.char(math.floor(bits/2^(i*8))%256)end
    msg=msg..table.concat(tail)
    for chunk=1,#msg,64 do
        local w={}
        for i=0,15 do
            local a,b,c,d=msg:byte(chunk+i*4,chunk+i*4+3)
            w[i]=bor(lshift(a,24),lshift(b,16),lshift(c,8),d)
        end
        for i=16,63 do
            local s0=bxor(rrot(w[i-15],7),rrot(w[i-15],18),rshift(w[i-15],3))
            local s1=bxor(rrot(w[i-2],17),rrot(w[i-2],19),rshift(w[i-2],10))
            w[i]=bit.tobit(w[i-16]+s0+w[i-7]+s1)
        end
        local a,b,c,d,e,f,g,hh=h[1],h[2],h[3],h[4],h[5],h[6],h[7],h[8]
        for i=0,63 do
            local S1=bxor(rrot(e,6),rrot(e,11),rrot(e,25))
            local ch=bxor(band(e,f),band(bnot(e),g))
            local t1=bit.tobit(hh+S1+ch+K[i+1]+w[i])
            local S0=bxor(rrot(a,2),rrot(a,13),rrot(a,22))
            local maj=bxor(band(a,b),band(a,c),band(b,c))
            local t2=bit.tobit(S0+maj)
            hh,g,f,e,d,c,b,a=g,f,e,bit.tobit(d+t1),c,b,a,bit.tobit(t1+t2)
        end
        h[1],h[2],h[3],h[4]=bit.tobit(h[1]+a),bit.tobit(h[2]+b),bit.tobit(h[3]+c),bit.tobit(h[4]+d)
        h[5],h[6],h[7],h[8]=bit.tobit(h[5]+e),bit.tobit(h[6]+f),bit.tobit(h[7]+g),bit.tobit(h[8]+hh)
    end
    local out={}
    for i=1,8 do
        local v=h[i]
        out[i]=string.char(band(rshift(v,24),255),band(rshift(v,16),255),band(rshift(v,8),255),band(v,255))
    end
    return table.concat(out)
end

-- The mod manager GUID ModBuilder derives from the resource id (SHA-256, version 5 bits, .NET byte order).
function M.guid(resource)
    local b={M.sha256('hd2runtime-mod:'..resource):byte(1,16)}
    b[8]=bor(band(b[8],0x0F),0x50)
    b[9]=bor(band(b[9],0x3F),0x80)
    local function hex(...)local t={} for _,i in ipairs({...})do t[#t+1]=string.format('%02x',b[i])end return table.concat(t)end
    return hex(4,3,2,1)..'-'..hex(6,5)..'-'..hex(8,7)..'-'..hex(9,10)..'-'..hex(11,12,13,14,15,16)
end

------------------------------------------------------------------------------------------------- containers --
local function u32(n)return string.char(n%256,math.floor(n/256)%256,math.floor(n/65536)%256,math.floor(n/16777216)%256)end
local function u16(n)return string.char(n%256,math.floor(n/256)%256)end
local function pad16(s)return s..string.rep('\0',(-#s)%16)end
M.LUA_TYPE='a14e8dfa2cd117e2'
M.ARCHIVE='9ba626afa44a3aa3.patch_0'

-- The Stingray patch archive of Lua resources (hd2_archive.make_archive): {[resource name] = source}.
function M.archive(resources)
    local list={}
    for name,body in pairs(resources)do list[#list+1]={hash=M.murmur64(name),body=u32(#body)..u32(2)..body}end
    assert(#list>0,'at least one Lua resource is required')
    table.sort(list,function(a,b)return a.hash<b.hash end)
    local count=#list
    local offset=104+80*count
    offset=offset+(-offset)%16
    local entries,data={},{}
    local position=offset
    for index,item in ipairs(list)do
        entries[#entries+1]=u64_bytes(item.hash)..u64_bytes(M.LUA_TYPE)..u32(position)..u32(0)
            ..string.rep('\0',32)..u32(#item.body)..u32(0)..u32(0)..u32(16)..u32(16)..u32(index-1)
        local block=pad16(item.body)
        data[#data+1]=block
        position=position+#block
    end
    local header=u32(0xF0000011)..u32(1)..u32(count)..string.rep('\0',20)..u32(position)..u32(0)..string.rep('\0',8)
        ..string.rep('\0',24)
    local types=u32(0)..u32(0)..u64_bytes(M.LUA_TYPE)..u32(count)..u32(0)..u32(16)..u32(16)
    local head=header..types..table.concat(entries)
    head=head..string.rep('\0',offset-#head)
    return head..table.concat(data)
end

-- A ZIP of stored entries (sorted names, forward slashes, DOS date 1980-01-01): {[name] = bytes}.
function M.zip(files)
    local names={}
    for name in pairs(files)do names[#names+1]=name end
    table.sort(names)
    local out,central,offset={},{},0
    for _,name in ipairs(names)do
        local data=files[name]
        local crc=M.crc32(data)
        local local_header='PK\3\4'..u16(20)..u16(0)..u16(0)..u16(0)..u16(0x21)..u32(crc)..u32(#data)..u32(#data)
            ..u16(#name)..u16(0)..name
        out[#out+1]=local_header..data
        central[#central+1]='PK\1\2'..u16(20)..u16(20)..u16(0)..u16(0)..u16(0)..u16(0x21)..u32(crc)..u32(#data)
            ..u32(#data)..u16(#name)..u16(0)..u16(0)..u16(0)..u16(0)..u32(0)..u32(offset)..name
        offset=offset+#local_header+#data
    end
    local cd=table.concat(central)
    return table.concat(out)..cd..'PK\5\6'..u16(0)..u16(0)..u16(#names)..u16(#names)..u32(#cd)..u32(offset)..u16(0)
end

-- A small JSON writer (objects with ordered keys: {__order = {...}}).
local function json(v,indent,level)
    level=level or 0
    local t=type(v)
    if t=='string'then
        return '"'..v:gsub('[%c"\\]',function(c)
            local map={['"']='\\"',['\\']='\\\\',['\n']='\\n',['\r']='\\r',['\t']='\\t'}
            return map[c]or string.format('\\u%04x',c:byte())
        end)..'"'
    elseif t=='number'then
        if v%1==0 and math.abs(v)<2^53 then return string.format('%d',v)end
        return string.format('%.17g',v)
    elseif t=='boolean'then return tostring(v)
    elseif v==nil then return'null'end
    local pad=string.rep('  ',level+1)
    local close=string.rep('  ',level)
    if#v>0 or rawget(v,'__array')then
        local parts={}
        for i,x in ipairs(v)do parts[i]=pad..json(x,indent,level+1)end
        if#parts==0 then return'[]'end
        return '[\n'..table.concat(parts,',\n')..'\n'..close..']'
    end
    local keys=v.__order
    if not keys then
        keys={}
        for k in pairs(v)do if k~='__order'and k~='__array'then keys[#keys+1]=k end end
        table.sort(keys)
    end
    local parts={}
    for _,k in ipairs(keys)do
        if v[k]~=nil then parts[#parts+1]=pad..json(tostring(k))..': '..json(v[k],indent,level+1)end
    end
    if#parts==0 then return'{}'end
    return '{\n'..table.concat(parts,',\n')..'\n'..close..'}'
end
M.json=json

---------------------------------------------------------------------------------------------- the addon --
-- Target code: the catalogue's hd2 is a proxy (catalog.lua); while tracing, every hd2 call returns a recorder whose
-- method calls extend its Lua text, so a row's own target function yields exactly the code that builds the target.
local function literal(v)
    local t=type(v)
    if t=='string'then return string.format('%q',v)end
    if t=='number'then
        if v%1==0 and math.abs(v)<2^53 then return string.format('%d',v)end
        local s=string.format('%.9g',v)
        if tonumber(s)~=v then s=string.format('%.17g',v)end
        return s
    end
    if t=='boolean'then return tostring(v)end
    if t=='table'and rawget(v,'__code')then return v.__code end
    if t=='table'and getmetatable(v)==nil then
        local parts={}
        for i,x in ipairs(v)do parts[i]=literal(x)end
        return '{'..table.concat(parts,',')..'}'
    end
    error('cannot write '..tostring(v)..' as Lua',0)
end
M.literal=literal
local Recorder={}
Recorder.__index=function(self,name)
    if name=='__code'then return rawget(self,'__code')end
    return function(_,...)
        local args={}
        for i,a in ipairs({...})do args[i]=literal(a)end
        return setmetatable({__code=rawget(self,'__code')..':'..name..'('..table.concat(args,',')..')'},Recorder)
    end
end
M.tracing=nil
function M.recorder(name)
    return function(...)
        local args={}
        for i,a in ipairs({...})do args[i]=literal(a)end
        return setmetatable({__code='hd2.'..name..'('..table.concat(args,',')..')'},Recorder)
    end
end
-- The Lua text a row function builds (target or expect), traced.
function M.trace(fn)
    M.tracing=M.recorder
    local ok,result=pcall(fn)
    M.tracing=nil
    if not ok then error(result,0)end
    if type(result)=='table'and rawget(result,'__code')then return result.__code end
    return literal(result)
end

-- The Lua text of a field value: plain values as literals, reference handles by what names them.
function M.value_code(catalog_module,row,value,target_code)
    if type(value)~='table'or getmetatable(value)==nil then return literal(value)end
    local stored=catalog_module.encode(row,value)
    if type(stored)~='table'then error('a '..tostring(row.kind)..' value that cannot be exported',0)end
    if stored.ref=='output'then return 'hd2.attack_output('..literal(stored.id)..')'end
    if stored.ref=='pickup'then return 'hd2.pickup('..literal(stored.id)..')'end
    if stored.ref=='none'then return target_code..':no_explosion()'end
    if stored.ref=='terminal'then
        return 'hd2.weapon('..literal(stored.weapon)..'):attack('..literal(stored.attack)..'):projectile():terminal_action('
            ..literal(stored.phase)..'):explosion()'
    end
    if stored.ref=='projectile'then
        return 'hd2.weapon('..literal(stored.weapon)..'):attack('..literal(stored.attack)..'):projectile()'
    end
    error('a '..tostring(stored.ref)..' reference that cannot be exported',0)
end

-- One operation's Lua text for a change {row, value}, or nil and why.
function M.operation(catalog_module,entry,id)
    local row,value=entry.row,entry.value
    if row.controller then return nil,row.export_reason or'this change is not an ensure and cannot be exported'end
    local ok,text=pcall(function()
        local target=M.trace(row.target)
        local expect=row.expect and M.trace(row.expect)or literal(row.vanilla)
        local val=M.value_code(catalog_module,row,value,target)
        local acks={}
        local okp,result=catalog_module.probe(row,value)
        if okp and type(result)=='table'then for k,on in pairs(result)do if on then acks[#acks+1]=k end end end
        table.sort(acks)
        local flags=''
        for _,k in ipairs(acks)do flags=flags..'\n        '..k..'=true,'end
        local binding=catalog_module.rate_binding(row,value)
        local comment='-- '..row.object.name..': '..row.label..'\n'
        if binding then
            return comment..'add(function() return hd2.ensure({\n    transaction={\n        id='..literal(id)..',\n'
                ..'        target='..target..',\n        changes={\n'
                ..'            {field='..literal(row.field)..',expect='..expect..',value='..val..'},\n'
                ..'            {field='..literal(binding.field)..',expect='..literal(binding.expect)..',value='
                ..literal(binding.value)..'},\n        },'..flags..'\n    }\n}) end)\n'
        end
        return comment..'add(function() return hd2.ensure({\n    patch={\n        id='..literal(id)..',\n'
            ..'        target='..target..',\n        field='..literal(row.field)..',\n        expect='..expect..',\n'
            ..'        value='..val..','..flags..'\n    }\n}) end)\n'
    end)
    if not ok then return nil,tostring(text)end
    return text
end

-- The addon source for the chosen changes, and the changes left out (with why).
function M.addon(catalog_module,entries,meta)
    local parts={'-- '..meta.name..' '..meta.version..': exported from HD2R Editor ('..#entries..' changes).\n',
        "local hd2=require('mods/skyeshade/hd2runtime')\n\nlocal operations={}\nlocal function add(build)\n",
        '    local ok,operation=pcall(build)\n    if ok then operations[#operations+1]=operation\n',
        "    else print('["..meta.name:gsub("'","").."] operation skipped: '..tostring(operation)) end\nend\n\n"}
    local skipped={}
    local prefix='hd2r-'..M.murmur64(meta.resource):sub(1,8)..'-'
    for i,entry in ipairs(entries)do
        local text,why=M.operation(catalog_module,entry,prefix..i)
        if text then parts[#parts+1]=text..'\n'else skipped[#skipped+1]={entry=entry,why=why}end
    end
    parts[#parts+1]='return operations\n'
    return table.concat(parts),skipped
end

-- The SDK wrapper (hd2.py wrap_addon): the dependency check, then the body once per session as the mod.
function M.wrap(resource,minimum,body,display)
    -- (the header text is assembled: the SDK refuses a source file that contains it)
    return '-- HD2'..'-Addon: '..resource..'\n'..[[local loader=rawget(_G,'CowboyBingusModLoader')
assert(loader and loader.api==1 and type(loader.version)=='number' and loader.version>=16,
    'Requires Bingus Shared Loader v15+ / API 1')
local hd2=require('mods/skyeshade/hd2runtime')
local function semver(v)
    local core,pre=tostring(v):match('^([^%-+]+)%-?([^+]*)')
    local a,b,c=(core or''):match('^(%d+)%.(%d+)%.(%d+)$')
    assert(a,'Invalid HD2Runtime version: '..tostring(v))
    local ids={}
    for id in(pre~=''and pre..'.'or''):gmatch('([^%.]*)%.')do ids[#ids+1]=id end
    return {tonumber(a),tonumber(b),tonumber(c),ids}
end
local function order(p,q)
    local x,y=tonumber(p:match('^%d+$')),tonumber(q:match('^%d+$'))
    if x and y then return x<y and -1 or x>y and 1 or 0 end
    if x then return -1 end
    if y then return 1 end
    return p<q and -1 or p>q and 1 or 0
end
local function at_least(have,need)
    local x,y=semver(have),semver(need)
    for i=1,3 do if x[i]~=y[i]then return x[i]>y[i]end end
    local p,q=x[4],y[4]
    if#p==0 then return true end
    if#q==0 then return false end
    for i=1,math.max(#p,#q)do
        if p[i]==nil then return false end
        if q[i]==nil then return true end
        local o=order(p[i],q[i])
        if o~=0 then return o>0 end
    end
    return true
end
]]..'local minimum='..literal(minimum)..'\n'..[[local satisfied=hd2.api_version==1 and at_least(hd2.version,minimum)
if not satisfied and hd2.api_version==1 then
    local compatibility=type(hd2.compatibility)=='table'and hd2.compatibility.require_runtime
    if type(compatibility)=='function'then pcall(compatibility,]]..literal(resource)..',minimum,'..literal(display)..[[)end
end
assert(satisfied,'HD2Runtime dependency version mismatch')
local key='HD2RuntimeMod:'..]]..literal(resource)..'\n'..[[local existing=rawget(_G,key)
if existing then return existing end
local function start()
]]..body..[[
end
local run=type(hd2.events)=='table' and hd2.events.run_as
local state
if type(run)=='function' then state=run(]]..literal(resource)..[[,start) else state=start() end
state=state or true
rawset(_G,key,state)
return state
]]
end

---------------------------------------------------------------------------------------------- the files --
local function slug(text)
    local s=tostring(text or''):lower():gsub('[^%w]+','_'):gsub('^_+',''):gsub('_+$','')
    return s~=''and s:sub(1,40)or'mod'
end
M.slug=slug
function M.safe_name(text)
    local s=tostring(text or''):gsub('[^%w%._%-]+','-'):gsub('^[%-%.]+',''):gsub('[%-%.]+$','')
    return s~=''and s or'HD2Mod'
end
local function read(path)
    local ok,f=pcall(io.open,path,'rb')
    if not ok or not f then return nil end
    local data=f:read('*a');f:close()
    return data
end
local function write(path,data)
    local f,why=io.open(path,'wb')
    if not f then error('cannot write '..path..': '..tostring(why),0)end
    f:write(data);f:close()
end

-- Everything an export writes, in memory: {zip = bytes, files = {[project path] = bytes}, name, resource, ...}.
-- meta = {name, version, description, author, image (file path or nil), minimum (HD2Runtime version)}.
function M.build(catalog_module,entries,meta)
    assert(tostring(meta.version):match('^%d+%.%d+%.%d+$'),'the version must look like 1.0.0')
    local author=slug(meta.author~=''and meta.author or'player')
    local resource='mods/'..author..'/'..slug(meta.name)
    meta.resource=resource
    local source,skipped=M.addon(catalog_module,entries,meta)
    assert(#entries>#skipped,'none of the chosen changes could be exported')
    local display=meta.name
    local requirement='Requires Bingus Shared Loader v15+ / API 1 and HD2Runtime '..meta.minimum
        ..'+ / API 1; install dependencies separately.'
    local guid=M.guid(resource)
    local icon_name,icon
    if meta.image then
        icon=read(meta.image)
        if not icon then error('cannot read the image '..meta.image,0)end
        local ext=(meta.image:match('%.(%w+)$')or'png'):lower()
        icon_name='thumbnail.'..ext
    end
    local description=meta.description~=''and meta.description or display
    local manifest={__order={'Version','Guid','Name','Description','IconPath','Options'},Version=1,Guid=guid,
        Name=display..' '..meta.version,Description=description..'\n\n// '..requirement,IconPath=icon_name,
        Options={{__order={'Name','Description','Include','Image'},Name=display,Description=description,
            Include={'mod'},Image=icon_name}}}
    local requires={__order={'bingus','hd2runtime'},bingus={__order={'min_release','api'},min_release=15,api=1},
        hd2runtime={__order={'module','min_version','api'},module='mods/skyeshade/hd2runtime',min_version=meta.minimum,api=1}}
    local spec={__order={'format','name','author','version','resource','guid','thumbnail','requires'},format=1,
        name=display,author=meta.author~=''and meta.author or nil,version=meta.version,resource=resource,guid=guid,
        thumbnail=icon_name,requires=requires}
    local report={__order={'resource','builder','runtime_bundled','sdk_stubs_bundled','requires','changes','skipped',
        'deployed','game_launched'},resource=resource,builder='HD2R Editor '..tostring(meta.editor_version or''),
        runtime_bundled=false,sdk_stubs_bundled=false,requires=requires,changes=#entries-#skipped,skipped=#skipped,
        deployed=false,game_launched=false}
    local readme='# '..display..'\n\n'..description..'\n\nBy '..(meta.author~=''and meta.author or'a player')
        ..'. Exported from HD2R Editor.\n\n'..requirement
        ..'\n\nInstall this gameplay ZIP through your mod manager after installing both dependencies.\n'
    local wrapped=M.wrap(resource,meta.minimum,source,display)
    local files={['manifest.json']=json(manifest)..'\n',['hd2runtime.json']=json(spec)..'\n',
        ['build-report.json']=json(report)..'\n',['README.md']=readme,['src/addon.lua']=source,
        ['mod/'..M.ARCHIVE]=M.archive({[resource]=wrapped}),['mod/'..M.ARCHIVE..'.stream']='',
        ['mod/'..M.ARCHIVE..'.gpu_resources']=''}
    if icon then files[icon_name]=icon end
    local project={['hd2runtime.json']=files['hd2runtime.json'],['src/addon.lua']=source}
    if icon then project[icon_name]=icon end
    return {zip=M.zip(files),files=files,project=project,resource=resource,guid=guid,skipped=skipped,
        zip_name=M.safe_name(display)..'-'..meta.version..'.zip',source=source,wrapped=wrapped}
end

-- Writes the build into folder: <name>-<version>.zip and project\..., returns the zip path.
function M.write(result,folder,mkdir)
    mkdir(folder)
    mkdir(folder..'\\project\\src')
    local zip_path=folder..'\\'..result.zip_name
    write(zip_path,result.zip)
    for name,data in pairs(result.project)do write(folder..'\\project\\'..name:gsub('/','\\'),data)end
    return zip_path
end

-- The export folder: Documents\HD2R Editor\Exports.
function M.folder()
    local ok,home=pcall(os.getenv,'USERPROFILE')
    if not ok or not home then return nil end
    return home..'\\Documents\\HD2R Editor\\Exports'
end

return M

-- Small helpers shared by the editor's modules: numbers, text and safe calls. No game access.
local M={}

M.DECIMALS=3            -- script values (the editor's live handles) carry at most three decimals
M.STEP=10^-M.DECIMALS

function M.finite(n)return type(n)=='number'and n==n and n>-math.huge and n<math.huge end
function M.clamp(v,lo,hi)
    if lo and v<lo then return lo end
    if hi and v>hi then return hi end
    return v
end
-- Rounds to `places` decimals and returns the value tostring() would print for it (no binary tail).
function M.round(v,places)
    places=places or M.DECIMALS
    return tonumber(string.format('%.'..places..'f',v))
end

-- float32 rounding (the bytes a f32 field stores). LuaJIT's ffi when present; otherwise the value itself.
local f32
do
    local ok,ffi=pcall(require,'ffi')
    if ok and ffi then
        local box=ffi.new('float[1]')
        f32=function(v)box[0]=v;return tonumber(box[0])end
    else
        f32=function(v)return v end
    end
end
M.f32=f32

-- The value as the editor can hold it in a live handle (three decimals, or an integer), or nil when the stored value
-- has no such form. A float field's 0.30000001192092896 is the f32 of 0.3, so it is held as 0.3: the same bytes.
function M.representable(v,integer,storage)
    if not M.finite(v)then return nil end
    if integer then
        if v%1==0 then return v end
        return nil
    end
    local r=M.round(v)
    if r==v then return r end
    if storage=='f32'and f32(r)==f32(v)then return r end
    if math.abs(r-v)<=1e-9*math.max(1,math.abs(v))then return r end
    return nil
end

-- A number as the editor shows it: integers plainly, decimals trimmed (at most `places`).
function M.format(v,places)
    if v==nil then return '-'end
    if type(v)~='number'then return tostring(v)end
    if v~=v then return 'nan'end
    if v%1==0 and math.abs(v)<1e15 then return string.format('%d',v)end
    local s=string.format('%.'..(places or M.DECIMALS)..'f',v)
    s=s:gsub('0+$',''):gsub('%.$','')
    if s=='-0'then s='0'end
    return s
end

-- Plain printable text of at most `limit` bytes (the overlay refuses control characters and long lines).
function M.plain(text,limit)
    text=tostring(text==nil and''or text):gsub('[%z\1-\31\127]',' ')
    limit=limit or 160
    if#text>limit then text=text:sub(1,limit)end
    return text
end

-- 'damage.ap_direct' -> 'AP direct'; 'fire_rate' -> 'Fire rate'.
local WORDS={ap='AP',rpm='RPM',hp='HP',id='ID',ui='UI',fov='FOV',aoe='AoE',ems='EMS',mg='MG'}
function M.humanize(id)
    local last=tostring(id):match('([^%.]+)$')or tostring(id)
    local words={}
    for word in last:gmatch('[^_]+')do words[#words+1]=WORDS[word]or word end
    local text=table.concat(words,' ')
    return (text:gsub('^%l',string.upper))
end

-- Short unit labels for the field list ('degrees_per_second' -> '°/s').
local UNITS={rpm='rpm',mrad='mrad',seconds='s',second='s',milliseconds='ms',degrees='°',degrees_per_second='°/s',
    degrees_per_second_squared='°/s²',meters='m',metres='m',meters_per_second='m/s',meters_per_second_squared='m/s²',
    grams='g',kilograms='kg',multiplier='×',factor='×',scale='×',fraction='',ratio='',percent='%',damage='',
    health='hp',armor_class='AP',armor='AP',force='',rounds='rnd',round='rnd',projectiles='',count='',
    throwables='',magazines='mag',radians='rad',radians_per_second='rad/s',heat='heat',uses='uses',charges='',
    shells='',salvos='',mines='',bombs='',rockets='',pellets='',units='',boolean=''}
function M.unit(unit)
    if unit==nil then return nil end
    local short=UNITS[unit]
    if short then return short~=''and short or nil end
    local text=tostring(unit):gsub('_per_','/'):gsub('_',' ')
    return text
end

-- Whether two field values are the same value: primitives by ==; typed reference handles (each built with its own
-- metatable) by every non-function field they carry; plain tables (calldown codes) element by element. The same rule
-- as HD2Runtime's script choices (api/options.lua same).
function M.same(a,b,depth)
    if rawequal(a,b)then return true end
    if type(a)~=type(b)then return false end
    if type(a)~='table'then return a==b end
    if(depth or 0)>8 then return false end
    if(getmetatable(a)~=nil)~=(getmetatable(b)~=nil)then return false end
    for k,v in pairs(a)do
        if type(v)~='function'and not M.same(v,rawget(b,k),(depth or 0)+1)then return false end
    end
    for k,v in pairs(b)do
        if type(v)~='function'and rawget(a,k)==nil then return false end
    end
    return true
end

-- A calldown code in arrows ('↑ → ↓').
local ARROWS={up='↑',down='↓',left='←',right='→'}
M.ARROWS=ARROWS
function M.code_text(code)
    local parts={}
    for i,d in ipairs(code)do parts[i]=ARROWS[d]or tostring(d)end
    return table.concat(parts,' ')
end
-- Any field value as text: numbers, On/Off, Unlimited/None, names, codes and reference handles.
function M.value_text(v)
    local t=type(v)
    if t=='number'then return M.format(v)end
    if t=='boolean'then return v and'On'or'Off'end
    if t=='string'then
        if v=='unlimited'then return 'Unlimited'end
        if v=='none'then return 'None'end
        return M.humanize(v)
    end
    if t~='table'then return tostring(v)end
    if getmetatable(v)==nil then
        if#v>0 and type(v[1])=='string'and ARROWS[v[1]]then return M.code_text(v)end
        if#v==3 and type(v[1])=='number'and type(v[2])=='number'and type(v[3])=='number'then
            local parts={}
            for i,x in ipairs(v)do parts[i]=x==0 and'-'or M.format(x)end
            return table.concat(parts,' / ')
        end
        if rawget(v,'is_null')or rawget(v,'path')=='no_explosion'then return 'None'end
        local parts={}
        for i,x in ipairs(v)do parts[i]=M.value_text(x)end
        return table.concat(parts,', ')
    end
    if rawget(v,'is_null')or rawget(v,'none')or rawget(v,'path')=='no_explosion'then return 'None'end
    local output=rawget(v,'output')
    if type(output)=='string'then return(output:match('([^/]+)$')or output):gsub('%-',' ')end
    if rawget(v,'resource')=='pickup'then return tostring(rawget(v,'name')or'pickup')end
    local weapon,attack,phase=rawget(v,'weapon'),rawget(v,'attack'),rawget(v,'phase')
    if weapon then
        return tostring(weapon)..(attack and attack~='primary'and(' · '..M.humanize(attack))or'')
            ..(phase and(' · '..M.humanize(phase))or'')
    end
    return 'reference'
end

function M.copy(t)
    local out={}
    for k,v in pairs(t)do out[k]=v end
    return out
end
function M.count(t)
    local n=0
    for _ in pairs(t)do n=n+1 end
    return n
end
function M.sorted_keys(t,cmp)
    local out={}
    for k in pairs(t)do out[#out+1]=k end
    table.sort(out,cmp or function(a,b)return tostring(a)<tostring(b)end)
    return out
end
-- Natural order for names with numbers ('AR-23' before 'AR-111'), case-insensitive.
function M.natural_less(a,b)
    local function key(s)return tostring(s):lower():gsub('%d+',function(d)return string.format('%09d',tonumber(d))end)end
    return key(a)<key(b)
end

-- pcall that returns (true, ...) or (false, message) with the message as a short string.
function M.try(fn,...)
    local results={pcall(fn,...)}
    if not results[1]then return false,tostring(results[2])end
    return unpack(results,1,table.maxn(results))
end

-- A short id fragment: [%w_-] only, at most `limit` bytes.
function M.slug(text,limit)
    local s=tostring(text):lower():gsub('[^%w]+','-'):gsub('^%-+',''):gsub('%-+$','')
    if#s>(limit or 24)then s=s:sub(1,limit or 24)end
    return s==''and'x'or s
end

return M

-- HD2R Editor (c) 2026 SkyeShade. All rights reserved except as granted in LICENSE
-- (https://github.com/SkyeShade/HD2Runtime-Editor). Do not redistribute or reuse without the credit it requires.
-- A small JSON reader for the mod managers' state files (Echelon state.json, HD2 Arsenal hd2a_data.json), preset
-- files and ModBuilder projects. decode(text, yield_every, strict): objects become tables, arrays become lists, null
-- becomes nil. With yield_every, the decoder calls coroutine.yield(position, length) after that many values (the byte
-- it reached and the text's length, for a progress line), so a caller running it in a coroutine can spread a large
-- file over several frames. strict: text after the value is an error too. An error names its byte ('JSON: <what> at
-- byte N'); M.explain turns that into a line and column.
local M={}

local ESCAPES={['"']='"',['\\']='\\',['/']='/',b='\b',f='\f',n='\n',r='\r',t='\t'}

local function utf8(code)
    if code<0x80 then return string.char(code)end
    if code<0x800 then return string.char(0xC0+math.floor(code/64),0x80+code%64)end
    return string.char(0xE0+math.floor(code/4096),0x80+math.floor(code/64)%64,0x80+code%64)
end

function M.decode(text,yield_every,strict)
    local pos,count=1,0
    local find,sub,byte=string.find,string.sub,string.byte
    local function fail(what)error('JSON: '..what..' at byte '..pos,0)end
    local function skip()
        local _,e=find(text,'^[ \t\r\n]*',pos)
        pos=e+1
    end
    local value
    local function str()
        pos=pos+1
        local parts={}
        while true do
            local s,e=find(text,'["\\]',pos)
            if not s then fail('unterminated string')end
            parts[#parts+1]=sub(text,pos,s-1)
            if sub(text,s,s)=='"'then pos=e+1;break end
            local c=sub(text,s+1,s+1)
            if c=='u'then
                local code=tonumber(sub(text,s+2,s+5),16)or 63
                if code>=0xD800 and code<0xDC00 and sub(text,s+6,s+7)=='\\u'then
                    local low=tonumber(sub(text,s+8,s+11),16)or 0xDC00
                    code=0x10000+(code-0xD800)*1024+(low-0xDC00)
                    pos=s+12
                    parts[#parts+1]=code<0x10000 and utf8(code)or string.char(0xF0+math.floor(code/262144),
                        0x80+math.floor(code/4096)%64,0x80+math.floor(code/64)%64,0x80+code%64)
                else
                    parts[#parts+1]=utf8(code)
                    pos=s+6
                end
            else
                parts[#parts+1]=ESCAPES[c]or c
                pos=s+2
            end
        end
        return table.concat(parts)
    end
    function value()
        count=count+1
        if yield_every and count%yield_every==0 then coroutine.yield(pos,#text)end
        skip()
        local c=byte(text,pos)
        if c==34 then return str()
        elseif c==123 then
            pos=pos+1
            local out={}
            skip()
            if byte(text,pos)==125 then pos=pos+1;return out end
            while true do
                skip()
                if byte(text,pos)~=34 then fail('object key expected')end
                local key=str()
                skip()
                if byte(text,pos)~=58 then fail('":" expected')end
                pos=pos+1
                out[key]=value()
                skip()
                local d=byte(text,pos)
                pos=pos+1
                if d==125 then return out end
                if d~=44 then fail('"," or "}" expected')end
            end
        elseif c==91 then
            pos=pos+1
            local out={}
            skip()
            if byte(text,pos)==93 then pos=pos+1;return out end
            while true do
                out[#out+1]=value()
                skip()
                local d=byte(text,pos)
                pos=pos+1
                if d==93 then return out end
                if d~=44 then fail('"," or "]" expected')end
            end
        elseif sub(text,pos,pos+3)=='true'then pos=pos+4;return true
        elseif sub(text,pos,pos+4)=='false'then pos=pos+5;return false
        elseif sub(text,pos,pos+3)=='null'then pos=pos+4;return nil
        else
            local s,e=find(text,'^-?%d+%.?%d*[eE]?[-+]?%d*',pos)
            if not s then fail('unexpected character')end
            pos=e+1
            return tonumber(sub(text,s,e))
        end
    end
    local result=value()
    if strict then
        skip()
        if pos<=#text then fail('unexpected text after the end')end
    end
    return result
end

-- The line and column of byte `pos` in text (1-based), for an error a person can find.
function M.where(text,pos)
    local line,last=1,0
    local find=string.find
    local at=1
    while true do
        local s=find(text,'\n',at,true)
        if not s or s>=pos then break end
        line,last,at=line+1,s,s+1
    end
    return line,pos-last
end
-- 'JSON: x at byte N' -> 'x at line L, column C' (any other message as it is).
function M.explain(text,message)
    message=tostring(message)
    local what,byte=message:match('^JSON: (.-) at byte (%d+)$')
    if not what then return message end
    local line,column=M.where(text,tonumber(byte))
    return what..' at line '..line..', column '..column
end

return M

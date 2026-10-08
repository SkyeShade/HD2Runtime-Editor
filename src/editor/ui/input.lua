-- HD2R Editor (c) 2026 SkyeShade. All rights reserved except as granted in LICENSE
-- (https://github.com/SkyeShade/HD2Runtime-Editor). Do not redistribute or reuse without the credit it requires.
-- One frame of input for the editor, read through hd2.input (sampled once per update, only while the game window has
-- the focus). Navigation keys repeat while held; typing keys become characters. Nothing is consumed: the game sees
-- every key too (docs/events.md "Input blocking"), so the editor only reads keys while it is open.
local M={}
local REPEAT_DELAY,REPEAT_RATE=0.36,0.045

local NAV={'UP','DOWN','LEFT','RIGHT','PAGEUP','PAGEDOWN','HOME','END','TAB','ENTER','ESCAPE','BACKSPACE','DELETE',
    'F9','F10','INSERT'}
local REPEATS={UP=true,DOWN=true,LEFT=true,RIGHT=true,PAGEUP=true,PAGEDOWN=true,BACKSPACE=true}
local CHARS={PERIOD='.',DECIMAL='.',MINUS='-',SUBTRACT='-',SPACE=' ',SLASH='/',COMMA=','}
for i=0,9 do CHARS[tostring(i)]=tostring(i);CHARS['NUMPAD'..i]=tostring(i)end
local LETTERS={}
for i=0,25 do LETTERS[#LETTERS+1]=string.char(65+i)end
-- the keys the editor reads while open (the open/close key must leave them alone)
M.NAV,M.CHARS=NAV,CHARS

local Input={};Input.__index=Input
function M.new(hd2)
    return setmetatable({hd2=hd2,held={},prev_left=false,last_mouse=nil,unknown={}},Input)
end
function Input:query(kind,name)
    if self.unknown[name]then return false end
    local fn=self.hd2.input and self.hd2.input[kind]
    if type(fn)~='function'then return false end
    local ok,value=pcall(fn,name)
    if not ok then self.unknown[name]=true;return false end
    return value==true
end
-- The engine mouse wheel this frame (+ up), as the Runtime's own panel reads it: the 'wheel' axis of stingray.Mouse, its
-- y read on its own (a failed field read must not hide the vector form). 0 when unavailable.
local function wheel()
    local stingray=rawget(_G,'stingray')
    local mouse=type(stingray)=='table'and stingray.Mouse
    if type(mouse)~='table'then return 0 end
    local ok,v=pcall(function()return mouse.axis(mouse.axis_index('wheel'))end)
    if not ok or v==nil then return 0 end
    if type(v)=='number'then return v>0 and 1 or v<0 and-1 or 0 end
    local y
    local oky,value=pcall(function()return v.y end)
    if oky and type(value)=='number'then y=value end
    if y==nil then
        local oke,_,ey=pcall(function()return stingray.Vector3.to_elements(v)end)
        if oke and type(ey)=='number'then y=ey end
    end
    if y==nil then
        local oki,value2=pcall(function()return v[2]end)
        if oki and type(value2)=='number'then y=value2 end
    end
    if type(y)~='number'or y~=y then return 0 end
    if y>0 then return 1 elseif y<0 then return-1 end
    return 0
end

-- The frame: {keys = {name = true} (presses and repeats), shift, ctrl, alt, chars = {...}, mouse, wheel}.
-- opts: {typing = poll digits and '.', '-'; letters = poll A-Z and space; mouse = function() -> {x, y, left}}.
function Input:poll(dt,opts)
    opts=opts or{}
    local frame={keys={},chars={},wheel=0}
    frame.shift=self:query('down','SHIFT')
    frame.ctrl=self:query('down','CTRL')
    frame.alt=self:query('down','ALT')
    for _,name in ipairs(NAV)do
        if self:query('pressed',name)then
            frame.keys[name]=true
            if REPEATS[name]then self.held[name]=REPEAT_DELAY end
        elseif REPEATS[name]and self.held[name]then
            if self:query('down',name)then
                self.held[name]=self.held[name]-dt
                if self.held[name]<=0 then
                    frame.keys[name]=true
                    self.held[name]=REPEAT_RATE
                end
            else self.held[name]=nil end
        end
    end
    if opts.typing or opts.letters then
        for name,char in pairs(CHARS)do
            if(opts.letters or char:match('[%d%.%-]'))and self:query('pressed',name)then
                frame.chars[#frame.chars+1]=char
            end
        end
    end
    if opts.letters then
        for _,name in ipairs(LETTERS)do
            if self:query('pressed',name)then
                frame.chars[#frame.chars+1]=frame.shift and name or name:lower()
            end
        end
    end
    if opts.mouse then
        local ok,m=pcall(opts.mouse)
        if ok and type(m)=='table'and type(m.x)=='number'then
            local moved=not self.last_mouse or math.abs(m.x-self.last_mouse.x)+math.abs(m.y-self.last_mouse.y)>1.5
            frame.mouse={x=m.x,y=m.y,left=m.left==true,clicked=m.left==true and not self.prev_left,
                released=m.left~=true and self.prev_left,moved=moved,rclicked=self:query('pressed','MOUSE2')}
            self.prev_left=m.left==true
            if moved then self.last_mouse={x=m.x,y=m.y}end
        else
            self.prev_left=false
        end
        -- HD2Runtime r51: hd2.input.wheel (the engine axis and a read-only message hook); before, the engine axis only
        local runtime_wheel=self.hd2.input and self.hd2.input.wheel
        if type(runtime_wheel)=='function'then
            local ok,v=pcall(runtime_wheel)
            frame.wheel=(ok and type(v)=='number'and v>0 and 1)or(ok and type(v)=='number'and v<0 and-1)or 0
        else
            frame.wheel=wheel()
        end
    end
    return frame
end
function Input:reset()self.held={};self.prev_left=false end

return M

-- HD2R Editor (c) 2026 SkyeShade. All rights reserved except as granted in LICENSE
-- (https://github.com/SkyeShade/HD2Runtime-Editor). Do not redistribute or reuse without the credit it requires.
-- A drawing surface over one overlay frame: 1080p units relative to the panel, scaled and snapped to whole pixels,
-- text measured with the overlay's own metrics (and cached), and the clickable regions of the frame.
local theme=require('mods/skyeshade/hd2runtime_editor/editor/ui/theme')
local util=require('mods/skyeshade/hd2runtime_editor/editor/util')
local M={}
local Canvas={};Canvas.__index=Canvas
local CACHE_LIMIT=4096

function M.new()return setmetatable({widths={},width_count=0,fits={},fit_count=0,hits={}},Canvas)end

function Canvas:begin(d,ox,oy)
    self.d,self.s,self.ox,self.oy=d,d.scale or 1,ox or 0,oy or 0
    self.width,self.height=(d.width or 1920)/self.s,(d.height or 1080)/self.s
    -- the previous frame's regions answer this frame's clicks (input is read before drawing)
    self.prev_hits=self.hits or{}
    self.hits={}
end
local function px(v)return math.floor(v+0.5)end
function Canvas:rect(x,y,w,h,colour,z)
    if w<=0 or h<=0 then return end
    local s=self.s
    local x0,y0=px((self.ox+x)*s),px((self.oy+y)*s)
    local x1,y1=px((self.ox+x+w)*s),px((self.oy+y+h)*s)
    if x1<=x0 then x1=x0+1 end
    if y1<=y0 then y1=y0+1 end
    self.d:rect(x0,y0,x1-x0,y1-y0,colour,z or 0)
end
-- A frame of `t` units around a box.
function Canvas:frame(x,y,w,h,colour,z,t)
    t=t or 1
    self:rect(x,y,w,t,colour,z);self:rect(x,y+h-t,w,t,colour,z)
    self:rect(x,y+t,t,h-2*t,colour,z);self:rect(x+w-t,y+t,t,h-2*t,colour,z)
end

-- Width of text in units.
function Canvas:measure(text,size,font)
    font=font or'body'
    local key=font..'\0'..size..'\0'..text
    local w=self.widths[key]
    if w then return w end
    local ok,value=pcall(self.d.text_width,self.d,text,size*self.s,font)
    w=ok and type(value)=='number'and value/self.s or#text*size*0.55
    if self.width_count>CACHE_LIMIT then self.widths,self.width_count={},0 end
    self.widths[key]=w
    self.width_count=self.width_count+1
    return w
end
-- The longest prefix of text that fits in `max` units, with '...' when cut.
function Canvas:fit(text,max,size,font)
    text=util.plain(text,160)
    if max<=0 then return ''end
    local key=(font or'body')..'\0'..size..'\0'..max..'\0'..text
    local cached=self.fits[key]
    if cached then return cached end
    local result=text
    if self:measure(text,size,font)>max then
        local lo,hi=0,#text
        while lo<hi do
            local mid=math.floor((lo+hi+1)/2)
            if self:measure(text:sub(1,mid)..'...',size,font)<=max then lo=mid else hi=mid-1 end
        end
        -- never cut inside a UTF-8 sequence
        while lo>0 and text:byte(lo+1)and text:byte(lo+1)>=0x80 and text:byte(lo+1)<0xC0 do lo=lo-1 end
        result=lo>0 and(text:sub(1,lo):gsub('%s+$','')..'...')or''
    end
    if self.fit_count>CACHE_LIMIT then self.fits,self.fit_count={},0 end
    self.fits[key]=result
    self.fit_count=self.fit_count+1
    return result
end
-- Text with its cap height centred on `cy` (opts: size, colour, font, align, z, max).
function Canvas:text(text,x,cy,opts)
    opts=opts or{}
    local size=opts.size or theme.size.body
    text=tostring(text==nil and''or text)
    if opts.max then text=self:fit(text,opts.max,size,opts.font)else text=util.plain(text,160)end
    if text==''then return 0 end
    local s=self.s
    local y=cy-size*theme.CAP_OFFSET
    local w
    if opts.align=='right'then w=self:measure(text,size,opts.font);x=x-w
    elseif opts.align=='center'then w=self:measure(text,size,opts.font);x=x-w/2 end
    self.d:text(text,px((self.ox+x)*s),px((self.oy+y)*s),
        {size=size*s,colour=opts.colour or theme.colour.text,font=opts.font or'body',z=opts.z or 5})
    return w or self:measure(text,size,opts.font)
end

-- One of the mod's images (HD2Runtime r50 d:image), in units; nothing when the overlay has no images.
function Canvas:image(handle,x,y,w,h,opts)
    if type(self.d.image)~='function'or handle==nil then return end
    local s=self.s
    local x0,y0=px((self.ox+x)*s),px((self.oy+y)*s)
    local size=px(w*s)
    self.d:image(handle,x0,y0,size,px(h*s),opts)
end
-- A clickable region (units, panel space) for this frame; later regions win.
function Canvas:hit(x,y,w,h,action)
    self.hits[#self.hits+1]={x=x,y=y,w=w,h=h,action=action}
end
function Canvas:hit_at(mx,my)
    local hits=self.prev_hits or{}
    for i=#hits,1,-1 do
        local h=hits[i]
        if mx>=h.x and mx<h.x+h.w and my>=h.y and my<h.y+h.h then return h.action,h end
    end
    return nil
end
-- The topmost region under the cursor that scrolls.
function Canvas:scroll_at(mx,my)
    local hits=self.prev_hits or{}
    for i=#hits,1,-1 do
        local h=hits[i]
        if h.action and h.action.scroll and mx>=h.x and mx<h.x+h.w and my>=h.y and my<h.y+h.h then return h.action end
    end
    return nil
end
-- Screen pixels -> panel units.
function Canvas:to_units(x,y)return x/self.s-self.ox,y/self.s-self.oy end

return M

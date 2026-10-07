-- Drives the editor window offline: the real app, catalogue, ledger and layer (over tests/lua/sim.lua), a scripted
-- keyboard and mouse, and a frame recorder with the overlay's own refusal rules and the Runtime's FS Sinclair metrics.
-- Returns {app, layer, ledger, catalog, sim, frame(keys, opts) -> frame record, presets, store}.
local args=...
local S=dofile(args.sim)
local hd2=S.hd2
local EDITOR='mods/skyeshade/hd2runtime_editor'
local catalog=require('mods/skyeshade/hd2runtime_editor/editor/catalog').new(hd2)
local ledger=require('mods/skyeshade/hd2runtime_editor/editor/ledger').install(hd2,EDITOR)
local layer=require('mods/skyeshade/hd2runtime_editor/editor/layer').new({hd2=hd2,id=EDITOR,ledger=ledger,catalog=catalog})
local presets_module=require('mods/skyeshade/hd2runtime_editor/editor/presets')
local fonts=require('hd2runtime/domains/ui_fonts').fonts
local ui_fonts=require('hd2runtime/runtime/ui_fonts')

-- An in-memory store with hd2.store's interface.
local store={data={}}
local function deep(v)
    if type(v)~='table'then return v end
    local c={}
    for k,x in pairs(v)do c[k]=deep(x)end
    return c
end
function store:get(k,default)local v=self.data[k];if v==nil then return default end return deep(v)end
function store:set(k,v)self.data[k]=deep(v)end
local presets=presets_module.new(store)

-- Scripted input: keys pressed this frame, keys held, mouse.
local input={pressed={},down={},mouse=nil}
local fake={input={
    pressed=function(name)return input.pressed[name]==true end,
    down=function(name)return input.down[name]==true or input.pressed[name]==true end}}
local app=require('mods/skyeshade/hd2runtime_editor/editor/ui/app').new({hd2=fake,catalog=catalog,layer=layer,
    ledger=ledger,presets=presets,hotkey='F8',label='HD2Runtime 0.30.0-dev  ·  Editor 0.1.0',
    mouse=function()return input.mouse end})

local W,H=args.width or 1920,args.height or 1080
local function frame_builder()
    local d={items={},width=W,height=H,scale=math.min(W/1920,H/1080),refused={}}
    local function refuse(why)d.refused[#d.refused+1]=why end
    local function finite(n)return type(n)=='number'and n==n and n>-math.huge and n<math.huge end
    function d:rect(x,y,w,h,c,z)
        if not(finite(x)and finite(y)and finite(w)and finite(h)and w>=0 and h>=0)then return refuse('rect '..tostring(x))end
        if type(z)~='number'or z%1~=0 or z<0 or 1011+z>1023 then return refuse('rect z '..tostring(z))end
        if type(c)~='table'then return refuse('rect colour')end
        self.items[#self.items+1]={k='r',x=x,y=y,w=w,h=h,c={c[1],c[2],c[3],c[4]or 255},z=z}
    end
    function d:text(s,x,y,o)
        o=o or{}
        if type(s)~='string'or s==''then return end
        if#s>160 or s:find('[%z\1-\31\127]')then return refuse('text: '..s:sub(1,40))end
        local size=o.size or 18
        if not(finite(x)and finite(y)and finite(size)and size>=4 and size<=256)then return refuse('text pos '..s)end
        local z=o.z or 0
        if z%1~=0 or z<0 or 1011+z>1023 then return refuse('text z '..tostring(z))end
        local c=o.colour or{255,255,255,255}
        self.items[#self.items+1]={k='t',s=s,x=x,y=y,size=size,c={c[1],c[2],c[3],c[4]or 255},z=z,font=o.font or'body'}
    end
    function d:text_width(s,size,role)return ui_fonts.width(fonts[role or'body']or fonts.body,tostring(s),size or 18)end
    return d
end

local H_={app=app,layer=layer,ledger=ledger,catalog=catalog,sim=S,presets=presets,store=store,hd2=hd2,input=input}
-- One frame: keys = {'DOWN', 'RIGHT', ...} pressed this frame; opts = {down = {...}, mouse = {x, y, left}, dt}.
function H_.frame(keys,opts)
    opts=opts or{}
    input.pressed={}
    for _,k in ipairs(keys or{})do input.pressed[k]=true end
    input.down={}
    for _,k in ipairs(opts.down or{})do input.down[k]=true end
    input.mouse=opts.mouse
    local dt=opts.dt or 1/60
    S.tick(dt,dt)
    layer:tick(dt)
    local d=frame_builder()
    app:frame(d,dt)
    H_.last=d
    return d
end
-- Many quiet frames (lets the layer settle).
function H_.idle(seconds)
    local t=0
    while t<seconds do H_.frame({},{dt=0.1});t=t+0.1 end
end
-- The frame as JSON-ish Lua text for the PNG renderer (tests/render_frames.py).
function H_.dump(d)
    local out={'{"width":'..d.width..',"height":'..d.height..',"items":['}
    for i,it in ipairs(d.items)do
        local c=string.format('[%d,%d,%d,%d]',it.c[1],it.c[2],it.c[3],it.c[4])
        if it.k=='r'then
            out[#out+1]=string.format('%s{"k":"r","x":%.2f,"y":%.2f,"w":%.2f,"h":%.2f,"z":%d,"c":%s}',i>1 and','or'',it.x,it.y,it.w,it.h,it.z,c)
        else
            local s=it.s:gsub('\\','\\\\'):gsub('"','\\"')
            out[#out+1]=string.format('%s{"k":"t","s":"%s","x":%.2f,"y":%.2f,"size":%.2f,"z":%d,"c":%s,"font":"%s"}',
                i>1 and','or'',s,it.x,it.y,it.size,it.z,c,it.font)
        end
    end
    out[#out+1]=']}'
    return table.concat(out)
end
return H_

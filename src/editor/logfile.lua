-- HD2R Editor (c) 2026 SkyeShade. All rights reserved except as granted in LICENSE
-- (https://github.com/SkyeShade/HD2Runtime-Editor). Do not redistribute or reuse without the credit it requires.
-- HD2Runtime.log, followed live: the last part of the file on first read, then only what was appended (read at most
-- every half second, only while someone looks). A file that shrank (a new game session) is read again from its end.
-- Each line is classified for its colour: error, warning, ok, editor, perf, info.
local M={}

local TAIL=256*1024      -- bytes read on the first look
local KEEP=4000          -- lines kept

function M.path()
    local ok,base=pcall(os.getenv,'LOCALAPPDATA')
    return ok and base and(base..'\\CowboyBingus\\Helldivers2\\Logs\\HD2Runtime.log')or nil
end

local RULES={
    {'error',{'REJECTED','rejected','refused','REFUSED','failed','FAILED','error','ERROR','CONFLICT','blocked',
        'not confirm','did not apply','unavailable','UNAVAILABLE','traceback','attempt to'}},
    {'warning',{'WAITING','waiting for','recovering','retry','not ready','still pending','stall','warning','WARNING',
        'cancelled','drift','EXPERIMENTAL'}},
    {'editor',{'[editor]','hd2runtime_editor'}},
    {'ok',{'APPLIED','ALREADY_DESIRED','verified status','READY','resident','REGISTERED','AVAILABLE','installed','ready;'}},
    {'perf',{'PERFORMANCE','PEER CHANNEL','ONGOING PROBE'}},
}
function M.classify(line)
    -- the Runtime's settle summary ("N registered operations settled in S s: A applied, R rejected, O other"): green
    -- when nothing was rejected, a warning when something was (each rejection has its own red line above it)
    if line:find('registered operations settled',1,true)then
        local rejected=tonumber(line:match('(%d+) rejected'))
        return(rejected and rejected>0)and'warning'or'ok'
    end
    -- a zero count is not a problem: "0 rejected", "0 failed", "errors=0" never make a line red
    line=(' '..line):gsub('%a+=0%f[^%w]',''):gsub('%s0 %a+',' ')
    for _,rule in ipairs(RULES)do
        for _,word in ipairs(rule[2])do
            if line:find(word,1,true)then return rule[1]end
        end
    end
    return 'info'
end

function M.new(path)
    local self={path=path or M.path(),lines={},kinds={},offset=nil,clock=0,next_read=0,version=0,error=nil}
    local function push(line)
        line=line:gsub('\r$',''):gsub('^%[HD2Runtime%] ','')
        if line==''then return end
        self.lines[#self.lines+1]=line
        self.kinds[#self.kinds+1]=M.classify(line)
        if#self.lines>KEEP then
            local drop=#self.lines-KEEP
            for _=1,drop do table.remove(self.lines,1);table.remove(self.kinds,1)end
        end
    end
    self.partial=''
    function self.poll(dt)
        self.clock=self.clock+(dt or 0)
        if self.clock<self.next_read then return false end
        self.next_read=self.clock+0.5
        if not self.path or type(io)~='table'then self.error='no log path';return false end
        local ok,f=pcall(io.open,self.path,'rb')
        if not ok or not f then self.error='cannot open '..tostring(self.path);return false end
        self.error=nil
        local size=f:seek('end')
        if self.offset==nil or size<self.offset then
            -- first look, or a new session: the last part of the file
            self.lines,self.kinds,self.partial={},{},''
            self.offset=math.max(0,size-TAIL)
            if self.offset>0 then
                f:seek('set',self.offset)
                f:read('*l')                         -- drop the partial first line
                self.offset=f:seek()
            end
        end
        if size==self.offset then f:close();return false end
        f:seek('set',self.offset)
        local data=f:read(math.min(size-self.offset,4*1024*1024))or''
        self.offset=self.offset+#data
        f:close()
        data=self.partial..data
        local last=1
        for line,stop in data:gmatch('([^\n]*)\n()')do push(line);last=stop end
        self.partial=data:sub(last)
        self.version=self.version+1
        return true
    end
    return self
end

return M

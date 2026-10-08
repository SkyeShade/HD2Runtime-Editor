-- HD2R Editor (c) 2026 SkyeShade. All rights reserved except as granted in LICENSE
-- (https://github.com/SkyeShade/HD2Runtime-Editor). Do not redistribute or reuse without the credit it requires.
-- The few Windows calls the editor makes itself, through LuaJIT's FFI (declared once, each call guarded): open a file
-- or folder with its default program (ShellExecuteW), list a folder (FindFirstFileW), create folders, the user's
-- folders, and the Windows open-file dialog. Every function returns nil and why when the FFI or the call is
-- unavailable.
local M={}

local ffi,kernel,shell,user,comdlg
local function load()
    if ffi~=nil then return ffi~=false end
    local ok=pcall(function()
        ffi=require('ffi')
        if not rawget(_G,'HD2REditorWinV1')then
            ffi.cdef[[
                typedef struct { uint32_t attributes; uint32_t c1,c2,a1,a2,w1,w2; uint32_t size_hi,size_lo;
                    uint32_t r0,r1; uint16_t name[260]; uint16_t alt[14]; uint32_t t,c,f; } HD2REditorFindW;
                void *FindFirstFileW(const uint16_t *pattern, HD2REditorFindW *data);
                int FindNextFileW(void *handle, HD2REditorFindW *data);
                int FindClose(void *handle);
                int CreateDirectoryW(const uint16_t *path, void *security);
                int MultiByteToWideChar(uint32_t cp, uint32_t flags, const char *s, int n, uint16_t *w, int wn);
                int WideCharToMultiByte(uint32_t cp, uint32_t flags, const uint16_t *w, int wn, char *s, int n,
                    const char *d, int *u);
                void *ShellExecuteW(void *hwnd, const uint16_t *op, const uint16_t *file, const uint16_t *params,
                    const uint16_t *dir, int show);
            ]]
            rawset(_G,'HD2REditorWinV1',true)
        end
        if not rawget(_G,'HD2REditorWinV2')then
            ffi.cdef[[
                typedef struct { uint32_t lStructSize; void *hwndOwner; void *hInstance; const uint16_t *lpstrFilter;
                    uint16_t *lpstrCustomFilter; uint32_t nMaxCustFilter; uint32_t nFilterIndex; uint16_t *lpstrFile;
                    uint32_t nMaxFile; uint16_t *lpstrFileTitle; uint32_t nMaxFileTitle; const uint16_t *lpstrInitialDir;
                    const uint16_t *lpstrTitle; uint32_t Flags; uint16_t nFileOffset; uint16_t nFileExtension;
                    const uint16_t *lpstrDefExt; intptr_t lCustData; void *lpfnHook; const uint16_t *lpTemplateName;
                    void *pvReserved; uint32_t dwReserved; uint32_t FlagsEx; } HD2REditorOFNW;
                int GetOpenFileNameW(HD2REditorOFNW *ofn);
                void *CreateThread(void *attributes, size_t stack, void *start, void *parameter, uint32_t flags,
                    uint32_t *id);
                uint32_t WaitForSingleObject(void *handle, uint32_t ms);
                int GetExitCodeThread(void *handle, uint32_t *code);
                int CloseHandle(void *handle);
                void *GetForegroundWindow(void);
                uint32_t GetWindowThreadProcessId(void *window, uint32_t *process);
                uint32_t GetCurrentProcessId(void);
            ]]
            rawset(_G,'HD2REditorWinV2',true)
        end
        kernel=ffi.load('kernel32')
        shell=ffi.load('shell32')
    end)
    if not ok then ffi=false end
    return ok
end

function M.wide(text)
    if not load()then return nil end
    local n=#text*2+2
    local w=ffi.new('uint16_t[?]',n)
    kernel.MultiByteToWideChar(65001,0,text,-1,w,n)
    return w
end
local function narrow(w)
    local buffer=ffi.new('char[1024]')
    local n=kernel.WideCharToMultiByte(65001,0,w,-1,buffer,1024,nil,nil)
    return n>1 and ffi.string(buffer,n-1)or''
end

-- Opens a file or folder with its default program (Explorer for a folder). True, or nil and why.
function M.open(path)
    if not load()then return nil,'no FFI'end
    local ok,result=pcall(function()return shell.ShellExecuteW(nil,M.wide('open'),M.wide(path),nil,nil,1)end)
    if not ok then return nil,tostring(result)end
    local code=tonumber(ffi.cast('intptr_t',result))
    if code<=32 then return nil,'ShellExecute failed ('..code..')'end
    return true
end
-- Opens Explorer with a file selected.
function M.reveal(path)
    if not load()then return nil,'no FFI'end
    local ok,result=pcall(function()
        return shell.ShellExecuteW(nil,M.wide('open'),M.wide('explorer.exe'),M.wide('/select,"'..path..'"'),nil,1)
    end)
    if not ok then return nil,tostring(result)end
    return tonumber(ffi.cast('intptr_t',result))>32 or nil
end

-- {{name, folder = true|false, size}} of a folder's entries matching pattern ('*' by default), '.' and '..' left out.
function M.list(folder,pattern)
    if not load()then return nil,'no FFI'end
    local out={}
    local ok,why=pcall(function()
        local data=ffi.new('HD2REditorFindW')
        local handle=kernel.FindFirstFileW(M.wide(folder..'\\'..(pattern or'*')),data)
        if handle==nil or tonumber(ffi.cast('intptr_t',handle))==-1 then return end
        repeat
            local name=narrow(data.name)
            if name~='.'and name~='..'and name~=''then
                local dir=bit.band(data.attributes,0x10)~=0
                local hidden=bit.band(data.attributes,0x2)~=0
                if not hidden then
                    out[#out+1]={name=name,folder=dir,size=tonumber(data.size_lo)+tonumber(data.size_hi)*4294967296}
                end
            end
        until kernel.FindNextFileW(handle,data)==0
        kernel.FindClose(handle)
    end)
    if not ok then return nil,tostring(why)end
    table.sort(out,function(a,b)
        if a.folder~=b.folder then return a.folder end
        return a.name:lower()<b.name:lower()
    end)
    return out
end

-- Creates a folder and every missing parent. True, or nil and why.
function M.mkdir(path)
    if not load()then return nil,'no FFI'end
    local built=''
    for part in path:gmatch('[^\\/]+')do
        built=built==''and part or(built..'\\'..part)
        if not built:match('^%a:$')then pcall(kernel.CreateDirectoryW,M.wide(built),nil)end
    end
    return true
end

function M.env(name)local ok,v=pcall(os.getenv,name);return ok and v or nil end
-- The user's own folders, for the image picker.
function M.places()
    local home=M.env('USERPROFILE')
    local out={}
    if home then
        for _,name in ipairs({'Pictures','Desktop','Downloads','Documents'})do out[#out+1]={label=name,path=home..'\\'..name}end
    end
    return out
end

-- The Windows open-file dialog, on its own thread so the game keeps running while it is open. GetOpenFileNameW takes
-- one pointer and returns a BOOL, the shape of a thread procedure, so it is the thread's start address itself. Owned
-- by the game window (the foreground window when it opens, if it is this process's), the dialog stays above the game. Returns a job:
-- job.poll() -> nil while the dialog is open, then the chosen path, or false when it was cancelled. Every buffer the
-- dialog uses is kept in `open_jobs` until its thread has ended.
local open_jobs={}
function M.pick_file(opts)
    if not load()then return nil,'no FFI'end
    opts=opts or{}
    local ok,job=pcall(function()
        user=user or ffi.load('user32')
        comdlg=comdlg or ffi.load('comdlg32')
        local j={file=ffi.new('uint16_t[1024]'),ofn=ffi.new('HD2REditorOFNW'),code=ffi.new('uint32_t[1]')}
        -- "label|patterns|label|patterns|" with every | a NUL (the list ends with two)
        local filter=(opts.filter or'All files|*.*|')..'|'
        j.filter=M.wide(filter)
        for i=0,#filter*2 do if j.filter[i]==124 then j.filter[i]=0 end end
        j.title=M.wide(opts.title or'Open')
        j.folder=opts.folder and M.wide(opts.folder)or nil
        local o=j.ofn
        o.lStructSize=ffi.sizeof('HD2REditorOFNW')
        -- the game window owns the dialog (an owner from another process would make the dialog fail)
        local front=user.GetForegroundWindow()
        local pid=ffi.new('uint32_t[1]')
        if front~=nil then user.GetWindowThreadProcessId(front,pid)end
        if front~=nil and pid[0]==kernel.GetCurrentProcessId()then o.hwndOwner=front end
        o.lpstrFilter=j.filter
        o.nFilterIndex=1
        o.lpstrFile=j.file
        o.nMaxFile=1024
        o.lpstrInitialDir=j.folder
        o.lpstrTitle=j.title
        -- file and path must exist, Explorer style, no read-only box, keep the working folder, not in Recent
        o.Flags=0x1000+0x800+0x80000+0x4+0x8+0x02000000
        j.thread=kernel.CreateThread(nil,0,ffi.cast('void*',comdlg.GetOpenFileNameW),o,0,nil)
        if j.thread==nil then error('CreateThread failed',0)end
        open_jobs[j]=true
        function j.poll()
            if j.result~=nil then return j.result end
            if kernel.WaitForSingleObject(j.thread,0)~=0 then return nil end
            kernel.GetExitCodeThread(j.thread,j.code)
            kernel.CloseHandle(j.thread)
            open_jobs[j]=nil
            j.result=j.code[0]~=0 and narrow(j.file)or false
            if j.result==''then j.result=false end
            return j.result
        end
        return j
    end)
    if not ok then return nil,tostring(job)end
    return job
end

return M

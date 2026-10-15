-- No user files, game process or UI: exercise the shipped localization modules with private in-memory files.
local module='mods/skyeshade/hd2runtime_editor/editor/'
local i=require(module..'i18n')
local data=require(module..'locale')
local strings=require(module..'strings')
local logfile=require(module..'logfile')
local getenv,open=os.getenv,io.open
local original_require=require
local function game(code)return {ui={language=function()return code end}}end

-- Bundled Chinese works without LOCALAPPDATA, external files, an index or FFI directory discovery.
os.getenv=function()return nil end
io.open=function()error('unexpected disk read')end
local languages=i.languages()
assert(#languages==2 and languages[1].name=='English')
assert(languages[2].name=='简体中文' and languages[2].builtin=='cn' and not languages[2].file)
assert(languages[2].count>2000)
assert(i.match_game_language('cn',languages)=='简体中文')
assert(i.use_game_language(game('cn'))=='简体中文')
for _,key in ipairs(strings)do assert(data.cn[key] and i.L(key)==data.cn[key],key)end
assert(i.L('BROWSE')=='浏览' and i.Lf('APPLY  %d',23)=='应用  23')
assert(i.L('damage.status_1_type')=='damage.status_1_type')
assert(i.L('ASSET_UNAVAILABLE')=='ASSET_UNAVAILABLE')
assert(i.L('m/s')=='m/s' and i.L('rpm')=='rpm')
assert(i.L('Unknown future field')=='Unknown future field')

local log=logfile.new()
assert(not log.poll(1) and log.error==i.L('no log path'))
log.path='private/path/HD2Runtime.log'
assert(not log.poll(1) and log.error==i.Lf('cannot open %s',log.path))
assert(logfile.classify('0 failed, 0 rejected')=='info')
assert(logfile.classify('ASSET_UNAVAILABLE failed')=='error')

-- Every printf template formats in the real Lua runtime. Literal environment variables are not formats.
for key,value in pairs(data.cn)do
    if not key:find('%%LOCALAPPDATA%%')and not key:find('%%USERPROFILE%%')then
        local args={}
        for c in key:gmatch('%%[-+ #0]*%d*%.?%d*([cdiouxXeEfgGqs%%])')do
            if c~='%'then args[#args+1]=(c=='s'or c=='q')and'路径/TEST'or 7 end
        end
        if #args>0 then assert(i.Lf(key,unpack(args))==string.format(value,unpack(args)),key)end
    end
end

-- A missing saved file falls back to bundled Chinese; unknown languages retain the English fallback.
assert(i.use('简体中文',{}) and i.L('APPLY')=='应用')
local ok,why=i.use('Missing',{})
assert(not ok and why=='找不到语言 Missing 的本地化文件' and i.language()=='English')
assert(i.Lf('APPLY  %d',23)=='APPLY  23')

-- An unenumerable non-ASCII profile still has the built-in language; no index is required.
os.getenv=function()return 'nonexistent/中文/profile' end
io.open=function()return nil end
assert(i.use_game_language(game('cn'))=='简体中文')

-- Custom files override built-ins and inherit missing entries, including an alias-named Chinese file.
require=function(name)if name=='ffi'then error('FFI unavailable')end return original_require(name)end
local files={['index.txt']='zh-cn.txt\nde.txt\n',
    ['zh-cn.txt']='@language My Chinese\n@code cn\nBROWSE = 自定义浏览\n',
    ['de.txt']='@language Deutsch\n@code de\nBROWSE = ANSEHEN\n'}
io.open=function(path)
    local text=files[path:match('[^\\/]+$')]
    if not text then return nil end
    return {read=function()return text end,close=function()end}
end
languages=i.languages()
assert(i.match_game_language('cn',languages)=='My Chinese')
assert(i.use_game_language(game('cn'))=='My Chinese')
assert(i.L('BROWSE')=='自定义浏览' and i.L('APPLY')=='应用')
assert(i.use('English') and i.L('APPLY')=='APPLY')
assert(i.use('简体中文',languages) and i.L('BROWSE')=='浏览')
assert(i.use_game_language(game('de'))=='Deutsch')
assert(i.L('BROWSE')=='ANSEHEN' and i.L('Landing thrust')==data.de['Landing thrust'])
assert(i.L('APPLY')=='APPLY') -- never borrow Chinese for a non-Chinese file
files['zh-cn.txt']='@language 简体中文\n@code cn\nBROWSE = 优先文件\n'
languages=i.languages()
local count=0;for _,l in ipairs(languages)do if l.name=='简体中文'then count=count+1 end end
assert(count==1 and i.use('简体中文',languages) and i.L('BROWSE')=='优先文件')
files['zh-cn.txt']=nil
assert(i.use('简体中文',languages) and i.L('BROWSE')=='浏览')

-- Other built-in supplements keep their previous automatic selection and English behavior.
os.getenv=function()return nil end
for code,rows in pairs(data)do
    if code~='cn'then
        assert(i.use_game_language(game(code))==code)
        for key,text in pairs(rows)do assert(i.L(key)==text)end
    end
end
i.use('English')
assert(i.use_game_language(game('us'))==nil and i.L('BROWSE')=='BROWSE')
i.set({['Saved preset %s (%d fields)']='%d %d'},'Broken')
assert(i.Lf('Saved preset %s (%d fields)','x',2)=='Saved preset x (2 fields)')
os.getenv,io.open=getenv,open
require=original_require
return 'ok'

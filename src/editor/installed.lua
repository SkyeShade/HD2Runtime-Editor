-- HD2R Editor (c) 2026 SkyeShade. All rights reserved except as granted in LICENSE
-- (https://github.com/SkyeShade/HD2Runtime-Editor). Do not redistribute or reuse without the credit it requires.
-- Every mod the player has deployed, HD2Runtime or not, as the mod manager that deployed it lists it: Echelon
-- (%APPDATA%\Echelon\state.json) or HD2 Arsenal (%LOCALAPPDATA%\hd2arsenal\hd2a_data.json), whichever deployed
-- last. Read-only. What a non-Runtime mod changes cannot be known (it replaces game files); its name, description and
-- the Lua addons it contains (Echelon scans them) are shown.
--
-- Reading is incremental: start() returns a reader whose step(budget_seconds) parses a slice per frame (the state
-- files are about 1 MB), then result() gives {source, deployed_at, mods = {{key, name, description, version, guid,
-- addons = {resource ids}, image (file path or nil), runtime (true when an addon is a known HD2Runtime mod)}}}.
local json=require('mods/skyeshade/hd2runtime_editor/editor/json')
local M={}

local function read(path)
    if type(io)~='table'or type(io.open)~='function'then return nil end
    local ok,f=pcall(io.open,path,'rb')
    if not ok or not f then return nil end
    local text=f:read('*a')
    f:close()
    return text
end
local function env(name)
    local ok,value=pcall(os.getenv,name)
    return ok and value or nil
end
local function time_of(stamp)
    -- 'YYYY-MM-DD HH:MM' (Echelon) or an ISO / epoch value (Arsenal): a sortable number
    if type(stamp)=='number'then return stamp>1e11 and stamp/1000 or stamp end
    local y,mo,d,h,mi=tostring(stamp or''):match('(%d%d%d%d)%-(%d%d)%-(%d%d)[ T](%d%d):(%d%d)')
    if not y then return 0 end
    return os.time({year=tonumber(y),month=tonumber(mo),day=tonumber(d),hour=tonumber(h),min=tonumber(mi)})
end

local function echelon(state,folder)
    local out={}
    for id in pairs(state.slots or{})do
        local e=state.library and state.library[id]
        if e then
            local addons={}
            for _,set in ipairs(e.scan and e.scan.sets or{})do
                for _,a in ipairs(set.addons or{})do addons[#addons+1]=a end
            end
            out[#out+1]={key='echelon:'..id,id=id,name=e.name or id,description=e.description,version=e.version,
                guid=e.guid or e.arsenal,addons=addons,image=e.image and(folder..'\\images\\'..e.image)or nil}
        end
    end
    return out
end
local function arsenal(state)
    local out={}
    local library={}
    for _,e in ipairs(state.modsLibrary or{})do if e.uuid then library[e.uuid]=e end end
    local profile=state.modsList and state.modsList[state.deployedProfile or'']
    for _,m in ipairs(profile and profile.mods or{})do
        local e=library[m.uuid]
        if e and m.deployed~=false and m.enabled~=false then
            out[#out+1]={key='arsenal:'..m.uuid,id=m.uuid,name=e.label or m.uuid,description=e.description,
                guid=m.uuid,addons={},image=e.iconPath}
        end
    end
    return out
end

M.from_echelon,M.from_arsenal=echelon,arsenal
-- A reader over the newest manager state. known(resource id) -> true marks HD2Runtime mods.
function M.start(known)
    local appdata,local_appdata=env('APPDATA'),env('LOCALAPPDATA')
    local reader={done=false}
    local job=coroutine.create(function()
        local candidates={}
        if appdata then
            local text=read(appdata..'\\Echelon\\state.json')
            if text then candidates[#candidates+1]={kind='echelon',text=text,folder=appdata..'\\Echelon'}end
        end
        if local_appdata then
            local text=read(local_appdata..'\\hd2arsenal\\hd2a_data.json')
            if text then candidates[#candidates+1]={kind='arsenal',text=text}end
        end
        if#candidates==0 then return {source=nil,mods={},why='no Echelon or HD2 Arsenal state found'}end
        local best
        for _,c in ipairs(candidates)do
            local ok,state=pcall(json.decode,c.text,2000)
            c.text=nil
            if ok and type(state)=='table'then
                c.state=state
                if c.kind=='echelon'then c.at=time_of(state.deployed_at)
                else
                    local snap=local_appdata and read(local_appdata..'\\hd2arsenal\\deployment_snapshot.json')
                    local sok,s=pcall(json.decode,snap or'{}')
                    c.at=time_of(sok and type(s)=='table'and s.timestamp or 0)
                end
                if not best or(c.at or 0)>(best.at or 0)then best=c end
            end
        end
        if not best then return {source=nil,mods={},why='the mod manager state could not be read'}end
        local mods=best.kind=='echelon'and echelon(best.state,best.folder)or arsenal(best.state)
        for _,m in ipairs(mods)do
            for _,a in ipairs(m.addons)do if known and known(a)then m.runtime=true;m.resource=a end end
        end
        table.sort(mods,function(a,b)return tostring(a.name):lower()<tostring(b.name):lower()end)
        return {source=best.kind,deployed_at=best.at,mods=mods}
    end)
    function reader.step(budget)
        if reader.done then return true end
        local clock=os.clock
        local deadline=clock()+(budget or 0.004)
        repeat
            local ok,result=coroutine.resume(job)
            if not ok then reader.done,reader.value=true,{mods={},why=tostring(result)}
            elseif coroutine.status(job)=='dead'then reader.done,reader.value=true,result end
        until reader.done or clock()>=deadline
        return reader.done
    end
    function reader.result()return reader.value end
    return reader
end

return M

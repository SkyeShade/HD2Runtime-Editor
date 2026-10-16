-- Mission pages are views of canonical shared timer rows, never duplicate edits.
local util=require('mods/skyeshade/hd2runtime_editor/editor/util')
local M={}
-- Timer rows are shared by many mission pages. Open all 162 pages (cheap) the first time any mission view is built,
-- so the native-bytes index, and the change markers of every page sharing an edited timer, are complete at once
-- instead of when the background index reaches the last category. Deferred until no build is running: opened from
-- inside a page's build, a page sharing its timer would build that unfinished page a second time (its rows lost).
local function open_all(cat)
    if cat.missions_opened then return end
    cat.missions_opened=true
    cat:after_build(function()
        for _,category in ipairs({'missions_terminids','missions_automatons','missions_illuminate'})do
            for _,object in ipairs((cat:objects(category)))do cat:open(object)end
        end
    end)
end
-- The Mission Timer page: the freeze only (ui/mission_overview.lua draw_timer). No rows: nothing is staged or saved.
function M.timer(cat)
    return {{key='mt|freeze',name='Mission Timer',subtitle='Freeze',missionTimer=true,build=function()return {}end}}
end
-- One overview control per original duration. Its members remain separate
-- canonical fields: equal defaults do not imply equal native addresses.
function M.overview(cat)
    if type(cat.real_hd2.missions)~='function'then return {}end
    local groups={}
    for _,m in ipairs(cat.real_hd2.missions())do
        local g=groups[m.timerGroup]
        if not g then g={missions={},fronts={}};groups[m.timerGroup]=g end
        g.missions[#g.missions+1]=m;g.fronts[m.faction]=true
    end
    local out={}
    for _,front in ipairs({'terminids','automatons','illuminate'})do
        local faction=front
        out[#out+1]={key='mo|'..faction,name=util.humanize(faction),subtitle='Mission Overview',
            missionFaction=faction,iconKind='faction',iconName=faction,iconFaction=faction,
            build=function(o)
                open_all(cat)
                local timers,rows,by_duration={},{},{}
                for source,g in pairs(groups)do if g.fronts[faction]then
                    local representative,count=nil,0
                    for _,m in ipairs(g.missions)do if m.faction==faction then
                        count=count+1
                        if not representative or(representative.nameSource=='unresolved'and m.nameSource~='unresolved')then
                            representative=m
                        end
                    end end
                    local owner=assert(cat:object('mi|'..representative.id));cat:open(owner)
                    local original=assert(owner.rows[1]);original=original.canonical or original
                    local row=setmetatable({canonical=original,object=o},{__index=original})
                    local fronts=0;for _ in pairs(g.fronts)do fronts=fronts+1 end
                    local g=by_duration[row.vanilla]
                    if not g then
                        g={duration=row.vanilla,rows={},count=0,crossFaction=false}
                        by_duration[row.vanilla]=g;timers[#timers+1]=g
                    end
                    g.rows[#g.rows+1]=row;rows[#rows+1]=row
                    g.count=g.count+count;g.crossFaction=g.crossFaction or fronts>1
                end end
                table.sort(timers,function(a,b)return a.duration>b.duration end)
                for _,g in ipairs(timers)do table.sort(g.rows,function(a,b)return a.key<b.key end)end
                o.timerGroups=timers
                return rows
            end}
    end
    return out
end
-- Called only for an explicit Apply with pending timer edits. Native guards
-- still check the state again when the write actually runs.
function M.apply_block(cat,pending)
    local has_timer=false
    for _,p in pairs(pending)do
        -- (a timer marked for reset goes back as an immediate reset always did)
        if p.row.field=='mission.duration_seconds'and not p.reset then has_timer=true;break end
    end
    if not has_timer or type(cat.real_hd2.game_state)~='function'then return end
    local ok,state=pcall(cat.real_hd2.game_state)
    if ok and state and state.state~=3 then return state.name or 'Unavailable'end
end
function M.category(cat,H,faction)
    if type(cat.real_hd2.missions)~='function'then return nil,'Mission timers require HD2Runtime 0.40.0 RC6 or later.'end
    local list={}
    for _,m in ipairs(cat.real_hd2.missions({faction=faction}))do
        local mission=m
        list[#list+1]={key='mi|'..m.id,name=m.name,game_name_key=m.id,subtitle=util.humanize(faction),
            iconKind='faction',iconName=faction,iconFaction=faction,
            filter_group=m.nameSource=='unresolved'and'Unidentified missions'or'Named missions',
            control_rank=m.nameSource=='unresolved'and 2 or 1,
            detail=m.description,
            build=function(o)
                open_all(cat)
                local canonical_id=mission.sharedWith[1]
                local row
                if canonical_id~=mission.id then
                    local owner=assert(cat:object('mi|'..canonical_id),'shared mission page absent')
                    cat:open(owner)
                    local original=assert(owner.rows and owner.rows[1],'shared mission timer absent')
                    row=setmetatable({canonical=original,object=o},{__index=original})
                else
                    local f=mission.fields[1]
                    row=H.make_row(o,{id='duration',field=f.semanticFieldId,label='Mission duration',unit='s',
                        vanilla=f.currentDefault,min=f.min,max=f.max,type=f.type,storage='f32',
                        target=function()return cat.hd2.mission(mission.id)end,descriptor=f,shared=true,
                        unverified=true,section='Mission timer',
                        note='Apply before launch. Shared missions change together; active countdowns are unchanged.'})
                end
                local names={}
                local D=require('hd2runtime/domains/missions')
                for _,other in ipairs(D.missions)do if other.source==mission.timerGroup then
                    names[#names+1]=util.humanize(other.faction)..': '..other.name
                end end
                return {row,H.info_row(o,{id='shared-timer',label='Shared timer group',text=table.concat(names,', '),
                    info=true,section='Mission timer',note='Includes dormant event and developer variants.'}),
                    H.info_row(o,{id='definition',label='Mission definition',text=mission.id,info=true,section='Mission details',
                        note='Listed missions may be unavailable in the current Galactic War.'})}
            end}
    end
    table.sort(list,function(a,b)
        if a.control_rank~=b.control_rank then return a.control_rank<b.control_rank end
        return a.name..a.key<b.name..b.key
    end)
    return list
end
return M

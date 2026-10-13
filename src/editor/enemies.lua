-- Expanded enemy controls from HD2Runtime 0.32.0. Catalogue access only; the
-- editor's normal override layer owns all writes, resets, presets and exports.
local util=require('mods/skyeshade/hd2runtime_editor/editor/util')
local M={}
local TITLES={unit='Size & Geometry',spawner='Spawning',hive='Director Multipliers',transport='Transport',
    breach='Bug Breach',shield='Shield',jammer='Stratagem Jammer',behavior='Behavior',entity='Health & Armor',
    gore='Destruction',difficulty='Mission Difficulty',spawn='Spawn Weights',composition='Composition',demolition='Demolition'}
local NOTES={
    ['unit.scale_min']='Creation-time scale: applies to newly spawned units. Physics and hit geometry need gameplay testing.',
    ['unit.scale_max']='Inspection only: not a proven random-scale maximum.',
    ['jammer.radius']='Positive 3D radius. Native zero or negative values bypass the distance check; they do not disable the jammer.',
    ['jammer.initially_enabled']='Initialization only. Does not switch off a jammer that already exists.',
}
local function title(s)return util.humanize(tostring(s or''))end
local function entity_name(name,W)
    local e=name and W.entry(name)
    if not e then return title(name)end
    local label=e.displayName or e.wikiName or title(name)
    return e.fullDisplayName or(label..(e.variantLabel and(' - '..e.variantLabel)or''))
end
local function section(id)return TITLES[tostring(id):match('^([^%.]+)')]or title(tostring(id):match('^([^%.]+)'))end
local function sorted(list)
    table.sort(list,function(a,b)
        if (a.control_rank or 0)~=(b.control_rank or 0)then return(a.control_rank or 0)<(b.control_rank or 0)end
        return a.name:lower()..a.key<b.name:lower()..b.key
    end);return list
end
-- Use the same descriptors and restore limits as the rows. Cache once per
-- canonical entity so navigation does not rebuild its field descriptors.
local control_groups=setmetatable({},{__mode='k'})
local function control_group(e,W)
    if control_groups[e] then return unpack(control_groups[e])end
    local gameplay,size=0,0
    for _,f in ipairs(e.fields or{})do
        local d=W.descriptor(e,f);local value=d.currentDefault
        if d.editable and type(value)=='number'and(not d.min or value>=d.min)and(not d.max or value<=d.max)then
            if f.id:match('^unit%.')then size=size+1 else gameplay=gameplay+1 end
        end
    end
    local group,rank='Inspection only',3
    if gameplay>0 then group,rank='Gameplay controls',1 elseif size>0 then group,rank='Size only',2 end
    control_groups[e]={group,rank}
    return group,rank
end
local SECTION_RANK={['Health & Armor']=10,['Damage Zones']=20,Attacks=30,Spawning=40,
    ['Director Multipliers']=40,Transport=45,['Bug Breach']=45,Shield=50,['Stratagem Jammer']=50,
    Destruction=60,Demolition=60,['Size & Geometry']=80,Behavior=90}
local function useful_rows_first(rows)
    for i,r in ipairs(rows)do r.control_order=i end
    table.sort(rows,function(a,b)
        local ar=SECTION_RANK[a.group or a.section]or 70
        local br=SECTION_RANK[b.group or b.section]or 70
        return ar<br or(ar==br and a.control_order<b.control_order)
    end)
    return rows
end
local function info(H,rows,o,id,label,text,section,group,note)
    text=tostring(text or'Unresolved')
    local reason=text
    if type(note)=='string'and note~=''then reason=text..' / '..note end
    rows[#rows+1]=H.info_row(o,{id='info:'..id,label=label,text=text,section=section,group=group,info=true,
        reason=reason,note=note})
end
local function stage_rows(H,rows,o,stages,prefix,group)
    for _,s in ipairs(stages or{})do
        local label='Stage '..tostring(s.index+1)
        info(H,rows,o,prefix..':'..s.index,label,tostring(s.template)..' / force '..tostring(s.force or'none'),
            'Demolition',group,'Stages are checked in order. Thresholds are shared; edit the matching Demolition Template. An earlier unmet stage can block later stages.')
    end
end
function M.entity_rows(cat,H,o,name,W)
    local e=assert(W.entry(name),'enemy catalogue entry unavailable')
    local zones,attacks={},{}
    for _,z in ipairs(e.zones or{})do zones[z.id]=z end
    for _,a in ipairs(e.attacks or{})do attacks[a.id]=a end
    local function root()return e.kind=='structure'and cat.hd2.structure(name)or cat.hd2.enemy(name)end
    local rows={}
    for _,f in ipairs(e.fields or{})do
        local d=W.descriptor(e,f)
        if type(d.currentDefault)=='number'then
            local target,part,group=root,section(f.id),nil
            if f.path=='damage_zone'then
                local z=zones[f.zone]or{};local slot=f.zone
                target=function()return root():zone(slot)end
                part=(z.wikiZone or title(z.name or slot))..' ('..slot..')';group='Damage Zones'
            elseif f.path=='attack'then
                local id=f.attack;local a=attacks[id]or{}
                target=function()return root():attack(id)end
                part=title(id)..' · '..title(a.role);group='Attacks'
            end
            local row=H.make_row(o,{id=f.path..':'..tostring(f.zone or f.attack or'')..':'..f.id,
                field=f.id,label=title(f.id),vanilla=d.currentDefault,min=d.min,max=d.max,type=d.type,
                storage=d.backing.storage,target=target,descriptor=d,shared=d.shared,
                unverified=d.acknowledgement=='allow_unverified_effect',editable=d.editable,
                reason=d.reason,section=part,group=group,disabled_value=d.disabledValue,
                note=NOTES[f.id]or d.semantics or d.lifecycle})
            row.mb_resource=e.kind=='structure'and'structure'or'enemy';row.mb_entity=e.semanticId
            row.mb_where=f.path..'|'..tostring(f.zone or f.attack or'')
            -- An authored negative/zero jammer radius cannot be restored through
            -- the positive-only API. Keep it inspectable until Runtime supports that reset.
            if row.editable and((d.min and d.currentDefault<d.min)or(d.max and d.currentDefault>d.max))then
                row.editable=false;row.reason='The authored value is outside the write range; the editor cannot safely restore it.'
            end
            rows[#rows+1]=row
        end
    end
    for _,z in ipairs(e.zones or{})do
        local names={};for _,n in ipairs(z.nameCandidates or{})do names[#names+1]=n.name..(n.observedInSource and' (observed)'or' (candidate)')end
        if #names>0 then info(H,rows,o,'zone-name:'..z.id,'Zone names',table.concat(names,', '),
            (z.wikiZone or title(z.name or z.id))..' ('..z.id..')','Damage Zones','Edits always use the exact zone slot. Candidate names are not confirmed anatomy.')end
    end
    local t=e.transport
    if t then
        info(H,rows,o,'capacity','Authored capacity',table.concat(t.dimensions,' x ')..' cells ('..t.capacityCells..' total)',
            'Transport',nil,'Cells, not a fixed passenger count. Only grid reductions are supported. Changes apply to subsequent creations.')
        for i,p in ipairs(t.footprints or{})do
            local names={};for _,name in ipairs(p.enemies)do names[#names+1]=entity_name(name,W)end
            info(H,rows,o,'footprint:'..i,table.concat(names,', '),table.concat(p.dimensions,' x ')..' cells; fits at most '..p.fixedOrientationGridUpperBound,
                'Passenger footprints','Transport bounds',t.footprintBoundsNote..' Matching footprints across factions do not prove these passengers are eligible for this ship.')
        end
    end
    for i,m in ipairs(e.mountedEntities or{})do
        info(H,rows,o,'mount:'..i,'Mounted entity',m.name and entity_name(m.name,W),'Mounted entities','Related entities',
            m.name and'Search for this entity to edit its own fields. It may hold a separate shield or weapon.'
                or'This mounted resource does not yet have an identified editable target.')
    end
    for i,m in ipairs(e.demolition or{})do
        local paths={};for _,p in pairs(m.modelPaths or{})do if type(p)=='string'then paths[#paths+1]=p end end
        info(H,rows,o,'model:'..i,'Model '..i,table.concat(paths,', '),'Models','Destruction models',
            m.association=='direct_unit'and'Direct model association.'or'Embedded model reference; this is not proof every placed variant uses it.')
        stage_rows(H,rows,o,m.stages,'model:'..i,'Destruction models')
    end
    return useful_rows_first(rows)
end
function M.entities(cat,H,filter)
    local ok,W=pcall(require,'hd2runtime/domains/enemy_writes')
    if not ok or type(W.entries)~='function'then return nil end
    local list={}
    for name,e in pairs(W.entries())do if filter(e)then
        e=W.entry(name)
        local control,rank=control_group(e,W)
        local key=name;local label=e.displayName or e.wikiName or e.name or key
        local components=e.components or(e.pendingControls and e.pendingControls.components)or{}
        local tags={}
        for _,component in ipairs(components)do tags[#tags+1]=component:gsub('ComponentData$','')end
        local iconKind,iconName,iconFaction=require('mods/skyeshade/hd2runtime_editor/editor/icons').entity(key,e)
        local subtitle=title(e.faction or e.kind)..' / '..control
        local full=e.fullDisplayName or(e.displayName and(e.displayName..(e.variantLabel and(' - '..e.variantLabel)or'')))
        list[#list+1]={key='en|'..key,name=full or title(label),subtitle=subtitle,
            filter_group=control,control_rank=rank,
            iconKind=iconKind,iconName=iconName,iconFaction=iconFaction,
            search_terms=key..' '..control..' '..(e.className or'')..' '..(e.gameName or'')..' '..table.concat(tags,' '),
            detail=table.concat(tags,', ')..'. Authored type values; existing instances may retain private copies.',
            build=function(o)return M.entity_rows(cat,H,o,key,W)end}
    end end
    return sorted(list)
end

local SHIP='Apply aboard the ship before the next mission. Existing compiled waves are not rebuilt.'
function M.overview(cat,H)
    if type(cat.real_hd2.enemies.spawn_multiplier)~='function'then return {}end
    local list={}
    for _,faction in ipairs({'terminids','automatons','illuminate'})do
        local f=faction
        list[#list+1]={key='eo|'..f,name=title(f),subtitle='Enemy Overview',spawnFaction=f,
            iconKind='faction',iconName=f,build=function()return {}end}
    end
    return list
end
function M.director_rows(cat,H,o,kind,key)
    local function target()return cat.hd2.enemies[kind](key)end
    local d=target():describe();local rows={}
    info(H,rows,o,'scope','Scope',kind=='demolition_template'and'Shared threshold'or'Ship / next mission',
        section(kind=='demolition_template'and'demolition.force'or kind..'.scope'),nil,
        kind=='demolition_template'and d.lifecycle or SHIP..' '..d.lifecycle)
    for _,f in ipairs(d.fields)do
        local id=f.semanticFieldId
        local note=d.lifecycle
        if kind=='roster'then note=SHIP..' Zero suppresses ordinary picks only: native bypasses and authored squads can still spawn this enemy.'
        elseif kind~='demolition_template'then note=SHIP..' '..note end
        local part=section(id)
        if kind=='composition'then
            local slot=id:match('group_(%d+)_');if slot then part='Group '..slot end
        end
        local row=H.make_row(o,{id=id,field=id,vanilla=f.currentDefault,min=f.min,max=f.max,type=f.type,
            storage=f.backing and f.backing.storage,target=target,descriptor=f,shared=true,unverified=true,
            section=part,editable=f.editable,reason=f.reason,note=note})
        -- Stable across reloads and shared with ledger claims of the same target.
        row.loc='director/'..kind..'/'..key..'/'..id
        row.exact=true -- enforce ordered eligibility bounds on the desired value, not an arbitrary slider range
        rows[#rows+1]=row
    end
    for _,g in ipairs(d.metadata.groups or{})do
        for i,candidate in ipairs(g.candidates or{})do
            info(H,rows,o,'group:'..g.slot..':'..i,(g.candidateNames or{})[i]or title(candidate),'Candidate','Group '..g.slot,nil,
                'Candidate group only. Native consumer: '..tostring(d.metadata.role or'unresolved')..'. Eligibility and mission scripts still apply.')
        end
    end
    return rows
end
function M.director(cat,H,kind)
    local api=cat.real_hd2.enemies
    if type(api)~='table'or type(api[kind])~='function'then return {} end
    local list,descriptions={},{ }
    if kind=='difficulty'then for i=1,10 do descriptions[#descriptions+1]=api.difficulty(i):describe()end
    else descriptions=api[kind=='composition'and'compositions'or kind=='roster'and'rosters'or'demolition_templates']()end
    for _,d in ipairs(descriptions)do
        local key=d.id;local m=d.metadata;local name,sub
        local search={key,m.path or''}
        for _,g in ipairs(m.groups or{})do
            for _,candidate in ipairs(g.candidates or{})do search[#search+1]=candidate end
            for _,candidate in ipairs(g.candidateNames or{})do search[#search+1]=candidate end
        end
        if kind=='difficulty'then name=(m.displayName or'Mission Difficulty')..' - '..key;sub='Mission budgets and cooldown'
        elseif kind=='roster'then name=m.fullDisplayName or m.displayName or title(m.path and m.path:match('([^/]+)$')or key)
            sub=title(m.roster)..' · Row '..m.row
        elseif kind=='composition'then name=title(m.faction)..' · '..title(m.role~='unresolved'and m.role or('Family '..m.family))..' · Row '..m.row;sub='Spawn composition'
        else name=key;sub='Shared demolition threshold'end
        list[#list+1]={key='ed|'..kind..'/'..key,name=name,subtitle=sub,detail=d.lifecycle,
            spawnDifficulty=kind=='difficulty'and tonumber(key)or nil,
            control_rank=kind=='difficulty'and tonumber(key)or nil,
            filter_group=(kind=='roster'or kind=='composition')and title(m.faction or'unknown')or nil,
            iconKind=kind=='difficulty'and'difficulty'or m.faction and'faction'or nil,
            iconName=kind=='difficulty'and key or m.faction,
            search_terms=table.concat(search,' '),
            build=function(o)return M.director_rows(cat,H,o,kind,key)end}
    end
    return sorted(list)
end
function M.models(cat,H)
    if type(cat.real_hd2.enemies.destruction_models)~='function'then return {}end
    local list={}
    for _,model in ipairs(cat.real_hd2.enemies.destruction_models())do
        local paths={};for _,p in pairs(model.paths or{})do if type(p)=='string'then paths[#paths+1]=p end end
        local m=model
        list[#list+1]={key='dm|'..m.id,name=paths[1]and title(paths[1]:match('([^/]+)$'))or('Unresolved '..m.id),
            subtitle=m.id,detail=table.concat(paths,', '),search_terms=table.concat(paths,' '),
            build=function(o)local rows={};stage_rows(H,rows,o,m.stages,m.id)
                for i,p in ipairs(paths)do info(H,rows,o,'path:'..i,'Model path',p,'Model')end
                return rows end}
    end
    return sorted(list)
end
return M

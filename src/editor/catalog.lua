-- The editor's field catalogue: every numeric field HD2Runtime publishes as writable, grouped like the ModBuilder
-- (Weapons, Stratagems, Equipment, Enemies), read in game from the Runtime's own generated catalogues. Those tables
-- are the ones the Runtime validates every write against, so the baselines, ranges and acknowledgements shown are
-- always the installed Runtime's own. Each family is read through a small adapter: a family whose table no longer
-- has the expected shape is reported unavailable instead of failing the editor.
--
-- A row is one field of one object:
--   {key, object, section, label, unit, vanilla, min, max, integer, storage, shared, unverified, acks,
--    field, target = function() return <hd2 target> end, descriptor, loc, editable, reason}
-- `key` is stable across sessions (presets store it). `loc` names the native bytes (shared rows have the same loc).
local util=require('mods/skyeshade/hd2runtime_editor/editor/util')
local M={}

M.GROUPS={
    {id='weapons',label='WEAPONS',items={
        {id='primary',label='Primary'},{id='secondary',label='Secondary'},{id='support',label='Support Weapons'},
        {id='throwables',label='Throwables'},{id='magazines',label='Magazines'}}},
    {id='stratagems',label='STRATAGEMS',items={
        {id='offensive',label='Offensive'},{id='defensive',label='Defensive'},{id='callins',label='Support Call-ins'}}},
    {id='equipment',label='EQUIPMENT',items={
        {id='backpacks',label='Backpacks'},{id='vehicles',label='Vehicles'},{id='vehicle_weapons',label='Vehicle Weapons'},
        {id='boosters',label='Boosters'}}},
    {id='enemies',label='ENEMIES',items={
        {id='terminids',label='Terminids'},{id='automatons',label='Automatons'},{id='illuminate',label='Illuminate'},
        {id='structures',label='Structures'}}},
}

local NUMERIC={number=true,integer=true}
local INTEGER_STORAGE={u8=true,u16=true,u32=true,u64=true,i8=true,i16=true,i32=true,i64=true}
local STORAGE_LIMITS={u8={0,255},u16={0,65535},u32={0,4294967295},i8={-128,127},i16={-32768,32767},
    i32={-2147483648,2147483647}}

local function load(name)
    local ok,value=pcall(require,'hd2runtime/domains/'..name)
    if ok and type(value)=='table'then return value end
    return nil,tostring(value)
end

---------------------------------------------------------------------------------------------- native identity --
local shared_records
local function location(descriptor,fallback)
    if shared_records==nil then
        local ok,value=pcall(require,'hd2runtime/core/shared_records')
        shared_records=ok and type(value)=='table'and value or false
    end
    if shared_records and type(descriptor)=='table'and type(shared_records.entry)=='function'then
        -- The Runtime's own index (the record identity its claims and CONFLICT messages use).
        local ok,entry=pcall(shared_records.entry,descriptor)
        if ok and type(entry)=='table'and entry.key and entry.offset~=nil then
            return entry.key..'@'..tostring(entry.offset)
        end
    end
    local backing=type(descriptor)=='table'and descriptor.backing
    if shared_records and type(backing)=='table'then
        local ok,key=pcall(shared_records.key,backing)
        if ok and key and backing.offset~=nil then return key..'@'..tostring(backing.offset)end
    end
    return fallback
end
M.location=location

------------------------------------------------------------------------------------------------- sections --
local DOMAIN_LABELS={weapon='Weapon',magazine='Ammo & Magazine',rounds='Ammo & Magazine',ammo='Ammo & Magazine',
    reload='Ammo & Magazine',fire_mode='Fire Mode',fire_rate='Fire Mode',heat='Heat',heatsink='Heat',
    projectile='Projectile',damage='Damage',explosion='Explosion',arc='Arc',beam='Beam',charge='Charge',
    status='Status',spread='Handling',recoil='Handling',sway='Handling',reticle='Handling',movement='Handling',
    function_ammo='Functions',entity='Health & Armor',zone='Damage Zones',shield='Shield',turret='Turret',
    targeting='Targeting',stratagem='Call-in',eagle='Eagle',orbital='Orbital Strike',minefield='Minefield',
    booster='Booster',throwable='Throwable',attachment='Magazine',jump='Jump Pack',hover='Hover Pack',
    warp='Warp Pack',recharge='Recharge',drone='Drone',payload='Hellpod'}
local HANDLING={recoil=true,spread=true,sway=true,ergonomics=true,reticle=true,aim=true,zoom=true}
local function domain_of(id)return tostring(id):match('^([^%.]+)')or'other'end
local function domain_label(id)
    local domain=domain_of(id)
    if domain=='weapon'then
        local name=tostring(id):match('^weapon%.(.+)$')or''
        for word in pairs(HANDLING)do if name:find(word,1,true)then return 'Handling'end end
    end
    return DOMAIN_LABELS[domain]or util.humanize(domain)
end
local function role_label(role)
    if role==nil or role=='primary'then return nil end
    return util.humanize(role)
end
local function join(...)
    local parts={}
    for i=1,select('#',...)do
        local p=select(i,...)
        if p and p~=''then parts[#parts+1]=p end
    end
    return table.concat(parts,' · ')
end

--------------------------------------------------------------------------------------------------- rows --
-- One editable numeric field. spec: {id, label, unit, vanilla, min, max, type, storage, field, target, shared,
-- unverified, unverified_reference, descriptor, section, editable, reason}.
local function make_row(object,spec)
    local integer=spec.type=='integer'or(spec.type~='number'and INTEGER_STORAGE[spec.storage or'']~=nil)
    local min,max=spec.min,spec.max
    local limits=STORAGE_LIMITS[spec.storage or'']
    if limits then
        min=min and math.max(min,limits[1])or limits[1]
        max=max and math.min(max,limits[2])or limits[2]
    end
    local row={key=object.key..'|'..spec.id,object=object,section=spec.section or'Fields',
        label=util.plain(spec.label or util.humanize(spec.field),60),unit=spec.unit,vanilla=spec.vanilla,
        min=min,max=max,integer=integer,storage=spec.storage,field=spec.field,target=spec.target,
        shared=spec.shared==true,unverified=spec.unverified==true,descriptor=spec.descriptor,
        acks={allow_shared=spec.shared==true or nil,allow_unverified_effect=spec.unverified==true or nil,
            allow_unverified_reference=spec.unverified_reference==true or nil},
        editable=spec.editable~=false,reason=spec.reason,semantic=spec.semantic or spec.field}
    row.loc=location(spec.descriptor,'row:'..row.key)
    if row.editable then
        local held=util.representable(row.vanilla,integer,spec.storage)
        if held==nil then
            row.editable,row.reason=false,'its default '..tostring(row.vanilla)..' needs more than 3 decimals'
        else row.held_vanilla=held end
    end
    return row
end
M.make_row=make_row

local function numeric(field_type,value)return NUMERIC[field_type or'']and type(value)=='number'end
local function unverified(f)
    if f.acknowledgement=='allow_unverified_effect'then return true end
    if type(f.acknowledgements)=='table'then
        for _,a in ipairs(f.acknowledgements)do if a=='allow_unverified_effect'then return true end end
    end
    return false
end
local function shared_ack(f)
    if f.affectsMultipleWeapons==true or f.allowSharedRequired==true or f.shared==true then return true end
    if type(f.acknowledgements)=='table'then
        for _,a in ipairs(f.acknowledgements)do if a=='allow_shared'then return true end end
    end
    return false
end
local function range_of(f)
    local r=type(f.range)=='table'and f.range or nil
    return (r and r.min)or f.min,(r and r.max)or f.max,r and r.integer
end
-- The field id a role-scoped target takes: the qualified id without its role / phase segments
-- ('explosion.primary.impact.damage.status_1_strength' on an impact explosion -> 'explosion.damage.status_1_strength').
local function strip(id,...)
    local out='.'..tostring(id)..'.'
    for i=1,select('#',...)do
        local segment=select(i,...)
        if segment then out=out:gsub('%.'..segment:gsub('%p','%%%0')..'%.','.',1)end
    end
    return out:sub(2,-2)
end
M.strip=strip
-- Whether a target builder accepts these arguments (the Runtime raises for an unknown role, zone or attack).
local function builds(fn)return(pcall(fn))end

------------------------------------------------------------------------------------------- player weapons --
local function player_rows(hd2,object,entry)
    local rows={}
    local name=entry.name
    for _,f in ipairs(entry.fields or{})do
        if f.editable and f.preferred and not f.deprecated and not f.derivedReadOnly
            and numeric(f.type,f.currentDefault)then
            local b=f.backing or{}
            local id=f.semanticFieldId
            local domain=domain_of(id)
            local branch,phase=b.branch,b.phase
            local section,target,field
            local role,when=branch,phase
            local projectile=function()return hd2.weapon(name):attack(role):projectile()end
            -- Weapons without a projectile attack (flame, arc, beam, melee) own their damage rows on the weapon.
            local has_projectile=branch and builds(projectile)
            if(domain=='projectile'or domain=='damage')and has_projectile then
                target=projectile
                field=strip(id,branch)
                section=join(DOMAIN_LABELS[domain],role_label(branch))
            elseif domain=='explosion'and has_projectile and phase then
                target=function()return projectile():terminal_action(when):explosion()end
                field=strip(id,branch,phase)
                section=join('Explosion',role_label(branch),util.humanize(phase))
            elseif branch and(domain=='projectile'or domain=='damage'or domain=='explosion')then
                target=function()return hd2.weapon(name)end
                field=id
                section=join(DOMAIN_LABELS[domain],role_label(branch),phase and util.humanize(phase)or nil)
            else
                target=function()return hd2.weapon(name)end
                field=id
                section=domain_label(id)
            end
            rows[#rows+1]=make_row(object,{id=id,label=f.displayName,unit=f.unit,vanilla=f.currentDefault,
                min=f.min,max=f.max,type=f.type,storage=b.storage,field=field,target=target,
                shared=shared_ack(f),unverified=unverified(f),descriptor=f,section=section})
        end
    end
    return rows
end

------------------------------------------------------------------------------------------- support weapons --
local function support_rows(hd2,object,entry)
    local rows={}
    local name=entry.name
    for _,f in ipairs(entry.fields or{})do
        if f.editable and not f.derivedReadOnly and not f.deprecated and(f.preferred~=false)
            and numeric(f.type,f.currentDefault)then
            local t=f.target or{}
            local role=t.attack
            local id=f.semanticFieldId
            local section,target,field
            if t.path=='projectile_reference'then
                target=function()return hd2.support_weapon(name):attack(role):projectile()end
                field=strip(id,role)
                section=join(DOMAIN_LABELS[domain_of(field)]or'Projectile',role_label(role))
            elseif t.path=='explosion'then
                target=function()return hd2.support_weapon(name):attack(role):explosion()end
                field=strip(id,role)
                section=join('Explosion',role_label(role))
            elseif t.path=='attack'then
                target=function()return hd2.support_weapon(name):attack(role)end
                field=strip(id,role)
                section=join(DOMAIN_LABELS[domain_of(field)]or util.humanize(domain_of(field)),role_label(role))
            else
                target=function()return hd2.support_weapon(name)end
                field=id
                section=domain_label(id)
            end
            rows[#rows+1]=make_row(object,{id=id..(role and('@'..role)or''),label=f.displayName,unit=f.unit,
                vanilla=f.currentDefault,min=f.min,max=f.max,type=f.type,storage=(f.backing or{}).storage,field=field,
                target=target,shared=shared_ack(f),unverified=unverified(f),descriptor=f,section=section})
        end
    end
    return rows
end

------------------------------------------------------------------------------------------------ stratagems --
local PATH_LABELS={stratagem='Call-in',eagle_rearm='Eagle Rearm',deployed_entity='Deployed Entity',shield='Shield',
    turret='Turret',targeting='Targeting',minefield='Minefield',weapon='Mounted Weapon'}
local function stratagem_target(hd2,name,t)
    local path=t.path
    if path=='stratagem'then return function()return hd2.stratagem(name)end end
    if path=='eagle_rearm'then return function()return hd2.stratagem(name):eagle_rearm()end end
    if path=='deployed_entity'then return function()return hd2.stratagem(name):deployed_entity()end end
    if path=='shield'or path=='turret'or path=='targeting'or path=='minefield'then
        return function()local e=hd2.stratagem(name):deployed_entity();return e[path](e)end
    end
    if path=='damage_zone'then
        local zone=t.zone
        return function()return hd2.stratagem(name):deployed_entity():damage_zone(zone)end
    end
    if path=='weapon'then
        local weapon=t.weapon or'primary'
        return function()return hd2.stratagem(name):deployed_entity():weapon(weapon)end
    end
    if path=='attack'then
        local role=t.attack
        if t.weapon=='mine'then
            if role=='mine'then return function()return hd2.stratagem(name):mine()end end
            return function()return hd2.stratagem(name):attack(role)end
        end
        if t.weapon then
            local weapon=t.weapon
            return function()return hd2.stratagem(name):deployed_entity():weapon(weapon):attack(role)end
        end
        return function()return hd2.stratagem(name):attack(role)end
    end
    return nil
end
local function stratagem_rows(hd2,object,entry)
    local rows={}
    local name=entry.name
    for _,f in ipairs(entry.fields or{})do
        local t=f.target or{}
        if f.editable and numeric(f.type,f.currentDefault)then
            local target=stratagem_target(hd2,name,t)
            if target then
                local section=PATH_LABELS[t.path]
                if t.path=='damage_zone'then section=join('Damage Zone',t.zone)
                elseif t.path=='attack'then
                    section=join(t.weapon=='mine'and'Mine'or(t.weapon and'Mounted Weapon')or'Attack',
                        util.humanize(t.attack or''),DOMAIN_LABELS[domain_of(f.semanticFieldId)])
                end
                rows[#rows+1]=make_row(object,{id=f.instanceKey or(f.semanticFieldId..'@'..tostring(t.path)),
                    label=f.displayName,unit=f.unit,vanilla=f.currentDefault,min=f.min,max=f.max,type=f.type,
                    storage=(f.backing or{}).storage,field=f.semanticFieldId,target=target,shared=shared_ack(f),
                    unverified=unverified(f),descriptor=f,section=section or util.humanize(t.path or'')})
            end
        end
    end
    return rows
end

----------------------------------------------------------------------------------------- vehicles, backpacks --
local function vehicle_rows(hd2,object,entry)
    local rows={}
    local name=entry.name
    for _,f in ipairs(entry.fields or{})do
        local t=f.target or{}
        if f.editable and numeric(f.type,f.currentDefault)and(t.path=='entity'or t.path=='damage_zone')then
            local target,section
            if t.path=='entity'then
                target=function()return hd2.vehicle(name)end
                section='Health & Armor'
            else
                local zone=t.zone
                target=function()return hd2.vehicle(name):damage_zone(zone)end
                section=join('Damage Zone',zone)
            end
            rows[#rows+1]=make_row(object,{id=f.instanceKey or(f.semanticFieldId..'@'..tostring(t.zone)),
                label=f.displayName,unit=f.unit,vanilla=f.currentDefault,min=f.min,max=f.max,type=f.type,
                storage=(f.backing or{}).storage,field=f.semanticFieldId,target=target,shared=shared_ack(f),
                unverified=unverified(f),descriptor=f,section=section})
        end
    end
    return rows
end
local function backpack_rows(hd2,object,entry)
    local rows={}
    local name=entry.name
    for _,f in ipairs(entry.fields or{})do
        local t=f.target or{}
        if f.editable and numeric(f.type,f.currentDefault)then
            local target,section
            if t.path=='backpack'then
                target=function()return hd2.backpack(name)end
                section=f.uiGroup or domain_label(f.semanticFieldId)
            elseif t.path=='linked'then
                local linked=t.linked
                if linked=='drone'then target=function()return hd2.backpack(name):drone()end
                elseif linked=='energy_shield'then target=function()return hd2.backpack(name):energy_shield()end end
                section=util.humanize(linked or'linked')
            elseif t.path=='damage_zone'then
                local zone,linked=t.zone,t.linked
                if linked=='drone'then target=function()return hd2.backpack(name):drone():damage_zone(zone)end
                elseif linked=='energy_shield'then
                    target=function()return hd2.backpack(name):energy_shield():damage_zone(zone)end
                else target=function()return hd2.backpack(name):damage_zone(zone)end end
                section=join(linked and util.humanize(linked)or nil,'Damage Zone',zone)
            end
            if target then
                rows[#rows+1]=make_row(object,{id=f.instanceKey or(f.semanticFieldId..'@'..tostring(t.path)),
                    label=f.displayName,unit=f.unit,vanilla=f.currentDefault,min=f.min,max=f.max,type=f.type,
                    storage=(f.backing or{}).storage,field=f.semanticFieldId,target=target,shared=shared_ack(f),
                    unverified=unverified(f),descriptor=f,section=section})
            end
        end
    end
    return rows
end

----------------------------------------------------------------------------------------- vehicle weapons --
local function vehicle_weapon_rows(hd2,object,entry)
    local rows={}
    local carrier,mount=entry.vehicle,entry.mount
    local drone=entry.carrier=='backpack_drone'
    local function base()
        if drone then return hd2.backpack(carrier):drone():weapon()end
        return hd2.vehicle(carrier):weapon(mount)
    end
    for _,f in ipairs(entry.fields or{})do
        local t=f.target or{}
        if f.editable and not f.derivedReadOnly and numeric(f.type,f.currentDefault)then
            local role=t.attack
            local target,section
            if t.path=='weapon'then
                target=base
                section=domain_label(f.semanticFieldId)
            elseif t.path=='projectile_reference'then
                if role==nil or role=='primary'then target=function()return base():projectile()end
                else target=function()return base():attack(role):projectile()end end
                section=join(DOMAIN_LABELS[domain_of(f.semanticTarget or f.semanticFieldId)]or'Projectile',role_label(role))
            elseif t.path=='explosion'then
                if role==nil or role=='impact'then target=function()return base():explosion()end
                else target=function()return base():attack(role)end end
                section=join('Explosion',role~='impact'and role_label(role)or nil)
            elseif t.path=='attack'then
                target=function()return base():attack(role)end
                section=join(domain_label(f.semanticTarget or f.semanticFieldId),role_label(role))
            end
            if target then
                local field=t.path=='weapon'and f.semanticFieldId or strip(f.semanticFieldId,role)
                rows[#rows+1]=make_row(object,{id=f.semanticFieldId..(role and('@'..role)or''),label=f.displayName,
                    unit=f.unit,vanilla=f.currentDefault,min=f.min,max=f.max,type=f.type,
                    storage=(f.backing or{}).storage,field=field,target=target,shared=shared_ack(f),
                    unverified=unverified(f),descriptor=f,section=section})
            end
        end
    end
    return rows
end

---------------------------------------------------------------------------------------- throwables, boosters --
local function throwable_target(hd2,name,t)
    local path=t.path
    if path=='throwable'then return function()return hd2.throwable(name)end end
    if path=='status_effect'then
        local key=t.key
        return function()return hd2.throwable(name):status_effect(key)end
    end
    if path=='bomblet_explosion'then return function()return hd2.throwable(name):bomblets():explosion()end end
    return function()local th=hd2.throwable(name);return th[path](th)end
end
local function throwable_rows(hd2,object,entry)
    local rows={}
    local name=entry.name
    local paths=util.sorted_keys(entry.targets or{})
    for _,key in ipairs(paths)do
        local t=entry.targets[key]
        local target=throwable_target(hd2,name,t)
        local section=t.label and join(util.humanize(t.path),t.label)or util.humanize(t.path or key)
        if t.path=='throwable'then section='Throwable'end
        for _,id in ipairs(util.sorted_keys(t.fields or{}))do
            local f=t.fields[id]
            local min,max,integer=range_of(f)
            if f.editable and numeric(f.type,f.currentDefault)then
                rows[#rows+1]=make_row(object,{id=f.instanceKey or(key..':'..id),label=f.displayName,unit=f.unit,
                    vanilla=f.currentDefault,min=min,max=max,type=integer and'integer'or f.type,
                    storage=(f.backing or{}).storage,field=f.semanticFieldId or id,target=target,
                    shared=shared_ack(f),unverified=unverified(f),descriptor=f,section=section})
            end
        end
    end
    return rows
end
local BOOSTER_PATHS={tuning='Tuning',explosion='Explosion',status_effect='Status Effect',status_damage='Status Damage',
    granted_stratagem='Granted Stratagem',deployed_entity='Deployed Entity'}
local function booster_rows(hd2,object,entry)
    local rows={}
    local name=entry.name
    for _,path in ipairs(util.sorted_keys(entry.targets or{}))do
        local t=entry.targets[path]
        local target=function()local b=hd2.booster(name);return b[path](b)end
        for _,id in ipairs(util.sorted_keys(t.fields or{}))do
            local f=t.fields[id]
            local min,max,integer=range_of(f)
            if f.editable and numeric(f.type,f.currentDefault)then
                rows[#rows+1]=make_row(object,{id=f.instanceKey or(path..':'..id),label=f.displayName,unit=f.unit,
                    vanilla=f.currentDefault,min=min,max=max,type=integer and'integer'or f.type,
                    storage=(f.backing or{}).storage,field=f.semanticFieldId or id,target=target,
                    shared=shared_ack(f),unverified=unverified(f),descriptor=f,section=BOOSTER_PATHS[path]or util.humanize(path)})
            end
        end
    end
    return rows
end

------------------------------------------------------------------------------------------- magazine options --
local function attachment_rows(hd2,object,entry)
    local rows={}
    local id=entry.semanticId
    for _,field_id in ipairs(util.sorted_keys(entry.fields or{}))do
        local f=entry.fields[field_id]
        if type(f.currentDefault)=='number'and f.editable~=false then
            rows[#rows+1]=make_row(object,{id=field_id,label=util.humanize(field_id),vanilla=f.currentDefault,
                type=INTEGER_STORAGE[f.storage or'']and'integer'or'number',storage=f.storage,field=field_id,
                target=function()return hd2.weapon_attachment(id)end,shared=true,unverified=true,descriptor=f,
                section='Magazine'})
        end
    end
    return rows
end

------------------------------------------------------------------------------------------------- enemies --
local function enemy_rows(hd2,object,entry,schema,structure_ack)
    local rows={}
    local class,structure=entry.className,entry.kind=='structure'
    local zones={}
    for _,z in ipairs(entry.zones or{})do zones[z.id]=z end
    local attacks={}
    for _,a in ipairs(entry.attacks or{})do attacks[a.id]=a end
    local function root()
        if structure then return hd2.structure(class)end
        return hd2.enemy(class)
    end
    for _,f in ipairs(entry.fields or{})do
        local s=schema[f.id]or{}
        if f.editable and type(f.currentDefault)=='number'and NUMERIC[s.type or'number']then
            local target,section
            if f.path=='entity'then target=root;section='Health & Armor'
            elseif f.path=='damage_zone'then
                local zone=f.zone
                local z=zones[zone]or{}
                target=function()return root():zone(zone)end
                section=join('Zone',z.wikiZone or util.humanize(z.name or zone))
            elseif f.path=='attack'then
                local attack=f.attack
                local base=tostring(attack):match('^(slot_%d+)')
                local a=attacks[attack]or attacks[base]or{}
                target=function()return root():attack(attack)end
                section=join('Attack',util.humanize(attack),a.role and util.humanize(a.role)or nil)
            end
            if target then
                local ack=s.acknowledgement
                -- Structures: the fields listed in structureAcknowledgement need allow_unverified_effect (their
                -- health writes are offline-proven only).
                if structure and type(structure_ack)=='table'and type(structure_ack.fields)=='table'then
                    for _,id in ipairs(structure_ack.fields)do
                        if id==f.id then ack='allow_unverified_effect'end
                    end
                end
                rows[#rows+1]=make_row(object,{id=f.path..':'..tostring(f.zone or f.attack or'')..':'..f.id,
                    label=util.humanize(f.id),vanilla=f.currentDefault,min=s.min,max=s.max,type=s.type,
                    storage=s.storage or(f.backing or{}).storage,field=f.id,target=target,shared=s.shared==true,
                    unverified=ack=='allow_unverified_effect',descriptor=f,section=section})
            end
        end
    end
    return rows
end

------------------------------------------------------------------------------------------------ families --
-- Each category: {family, list = function(cat) -> {{key, name, subtitle, build = function() -> rows}}}.
local CATEGORY={}
local function sorted_objects(list)
    table.sort(list,function(a,b)return util.natural_less(a.name,b.name)end)
    return list
end
local function player_category(slot)
    return function(cat)
        local W,why=load('player_weapon_authoring')
        if not W then return nil,why end
        local list={}
        for name,entry in pairs(W.weapons or{})do
            if entry.slot==slot then
                list[#list+1]={key='pw|'..name,name=name,subtitle=entry.category,
                    build=function(object)return player_rows(cat.hd2,object,entry)end}
            end
        end
        return sorted_objects(list)
    end
end
CATEGORY.primary=player_category('primary')
CATEGORY.secondary=player_category('secondary')
function CATEGORY.support(cat)
    local S,why=load('support_weapon_authoring')
    if not S then return nil,why end
    local list={}
    for name,entry in pairs(S.weapons or{})do
        list[#list+1]={key='sw|'..name,name=name,subtitle='Support weapon',
            build=function(object)return support_rows(cat.hd2,object,entry)end}
    end
    return sorted_objects(list)
end
local function stratagem_category(families,subtitles)
    return function(cat)
        local ST,why=load('stratagem_authoring')
        if not ST then return nil,why end
        local list={}
        for name,entry in pairs(ST.stratagems or{})do
            if families[entry.family]then
                list[#list+1]={key='st|'..name,name=name,subtitle=subtitles[entry.family]or util.humanize(entry.family),
                    build=function(object)return stratagem_rows(cat.hd2,object,entry)end}
            end
        end
        return sorted_objects(list)
    end
end
CATEGORY.offensive=stratagem_category({orbital=true,eagle=true},{orbital='Orbital',eagle='Eagle'})
CATEGORY.defensive=stratagem_category({sentry=true,emplacement=true,mine=true},
    {sentry='Sentry',emplacement='Emplacement',mine='Mines'})
CATEGORY.callins=stratagem_category({support=true,vehicle=true,backpack=true,mission=true},
    {support='Support weapon call-in',vehicle='Vehicle call-in',backpack='Backpack call-in',mission='Mission'})
function CATEGORY.vehicles(cat)
    local E,why=load('entity_authoring')
    if not E then return nil,why end
    local list={}
    for name,entry in pairs(E.vehicles or{})do
        list[#list+1]={key='vh|'..name,name=name,subtitle='Vehicle',
            build=function(object)return vehicle_rows(cat.hd2,object,entry)end}
    end
    return sorted_objects(list)
end
function CATEGORY.backpacks(cat)
    local E,why=load('entity_authoring')
    if not E then return nil,why end
    local list={}
    for name,entry in pairs(E.backpacks or{})do
        list[#list+1]={key='bp|'..name,name=name,subtitle='Backpack',
            build=function(object)return backpack_rows(cat.hd2,object,entry)end}
    end
    return sorted_objects(list)
end
function CATEGORY.vehicle_weapons(cat)
    local V,why=load('vehicle_weapon_authoring')
    if not V then return nil,why end
    local list={}
    for key,entry in pairs(V.weapons or{})do
        list[#list+1]={key='vw|'..key,name=key,
            subtitle=entry.carrier=='backpack_drone'and'Drone weapon'or'Vehicle weapon',
            build=function(object)return vehicle_weapon_rows(cat.hd2,object,entry)end}
    end
    return sorted_objects(list)
end
function CATEGORY.throwables(cat)
    local T,why=load('throwable_authoring')
    if not T then return nil,why end
    local list={}
    for name,entry in pairs(T.throwables or{})do
        list[#list+1]={key='th|'..name,name=name,subtitle=entry.family or entry.category,
            build=function(object)return throwable_rows(cat.hd2,object,entry)end}
    end
    return sorted_objects(list)
end
function CATEGORY.boosters(cat)
    local B,why=load('booster_authoring')
    if not B then return nil,why end
    local list={}
    for name,entry in pairs(B.boosters or{})do
        list[#list+1]={key='bo|'..name,name=name,subtitle='Booster',
            build=function(object)return booster_rows(cat.hd2,object,entry)end}
    end
    return sorted_objects(list)
end
function CATEGORY.magazines(cat)
    local A,why=load('attachment_authoring')
    if not A then return nil,why end
    local users={}
    for weapon,ids in pairs(A.weapons or{})do
        if type(ids)=='table'then
            for _,item in pairs(ids)do
                local id=type(item)=='table'and(item.semanticId or item.attachment or item.id)or item
                if type(id)=='string'then
                    users[id]=users[id]or{}
                    users[id][#users[id]+1]=weapon
                end
            end
        end
    end
    local list={}
    for id,entry in pairs(A.attachments or{})do
        local names=users[id]or{}
        table.sort(names,util.natural_less)
        local name=util.plain((entry.name or id):gsub('%s+',' '),80)
        list[#list+1]={key='mg|'..id,name=name,subtitle=#names>0 and table.concat(names,', ')or'Magazine option',
            build=function(object)return attachment_rows(cat.hd2,object,entry)end}
    end
    return sorted_objects(list)
end
local function enemy_category(filter)
    return function(cat)
        local EN,why=load('enemy_authoring')
        if not EN then return nil,why end
        local list={}
        for class,entry in pairs(EN.enemies or{})do
            if filter(entry)then
                entry.className=entry.className or class
                local name=entry.wikiName or entry.name or class
                if name:find('_')or name==name:lower()then name=util.humanize(name)end
                list[#list+1]={key='en|'..class,name=name,
                    subtitle=util.humanize(entry.faction or entry.kind or''),
                    build=function(object)return enemy_rows(cat.hd2,object,entry,EN.schema or{},EN.structureAcknowledgement)end}
            end
        end
        return sorted_objects(list)
    end
end
CATEGORY.terminids=enemy_category(function(e)return e.kind=='enemy'and e.faction=='terminids'end)
CATEGORY.automatons=enemy_category(function(e)return e.kind=='enemy'and e.faction=='automatons'end)
CATEGORY.illuminate=enemy_category(function(e)return e.kind=='enemy'and e.faction=='illuminate'end)
CATEGORY.structures=enemy_category(function(e)return e.kind=='structure'end)
M.CATEGORY=CATEGORY

-- The category that holds an object key's family (for presets: a key names its object, the object its category).
local FAMILY_CATEGORIES={pw={'primary','secondary'},sw={'support'},st={'offensive','defensive','callins'},
    vh={'vehicles'},bp={'backpacks'},vw={'vehicle_weapons'},th={'throwables'},bo={'boosters'},mg={'magazines'},
    en={'terminids','automatons','illuminate','structures'}}

------------------------------------------------------------------------------------------------- catalogue --
local Catalog={};Catalog.__index=Catalog

function M.new(hd2)
    return setmetatable({hd2=hd2,lists={},errors={},by_key={},rows={},by_loc={}},Catalog)
end
-- The category's objects (built once), or {} and the reason it is unavailable.
function Catalog:objects(category)
    local list=self.lists[category]
    if list then return list,self.errors[category]end
    local builder=CATEGORY[category]
    local ok,result,why=pcall(function()return builder(self)end)
    if not ok then why=result;result=nil end
    list=result or{}
    for _,object in ipairs(list)do
        object.category=category
        self.by_key[object.key]=object
    end
    self.lists[category]=list
    self.errors[category]=result==nil and tostring(why or'unavailable')or nil
    return list,self.errors[category]
end
function Catalog:count(category)return#(self:objects(category))end
-- An object's rows and sections (built once): object.rows, object.sections = {{label, rows}}.
function Catalog:open(object)
    if object.rows then return object end
    local ok,rows=pcall(object.build,object)
    if not ok then
        object.rows,object.sections,object.error={},{},tostring(rows)
        return object
    end
    object.rows,object.sections={},{}
    local by_label={}
    for _,row in ipairs(rows)do
        if not self.rows[row.key]then
            object.rows[#object.rows+1]=row
            self.rows[row.key]=row
            local list=self.by_loc[row.loc]
            if not list then list={};self.by_loc[row.loc]=list end
            list[#list+1]=row
            local section=by_label[row.section]
            if not section then
                section={label=row.section,rows={}}
                by_label[row.section]=section
                object.sections[#object.sections+1]=section
            end
            section.rows[#section.rows+1]=row
        end
    end
    return object
end
function Catalog:object(key)
    local object=self.by_key[key]
    if object then return object end
    local family=tostring(key):match('^(%a+)|')
    for _,category in ipairs(FAMILY_CATEGORIES[family]or{})do
        self:objects(category)
        object=self.by_key[key]
        if object then return object end
    end
    return nil
end
-- A row by its stable key (opens its object), or nil.
function Catalog:row(key)
    local row=self.rows[key]
    if row then return row end
    local family,name=tostring(key):match('^(%a+)|([^|]+)|')
    if not family then return nil end
    local object=self:object(family..'|'..name)
    if not object then return nil end
    self:open(object)
    return self.rows[key]
end
-- The row of a field another mod wrote: its object (from the validated spec), then the same descriptor or bytes.
function Catalog:find(object_key,loc,descriptor)
    local object=object_key and self:object(object_key)
    if object then
        self:open(object)
        for _,row in ipairs(object.rows)do
            if descriptor~=nil and row.descriptor==descriptor then return row end
        end
        for _,row in ipairs(object.rows)do if row.loc==loc then return row end end
    end
    return self:row_at(loc)
end
-- Every open row on the same native bytes.
function Catalog:siblings(row)return self.by_loc[row.loc]or{row}end
function Catalog:row_at(loc)local list=self.by_loc[loc];return list and list[1]or nil end

return M

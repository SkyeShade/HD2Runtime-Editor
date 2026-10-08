-- HD2R Editor (c) 2026 SkyeShade. All rights reserved except as granted in LICENSE
-- (https://github.com/SkyeShade/HD2Runtime-Editor). Do not redistribute or reuse without the credit it requires.
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
        {id='primary',label='Primary'},{id='secondary',label='Secondary'},{id='throwables',label='Throwables'}}},
    {id='stratagems',label='STRATAGEMS',items={
        {id='offensive',label='Offensive',tone='offensive'},{id='defensive',label='Defensive',tone='defensive'},
        {id='support_weapons',label='Support Weapons',tone='support'},
        {id='support_backpacks',label='Support Backpacks',tone='support'},
        {id='vehicles',label='Vehicles',tone='support'},{id='resupply',label='Resupply',tone='support'}}},
    {id='equipment',label='EQUIPMENT',items={{id='boosters',label='Boosters'}}},
    {id='helldiver',label='HELLDIVER',items={{id='helldiver',label='Helldiver'},{id='armor',label='Armor'}}},
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
    -- armor stats (not records): a kit's piece in one slot, or an entry of a game.dll table
    if type(backing)=='table'and backing.kind=='armor_piece'and backing.kit and backing.slot then
        return 'armor_kit/'..tostring(backing.kit)..'/'..tostring(backing.slot)
    end
    if type(backing)=='table'and backing.kind=='image_table'and backing.rva then
        return 'image/'..tostring(backing.table)..'@'..tostring(backing.rva)
    end
    -- no record identity (an attachment's field: one attachment mounted by several weapons): the Runtime's own field
    -- descriptor is one object per field instance, so rows that carry the same one write the same bytes
    if type(descriptor)=='table'then return(('field:'..tostring(descriptor)):gsub('table: ',''))end
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
-- unverified, unverified_reference, descriptor, section, editable, reason, disabled_value}. disabled_value: a field
-- whose reviewed domain is that sentinel OR a value above 0 up to max (the whole-body gib threshold: -1 disables it);
-- nothing between the two is valid.
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
        editable=spec.editable~=false,reason=spec.reason,semantic=spec.semantic or spec.field,group=spec.group,
        note=spec.note,disabled_value=spec.disabled_value}
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

-- A row whose value is not a plain number: kind = 'choice' (booleans, statuses, enums), 'code' (calldown codes),
-- 'uses' (mission uses: a count or 'unlimited') or 'reference' (projectile swaps, terminal explosions). spec adds:
-- expect = function() -> the request's expect (references; default the vanilla value), options = function(row) ->
-- {{value, label, sub}} (choices and references), labels = {{value, label}} (display names), min / max (uses),
-- directions / min_length / max_length (codes).
local function make_value_row(object,spec)
    local row={key=object.key..'|'..spec.id,object=object,section=spec.section or'Fields',kind=spec.kind,
        label=util.plain(spec.label or util.humanize(spec.field),60),unit=spec.unit,vanilla=spec.vanilla,
        held_vanilla=spec.vanilla,field=spec.field,target=spec.target,expect=spec.expect,shared=spec.shared==true,
        unverified=spec.unverified==true,descriptor=spec.descriptor,
        acks={allow_shared=spec.shared==true or nil,allow_unverified_effect=spec.unverified==true or nil,
            allow_unverified_reference=spec.unverified_reference==true or nil},
        editable=spec.editable~=false,reason=spec.reason,semantic=spec.field,options=spec.options,labels=spec.labels,
        min=spec.min,max=spec.max,integer=spec.kind=='uses'or nil,directions=spec.directions,
        min_length=spec.min_length,max_length=spec.max_length,unlimited=spec.unlimited,group=spec.group,
        modes=spec.modes,max_modes=spec.max_modes,slots=spec.slots,note=spec.note,controller=spec.controller,
        export_reason=spec.export_reason}
    row.loc=location(spec.descriptor,'row:'..row.key)
    return row
end
M.make_value_row=make_value_row

-- A row's value as text (its own labels first).
function M.text(row,value)
    for _,item in ipairs(row.labels or{})do
        if util.same(item.value,value)then return item.label end
    end
    if row.kind=='traits'and type(value)=='table'then
        if#value==0 then return'None'end
        local names={}
        for i,id in ipairs(value)do
            names[i]=id
            for _,t in ipairs(row.traits or{})do if t.value==id then names[i]=t.label end end
        end
        return table.concat(names,', ')
    end
    return util.value_text(value)
end
-- The value a request expects (vanilla; references build their own handle).
function M.expect(row)
    if row.expect then return row.expect()end
    return row.vanilla
end

-- Validates a request for `value` with the Runtime's own validator, adding each acknowledgement the validator asks
-- for (at most three). Returns true and the acknowledgements, or false and why. Without the validator (an unknown
-- Runtime) every value passes with the row's own acknowledgements; the ensure's bind-time proof still applies.
local patches
-- How many rate slots a fire_rate.modes list fills.
function M.filled(list)
    local n=0
    for _,v in ipairs(type(list)=='table'and list or{})do if type(v)=='number'and v>0 then n=n+1 end end
    return n
end
-- The selector binding {field, expect, value} a rates value needs written with it: more than one filled slot on a
-- weapon whose rate-of-fire selector is not bound yet (fire_rate_modes().state 'addable'); nil otherwise.
function M.rate_binding(row,value)
    if row.kind~='rates'or not row.rate_info or M.filled(value)<2 then return nil end
    local info=row.rate_info()
    if info and info.state=='addable'and type(info.binding)=='table'and info.binding.field then return info.binding end
    return nil
end
function M.probe(row,value,acks)
    if row.controller then return true,{}end
    if patches==nil then
        local ok,module=pcall(require,'hd2runtime/domains/patches')
        patches=ok and type(module)=='table'and type(module.validate)=='function'and module or false
    end
    local use={}
    for k,v in pairs(acks or row.acks or{})do if v then use[k]=true end end
    if not patches then return true,use end
    local binding=M.rate_binding(row,value)
    for _=1,4 do
        local ok,err=pcall(function()
            if binding then
                -- the rates and the selector binding in one transaction, as the editor registers them
                local request={id='hd2editor-probe',target=row.target(),changes={
                    {field=row.field,expect=M.expect(row),value=value},
                    {field=binding.field,expect=binding.expect,value=binding.value}}}
                for k in pairs(use)do request[k]=true end
                return require('hd2runtime/domains/transactions').validate(request)
            end
            local request={id='hd2editor-probe',target=row.target(),field=row.field,expect=M.expect(row),value=value}
            for k in pairs(use)do request[k]=true end
            return patches.validate(request)
        end)
        if ok then return true,use end
        local text=tostring(err)
        local missing=text:match('requires (allow_[%w_]+)')
        if missing and not use[missing]then use[missing]=true
        else return false,(text:gsub('^[^:]+:%d+: ',''))end
    end
    return false,'too many acknowledgements'
end

-- Storable forms of values (presets, the saved session): numbers, booleans, strings and codes as they are; reference
-- handles by what names them.
function M.encode(row,value)
    if type(value)~='table'then return value end
    if getmetatable(value)==nil and rawget(value,'path')~='no_explosion'then return value end
    local output=rawget(value,'output')
    if output then return {ref='output',id=output}end
    if rawget(value,'resource')=='pickup'then return {ref='pickup',id=rawget(value,'semanticId')}end
    if rawget(value,'path')=='no_explosion'then return {ref='none'}end
    local weapon,attack,phase=rawget(value,'weapon'),rawget(value,'attack'),rawget(value,'phase')
    if weapon and phase then return {ref='terminal',weapon=weapon,attack=attack,phase=phase}end
    if weapon and attack then return {ref='projectile',weapon=weapon,attack=attack}end
    return nil
end
function M.decode(cat,row,stored)
    if type(stored)~='table'or stored.ref==nil then return stored end
    local hd2=cat.hd2
    local ok,value=pcall(function()
        if stored.ref=='output'then return hd2.attack_output(stored.id)end
        if stored.ref=='pickup'then return hd2.pickup(stored.id)end
        if stored.ref=='none'then return row.target():no_explosion()end
        if stored.ref=='terminal'then
            return hd2.weapon(stored.weapon):attack(stored.attack):projectile():terminal_action(stored.phase):explosion()
        end
        if stored.ref=='projectile'then return hd2.weapon(stored.weapon):attack(stored.attack):projectile()end
    end)
    return ok and value or nil
end

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
-- Donor projectiles: every reviewed projectile attack output (labels from its owner).
local function projectile_options(hd2,row)
    local out={{value=M.expect(row),label='Own projectile',sub=row.object.name}}
    local A=load('attack_outputs')
    if A then
        local ids=util.sorted_keys(A.outputs or{})
        for _,id in ipairs(ids)do
            local o=A.outputs[id]
            if o.family=='projectile'and o.editable~=false then
                local owner=type(o.owner)=='table'and o.owner.name or'?'
                local ok,value=pcall(hd2.attack_output,id)
                if ok then out[#out+1]={value=value,label=tostring(owner),sub=(id:match('([^/]+)$')or id)}end
            end
        end
    end
    return out
end
-- Donor terminal explosions: none, and one player weapon terminal action per reviewed explosion type.
local function explosion_options(hd2,row)
    local out={}
    local okn,none=pcall(function()return row.target():no_explosion()end)
    if okn then out[1]={value=none,label='None',sub='no terminal explosion'}end
    local W=load('player_weapon_authoring')
    local seen={}
    for _,wname in ipairs(util.sorted_keys(W and W.weapons or{},util.natural_less))do
        for _,f in ipairs(W.weapons[wname].fields or{})do
            local d=type(f.currentDefault)=='table'and f.currentDefault
            if f.type=='explosion_reference'and d and(d.explosionType or 0)>0 and not seen[d.explosionType]then
                local ok,value=pcall(function()
                    return hd2.weapon(d.weapon):attack(d.attack):projectile():terminal_action(d.phase):explosion()
                end)
                if ok then
                    seen[d.explosionType]=true
                    out[#out+1]={value=value,label=tostring(d.weapon),sub=util.humanize(d.phase)..' explosion '..d.explosionType}
                end
            end
        end
    end
    return out
end
local function bool_labels()return {{value=false,label='Off'},{value=true,label='On'}}end
-- Fire modes (a list of 'automatic' / 'single' / 'burst' ...) and rate-of-fire modes (three rpm slots, 0 = unused).
local function mode_row(object,common,f)
    local modes={}
    for _,m in ipairs(f.allowedModes or{})do modes[#modes+1]=m end
    if#modes==0 then return nil end
    common.kind,common.modes,common.max_modes='modes',modes,f.maxModes or#modes
    common.vanilla=util.copy(f.currentDefault)
    common.section='Fire Mode'
    return make_value_row(object,common)
end
local function rate_row(object,common,f)
    if type(f.currentDefault)~='table'or#f.currentDefault~=3 then return nil end
    common.kind='rates'
    common.vanilla=util.copy(f.currentDefault)
    common.min,common.max=f.min or 1,f.max or 3000
    common.slots=f.slotNames or{'x','y','z'}
    common.section='Fire Mode'
    local row=make_value_row(object,common)
    -- the weapon's own rate-of-fire facts (state, binding): filling an empty slot of a weapon without a rate selector
    -- binds the game's selector in the same write (M.rate_binding)
    local target=common.target
    row.rate_info=function()
        local ok,info=pcall(function()return target():fire_rate_modes()end)
        return ok and type(info)=='table'and info or nil
    end
    return row
end
local function static_options(labels)
    return function()
        local out={}
        for i,item in ipairs(labels)do out[i]={value=item.value,label=item.label}end
        return out
    end
end
-- The armory's presentation of a weapon (presentation only: menus read it when they build an item view):
-- the displayed armor penetration (one label) and the displayed traits (an ordered list of up to five), which share
-- the weapon's five label slots (the layer edits one of them at a time).
local presentation_names
local function presentation_labels()
    if presentation_names==nil then
        local ok,WP=pcall(require,'hd2runtime/domains/weapon_presentation')
        presentation_names=ok and type(WP)=='table'and WP or false
    end
    return presentation_names or{}
end
local function title_case(text)
    return(tostring(text):lower():gsub('(%a)([%w]*)',function(a,b)return a:upper()..b end))
end
local function presentation_row(object,common,f)
    local WP=presentation_labels()
    common.section='Armory'
    if f.type=='armor_penetration_label'then
        local labels={}
        for _,v in ipairs(f.allowedValues or{})do
            local name=(f.labels and f.labels[v])or(WP.penetration and WP.penetration[v])
            labels[#labels+1]={value=v,label=v=='none'and'None'or title_case(name or util.humanize(v))}
        end
        common.kind,common.vanilla,common.labels='choice',f.currentDefault,labels
        common.options=static_options(labels)
        return make_value_row(object,common)
    end
    if f.type=='trait_set'and type(f.currentDefault)=='table'then
        local traits={}
        for id,name in pairs(WP.traits or{})do
            if not f.traitValues or f.traitValues[id]then traits[#traits+1]={value=id,label=title_case(name)}end
        end
        table.sort(traits,function(a,b)return a.label..a.value<b.label..b.value end)
        -- two localisation entries can read the same (the game has two INCENDIARY labels): number the repeats
        for i=2,#traits do
            if traits[i].label==traits[i-1].label:gsub(' %(%d+%)$','')then
                traits[i].label=traits[i].label..' ('..(tonumber(traits[i-1].label:match('%((%d+)%)$'))or 1)+1 ..')'
            end
        end
        if#traits==0 then return nil end
        common.kind,common.vanilla='traits',util.copy(f.currentDefault)
        local row=make_value_row(object,common)
        row.traits,row.max_traits=traits,f.maxTraits or 5
        return row
    end
    return nil
end
-- A weapon HD2Runtime blocks (entry.ordinaryWritesBlocked: a DUPLICATE identity, two game records under one name, e.g.
-- the LAS-5 Scythe and LAS-7 Dagger; docs/player-weapon-authoring.md) publishes its stats read-only. They are shown as
-- locked rows (their values, this reason) instead of being left out.
local BLOCKED_REASON='read only for now: HD2Runtime cannot yet tell this weapon\'s two game records apart, so it blocks '
    ..'writes to it'
local function player_rows(hd2,object,entry)
    local rows={}
    local name=entry.name
    for _,f in ipairs(entry.fields or{})do
        -- a field locked only by the weapon's blocked identity (not one that is read-only in itself)
        local locked=f.editable==false and entry.ordinaryWritesBlocked==true and f.reason~=nil
            and f.reason==entry.blockReason
        -- (a reorder-only enum such as the default fire mode refuses its own value, so nothing can hold it: left out)
        local value_kind=f.type=='boolean'or f.type=='status_reference'
            or(f.type=='enum'and type(f.allowedValues)=='table'and f.writeKind~='reorder_native_mode_vector')
            or f.type=='projectile_reference'or f.type=='explosion_reference'
            or f.type=='fire_mode_set'or f.type=='fire_rate_set'
            or f.type=='trait_set'or f.type=='armor_penetration_label'
        if(f.editable or locked)and f.preferred and not f.deprecated and not f.derivedReadOnly
            and(numeric(f.type,f.currentDefault)or value_kind)then
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
            local common={id=id,label=f.displayName,unit=f.unit,field=field,target=target,shared=shared_ack(f),
                unverified=unverified(f),descriptor=f,section=section}
            if locked then common.editable,common.reason=false,BLOCKED_REASON end
            if numeric(f.type,f.currentDefault)then
                common.vanilla,common.min,common.max,common.type,common.storage=f.currentDefault,f.min,f.max,f.type,b.storage
                rows[#rows+1]=make_row(object,common)
            elseif f.type=='fire_mode_set'then
                rows[#rows+1]=mode_row(object,common,f)
            elseif f.type=='fire_rate_set'then
                rows[#rows+1]=rate_row(object,common,f)
            elseif f.type=='trait_set'or f.type=='armor_penetration_label'then
                rows[#rows+1]=presentation_row(object,common,f)
            elseif f.type=='boolean'then
                common.kind,common.vanilla,common.labels='choice',f.currentDefault==true,bool_labels()
                common.options=static_options(common.labels)
                rows[#rows+1]=make_value_row(object,common)
            elseif f.type=='status_reference'then
                local labels={}
                if f.allowNone then labels[1]={value='none',label='None'}end
                for _,v in ipairs(f.allowedValues or{})do labels[#labels+1]={value=v,label=util.humanize(v)}end
                common.kind,common.vanilla,common.labels='choice',f.currentDefault,labels
                common.options=static_options(labels)
                common.section=join(section,'Status')
                rows[#rows+1]=make_value_row(object,common)
            elseif f.type=='enum'then
                local names={}
                for label,v in pairs(f.enumValues or{})do names[v]=util.humanize(label)end
                -- a reordered mode vector can only start with a mode the weapon already has
                local native
                if type(f.nativeModeVector)=='table'then
                    native={}
                    for _,v in pairs(f.nativeModeVector)do if v~=0 then native[v]=true end end
                end
                local labels={}
                for _,v in ipairs(f.allowedValues)do
                    if type(v)~='table'and(not native or native[v])then labels[#labels+1]={value=v,label=names[v]or tostring(v)}end
                end
                common.kind,common.vanilla,common.labels='choice',f.currentDefault,labels
                common.options=static_options(labels)
                rows[#rows+1]=make_value_row(object,common)
            elseif f.type=='projectile_reference'then
                local role=f.referenceRole or b.branch or'primary'
                if builds(function()return hd2.weapon(name):attack(role):projectile()end)then
                    common.kind='reference'
                    common.target=function()return hd2.weapon(name):attack(role)end
                    common.field='attack.projectile'
                    common.expect=function()return hd2.weapon(name):attack(role):projectile()end
                    common.vanilla=common.expect()
                    common.label='Projectile'
                    common.section=join('Projectile',role_label(role),'Swap')
                    common.options=function(row)return projectile_options(hd2,row)end
                    rows[#rows+1]=make_value_row(object,common)
                    rows[#rows].swap={kind='projectile',role=role}
                end
            elseif f.type=='explosion_reference'and b.branch and b.phase then
                local role,phase=b.branch,b.phase
                local terminal=function()return hd2.weapon(name):attack(role):projectile():terminal_action(phase)end
                if builds(terminal)then
                    local d=type(f.currentDefault)=='table'and f.currentDefault or{}
                    local none=(d.explosionType or 0)==0
                    common.kind='reference'
                    common.target=terminal
                    common.field='terminal.explosion'
                    common.expect=function()local t=terminal();if none then return t:no_explosion()end return t:explosion()end
                    local ok,vanilla=pcall(common.expect)
                    if ok then
                        common.vanilla=vanilla
                        common.label=util.humanize(phase)..' payload'
                        common.section=join('Explosion',role_label(role),util.humanize(phase))
                        common.options=function(row)return explosion_options(hd2,row)end
                        rows[#rows+1]=make_value_row(object,common)
                        rows[#rows].swap={kind='terminal',role=role,phase=phase}
                    end
                end
            end
        end
    end
    -- the catalogue weapon each row writes ('AR/GL-21 One-Two / underbarrel' for a sub-weapon): ModBuilder's identity
    for _,r in ipairs(rows)do r.weapon_name=name end
    return rows
end

------------------------------------------------------------------------------------------- support weapons --
local function support_rows(hd2,object,entry)
    local rows={}
    local name=entry.name
    for _,f in ipairs(entry.fields or{})do
        local value_kind=f.type=='boolean'or f.type=='status_reference'or f.type=='fire_mode_set'or f.type=='fire_rate_set'
            or f.type=='trait_set'or f.type=='armor_penetration_label'
        if f.editable and not f.derivedReadOnly and not f.deprecated and(f.preferred~=false)
            and(numeric(f.type,f.currentDefault)or value_kind)then
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
            local common={id=id..(role and('@'..role)or''),label=f.displayName,unit=f.unit,field=field,target=target,
                shared=shared_ack(f),unverified=unverified(f),descriptor=f,section=section}
            if numeric(f.type,f.currentDefault)then
                common.vanilla,common.min,common.max,common.type=f.currentDefault,f.min,f.max,f.type
                common.storage=(f.backing or{}).storage
                rows[#rows+1]=make_row(object,common)
            elseif f.type=='fire_mode_set'then
                rows[#rows+1]=mode_row(object,common,f)
            elseif f.type=='fire_rate_set'then
                rows[#rows+1]=rate_row(object,common,f)
            elseif f.type=='trait_set'or f.type=='armor_penetration_label'then
                rows[#rows+1]=presentation_row(object,common,f)
            elseif f.type=='boolean'then
                common.kind,common.vanilla,common.labels='choice',f.currentDefault==true,bool_labels()
                common.options=static_options(common.labels)
                rows[#rows+1]=make_value_row(object,common)
            else
                local labels={}
                if f.allowNone then labels[1]={value='none',label='None'}end
                for _,v in ipairs(f.allowedValues or{})do labels[#labels+1]={value=v,label=util.humanize(v)}end
                common.kind,common.vanilla,common.labels='choice',f.currentDefault,labels
                common.options=static_options(labels)
                common.section=join(section,'Status')
                rows[#rows+1]=make_value_row(object,common)
            end
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
        if f.editable and f.type=='calldown_code'and type(f.currentDefault)=='table'then
            local directions={}
            for i,d in ipairs(f.directions or{'up','right','down','left'})do directions[i]=d end
            rows[#rows+1]=make_value_row(object,{id=f.instanceKey or'stratagem.calldown_code',kind='code',
                label=f.displayName or'Calldown code',field=f.semanticFieldId,target=stratagem_target(hd2,name,t),
                vanilla=util.copy(f.currentDefault),descriptor=f,section='Call-in',directions=directions,
                min_length=f.minLength or 1,max_length=f.maxLength or 9})
        elseif f.editable and f.type=='stratagem_uses'then
            local allowed={}
            for _,tr in ipairs(f.transitions or{})do allowed[tr]=true end
            local vanilla=f.currentDefault
            local unlimited=vanilla=='unlimited'or allowed.finite_to_unlimited==true
            rows[#rows+1]=make_value_row(object,{id=f.instanceKey or'stratagem.max_uses',kind='uses',
                label=f.displayName or'Mission uses',field=f.semanticFieldId,target=stratagem_target(hd2,name,t),
                vanilla=vanilla,descriptor=f,section='Call-in',min=f.min or 1,max=f.max or 100,unlimited=unlimited,
                unverified=unverified(f),
                labels={{value='unlimited',label='Unlimited'}}})
        elseif f.editable and f.type=='enum'and type(f.allowedValues)=='table'then
            local labels={}
            for _,v in ipairs(f.allowedValues)do
                if type(v)=='table'then labels[#labels+1]={value=v.value,label=util.humanize(v.name or tostring(v.value))}
                else labels[#labels+1]={value=v,label=tostring(v)}end
            end
            local target=stratagem_target(hd2,name,t)
            if target then
                rows[#rows+1]=make_value_row(object,{id=f.instanceKey or(f.semanticFieldId..'@'..tostring(t.path)),
                    kind='choice',label=f.displayName,field=f.semanticFieldId,target=target,vanilla=f.currentDefault,
                    descriptor=f,section=PATH_LABELS[t.path]or util.humanize(t.path or''),labels=labels,
                    options=static_options(labels),shared=shared_ack(f),unverified=unverified(f)})
            end
        elseif f.editable and numeric(f.type,f.currentDefault)then
            local target=stratagem_target(hd2,name,t)
            if target then
                local section=PATH_LABELS[t.path]
                local group
                if t.path=='damage_zone'then section=util.humanize(t.zone or'');group='Damage Zones'
                elseif t.path=='attack'then
                    section=join(t.weapon=='mine'and'Mine'or(t.weapon and'Mounted Weapon')or'Attack',
                        util.humanize(t.attack or''),DOMAIN_LABELS[domain_of(f.semanticFieldId)])
                end
                rows[#rows+1]=make_row(object,{id=f.instanceKey or(f.semanticFieldId..'@'..tostring(t.path)),
                    label=f.displayName,unit=f.unit,vanilla=f.currentDefault,min=f.min,max=f.max,type=f.type,
                    storage=(f.backing or{}).storage,field=f.semanticFieldId,target=target,shared=shared_ack(f),
                    unverified=unverified(f),descriptor=f,section=section or util.humanize(t.path or''),group=group})
            end
        end
    end
    return rows
end

----------------------------------------------------------------------------------------- vehicles, backpacks --
-- A mounted weapon's readable name: its display name, made unique with a short id when several share it.
local mount_names
local function mounted_weapon_name(id)
    if not mount_names then
        mount_names={}
        local E=load('entity_authoring')
        local count={}
        for _,w in pairs(E and E.mountedWeapons or{})do
            local n=w.displayName or'?'
            count[n]=(count[n]or 0)+1
        end
        for key,w in pairs(E and E.mountedWeapons or{})do
            local n=util.humanize(w.displayName or key):gsub('^%l',string.upper)
            if(count[w.displayName or'?']or 0)>1 then n=n..' #'..(tostring(key):match('/(%x%x%x%x)%x*$')or'?')end
            mount_names[key]=n
        end
    end
    return mount_names[id]or tostring(id):match('mounted%-weapon/v1/([^/]+)')or tostring(id)
end
M.mounted_weapon_name=mounted_weapon_name
-- The catalogued vehicle (or drone) weapon that IS a mounted weapon (same attack resource), or nil: its key and entry.
function M.mounted_weapon_entry(id)
    local E,V=load('entity_authoring'),load('vehicle_weapon_authoring')
    local w=E and E.mountedWeapons and E.mountedWeapons[id]
    if not(w and V)then return nil end
    for _,key in ipairs(util.sorted_keys(V.weapons or{}))do
        if V.weapons[key].attackResource==w.resource then return key,V.weapons[key]end
    end
    return nil
end
local function vehicle_rows(hd2,object,entry)
    local rows={}
    local name=entry.name
    -- mounts: which weapon each slot holds (a same-family swap, as ModBuilder offers it)
    for _,f in ipairs(entry.fields or{})do
        local t=f.target or{}
        if f.editable and t.path=='mount'and f.type=='mounted_weapon_reference'and type(f.currentDefault)=='string'then
            local slot=t.mount
            local info=entry.mounts and entry.mounts[slot]or{}
            local labels={{value=f.currentDefault,label=mounted_weapon_name(f.currentDefault)}}
            for _,id in ipairs(f.allowedValues or{})do labels[#labels+1]={value=id,label=mounted_weapon_name(id)}end
            local vanilla=f.currentDefault
            rows[#rows+1]=make_value_row(object,{id=f.instanceKey or('mount.weapon@'..tostring(slot)),kind='reference',
                label=util.humanize(info.role or slot),field=f.semanticFieldId,descriptor=f,section='Mounted Weapons',
                target=function()return hd2.vehicle(name):mount(slot)end,expect=function()return vanilla end,
                vanilla=vanilla,labels=labels,unverified_reference=true,
                options=function()
                    local out={}
                    for i,item in ipairs(labels)do
                        local key=M.mounted_weapon_entry(item.value)
                        out[#out+1]={value=item.value,label=item.label..(i==1 and' (vanilla)'or''),
                            sub=key and('stats editable: '..key)or'stats not editable'}
                    end
                    return out
                end})
            rows[#rows].mount_slot=slot
        end
    end
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
                section=util.humanize(zone)
            end
            rows[#rows+1]=make_row(object,{id=f.instanceKey or(f.semanticFieldId..'@'..tostring(t.zone)),
                label=f.displayName,unit=f.unit,vanilla=f.currentDefault,min=f.min,max=f.max,type=f.type,
                storage=(f.backing or{}).storage,field=f.semanticFieldId,target=target,shared=shared_ack(f),
                unverified=unverified(f),descriptor=f,section=section,
                group=t.path=='damage_zone'and'Damage Zones'or nil})
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
                section=join(linked and util.humanize(linked)or nil,util.humanize(zone))
            end
            if target then
                rows[#rows+1]=make_row(object,{id=f.instanceKey or(f.semanticFieldId..'@'..tostring(t.path)),
                    label=f.displayName,unit=f.unit,vanilla=f.currentDefault,min=f.min,max=f.max,type=f.type,
                    storage=(f.backing or{}).storage,field=f.semanticFieldId,target=target,shared=shared_ack(f),
                    unverified=unverified(f),descriptor=f,section=section,
                    group=t.path=='damage_zone'and'Damage Zones'or nil})
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
    -- ModBuilder's identity (entityChanges: resource vehicle_weapon, entity = the weapon's catalogue name)
    for _,r in ipairs(rows)do r.mb_resource,r.mb_entity,r.mb_where='vehicle_weapon',entry.name,''end
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
-- An attachment's fields (shared by every weapon that can mount it): a magazine's capacity and ammo, and the stat
-- modifiers of muzzles, optics and underbarrels (attachment.modifier.*: multipliers, ergonomics an addition).
local MODIFIER_LABELS={sway='Sway multiplier',recoil_horizontal='Horizontal recoil multiplier',
    recoil_vertical='Vertical recoil multiplier',climb_horizontal='Horizontal climb multiplier',
    climb_vertical='Vertical climb multiplier',spread_horizontal='Horizontal spread multiplier',
    spread_vertical='Vertical spread multiplier'}
local function attachment_rows(hd2,object,entry)
    local rows={}
    local id=entry.semanticId
    for _,field_id in ipairs(util.sorted_keys(entry.fields or{}))do
        local f=entry.fields[field_id]
        if type(f.currentDefault)=='number'and f.editable~=false then
            local modifier=field_id:match('^attachment%.modifier%.(.+)$')
            local label=f.displayName or MODIFIER_LABELS[modifier or'']
                or(field_id=='attachment.ergonomics_modifier'and'Ergonomics')or util.humanize(field_id)
            rows[#rows+1]=make_row(object,{id=field_id,label=label,vanilla=f.currentDefault,min=f.min,max=f.max,
                type=INTEGER_STORAGE[f.storage or'']and'integer'or'number',storage=f.storage,field=field_id,
                target=function()return hd2.weapon_attachment(id)end,shared=true,unverified=true,descriptor=f,
                section=util.humanize(entry.slot or'magazine')})
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
            local target,section,group
            if f.path=='entity'then target=root;section='Health & Armor'
            elseif f.path=='damage_zone'then
                local zone=f.zone
                local z=zones[zone]or{}
                target=function()return root():zone(zone)end
                section=z.wikiZone or util.humanize(z.name or zone)
                group='Damage Zones'
            elseif f.path=='attack'then
                local attack=f.attack
                local base=tostring(attack):match('^(slot_%d+)')
                local a=attacks[attack]or attacks[base]or{}
                target=function()return root():attack(attack)end
                section=join(util.humanize(attack),a.role and util.humanize(a.role)or nil)
                group='Attacks'
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
                    unverified=ack=='allow_unverified_effect',descriptor=f,section=section,group=group,
                    disabled_value=s.disabledValue or f.disabledValue})
                rows[#rows].mb_resource=structure and'structure'or'enemy'
                rows[#rows].mb_entity=entry.semanticId
                rows[#rows].mb_where=f.path..'|'..tostring(f.zone or f.attack or'')
            end
        end
    end
    return rows
end

------------------------------------------------------------------------------------------------ families --
-- Each category: list = function(cat) -> {{key, name, subtitle, build = function(object) -> rows}}.
local CATEGORY={}
local function sorted_objects(list)
    table.sort(list,function(a,b)return util.natural_less(a.name,b.name)end)
    return list
end
-- Rows of one part of a composite object (a stratagem with its weapon, backpack, drone, vehicle weapons and pod):
-- the part's rows keep stable keys under the composite (<composite key>|<prefix>|<field>) and belong to the
-- composite. decorate(row) may rename the row's section or put it in a collapsible group.
local function part_rows(object,prefix,build,decorate)
    local proxy=setmetatable({key=object.key..'|'..prefix},{__index=object})
    local ok,rows=pcall(build,proxy)
    if not ok or type(rows)~='table'then return {}end
    for _,row in ipairs(rows)do
        row.object=object
        if decorate then decorate(row)end
    end
    return rows
end
local function append(into,rows)for _,r in ipairs(rows)do into[#into+1]=r end return into end

-- A player weapon's attachments, each slot a collapsed group: its magazines (attachment_authoring weapons[name]) and
-- its muzzles, optics and underbarrels (slots[name][slot]). {{id, entry, group}}, sorted by name in a slot.
local ATTACHMENT_GROUPS={{key='magazine',label='Magazines'},{key='muzzle',label='Muzzles'},{key='optics',label='Optics'},
    {key='underbarrel',label='Underbarrels'}}
local function weapon_attachments(name)
    local A=load('attachment_authoring')
    if not A or type(A.attachments)~='table'then return {}end
    local by_slot={}
    local function add(slot,list)
        if type(list)~='table'then return end
        -- {default, options = {{attachment, name}}} (current) or a plain list of ids / {semanticId} (older domains)
        local items=list.options or list
        for _,item in pairs(items)do
            local id=type(item)=='table'and(item.attachment or item.semanticId or item.id)or item
            local entry=type(id)=='string'and A.attachments[id]
            if entry then
                by_slot[slot]=by_slot[slot]or{}
                by_slot[slot][id]=entry
            end
        end
        if type(list.default)=='string'and A.attachments[list.default]then
            by_slot[slot]=by_slot[slot]or{}
            by_slot[slot][list.default]=A.attachments[list.default]
        end
    end
    add('magazine',A.weapons and A.weapons[name])
    for slot,list in pairs(A.slots and A.slots[name]or{})do add(slot,list)end
    local out={}
    for _,g in ipairs(ATTACHMENT_GROUPS)do
        local list={}
        for id,entry in pairs(by_slot[g.key]or{})do list[#list+1]={id=id,entry=entry,group=g.label}end
        table.sort(list,function(a,b)return util.natural_less(a.entry.name or a.id,b.entry.name or b.id)end)
        for _,item in ipairs(list)do out[#out+1]=item end
    end
    return out
end

-- Hellpod contents of a stratagem's pod rack (pod_payload_authoring): spawn count and the four payload slots.
local function pickup_options(hd2,row)
    local P=load('pod_payload_authoring')
    local out={{value='empty',label='Empty',sub='nothing in this slot'}}
    local ids=util.sorted_keys(P and P.pickups or{},function(a,b)
        return util.natural_less(P.pickups[a].name or a,P.pickups[b].name or b)end)
    for _,id in ipairs(ids)do
        local p=P.pickups[id]
        local ok,value=pcall(hd2.pickup,id)
        if ok then out[#out+1]={value=value,label=tostring(p.name or id),sub=util.humanize(p.category or'')}end
    end
    return out
end
local function pod_rows(hd2,object,rack)
    local rows={}
    local name=rack.name
    local target=function()return hd2.pod_rack(name)end
    local shared=rack.shared==true or(type(rack.consumers)=='table'and#rack.consumers>1)
    local locked=rack.writable==false
    local reason=locked and(rack.reason or rack.readOnlyReason or'this pod is read-only')or nil
    if type(rack.spawnCount)=='number'then
        rows[#rows+1]=make_row(object,{id='payload.spawn_count',label='Items spawned',vanilla=rack.spawnCount,min=1,max=4,
            type='integer',field='payload.spawn_count',target=target,unverified=true,section='Hellpod',
            unit='items',shared=shared,editable=not locked,reason=reason})
    end
    for i=1,4 do
        local slot=rack.slots and(rack.slots[tostring(i)]or rack.slots[i])
        if type(slot)=='table'then
            local index=i
            local current=slot.current
            local expect=function()
                if current then return hd2.pickup(current)end
                return 'empty'
            end
            local ok,vanilla=pcall(expect)
            if ok then
                rows[#rows+1]=make_value_row(object,{id='payload.slot_'..i,kind='reference',
                    label='Slot '..i..(slot.active==false and' (spare)'or''),field='payload.entity',
                    target=function()return hd2.pod_rack(name):slot(index)end,expect=expect,vanilla=vanilla,
                    section='Hellpod',options=function(row)return pickup_options(hd2,row)end,shared=shared,
                    editable=not locked and slot.writable~=false,reason=reason or slot.reason})
                if rack.semanticId then rows[#rows].mb_key='pod_rack|'..rack.semanticId..'|'..i end
            end
        end
    end
    return rows
end
local function rack_for(stratagem)
    local P=load('pod_payload_authoring')
    if not P then return nil end
    local rack=P.byStratagem and P.byStratagem[stratagem]
    if type(rack)=='string'then rack=P.racks and P.racks[rack]end
    if type(rack)=='table'and rack.name==nil then rack=P.racks and P.racks[stratagem..' pod']end
    return type(rack)=='table'and rack or nil
end

local function player_category(slot)
    return function(cat)
        local W,why=load('player_weapon_authoring')
        if not W then return nil,why end
        local list={}
        for name,entry in pairs(W.weapons or{})do
            if entry.slot==slot then
                list[#list+1]={key='pw|'..name,name=name,subtitle=entry.category,
                    detail=entry.ordinaryWritesBlocked and'stats read only (HD2Runtime blocks this weapon for now)'or nil,
                    build=function(object)
                        local rows=player_rows(cat.hd2,object,entry)
                        -- its underbarrel weapon (One-Two launcher, Arbitrator shotgun, Stoker flamer): a separate weapon
                        -- entity with its own rounds, fire rate and spread, written through hd2.weapon('<host> / underbarrel')
                        for _,sub in ipairs(entry.subweapons or{})do
                            local sub_entry=W.weapons[sub.name]
                            if sub_entry then
                                append(rows,part_rows(object,'ub:'..sub.name,function(proxy)
                                    return player_rows(cat.hd2,proxy,sub_entry)
                                end,function(row)row.group='Underbarrel Weapon'end))
                            end
                        end
                        for _,m in ipairs(weapon_attachments(name))do
                            local label=util.plain((m.entry.name or m.id):gsub('%s+',' '),60)
                            append(rows,part_rows(object,'mag:'..m.id,function(proxy)
                                return attachment_rows(cat.hd2,proxy,m.entry)
                            end,function(row)row.group=m.group;row.section=label end))
                        end
                        return rows
                    end}
            end
        end
        return sorted_objects(list)
    end
end
CATEGORY.primary=player_category('primary')
CATEGORY.secondary=player_category('secondary')
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

-- Support weapons: the call-in, the weapon, the backpack it comes with and its hellpod, as one stratagem.
function CATEGORY.support_weapons(cat)
    local S,why=load('support_weapon_authoring')
    if not S then return nil,why end
    local ST=load('stratagem_authoring')or{stratagems={}}
    local E=load('entity_authoring')or{backpacks={}}
    local list={}
    for name,weapon in pairs(S.weapons or{})do
        local stratagem=ST.stratagems and ST.stratagems[name]
        local backpack=E.backpacks and E.backpacks[name..' Backpack']
        local rack=rack_for(name)
        local subtitle=stratagem and'Support weapon'or'Support weapon (no call-in)'
        -- comes with a backpack: an authored one, or a backpack in its hellpod
        local bundled=backpack~=nil
        if rack and not bundled then
            local P=load('pod_payload_authoring')
            for _,slot in pairs(rack.slots or{})do
                local pickup=type(slot)=='table'and slot.active~=false and P and P.pickups and P.pickups[slot.current]
                if pickup and pickup.category=='backpack'then bundled=true end
            end
        end
        if bundled then subtitle='Support weapon + backpack'end
        list[#list+1]={key='sp|'..name,name=name,subtitle=subtitle,stratagem=stratagem and name or nil,
            aliases={'st|'..name,'sw|'..name,backpack and('bp|'..name..' Backpack')or nil},
            build=function(object)
                local rows={}
                if stratagem then append(rows,part_rows(object,'st',function(p)return stratagem_rows(cat.hd2,p,stratagem)end))end
                append(rows,part_rows(object,'sw',function(p)return support_rows(cat.hd2,p,weapon)end))
                if backpack then
                    append(rows,part_rows(object,'bp',function(p)return backpack_rows(cat.hd2,p,backpack)end,
                        function(row)if not row.group then row.section=join('Backpack',row.section)end end))
                end
                if rack then append(rows,part_rows(object,'pod',function(p)return pod_rows(cat.hd2,p,rack)end))end
                return rows
            end}
    end
    return sorted_objects(list)
end
-- Support backpacks: backpack stratagems with the backpack, its drone weapon and its hellpod.
function CATEGORY.support_backpacks(cat)
    local ST,why=load('stratagem_authoring')
    if not ST then return nil,why end
    local E=load('entity_authoring')or{backpacks={}}
    local V=load('vehicle_weapon_authoring')or{weapons={}}
    local list={}
    for name,stratagem in pairs(ST.stratagems or{})do
        if stratagem.family=='backpack'then
            local backpack=E.backpacks and E.backpacks[name]
            local drones={}
            for key,w in pairs(V.weapons or{})do
                if w.vehicle==name then drones[#drones+1]={key=key,entry=w}end
            end
            table.sort(drones,function(a,b)return a.key<b.key end)
            local rack=rack_for(name)
            local aliases={'st|'..name,'bp|'..name}
            for _,d in ipairs(drones)do aliases[#aliases+1]='vw|'..d.key end
            list[#list+1]={key='sb|'..name,name=name,subtitle=#drones>0 and'Backpack + drone'or'Backpack',
                stratagem=name,aliases=aliases,
                build=function(object)
                    local rows=part_rows(object,'st',function(p)return stratagem_rows(cat.hd2,p,stratagem)end)
                    if backpack then append(rows,part_rows(object,'bp',function(p)return backpack_rows(cat.hd2,p,backpack)end))end
                    for _,d in ipairs(drones)do
                        append(rows,part_rows(object,'vw:'..(d.entry.mount or'gun'),function(p)
                            return vehicle_weapon_rows(cat.hd2,p,d.entry)end,
                            function(row)row.group='Drone Weapon';row.vw_key=d.key end))
                    end
                    if rack then append(rows,part_rows(object,'pod',function(p)return pod_rows(cat.hd2,p,rack)end))end
                    return rows
                end}
        end
    end
    return sorted_objects(list)
end
-- Vehicles: the call-in, the vehicle, its damage zones and every mounted weapon (also vehicles without a call-in).
function CATEGORY.vehicles(cat)
    local E,why=load('entity_authoring')
    if not E then return nil,why end
    local ST=load('stratagem_authoring')or{stratagems={}}
    local V=load('vehicle_weapon_authoring')or{weapons={}}
    local list={}
    for name,vehicle in pairs(E.vehicles or{})do
        local stratagem=ST.stratagems and ST.stratagems[name]
        local mounts={}
        for key,w in pairs(V.weapons or{})do
            if w.vehicle==name and w.carrier~='backpack_drone'then mounts[#mounts+1]={key=key,entry=w}end
        end
        table.sort(mounts,function(a,b)return a.key<b.key end)
        local aliases={'vh|'..name,stratagem and('st|'..name)or nil}
        for _,m in ipairs(mounts)do aliases[#aliases+1]='vw|'..m.key end
        list[#list+1]={key='ve|'..name,name=name,subtitle=stratagem and'Vehicle'or'Vehicle (no call-in)',
            stratagem=stratagem and name or nil,aliases=aliases,
            build=function(object)
                local rows={}
                if stratagem then append(rows,part_rows(object,'st',function(p)return stratagem_rows(cat.hd2,p,stratagem)end))end
                append(rows,part_rows(object,'vh',function(p)return vehicle_rows(cat.hd2,p,vehicle)end))
                for _,m in ipairs(mounts)do
                    local label='Weapon · '..util.humanize(m.entry.mount or m.key)
                    local slot=m.entry.slot and('slot_'..m.entry.slot)or nil
                    append(rows,part_rows(object,'vw:'..(m.entry.mount or m.key),function(p)
                        return vehicle_weapon_rows(cat.hd2,p,m.entry)end,function(row)
                            row.group=label;row.vw_key=m.key;row.home_slot=slot end))
                end
                return rows
            end}
    end
    return sorted_objects(list)
end
-- The Resupply mission stratagem and its pod.
function CATEGORY.resupply(cat)
    local ST,why=load('stratagem_authoring')
    if not ST then return nil,why end
    local list={}
    for name,stratagem in pairs(ST.stratagems or{})do
        if stratagem.family=='mission'then
            local rack=rack_for(name)
            list[#list+1]={key='rs|'..name,name=name,subtitle='Mission stratagem',stratagem=name,aliases={'st|'..name},
                build=function(object)
                    local rows=part_rows(object,'st',function(p)return stratagem_rows(cat.hd2,p,stratagem)end)
                    if rack then append(rows,part_rows(object,'pod',function(p)return pod_rows(cat.hd2,p,rack)end))end
                    return rows
                end}
        end
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
------------------------------------------------------------------------------------------------ helldiver --
-- The Helldiver type (hd2.helldiver(); HD2Runtime docs/helldiver-fields.md): movement speeds, stamina, the
-- explosion share and the six body zones. Type records every Helldiver this machine simulates reads: each write needs
-- allow_shared and allow_unverified_effect. An enum field takes a name; its labels are listed by native value.
local HELLDIVER_LABELS={direction_factor='Strafe and backpedal factor',aim='Aiming',sprint_exhausted='Sprint (exhausted)',
    crouch_aim='Crouched, aiming',crouch_walk='Crouched, walking',crouch_jog='Crouched, jogging',
    crouch_sprint='Crouched, sprinting',prone='Prone',swim='Swimming',sprint_duration='Sprint duration',
    recover_time_standing='Recovery standing',recover_time_crouching='Recovery crouching',
    recover_time_prone='Recovery prone',recover_delay='Recovery delay',cost_jump='Cost of a jump',
    cost_dodge='Cost of a dive',cost_climb='Cost of a climb',cost_slide='Cost of a slide',
    explosive_damage_percentage='Explosion damage share',damage_multiplier='Damage multiplier',
    damage_multiplier_dps='Damage over time multiplier',durable_resistance='Durable damage share',
    affects_main_health='Main health share',health='Health'}
local ZONE_LABELS={head='Head',body='Body',arm_left='Left arm',arm_right='Right arm',leg_left='Left leg',
    leg_right='Right leg'}
local function enum_labels(f)
    local out={}
    for name,native in pairs(type(f.allowedValues)=='table'and f.allowedValues or{})do
        if type(name)=='number'then name,native=native,name-1 end
        out[#out+1]={value=name,label=util.humanize(name),native=native}
    end
    table.sort(out,function(a,b)return a.native<b.native end)
    return out
end
local function helldiver_field_row(object,f,target,section,group,note,zone)
    local name=f.semanticFieldId:match('([^%.]+)$')
    local common={id=(zone and(zone..':')or'')..f.semanticFieldId,label=HELLDIVER_LABELS[name]or util.humanize(name),
        field=f.semanticFieldId,target=target,shared=true,unverified=true,descriptor=f,section=section,group=group,
        unit=f.unit,note=note}
    if f.type=='enum'then
        common.kind,common.vanilla='choice',f.currentDefault
        common.labels=enum_labels(f)
        common.options=static_options(common.labels)
        return make_value_row(object,common)
    end
    common.vanilla,common.min,common.max,common.type,common.storage=f.currentDefault,f.min,f.max,f.type,
        (f.backing or{}).storage
    return make_row(object,common)
end
local function helldiver_rows(hd2,object)
    local H=load('helldiver_writes')
    if not H or type(H.fields)~='function'then error('this HD2Runtime has no Helldiver fields (HD2Runtime 0.30.0)',0)end
    local rows={}
    local entity=function()return hd2.helldiver()end
    local ship='Not on the ship: its Helldiver carries its own copy. Applies on the next deploy.'
    for _,f in ipairs(H.fields('entity'))do
        local id=f.semanticFieldId
        local section=id:find('^helldiver%.speed%.')and'Speed'or id:find('^helldiver%.stamina%.')and'Stamina'
            or'Damage'
        rows[#rows+1]=helldiver_field_row(object,f,entity,section,nil,section=='Damage'and'Live, every Helldiver'or ship)
    end
    for _,zone in ipairs(H.ZONES or{})do
        local zid=zone
        local target=function()return hd2.helldiver():zone(zid)end
        for _,f in ipairs(H.fields('damage_zone',zid))do
            local note=f.semanticFieldId=='zone.health'and'Applies to Helldivers spawned after the change'
                or'Live, every Helldiver'
            rows[#rows+1]=helldiver_field_row(object,f,target,ZONE_LABELS[zid]or util.humanize(zid),'Damage Zones',note,zid)
        end
    end
    return rows
end

-- Armor perks: the local player's own armor passive and a second passive (hd2.player_passives, solo only). Not an
-- ensure: the layer's perk controller holds one hd2.player_passives.set handle for both rows (editor/layer.lua).
local function passive_rows(hd2,object)
    local P=hd2.passives
    if type(P)~='table'or type(P.list)~='function'or type(hd2.player_passives)~='table'then
        error('this HD2Runtime has no armor passives (HD2Runtime 0.30.0)',0)
    end
    local armor={{value='kit',label="The armor's own"}}
    local second={{value='none',label='None'}}
    for _,p in ipairs(P.list())do
        local name=title_case(p.name or('Passive '..tostring(p.id)))
        armor[#armor+1]={value=p.id,label=name}
        local slot_only=type(p.package_info)=='table'and#(p.package_info.armor_slot_only or{})>0
        if p.id~=0 and not slot_only then second[#second+1]={value=p.id,label=name}end
    end
    local why='armor perks are held by the editor in this session (the Runtime keeps one perk override per game, solo only), not exported as a mod'
    local function row(id,label,labels,vanilla,note)
        return make_value_row(object,{id=id,kind='choice',label=label,field='player_passives.'..id,vanilla=vanilla,
            labels=labels,options=static_options(labels),section='Armor perks',unverified=true,controller='passives',
            note=note,export_reason=why,target=function()return hd2.player_passives end})
    end
    return {row('armor','Armor passive',armor,'kit','Your own armor, solo only; follows armor changes'),
        row('second','Second passive',second,'none','Added to the armor passive (no stacking of the same bonus)')}
end
function CATEGORY.helldiver(cat)
    if not load('helldiver_writes')and type(cat.real_hd2.passives)~='table'then
        return nil,'this HD2Runtime has no Helldiver fields (HD2Runtime 0.30.0)'
    end
    local list={}
    if load('helldiver_writes')then
        list[#list+1]={key='hd|Helldiver',name='Helldiver',subtitle='Every Helldiver',
            build=function(object)return helldiver_rows(cat.hd2,object)end}
    end
    if type(cat.real_hd2.passives)=='table'and type(cat.real_hd2.player_passives)=='table'then
        list[#list+1]={key='hd|Armor perks',name='Armor perks',subtitle='Your Helldiver',
            build=function(object)return passive_rows(cat.real_hd2,object)end}
    end
    return list
end

-- Armor (hd2.armor_stats; HD2Runtime docs/armor-stats.md): each kit's piece weights, the per-weight class
-- tables and the armor damage curve. Kits are named by id (several share a name).
local WEIGHT_LABELS={{value='light',label='Light'},{value='medium',label='Medium'},{value='heavy',label='Heavy'}}
local SLOT_LABELS={helmet='Helmet',cape='Cape',torso='Torso',hips='Hips',left_leg='Left leg',right_leg='Right leg',
    left_arm='Left arm',right_arm='Right arm',left_shoulder='Left shoulder',right_shoulder='Right shoulder'}
local CLASS_LABELS={rating='Armor value',speed='Speed factor',stamina='Stamina factor'}
local function armor_note(f)
    return f.lifecycle and('Applies: '..tostring(f.lifecycle))or nil
end
local function kit_rows(hd2,object,kit)
    local W=load('armor_stats_writes')
    local rows={}
    local id=kit.id
    for _,f in ipairs(W.kit_fields(kit))do
        rows[#rows+1]=make_value_row(object,{id=f.semanticFieldId,kind='choice',label=SLOT_LABELS[f.slot]or util.humanize(f.slot),
            field=f.semanticFieldId,vanilla=f.currentDefault,labels=WEIGHT_LABELS,options=static_options(WEIGHT_LABELS),
            target=function()return hd2.armor_stats.kit(id)end,shared=true,unverified=true,descriptor=f,
            section='Piece weights',note=armor_note(f)})
    end
    return rows
end
-- The armor class tables and the damage curve are in game.dll's own image (HD2Runtime docs/armor-stats.md, reviewed
-- executable data). A player reported GameGuard closing the game after writing them (docs/runtime-requests.md R10):
-- those rows carry risk = 'gameguard' and say so.
M.GAMEGUARD_RISK='Writes game.dll\'s own data: GameGuard was reported to close the game after these edits.'
local function number_rows(object,fields,target,section,label_of)
    local rows={}
    for _,f in ipairs(fields)do
        rows[#rows+1]=make_row(object,{id=f.semanticFieldId,label=label_of(f),vanilla=f.currentDefault,min=f.min,
            max=f.max,type='number',storage=(f.backing or{}).storage,field=f.semanticFieldId,target=target,shared=true,
            unverified=true,descriptor=f,section=section,note=armor_note(f)})
        rows[#rows].risk='gameguard'
    end
    return rows
end
function CATEGORY.armor(cat)
    local D,why=load('armor_stats')
    local W=load('armor_stats_writes')
    if not D or not W or type(D.kits)~='table'then return nil,why or'this HD2Runtime has no armor stats (HD2Runtime 0.30.0)'end
    local hd2=cat.hd2
    local list={}
    list[1]={key='ar|classes',name='Armor classes',subtitle='Shared tables',detail='may trigger GameGuard (game.dll data)',
        build=function(object)
            local rows={}
            for index,name in ipairs(D.classes or{})do
                local class=name
                append(rows,number_rows(object,W.class_fields(index-1),function()return hd2.armor_stats.class(class)end,
                    util.humanize(name),function(f)
                        return CLASS_LABELS[f.semanticFieldId:match('([^%.]+)$')]or util.humanize(f.semanticFieldId)end))
            end
            return rows
        end}
    list[2]={key='ar|damage curve',name='Armor damage curve',subtitle='Shared tables',
        detail='may trigger GameGuard (game.dll data)',
        build=function(object)
            return number_rows(object,W.curve_fields(),function()return hd2.armor_stats.damage_curve()end,
                'Damage taken at each armor value',function(f)return 'At armor value '..tostring(f.armorValue)end)
        end}
    local passives=type(D.passives)=='table'and D.passives or{}
    local seen={}
    for _,kit in ipairs(D.kits)do seen[kit.name or'']=(seen[kit.name or'']or 0)+1 end
    local kits={}
    for _,kit in ipairs(D.kits)do
        local entry=kit
        local name=kit.name or('Armor '..tostring(kit.id))
        if(seen[kit.name or'']or 0)>1 or not kit.name then name=name..' ('..tostring(kit.id)..')'end
        local passive=passives[kit.passive]
        local v=type(kit.vanilla)=='table'and kit.vanilla or{}
        local detail={}
        if passive and passive.name then detail[#detail+1]=title_case(passive.name)end
        if v.rating then detail[#detail+1]='armor '..util.format(v.rating)end
        if v.speed then detail[#detail+1]='speed '..util.format(v.speed)end
        if v.stamina then detail[#detail+1]='stamina regen '..util.format(v.stamina)end
        kits[#kits+1]={key='ar|'..tostring(kit.id),name=name,subtitle=util.humanize(kit.class or'armor')..' armor',
            detail=table.concat(detail,' · '),
            build=function(object)return kit_rows(hd2,object,entry)end}
    end
    for _,o in ipairs(sorted_objects(kits))do list[#list+1]=o end
    return list
end

CATEGORY.terminids=enemy_category(function(e)return e.kind=='enemy'and e.faction=='terminids'end)
CATEGORY.automatons=enemy_category(function(e)return e.kind=='enemy'and e.faction=='automatons'end)
CATEGORY.illuminate=enemy_category(function(e)return e.kind=='enemy'and e.faction=='illuminate'end)
CATEGORY.structures=enemy_category(function(e)return e.kind=='structure'end)
M.CATEGORY=CATEGORY

-- The categories that can hold an object key's family (presets name rows by key; mods' claims name family objects).
local FAMILY_CATEGORIES={pw={'primary','secondary'},th={'throwables'},bo={'boosters'},
    st={'offensive','defensive','support_weapons','support_backpacks','vehicles','resupply'},
    sw={'support_weapons'},sp={'support_weapons'},bp={'support_weapons','support_backpacks'},sb={'support_backpacks'},
    vh={'vehicles'},ve={'vehicles'},vw={'vehicles','support_backpacks'},rs={'resupply'},
    en={'terminids','automatons','illuminate','structures'},hd={'helldiver'},ar={'armor'}}

------------------------------------------------------------------------------------------------- catalogue --
local Catalog={};Catalog.__index=Catalog

-- The hd2 the rows' target functions use: the real one, except while the exporter traces a row (editor/export.lua
-- sets export.tracing), when every hd2 call returns a recorder of the Lua code that builds the target.
local export_module
local function traced(hd2)
    export_module=export_module or require('mods/skyeshade/hd2runtime_editor/editor/export')
    return setmetatable({},{__index=function(_,key)
        local tracing=export_module.tracing
        if tracing and type(hd2[key])=='function'then return tracing(key)end
        return hd2[key]
    end})
end
function M.new(hd2)
    return setmetatable({hd2=traced(hd2),real_hd2=hd2,lists={},errors={},by_key={},rows={},by_loc={},aliases={}},Catalog)
end
-- The category's objects (built once), or {} and the reason it is unavailable.
function Catalog:objects(category)
    local list=self.lists[category]
    if list then return list,self.errors[category]end
    local builder=CATEGORY[category]
    local ok,result,why=pcall(function()return builder(self)end)
    if not ok then why=result;result=nil end
    list=result or{}
    local tone
    for _,group in ipairs(M.GROUPS)do
        for _,item in ipairs(group.items)do if item.id==category then tone=item.tone end end
    end
    for _,object in ipairs(list)do
        object.category,object.tone=category,tone
        self.by_key[object.key]=object
        for _,alias in pairs(object.aliases or{})do self.aliases[alias]=object end
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
        if row and not self.rows[row.key]then
            object.rows[#object.rows+1]=row
            self.rows[row.key]=row
            local list=self.by_loc[row.loc]
            if not list then list={};self.by_loc[row.loc]=list end
            list[#list+1]=row
            local label=(row.group or'')..'\0'..row.section
            local section=by_label[label]
            if not section then
                section={label=row.section,group=row.group,rows={}}
                by_label[label]=section
                object.sections[#object.sections+1]=section
            end
            section.rows[#section.rows+1]=row
        end
    end
    return object
end
-- An object by its key, or by the key of a part it holds (a stratagem, weapon, backpack or vehicle of a composite).
function Catalog:object(key)
    local object=self.by_key[key]or self.aliases[key]
    if object then return object end
    local family=tostring(key):match('^(%a+)|')
    for _,category in ipairs(FAMILY_CATEGORIES[family]or{})do
        self:objects(category)
        object=self.by_key[key]or self.aliases[key]
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
-- The rows of a catalogued vehicle or drone weapon (vehicle_weapon_authoring key), from the object that carries it.
function Catalog:weapon_rows(key)
    local object=self:object('vw|'..key)
    if not object then return {},nil end
    self:open(object)
    local out={}
    for _,row in ipairs(object.rows)do if row.vw_key==key then out[#out+1]=row end end
    return out,object
end
-- Every open row on the same native bytes.
function Catalog:siblings(row)return self.by_loc[row.loc]or{row}end
-- Opens up to `budget` more objects (every category, in order) so the native-bytes index covers the whole catalogue;
-- true once every object is open. With `seconds`, it also stops once that much CPU time has passed (after at least
-- one object). The editor calls it every frame with a few milliseconds, so the full index (about 20,000 rows) builds
-- in the background without a hitch.
function Catalog:index_step(budget,seconds)
    local started=seconds and os.clock()
    if self.indexed then return true end
    self.index_queue=self.index_queue or{}
    if not self.index_categories then
        self.index_categories={}
        for _,group in ipairs(M.GROUPS)do
            for _,item in ipairs(group.items)do self.index_categories[#self.index_categories+1]=item.id end
        end
    end
    local opened=0
    while opened<(budget or 4)do
        if#self.index_queue==0 then
            local category=table.remove(self.index_categories,1)
            if not category then self.indexed=true;return true end
            for _,object in ipairs((self:objects(category)))do self.index_queue[#self.index_queue+1]=object end
        else
            local object=table.remove(self.index_queue,1)
            if not object.rows then self:open(object);opened=opened+1 end
            if started and opened>0 and os.clock()-started>=seconds then return false end
        end
    end
    return false
end
-- Every row by the identities ModBuilder projects name them with (editor/modbuilder.lua): instance[instanceKey] and
-- weapon['<catalogue weapon>|<semanticFieldId>'], swap (projectile and terminal explosion swaps), ident (rows without
-- an instance key, by ModBuilder's other identity fields), and rows (all). Opens the whole catalogue first; built once.
function Catalog:import_index()
    if self.import_lookup then return self.import_lookup end
    while not self:index_step(500)do end
    local lookup={instance={},weapon={},swap={},ident={},rows={}}
    for _,group in ipairs(M.GROUPS)do
        for _,item in ipairs(group.items)do
            for _,object in ipairs((self:objects(item.id))or{})do
                for _,row in ipairs(object.rows or{})do
                    lookup.rows[#lookup.rows+1]=row
                    local d=type(row.descriptor)=='table'and row.descriptor or{}
                    if d.instanceKey and not lookup.instance[d.instanceKey]then lookup.instance[d.instanceKey]=row end
                    if row.weapon_name and d.semanticFieldId then
                        local key=row.weapon_name..'|'..d.semanticFieldId
                        if not lookup.weapon[key]then lookup.weapon[key]=row end
                    end
                    -- the identities of rows without an instance key: support weapon fields by weapon, role and field;
                    -- vehicle weapons, enemies and structures by entity (and path / zone); pod slots by rack and slot
                    local function reg(key)if key and not lookup.ident[key]then lookup.ident[key]=row end end
                    local t=type(d.target)=='table'and d.target or{}
                    local sids={d.semanticTarget,d.semanticFieldId,d.id}
                    if t.resource=='support_weapon'and t.weapon then
                        for _,sid in pairs(sids)do reg('support|'..t.weapon..'|'..tostring(t.attack or'')..'|'..sid)end
                    end
                    if row.mb_entity then
                        for _,sid in pairs(sids)do
                            reg(row.mb_resource..'|'..row.mb_entity..'|'..row.mb_where..'|'..sid)
                        end
                    end
                    reg(row.mb_key)
                    -- swaps: 'projectile|<weapon>|<role>' and 'terminal|<weapon>|<role>|<phase>'
                    local s=row.swap
                    if s and row.weapon_name then
                        lookup.swap[s.kind..'|'..row.weapon_name..'|'..s.role..(s.phase and('|'..s.phase)or'')]=row
                    end
                end
            end
        end
    end
    self.import_lookup=lookup
    return lookup
end
-- The other rows that write a row's native bytes, on other objects (a value shared by several weapons, enemies or
-- stratagems: changing one changes them all). {row, ...}; complete once the index is built (index_step).
function Catalog:shared_with(row)
    local out={}
    for _,other in ipairs(self.by_loc[row.loc]or{})do
        if other~=row and other.object~=row.object then out[#out+1]=other end
    end
    return out
end
function Catalog:row_at(loc)local list=self.by_loc[loc];return list and list[1]or nil end

return M

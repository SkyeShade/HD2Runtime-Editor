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
        {id='vehicles',label='Vehicles',tone='support'},{id='resupply',label='Mission',tone='support'}}},
    {id='equipment',label='EQUIPMENT',items={{id='boosters',label='Boosters'},{id='status_effects',label='Status Effects'}}},
    {id='helldiver',label='HELLDIVER',items={{id='helldiver',label='Helldiver'},{id='armor',label='Armor'},
        {id='armor_perks',label='Armor perks'}}},
    {id='enemies',label='ENEMIES',items={
        {id='terminids',label='Terminids'},{id='automatons',label='Automatons'},{id='illuminate',label='Illuminate'},
        {id='structures',label='Structures'},{id='enemy_entities',label='Other Entities'}}},
    {id='enemy_director',label='SPAWNING & DESTRUCTION',items={
        {id='enemy_overview',label='Enemy Overview'},
        {id='enemy_difficulty',label='Mission Difficulty'},{id='enemy_rosters',label='Spawn Rosters'},
        {id='enemy_compositions',label='Spawn Compositions'},{id='demolition_templates',label='Demolition Templates'},
        {id='destruction_models',label='Destruction Models'}}},
    -- (the user's requests of 2026-10-14: one overview per front, its sliders capped at the game's 41:40, a freeze
    -- button and "Freeze automatically" per duration. The per-mission pages and the Mission Timer page are kept,
    -- unlisted: their categories still resolve saved and preset values, FAMILY_CATEGORIES below)
    {id='missions',label='MISSIONS',items={{id='mission_overview',label='Mission Overview'}}},
}

local NUMERIC={number=true,integer=true}
-- The game's network limits of a weapon's ammunition (rounds in a magazine, magazine counts), and of the mission
-- countdown (seconds): the host clamps its countdown every frame to the replicated timer field's range 0..2500.
local NETWORK_MAX={rounds=2047,magazines=31,mission_seconds=2500}
M.NETWORK_MAX=NETWORK_MAX
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
    if type(descriptor)=='table'and type(descriptor.backing)=='table'and descriptor.backing.kind=='mission_timer'then
        return 'mission/'..descriptor.backing.source..'/'..descriptor.semanticFieldId
    end
    if type(descriptor)=='table'and type(descriptor.target)=='table'and descriptor.target.resource=='enemy_director'then
        local t=descriptor.target
        return 'director/'..t.path..'/'..t.key..'/'..descriptor.semanticFieldId
    end
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
    reload='Ammo & Magazine',fire_mode='Fire Mode',fire_rate='Fire Mode',heat='Heat',heatsink='Heatsinks',
    projectile='Projectile',damage='Damage',explosion='Explosion',arc='Arc',beam='Beam',charge='Charge',
    status='Status',spread='Handling',recoil='Handling',sway='Handling',reticle='Handling',movement='Handling',
    function_ammo='Functions',entity='Health & Armor',zone='Damage Zones',shield='Shield',turret='Turret',
    targeting='Targeting',stratagem='Call-in',eagle='Eagle',orbital='Orbital Strike',minefield='Minefield',
    booster='Booster',throwable='Throwable',attachment='Magazine',jump='Jump Pack',hover='Hover Pack',
    warp='Warp Pack',recharge='Recharge',drone='Drone',payload='Hellpod',windup='Wind-up',
    -- HD2Runtime 0.31.0: the W.A.S.P., Spear, Commando, P-33 and P-92 missiles' own SeekingMissile records
    missile='Missile',function_missile='Function Missile',deposit='Ammo'}
-- A backpack field's own group (the Runtime's uiGroup): its section name.
local UI_GROUPS={backpack_ammo='Ammo',drone_magazines='Drone Magazines',supply_boxes='Supply boxes'}
-- The firing charge members of a heat weapon are its wind-up (HD2Runtime 0.31.0, research/windup-controls): shown with
-- the spin-up fields under "Wind-up", where a player looking for the Sickle's wind-up finds them.
local WIND_UP={['heat.firing_charge']=true,['heat.charge_gain_per_second']=true,['heat.charge_loss_per_second']=true,
    ['heat.reset_charge_after_shot']=true}
local HANDLING={recoil=true,spread=true,sway=true,ergonomics=true,reticle=true,aim=true,zoom=true}
-- The ammunition supply, together in one section ("Ammo & Magazine", the page's Ammunition category) wherever its
-- fields come from: the rounds a magazine or feed holds first (weapon.capacity is a weapon field, but a player looks
-- for it beside the spare magazines), then the spare, starting and supply counts, then the reload. By field id; a rank
-- orders the rows of one section (presentation only: row keys and preset keys are unchanged).
local AMMO_SUPPLY={['weapon.capacity']=true,['weapon.base_capacity']=true,['weapon.feed_capacity_1']=true,
    ['weapon.feed_capacity_2']=true}
local AMMO_RANK={['weapon.capacity']=1,['weapon.base_capacity']=1,['weapon.feed_capacity_1']=1,
    ['weapon.feed_capacity_2']=1,['magazine.capacity']=1,['rounds.capacity']=1,['rounds.feed_capacity_1']=1,
    ['rounds.feed_capacity_2']=1,['attachment.magazine_capacity']=1,
    ['magazine.spare_magazines']=2,['rounds.spare_rounds']=2,['attachment.spare_magazines']=2,
    ['magazine.starting_magazines']=3,['rounds.starting_rounds']=3,['attachment.starting_magazines']=3,
    ['magazine.magazines_from_supply']=4,['rounds.rounds_from_supply']=4,['attachment.magazines_from_supply']=4,
    ['magazine.magazines_from_ammo_box']=4,['rounds.rounds_from_ammo_box']=4,
    ['attachment.reload_duration']=5}
local function ammo_rank(field)
    field=tostring(field)
    return AMMO_RANK[field]or(field:find('^reload%.')and 5)or nil
end
M.ammo_rank=ammo_rank
local function domain_of(id)return tostring(id):match('^([^%.]+)')or'other'end
local function domain_label(id)
    if WIND_UP[tostring(id)]then return 'Wind-up'end
    if AMMO_SUPPLY[tostring(id)]then return DOMAIN_LABELS.magazine end
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
-- A projectile's own DamageInfo is the damage of its direct hit; its explosion has rows of its own ("Explosion · ...").
-- Labelled so, as the missiles' "Damage · Missile direct hit" (a player took the RL-77's 350 for its blast).
local function direct_hit(role)
    if role==nil or role==''then return 'Direct hit'end
    return role..' direct hit'
end
-- A second ammunition whose projectile carries the very DamageInfo row of the weapon's main round (HD2Runtime shares
-- one record): its direct-hit rows say so (the same bytes; editing either changes both).
local SAME_HIT_LABELS={['RL-77 Airburst Rocket Launcher']='Cluster rocket direct hit (same row as the rocket)'}
local function same_hit_rows(name,rows)
    local first={}
    for _,r in ipairs(rows)do
        local section=tostring(r.section)
        local base=section:gsub(' · Status$','')
        if base:find('^Damage · ')and r.loc then
            local seen=first[r.loc]
            if not seen then first[r.loc]=base
            elseif seen~=base then
                local role=base:match('^Damage · (.-) direct hit$')or base:gsub('^Damage · ','')
                r.section=join('Damage',SAME_HIT_LABELS[name]
                    or(role..' direct hit (same row as the '..(seen=='Damage · Direct hit'and'main round'
                        or seen:gsub('^Damage · ',''))..')'),section:find(' · Status$')and'Status'or nil)
            end
        end
    end
end

--------------------------------------------------------------------------------------------------- rows --
-- One editable numeric field. spec: {id, label, unit, vanilla, min, max, type, storage, field, target, shared,
-- unverified, unverified_reference, descriptor, section, editable, reason, disabled_value}. disabled_value: a field
-- whose reviewed domain is that sentinel OR a value above 0 up to max (the whole-body gib threshold: -1 disables it);
-- nothing between the two is valid.
-- Fields the Runtime checks against another field (HD2Runtime player_weapon_writes TURRET_PAIRS).
local ORDERED_LIMITS={['turret.yaw_min']=true,['turret.yaw_max']=true,['turret.pitch_min']=true,['turret.pitch_max']=true}
local make_value_row
-- The beam fire mode (HD2Runtime 0.31.0, BeamWeapon +100, a typed enum published as an integer 4 to 6): the game's
-- three beam kinds by name.
local BEAM_MODES={{value=4,label='Continuous (4)'},{value=5,label='Charged blast, 40-K (5)'},
    {value=6,label='Pulsed, Trident (6)'}}
-- The pulse length limits the beam fire rate (HD2Runtime 0.31.0 docs "beam.pulse_seconds limits beam.fire_rate"): a
-- new pulse starts only in the update after the previous one ended.
local PULSE_NOTE='Pulsed beams (mode 6): the pulse length caps the fire rate (600 rpm needs at most 0.067 s, 900 rpm 0.033 s)'
local function beam_note(spec)
    local d=type(spec.descriptor)=='table'and spec.descriptor or{}
    local p=type(d.beamPulse)=='table'and d.beamPulse
    if p and p.limitsFireRate==false then return nil end
    if spec.field=='beam.pulse_seconds'or spec.field=='beam.fire_rate'then return PULSE_NOTE end
    return nil
end
local function make_row(object,spec)
    if spec.field=='beam.fire_mode'and type(spec.vanilla)=='number'and(spec.unit=='enum'or spec.min==4)then
        local labels={}
        for _,m in ipairs(BEAM_MODES)do
            if(not spec.min or m.value>=spec.min)and(not spec.max or m.value<=spec.max)then labels[#labels+1]=m end
        end
        local copy={}
        for k,v in pairs(spec)do copy[k]=v end
        copy.kind,copy.labels,copy.unit='choice',labels,nil
        copy.options=function()
            local out={}
            for i,item in ipairs(labels)do out[i]={value=item.value,label=item.label}end
            return out
        end
        return make_value_row(object,copy)
    end
    local integer=spec.type=='integer'or(spec.type~='number'and INTEGER_STORAGE[spec.storage or'']~=nil)
    local min,max=spec.min,spec.max
    -- the most rounds and magazines the game's network state carries (11 and 5 bits): HD2Runtime 0.31.2 publishes
    -- them as the fields' maxima; an older Runtime publishes none, so a larger value would desync. Never below the
    -- game's own value.
    if max==nil and integer and type(spec.vanilla)=='number'then
        local cap=spec.field=='weapon.capacity'and NETWORK_MAX.rounds
            or(tostring(spec.field):find('^magazine%.')and NETWORK_MAX.magazines)or nil
        if cap and spec.vanilla<=cap then max=cap end
    end
    -- (HD2Runtime 0.40.0 RC14 and earlier published 7200: anything above 2500 started at 41:40 in the mission)
    if spec.field=='mission.duration_seconds'then max=math.min(max or NETWORK_MAX.mission_seconds,NETWORK_MAX.mission_seconds)end
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
            allow_unverified_reference=spec.unverified_reference==true or nil,
            allow_component_swap=spec.component_swap==true or nil},
        editable=spec.editable~=false,reason=spec.reason,semantic=spec.semantic or spec.field,group=spec.group,
        note=spec.note or beam_note(spec),disabled_value=spec.disabled_value,info=spec.info,
        fires_scope=spec.fires_scope,swap_scope=spec.swap_scope}
    -- a turret's limits are ordered (minimum below maximum, checked against the other limit's reviewed value): the
    -- layer gives them exact-value handles, never a range that would cross the other limit
    row.exact=ORDERED_LIMITS[tostring(spec.field)]or nil
    -- a native value outside the reviewed range (the Constitution status lasts 999999 s; durations are reviewed 0 to
    -- 100000): a slider spanning it would be refused, so exact values too (any value in range, reset back to native)
    if type(spec.vanilla)=='number'and(min and spec.vanilla<min or max and spec.vanilla>max)then row.exact=true end
    row.loc=location(spec.descriptor,'row:'..row.key)
    if row.editable then
        local held=util.representable(row.vanilla,integer,spec.storage)
        if held==nil then
            row.editable,row.reason=false,'its default '..tostring(row.vanilla)..' needs more than 3 decimals'
            row.editor_lock=true
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
make_value_row=function(object,spec)
    local row={key=object.key..'|'..spec.id,object=object,section=spec.section or'Fields',kind=spec.kind,
        label=util.plain(spec.label or util.humanize(spec.field),60),unit=spec.unit,vanilla=spec.vanilla,
        held_vanilla=spec.vanilla,field=spec.field,target=spec.target,expect=spec.expect,shared=spec.shared==true,
        unverified=spec.unverified==true,descriptor=spec.descriptor,info=spec.info,
        acks={allow_shared=spec.shared==true or nil,allow_unverified_effect=spec.unverified==true or nil,
            allow_unverified_reference=spec.unverified_reference==true or nil,
            allow_component_swap=spec.component_swap==true or nil},
        editable=spec.editable~=false,reason=spec.reason,semantic=spec.field,options=spec.options,labels=spec.labels,
        min=spec.min,max=spec.max,integer=spec.kind=='uses'or nil,directions=spec.directions,
        min_length=spec.min_length,max_length=spec.max_length,unlimited=spec.unlimited,group=spec.group,
        modes=spec.modes,max_modes=spec.max_modes,slots=spec.slots,note=spec.note,controller=spec.controller,
        export_reason=spec.export_reason,fires_scope=spec.fires_scope,swap_scope=spec.swap_scope}
    row.loc=location(spec.descriptor,'row:'..row.key)
    return row
end
M.make_value_row=make_value_row

-- A row's value as the window shows it, in the player's language (its own labels first).
local i18n=require('mods/skyeshade/hd2runtime_editor/editor/i18n')
local function Lf(...)return i18n.Lf(...)end
-- A catalogued explosion's label (hd2.explosion(name), an alias resolved), or nil.
local function explosion_label(id)
    local ok,E=pcall(require,'hd2runtime/domains/explosion_catalogue')
    if not ok or type(E)~='table'or type(E.explosions)~='table'then return nil end
    local e=E.explosions[id]or E.explosions[(E.aliases or{})[id]or'']
    return e and e.label and tostring(e.label)or nil
end
function M.text(row,value)
    local L=i18n.L
    if row.calculate then
        if type(value)=='number'then return ('%.3f'):format(value):gsub('0+$',''):gsub('%.$','')..' s'end
        return L(tostring(value))
    end
    for _,item in ipairs(row.labels or{})do
        if util.same(item.value,value)then return L(item.label)end
    end
    -- a catalogued explosion (a payload slot's value): its catalogue label
    if type(value)=='table'and rawget(value,'resource')=='explosion'and type(rawget(value,'explosion'))=='string'then
        return L(explosion_label(rawget(value,'explosion'))or rawget(value,'explosion'))
    end
    if row.kind=='traits'and type(value)=='table'then
        if#value==0 then return L('None')end
        local names={}
        for i,id in ipairs(value)do
            names[i]=id
            for _,t in ipairs(row.traits or{})do if t.value==id then names[i]=L(t.label)end end
        end
        return table.concat(names,', ')
    end
    return util.value_label(value)
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
-- The selector binding {field, expect, value} a value needs written with it: more than one filled rate slot on a
-- weapon whose rate-of-fire selector is not bound yet (fire_rate_modes().state 'addable'), or more than one fire mode
-- on a weapon whose fire-mode selector is not bound yet (HD2Runtime 0.31.0: fire_mode.modes descriptor fireModeState
-- 'addable', bound on its first free input); nil otherwise.
function M.rate_binding(row,value)
    if row.kind=='modes'then
        local d=row.descriptor
        if type(value)=='table'and#value>1 and type(d)=='table'and d.fireModeState=='addable'
            and type(d.bindableInputs)=='table'and d.bindableInputs[1]then
            return {field='weapon_function.'..d.bindableInputs[1],expect='none',value='fire_mode'}
        end
        return nil
    end
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
    if rawget(value,'resource')=='vehicle_weapon'then return nil end
    if rawget(value,'resource')=='pickup'then return {ref='pickup',id=rawget(value,'semanticId')}end
    if rawget(value,'path')=='no_explosion'then return {ref='none'}end
    -- a catalogued explosion (hd2.explosion(name): HD2Runtime 0.31.2 payload options)
    if rawget(value,'resource')=='explosion'and type(rawget(value,'explosion'))=='string'then
        return {ref='explosion',id=rawget(value,'explosion')}
    end
    local weapon,attack,phase=rawget(value,'weapon'),rawget(value,'attack'),rawget(value,'phase')
    if weapon and phase then
        -- (a support weapon's own terminal explosion keeps its resource; a player weapon's is stored as before)
        return {ref='terminal',weapon=weapon,attack=attack,phase=phase,
            resource=rawget(value,'resource')=='support_weapon'and'support_weapon'or nil}
    end
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
        if stored.ref=='explosion'then return hd2.explosion(stored.id)end
        if stored.ref=='terminal'and stored.resource=='support_weapon'then
            return hd2.support_weapon(stored.weapon):attack(stored.attack):projectile():terminal_action(stored.phase)
                :explosion()
        end
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
-- Donor beams (HD2Runtime 0.31.0 beam swaps): every catalogued beam output a beam host can fire.
local beam_options
-- A swap reached through a Runtime source call (weapon:projectile_source() / beam_source(): {target, field, expect,
-- writable, reason, acknowledgements}). Its target is a handle no hd2 chain builds, so the row carries the Lua of the
-- call (code) for the exporter and the ModBuilder import. A source that is not writable shows its reason read-only.
local function source_row(object,spec)
    local ok,src=pcall(spec.source)
    local common={id=spec.id,kind='reference',label=spec.label,section=spec.section,descriptor=spec.descriptor,
        unverified=true,field=spec.field,swap_scope=spec.swap_scope,
        target=function()return spec.source().target end,expect=function()return spec.source().expect end,
        options=spec.options,note=spec.note}
    if ok and type(src)=='table'and src.writable and src.expect then
        common.vanilla=src.expect
        if src.field then common.field=src.field end
        for _,a in ipairs(src.acknowledgements or{})do if a=='allow_shared'then common.shared=true end end
    else
        common.editable=false
        common.reason=tostring(ok and type(src)=='table'and src.reason or(not ok and src)or'read-only in this HD2Runtime')
        common.vanilla='own'
        common.labels={{value='own',label=spec.own_label or'Own'}}
    end
    local row=M.make_value_row(object,common)
    row.target_code,row.expect_code=spec.code..'.target',spec.code..'.expect'
    return row
end
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
beam_options=function(hd2,row)
    local out={{value=M.expect(row),label='Own beam',sub=row.object.name}}
    local A=load('attack_outputs')
    for _,id in ipairs(util.sorted_keys(A and A.outputs or{}))do
        local o=A.outputs[id]
        if o.family=='beam'and o.selectableAsBeamReference~=false and o.editable~=false then
            local ok,value=pcall(hd2.attack_output,id)
            if ok then
                out[#out+1]={value=value,label=tostring(type(o.owner)=='table'and o.owner.name or id),sub=(id:match('([^/]+)$')or id)}
            end
        end
    end
    return out
end
-- Payload slots (terminal.explosion rows): their labels, the picker's group headers (HD2Runtime 0.31.2 payload option
-- groups, by id) and its warning badges with a short explanation each (shown through L()).
local PAYLOAD_LABELS={impact='Impact payload',expiry='Expiry payload',not_offered='Not offered',own='Own explosion',
    none='None',none_sub='no terminal explosion'}
M.PAYLOAD_LABELS=PAYLOAD_LABELS
local PAYLOAD_GROUPS={weapon='Weapons',support_weapon='Support weapons',throwable='Throwables',orbital='Orbitals',
    eagle='Eagles',hellbomb='Hellbombs',sentry='Sentries',mine='Mines',vehicle='Vehicles',backpack='Backpacks',
    enemy='Enemies',other='Other'}
M.PAYLOAD_GROUPS=PAYLOAD_GROUPS
local PAYLOAD_WARNINGS={
    very_large={badge='VERY LARGE',text='A very large blast: it can kill the shooter and teammates nearby'},
    lingering_field={badge='LINGERING',text='Leaves a lingering status field; the game holds at most 4096 of them, '
        ..'so avoid it on fast-firing weapons'},
    fire={badge='FIRE',text='Leaves fire on the ground'},
    shrapnel={badge='SHRAPNEL',text='Releases shrapnel or bomblets of its own'},
    arc={badge='ARC',text='Releases an electric arc'},
    no_damage={badge='NO DAMAGE',text='Deals no damage itself (a status field, smoke or a push)'},
    objective_packages={badge='300 MB LOAD',text='Loads two mission objective packages (about 300 MB) before the '
        ..'write: up to 90 s and a hitch, and they stay loaded'}}
M.PAYLOAD_WARNINGS=PAYLOAD_WARNINGS
-- An option's damage and radius as its picker subtitle ("350 damage · 3 to 6 m").
local function option_sub(o)
    local parts={}
    if type(o.damage)=='number'then
        local text=Lf('%s damage',util.format(o.damage))
        if type(o.durable_damage)=='number'and o.durable_damage~=o.damage then
            text=Lf('%s damage (%s durable)',util.format(o.damage),util.format(o.durable_damage))
        end
        parts[#parts+1]=text
    end
    if type(o.outer_radius)=='number'then
        parts[#parts+1]=type(o.inner_radius)=='number'and Lf('%s to %s m',util.format(o.inner_radius),
            util.format(o.outer_radius))or Lf('%s m',util.format(o.outer_radius))
    end
    if type(o.statuses)=='table'and#o.statuses>0 then
        parts[#parts+1]=#o.statuses==1 and Lf('1 status')or Lf('%d statuses',#o.statuses)
    end
    return table.concat(parts,' · ')
end
-- The values a payload slot takes from HD2Runtime 0.31.2 (terminal:payload_options()): its own explosion and none
-- first, then every option in the Runtime's display order, each with its group, warnings and acknowledgements; the
-- options the field refuses as a note. nil when the Runtime has no payload options (older Runtimes).
local function payload_options(row)
    local ok,o=pcall(function()
        local t=row.target()
        if type(t)~='table'or type(t.payload_options)~='function'then return nil end
        return t:payload_options()
    end)
    if not ok or type(o)~='table'or type(o.options)~='table'then return nil end
    local out={}
    local function item(value,label,sub,acks)
        out[#out+1]={value=value,label=label,sub=sub,acks=acks,checked=true,search=sub}
        return out[#out]
    end
    if type(o.own)=='table'and o.own.value~=nil then
        item(o.own.value,PAYLOAD_LABELS.own,o.own.label and tostring(o.own.label)or nil,o.own.acknowledgements).own=true
    end
    if type(o.none)=='table'and o.none.value~=nil then
        item(o.none.value,PAYLOAD_LABELS.none,PAYLOAD_LABELS.none_sub,o.none.acknowledgements)
    end
    for _,x in ipairs(o.options)do
        if type(x)=='table'and x.value~=nil then
            local it=item(x.value,tostring(x.label or x.name),option_sub(x),x.acknowledgements)
            it.group=PAYLOAD_GROUPS[x.group]or(x.group_label and tostring(x.group_label))or PAYLOAD_GROUPS.other
            it.search=table.concat({tostring(x.owner or''),tostring(x.name or''),tostring(x.group_label or''),
                it.group},' ')
            it.warnings={}
            for _,code in ipairs(type(x.warnings)=='table'and x.warnings or{})do it.warnings[#it.warnings+1]=code end
            it.explosion=x.name
            it.note=type(x.note)=='string'and x.note~=''and x.note or nil
        end
    end
    local note={}
    for _,x in ipairs(type(o.excluded)=='table'and o.excluded or{})do
        if#note<2 and type(x)=='table'then
            note[#note+1]=Lf('Not offered: %s (%s)',tostring(x.label or x.name),util.plain(tostring(x.reason),160))
        end
    end
    out.note=#note>0 and note or nil
    return out
end
M.payload_options=payload_options
-- Donor terminal explosions: with HD2Runtime 0.31.2 every payload option (payload_options above); before, none and one
-- player weapon terminal action per reviewed explosion type.
local function explosion_options(hd2,row)
    local options=payload_options(row)
    if options then return options end
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
    if f.modeValues and f.modeValues.unsafe then
        common.note='Unsafe permits overcharging. With explosion enabled, reaching the overcharge time destroys the weapon. Modes apply to newly built weapons.'
    end
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
-- A read-only row that only shows a fact (a derived value, a verdict, a caveat): its text in the value box and the
-- reason in the status line. spec: {id, label, field, section, group, reason, text, target, descriptor, info, note}.
local function info_row(object,spec)
    local labels={{value='info',label=spec.text or'-'}}
    return make_value_row(object,{id=spec.id,kind='choice',label=spec.label,field=spec.field or'info',section=spec.section,
        group=spec.group,vanilla='info',labels=labels,options=static_options(labels),editable=false,
        reason=spec.reason,target=spec.target,descriptor=spec.descriptor,info=spec.info,note=spec.note})
end
M.info_row=info_row
-- Derived heat values (HD2Runtime 0.31.0 heat.warmup, heat.overheat_cooldown) and the section that shows them.
local DERIVED_HEAT={['heat.warmup']='Wind-up',['heat.overheat_cooldown']='Heat'}
-- Notes shown with a field, by field id. HD2Runtime 0.31.2: the LAS-99 Quasar's lockout after an overheat is its own
-- member (WeaponHeat +140: the heat lost per second while overheated); "Cooling rate" never governs it.
local FIELD_NOTES={['heat.cool_per_second_overheated']='Lockout after overheating = 100 / this value (6.66 = 15 s); '
    ..'"Cooling rate" does not change it'}
-- A field shown right after another one of the same section (where a player looks for it), by field id.
local PLACED_AFTER={['heat.cool_per_second_overheated']='heat.cool_per_second'}
local function field_note(f)
    if f.reloadTiming then return f.reloadTiming.note end
    if f.reviewedReloadHeat and f.semanticFieldId=='heat.cool_per_second_overheated' then
        return 'Used only when cooling while charging or overheated is enabled. Disable Prevent cooling to use this rate.'
    end
    if f.semanticFieldId=='heat.fire_rate_curve_exponent' then
        return 'Rate multiplier = 1 + (maximum multiplier - 1) * (heat / capacity) ^ exponent'
    end
    return FIELD_NOTES[f.semanticFieldId]
end

local function place_after(rows)
    for field,anchor in pairs(PLACED_AFTER)do
        local from,to
        for i,r in ipairs(rows)do
            if r.field==field then from=i elseif r.field==anchor and not to then to=i end
        end
        if from and to and from~=to+1 and rows[from].section==rows[to].section then
            local row=table.remove(rows,from)
            if from<to then to=to-1 end
            table.insert(rows,to+1,row)
        end
    end
    return rows
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
-- Build Supply Pack views without expanding every weapon's damage and payload rows.
local function refill_entry(object,entry)
    if not object.refill_only then return entry end
    local fields={}
    for _,f in ipairs(entry.fields or{})do
        if tostring(f.semanticFieldId):match('from_supply$')then fields[#fields+1]=f end
    end
    return setmetatable({fields=fields},{__index=entry})
end
local function player_rows(hd2,object,entry)
    entry=refill_entry(object,entry)
    local rows={}
    local name=entry.name
    for _,f in ipairs(entry.fields or{})do
        local timing=f.reloadTiming
        if timing and timing.noReloadAbility then
            rows[#rows+1]=info_row(object,{id='reload.not_applicable',label='Reload',text='Not applicable',
                reason=f.reason,section='Ammo & Magazine'})
        end
        if timing and timing.defaultAttachment then
            local A=load('attachment_authoring')
            local attachment=A and A.attachments[timing.defaultAttachment]
            local duration=attachment and attachment.fields['attachment.reload_duration']
            if duration then
                local id=timing.defaultAttachment
                rows[#rows+1]=make_row(object,{id='reload.default_magazine',label='Reload duration (default magazine)',
                    vanilla=duration.currentDefault,min=duration.min,max=duration.max,type='number',storage='f32',
                    unit='seconds',field='attachment.reload_duration',target=function()return hd2.weapon_attachment(id)end,
                    shared=true,unverified=true,descriptor=duration,section='Ammo & Magazine',
                    note='Edits the default magazine definition. Other equipped magazines use their own reload duration under Magazines.'})
            end
        end
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
            local section,target,field,fires
            local role,when=branch,phase
            local projectile=function()return hd2.weapon(name):attack(role):projectile()end
            -- Weapons without a projectile attack (flame, arc, beam, melee) own their damage rows on the weapon.
            local has_projectile=branch and builds(projectile)
            if(domain=='projectile'or domain=='damage')and has_projectile then
                target=projectile
                field=strip(id,branch)
                section=domain=='damage'and join('Damage',direct_hit(role_label(branch)))
                    or join(DOMAIN_LABELS[domain],role_label(branch))
                fires='attack:'..branch
            elseif domain=='explosion'and has_projectile and phase then
                target=function()return projectile():terminal_action(when):explosion()end
                field=strip(id,branch,phase)
                section=join('Explosion',role_label(branch),util.humanize(phase))
                fires='attack:'..branch
            elseif branch and(domain=='projectile'or domain=='damage'or domain=='explosion')then
                target=function()return hd2.weapon(name)end
                field=id
                section=join(DOMAIN_LABELS[domain],role_label(branch),phase and util.humanize(phase)or nil)
            else
                target=function()return hd2.weapon(name)end
                field=id
                section=domain_label(id)
            end
            -- (fires_scope: the swap whose donor these rows give way to, "What a swapped weapon fires" below)
            local common={id=id,label=f.displayName,unit=f.unit,field=field,target=target,shared=shared_ack(f),
                unverified=unverified(f),descriptor=f,section=section,fires_scope=fires,note=field_note(f)}
            if id:match('^heatsink%.')then common.group='Heatsinks';common.section='Supply'end
            if id=='reload.duration'and timing then
                common.label=entry.kind=='underbarrel'and'Reload duration (underbarrel)'
                    or(name=='AR-11 Arbitrator'and'Reload duration (AR mode)'or'Reload duration')
                if timing.nativeAbilitySeconds then
                    common.note=string.format('Native ability: %.2f s. ',timing.nativeAbilitySeconds)..(common.note or'')
                end
            end
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
                    common.fires_scope,common.swap_scope=nil,'attack:'..role
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
                        common.label=PAYLOAD_LABELS[phase]or(util.humanize(phase)..' payload')
                        common.section=join('Explosion',role_label(role),util.humanize(phase))
                        common.options=function(row)return explosion_options(hd2,row)end
                        rows[#rows+1]=make_value_row(object,common)
                        rows[#rows].swap={kind='terminal',role=role,phase=phase}
                    end
                end
            end
        end
    end
    if object.refill_only then
        for _,r in ipairs(rows)do r.weapon_name=name end
        return rows
    end
    -- HD2Runtime 0.31.0 beam swaps: a beam weapon fires another catalogued beam (weapon:beam_source()). The source
    -- decides, not the field: the LAS-5 Scythe's own member is dormant (read-only), and its beam is swapped on the
    -- default muzzle's delta row (shared by every weapon that defaults to that muzzle)
    for _,f in ipairs(entry.fields or{})do
        if f.type=='beam_reference'and not entry.subweaponOf then
            local row=source_row(object,{id='attack.beam',label='Beam',section='Beam · Swap',descriptor=f,
                field='attack.beam',code='hd2.weapon('..string.format('%q',name)..'):beam_source()',
                source=function()return hd2.weapon(name):beam_source()end,
                options=function(row)return beam_options(hd2,row)end,own_label='Own beam'})
            if entry.ordinaryWritesBlocked==true and row.editable then row.editable,row.reason=false,BLOCKED_REASON end
            rows[#rows+1]=row
        end
    end
    -- HD2Runtime 0.30.x: a weapon that fires its default ammunition's projectile (the Liberator, Dominator, Diligence,
    -- Breaker, Peacemaker and Redeemer) swaps it on that ammunition (weapon:projectile_source(): ammunition.projectile),
    -- not on its dormant base member
    if not entry.subweaponOf then
        local ok,src=pcall(function()return hd2.weapon(name):projectile_source('primary')end)
        local A=load('attack_outputs')
        local ammunition=A and A.ammunition and A.ammunition[name]
        if ok and type(src)=='table'and src.mechanism=='ammunition'and type(ammunition)=='table'then
            -- (the Runtime's own ammunition source, which its write path uses as this field's descriptor)
            local row=source_row(object,{id='ammunition.projectile',label='Projectile',section='Projectile · Swap',
                descriptor=ammunition,field='ammunition.projectile',swap_scope='attack:primary',
                code='hd2.weapon('..string.format('%q',name)..'):projectile_source("primary")',
                source=function()return hd2.weapon(name):projectile_source('primary')end,
                options=function(row)return projectile_options(hd2,row)end,own_label='Own ammunition'})
            row.note='Swapped on the default ammunition ('..tostring(hd2.weapon(name):ammunition():describe().item)
                ..'), which every weapon that equips it shares'
            if entry.ordinaryWritesBlocked==true and row.editable then row.editable,row.reason=false,BLOCKED_REASON end
            rows[#rows+1]=row
        end
    end
    -- HD2Runtime 0.31.0 (the LAS-99 Quasar report): the warm-up and the cooldown after an overheat are no members of
    -- their own. Shown as read-only notes that name the fields to edit, where a player looks for them.
    for _,f in ipairs(entry.fields or{})do
        local id=f.semanticFieldId
        local section=DERIVED_HEAT[tostring(id)]
        if section and not f.editable and f.reason and not f.deprecated then
            rows[#rows+1]=info_row(object,{id=id..'@derived',label=f.displayName or util.humanize(id),field=id,
                section=section,reason=f.reason,descriptor=f,
                text=type(f.currentDefault)=='number'and(util.format(f.currentDefault)..' (derived)')or'derived',
                target=function()return hd2.weapon(name)end})
        end
    end
    -- the catalogue weapon each row writes ('AR/GL-21 One-Two / underbarrel' for a sub-weapon): ModBuilder's identity
    for _,r in ipairs(rows)do r.weapon_name=name end
    return place_after(rows)
end

--------------------------------------------------------------------------------------- catalogue explosions --
-- Explosions of the Runtime's explosion catalogue (HD2Runtime 0.31.1+, edited through hd2.explosion(id)) shown on the
-- page of what sets them off. An object takes the explosions the catalogue lists with an owner of its name, for the
-- roles it asks for (a support weapon's programmable burst: function_impact; a Hellbomb: behavior), and every
-- explosion those or any other of its own explosions spawn (owners of category 'explosion': a burst's shrapnel, the
-- RL-77's bomblets). The rows carry the Runtime's own descriptors (the record identity of every other route to the same
-- bytes, its shared flag and acknowledgement), so a value the page already shows is not shown twice. Nothing without
-- hd2.explosion and the catalogue (an older HD2Runtime).
-- A chain explosion by its owner-neutral alias (HD2Runtime 0.31.2: the RL-77's 'bomblet'), else as shrapnel.
local CHAIN_LABELS={bomblet='Bomblets',shrapnel='Shrapnel'}
local function chain_label(e)
    for _,alias in pairs(type(e.aliases)=='table'and e.aliases or{})do
        local label=CHAIN_LABELS[tostring(alias):match('([^/]+)$')or'']
        if label then return label end
    end
    return CHAIN_LABELS.shrapnel
end
-- Notes on a catalogue explosion's rows, by explosion id.
local HELLBOMB_NOTE='Shared by both Hellbombs and some mission objectives'
local EXPLOSION_NOTES={['backpack/b100_portable_hellbomb/behavior']=HELLBOMB_NOTE,
    ['stratagem/nux223_hellbomb/behavior']=HELLBOMB_NOTE}
local function explosion_api()
    local explosions=load('explosion_catalogue')
    local ok,writes=pcall(require,'hd2runtime/domains/explosion_writes')
    if not(explosions and type(explosions.explosions)=='table'and ok and type(writes)=='table'
        and type(writes.descriptor)=='function')then return nil end
    return explosions,writes
end
-- The owners of a catalogue explosion, in the catalogue's order (the list may have holes).
local function owners_of(e)
    local out={}
    local list=type(e.owners)=='table'and e.owners or{}
    for i=1,table.maxn(list)do if type(list[i])=='table'then out[#out+1]=list[i]end end
    return out
end
-- The row of one field of catalogue explosion `eid` on `object` (row id: id_prefix .. field id), or nil when the
-- Runtime publishes the field read-only or not numeric there.
local function explosion_field_row(hd2,object,writes,e,eid,field,section,id_prefix)
    local okd,d=pcall(writes.descriptor,e,eid,field.id)
    if not(okd and type(d)=='table'and d.editable and numeric(d.type,d.currentDefault))then return nil end
    local suffix=field.id:gsub('^explosion%.',''):gsub('^damage%.','')
    local ap=suffix:match('^ap_(%a+)$')
    local label=ap and('Armor penetration: '..(ap=='direct'and'direct'or ap..' angle'))or util.humanize(suffix)
    local row=make_row(object,{id=id_prefix..field.id,label=label,
        unit=d.unit,field=field.id,target=function()return hd2.explosion(eid)end,
        shared=shared_ack(d),
        -- (no hd2.explosion edit is live-tested: a descriptor without an acknowledgement still gets one)
        unverified=unverified(d)or(d.acknowledgement==nil and d.acknowledgements==nil),descriptor=d,
        section=section,vanilla=d.currentDefault,note=EXPLOSION_NOTES[eid],
        min=d.range and d.range.min,max=d.range and d.range.max,type=d.type,
        storage=(d.backing or{}).storage})
    row.catalogue_explosion=eid
    return row
end
-- opts: {roles = {[role] = true}, section = function(role, entry, id, chained) -> section label or nil}. `rows` are
-- the rows already on the page. Returns the new rows.
local function catalogue_explosion_rows(hd2,object,name,rows,opts)
    if type(hd2.explosion)~='function'then return {}end
    local explosions,writes=explosion_api()
    if not explosions then return {}end
    local all=explosions.explosions
    local ids=util.sorted_keys(all)
    local own,picked,order={},{},{}
    for _,eid in ipairs(ids)do
        for _,o in ipairs(owners_of(all[eid]))do
            if o.name==name and o.category~='explosion'then
                own[eid]=true
                if opts.roles[o.role]and not picked[eid]then picked[eid]={role=o.role};order[#order+1]=eid end
            end
        end
    end
    -- what those explosions spawn, and what that spawns in turn
    local grew=true
    while grew do
        grew=false
        for _,eid in ipairs(ids)do
            if not picked[eid]then
                for _,o in ipairs(owners_of(all[eid]))do
                    if o.category=='explosion'and(own[o.name]or picked[o.name])and not picked[eid]then
                        picked[eid]={role=o.role,chained=true};order[#order+1]=eid;grew=true
                    end
                end
            end
        end
    end
    local covered={}
    for _,r in ipairs(rows or{})do if r.loc then covered[r.loc]=true end end
    local out={}
    for _,eid in ipairs(order)do
        local e,p=all[eid],picked[eid]
        local section=opts.section(p.role,e,eid,p.chained)
        for _,field in ipairs(section and explosions.fields or{})do
            local row=explosion_field_row(hd2,object,writes,e,eid,field,section,eid..'|')
            if row and not covered[row.loc]then covered[row.loc]=true;out[#out+1]=row end
        end
    end
    return out
end

------------------------------------------------------------------------------------------- support weapons --
-- The maximum rows of a team-reload weapon's own ammunition (HD2Runtime 0.31.0 teamReload.ownSpares)
local TEAM_RELOAD_NOTES={
    ['magazine.spare_magazines']='Most own spares (0 natively); the reload uses them before the backpack',
    ['rounds.spare_rounds']='Most own rounds (0 natively); each reload takes a 5-round clip from them before the '
        ..'backpack (multiples of 5 recommended)'}
-- A feed's in-game name as a section label: FLAK -> Flak, CLUSTER BOMB -> Cluster Bomb; short ones (HE) stay as they are.
-- Notes on a support weapon's status slots (Status applied), by weapon: shown where the status is picked.
local STATUS_SLOT_NOTE={['TX-41 Sterilizer']={needs='acid_splash',
    text='Acid splash and Acid stream (acid_splash, acid_stream) are available for the spray too'}}
local function feed_title(text)
    return(tostring(text):gsub('%S+',function(word)
        if#word<=3 then return word:upper()end
        return word:sub(1,1):upper()..word:sub(2):lower()
    end))
end
-- The swap a support weapon's field follows (its swap_scope), by the record its linkage reaches: the attack's projectile,
-- its damage, its impact or expiry explosion and their statuses ('attack:<role>'), or the ProgrammableAmmo projectile's
-- ('function:programmable'). The Runtime resolves those records through the projectile the weapon fires, so after a
-- swap it refuses them (COMPOSITION_TARGET_CHANGED or a changed record identity).
local function support_fires(f)
    local b=type(f.backing)=='table'and f.backing or{}
    local link=b.linkage=='status'and b.parentLinkage or b.linkage
    if type(link)~='string'then return nil end
    if link:find('^function_projectile')then return 'function:programmable'end
    if link=='projectile'or link=='projectile_damage'or link:find('^projectile_explosion')then
        local role=b.parentRole or tostring((type(f.target)=='table'and f.target.attack)or'primary'):gsub('_status_%d+$','')
        return 'attack:'..role
    end
    return nil
end
-- HD2Runtime 0.31.2 (docs/explosions.md "Payloads on support weapons"): a support weapon's impact and expiry payload
-- slots, hd2.fields.terminal.explosion on attack(role):projectile():terminal_action(phase), one per projectile row an
-- attack fires (the AC-8's HE round and its flak, the Epoch's charge levels, the SG-88's rounds feed), shown like the
-- primaries' (editor/catalog.lua "What a payload slot sets off"): in the section of the round's explosion
-- ("Explosion · Primary impact", "Explosion · Flak · Impact"), first in it. The rows of the explosion the slot sets off
-- natively (by its settings record, referenceSettings) are moved into the slot's section, so they are the slot's own
-- explosion rows; a slot whose explosion another slot already holds (the GL-21's expiry is its impact explosion) keeps
-- a section of its own. A slot the Runtime refuses (the missiles' expiry: fieldRefusals) is shown read-only with its
-- reason. `rows` are the support weapon's rows so far; returns the new rows.
local function payload_section(role,phase,role_text)
    if role=='programmable'then return join('Explosion',role_text(role),util.humanize(phase))end
    return join('Explosion',util.humanize(role..'_'..phase))
end
local function payload_note(f)
    local p=type(f.payload)=='table'and f.payload or{}
    local notes={}
    for _,n in ipairs(type(p.notes)=='table'and p.notes or{})do notes[#notes+1]=tostring(n)end
    return#notes>0 and table.concat(notes,' ')or nil
end
local function support_payload_rows(hd2,object,entry,rows,role_text)
    local name=entry.name
    local out,claimed={},{}
    local ids={}
    -- (impact slots first: an explosion both phases set off natively, the RL-77 cluster round's, is the impact's)
    local fields={}
    for _,phase in ipairs({'impact','expiry'})do
        for _,f in ipairs(entry.fields or{})do
            local t=type(f.target)=='table'and f.target or{}
            if f.type=='explosion_reference'and t.path=='terminal_action'and not f.deprecated and t.phase==phase then
                fields[#fields+1]=f
            end
        end
    end
    for _,f in ipairs(fields)do
        local t=f.target
        do
            local ok,row=pcall(function()
                local role,phase=t.attack or'primary',t.phase
                local terminal=function()return hd2.support_weapon(name):attack(role):projectile():terminal_action(phase)end
                if not builds(terminal)then return nil end
                local none=(type(f.currentDefault)=='table'and f.currentDefault.explosionType or 0)==0
                local expect=function()
                    local h=terminal()
                    if type(h.current)=='function'then return h:current()end
                    if none then return h:no_explosion()end
                    return h:explosion()
                end
                local okv,vanilla=pcall(expect)
                if not okv then return nil end
                local section=payload_section(role,phase,role_text)
                -- the rows of the explosion it sets off natively, moved into its section (once)
                local ref=type(f.referenceSettings)=='table'and tonumber(f.referenceSettings.row)
                local own
                for _,r in ipairs(ref and rows or{})do
                    if not r.group and tonumber(tostring(r.loc):match('^settings/explosion/(%d+)@'))==ref then
                        own=tostring(r.section):gsub(' · Status$','');break
                    end
                end
                if own and not claimed[own]then
                    claimed[own],claimed[section]=true,true
                    if own~=section then
                        for _,r in ipairs(rows)do
                            if r.section==own then r.section=section
                            elseif r.section==own..' · Status'then r.section=section..' · Status'end
                        end
                    end
                end
                local row=make_value_row(object,{id=f.semanticFieldId..'@'..role,kind='reference',
                    label=PAYLOAD_LABELS[phase],field='terminal.explosion',target=terminal,expect=expect,vanilla=vanilla,
                    shared=shared_ack(f),unverified=true,descriptor=f,section=section,fires_scope=support_fires(f),
                    note=payload_note(f),options=function(r)return explosion_options(hd2,r)end})
                row.swap={kind='terminal',role=role,phase=phase}
                if f.editable==false then
                    row.editable,row.reason=false,tostring(f.reason or'read-only in this HD2Runtime')
                end
                return row
            end)
            if ok and row then out[#out+1]=row;ids[f.semanticFieldId]=true end
        end
    end
    -- the payloads HD2Runtime does not offer, with its reason (the missiles' expiry, the W.A.S.P.'s own missile)
    local refusals=type(entry.fieldRefusals)=='table'and entry.fieldRefusals or{}
    for _,id in ipairs(util.sorted_keys(refusals))do
        local role,phase=tostring(id):match('^terminal%.(.+)%.(%a+)%.explosion$')
        if role and(phase=='impact'or phase=='expiry')and not ids[id]then
            local ok,section=pcall(payload_section,role,phase,role_text)
            if ok then
                out[#out+1]=info_row(object,{id=id..'@'..role..'@refused',label=PAYLOAD_LABELS[phase],section=section,
                    text=PAYLOAD_LABELS.not_offered,reason=util.plain(tostring(refusals[id]),300),
                    target=function()return hd2.support_weapon(name)end})
            end
        end
    end
    return out
end
local function support_rows(hd2,object,entry)
    entry=refill_entry(object,entry)
    local rows={}
    local name=entry.name
    -- HD2Runtime 0.31.1: the rows of the native ProgrammableAmmo projectile (role 'programmable') carry the feed's own
    -- name, the AC-8's FLAK, the GR-8's HE, the RL-77's CLUSTER BOMB
    local feed_name
    local function role_text(role)
        if role~='programmable'then return role_label(role)end
        if feed_name==nil then
            local ok,d=pcall(function()return hd2.support_weapon(name):feed('programmable'):describe()end)
            local shown=ok and type(d)=='table'and type(d.presentation)=='table'and d.presentation.displayName
            feed_name=type(shown)=='string'and shown~=''and feed_title(shown)or'Programmable ammo'
        end
        return feed_name
    end
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
                section=join(DOMAIN_LABELS[domain_of(field)]or'Projectile',role_text(role))
                if domain_of(field)=='damage'then section=join('Damage',direct_hit(role_text(role)))end
                -- HD2Runtime 0.31.1: the hit of the missile the weapon spawns (Spear, Commando, W.A.S.P.), apart from
                -- its impact explosion
                if f.missileHit then section=join('Damage','Missile direct hit')end
            elseif t.path=='explosion'then
                target=function()return hd2.support_weapon(name):attack(role):explosion()end
                field=strip(id,role)
                section=join('Explosion',role_text(role))
            elseif t.path=='attack'then
                target=function()return hd2.support_weapon(name):attack(role)end
                field=strip(id,role)
                section=join(DOMAIN_LABELS[domain_of(field)]or util.humanize(domain_of(field)),role_text(role))
            else
                target=function()return hd2.support_weapon(name)end
                field=id
                section=domain_label(id)
            end
            local common={id=id..(role and('@'..role)or''),label=f.displayName,unit=f.unit,field=field,target=target,
                shared=shared_ack(f),unverified=unverified(f),descriptor=f,section=section,fires_scope=support_fires(f),
                note=FIELD_NOTES[id]}
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
    if object.refill_only then return rows end
    -- HD2Runtime 0.31.0: its projectile swaps (projectile_source(role)), its beam swap (beam_source()) and its
    -- overcharge explosion (its own, or another charge weapon's)
    local base_code='hd2.support_weapon('..string.format('%q',name)..')'
    local swapped={}
    for _,f in ipairs(entry.fields or{})do
        local t=f.target or{}
        if f.type=='projectile_reference'and t.path=='attack'and not f.deprecated then
            -- (a swap HD2Runtime publishes read-only is shown locked with its reason, where a player looks for it)
            local role=t.attack or'primary'
            swapped[role]=true
            local row=source_row(object,{id='attack.projectile@'..role,label='Projectile',
                section=join('Projectile',role_label(role),'Swap'),descriptor=f,field='attack.projectile',
                code=base_code..':projectile_source('..string.format('%q',role)..')',swap_scope='attack:'..role,
                source=function()return hd2.support_weapon(name):projectile_source(role)end,
                options=function(row)return projectile_options(hd2,row)end,own_label='Own projectile',
                    note=f.missileProjectileNote})
            if not f.editable and row.editable then
                row.editable,row.reason=false,tostring(f.reason or'read-only in this HD2Runtime')
                row.vanilla,row.kind,row.labels='own','reference',{{value='own',label='Own projectile'}}
            end
            rows[#rows+1]=row
        elseif f.editable and f.type=='beam_reference'then
            rows[#rows+1]=source_row(object,{id='attack.beam',label='Beam',section='Beam · Swap',descriptor=f,
                field='attack.beam',code=base_code..':beam_source()',
                source=function()return hd2.support_weapon(name):beam_source()end,
                options=function(row)return beam_options(hd2,row)end,own_label='Own beam'})
        elseif f.editable and f.type=='overcharge_explosion_reference'and type(f.allowedValues)=='table'then
            local labels={}
            for _,v in ipairs(f.allowedValues)do labels[#labels+1]={value=v,label=v==name and('Own ('..v..')')or v}end
            rows[#rows+1]=make_value_row(object,{id=f.semanticFieldId,kind='choice',label=f.displayName or'Overcharge explosion',
                field=f.semanticFieldId,target=function()return hd2.support_weapon(name)end,vanilla=f.currentDefault,
                labels=labels,options=static_options(labels),descriptor=f,unverified=true,section='Charge'})
        end
    end
    -- A projectile host HD2Runtime keeps read-only publishes no swap field at all (HD2Runtime 0.31.2: the M-1000 Maxigun
    -- and the GL-28, linked-ammunition weapons whose fired type the trace does not prove; the magazine-pattern and
    -- rounds-fed weapons): its projectile_source() says why. Shown locked with that reason, where a player looks for it.
    if not swapped.primary then
        local ok,src=pcall(function()return hd2.support_weapon(name):projectile_source('primary')end)
        if ok and type(src)=='table'and src.status~=nil and not src.writable and type(src.reason)=='string'then
            local labels={{value='own',label='Own projectile'}}
            rows[#rows+1]=make_value_row(object,{id='attack.projectile@primary',kind='reference',label='Projectile',
                section='Projectile · Swap',field='attack.projectile',vanilla='own',labels=labels,
                options=static_options(labels),editable=false,reason=src.reason,
                target=function()return hd2.support_weapon(name)end})
        end
    end
    -- HD2Runtime 0.31.1: a native ProgrammableAmmo projectile (the AC-8's flak) is swapped on the weapon itself
    -- (feed('programmable'):source(): function_ammo.projectile); a weapon without one would need its function input
    -- bound first, which is not offered here
    for _,f in ipairs(entry.fields or{})do
        if f.editable and f.type=='function_projectile_reference'then
            local ok,d=pcall(function()return hd2.support_weapon(name):feed('programmable'):describe()end)
            if ok and type(d)=='table'and d.state=='native'then
                rows[#rows+1]=source_row(object,{id='function_ammo.projectile',label='Projectile',
                    section=join('Projectile',role_text('programmable'),'Swap'),descriptor=f,field='function_ammo.projectile',
                    swap_scope='function:programmable',
                    code=base_code..':feed("programmable"):source()',
                    source=function()return hd2.support_weapon(name):feed('programmable'):source()end,
                    options=function(row)return projectile_options(hd2,row)end,own_label='Own projectile',
                    note=f.missileProjectileNote})
            end
        end
    end
    -- HD2Runtime 0.31.1: the burst of that projectile (the AC-8's flak, the GR-8's HE), a catalogued explosion edited
    -- through hd2.explosion(name); 0.31.2: what its explosions spawn (the RL-77's bomblets, from both its rockets; the
    -- EAT-700's napalm shrapnel). A burst the weapon's own rows already reach (the RL-77's, which is its primary
    -- rocket's) is not shown twice.
    for _,r in ipairs(catalogue_explosion_rows(hd2,object,name,rows,{roles={function_impact=true},
        section=function(_,e,_,chained)
            if chained then return join('Explosion',chain_label(e))end
            return join('Explosion',role_text('programmable'))
        end}))do rows[#rows+1]=r end
    -- HD2Runtime 0.31.2: the impact and expiry payload slots of every projectile row an attack fires, per role and feed
    for _,r in ipairs(support_payload_rows(hd2,object,entry,rows,role_text))do rows[#rows+1]=r end
    -- the RL-77's cluster rocket hits with its main rocket's own DamageInfo row: said so where it is shown again
    same_hit_rows(name,rows)
    -- a hint on a status slot where a player looks for it (the slot's choices are the Runtime's, unchanged)
    local slot_note=STATUS_SLOT_NOTE[name]
    if slot_note then
        for _,r in ipairs(rows)do
            local offered={}
            for _,l in ipairs(r.kind=='choice'and r.labels or{})do offered[l.value]=true end
            if offered[slot_note.needs]and tostring(r.field):find('status_%d+_type$')and not r.note then
                r.note=slot_note.text
            end
        end
    end
    -- HD2Runtime 0.30.2: a team-reload weapon's own ammunition rows the Runtime flags noEffect are shown locked with
    -- the Runtime's reason, so nobody edits a value the game ignores (0.31.0: none are left; the GR-8, RL-77, FAF-14
    -- and StA-X3 own spares and, since the 0.31.0 rc2, the AC-8's own rounds are real fields)
    for _,r in ipairs(rows)do
        local d=type(r.descriptor)=='table'and r.descriptor
        -- (the reason itself in the domain, {reason} in the SDK JSON)
        local why=d and(type(d.noEffect)=='table'and d.noEffect.reason or d.noEffect)
        if why and r.editable then
            r.editable,r.reason=false,'team-reload weapon, its backpack holds the ammunition (HD2Runtime: '
                ..util.plain(tostring(why),160)..')'
        elseif d and type(d.teamReload)=='table'and d.teamReload.ownSpares==true and not r.note then
            -- HD2Runtime 0.31.0: its own spares are used first, then the backpack; spawn and resupply are capped by
            -- the spare maximum (0 natively). The AC-8 counts rounds (a reload takes a 5-round clip)
            r.note=TEAM_RELOAD_NOTES[r.field]or(tostring(r.field):find('^rounds%.')
                and'Capped by Spare rounds (0 natively); the reload uses own rounds before the backpack'
                or'Capped by Spare magazines (0 natively); the reload uses own spares before the backpack')
        end
    end
    return place_after(rows)
end

-- Damage zone sections of vehicles, backpacks (and their linked drone or shield) and stratagems' deployed entities: the
-- zone's native name when the Runtime's entity data carries one (entity_authoring zones[id].name, stratagem_authoring
-- damageZones[].name: "cockpit_rear" -> "Cockpit rear"), else "Zone N"; a name two zones of the entity share gets the
-- zone number. Shown through L() like every section. (Enemy pages keep their own labels.)
local function zone_namer(zones)
    local names,count={},{}
    for key,z in pairs(type(zones)=='table'and zones or{})do
        if type(z)=='table'and type(z.name)=='string'and z.name~=''then
            local id=z.zoneId or key
            local label=util.humanize(z.name)
            names[id]=label
            count[label]=(count[label]or 0)+1
        end
    end
    return function(zone)
        local label=names[zone]
        if label and count[label]>1 then label=label..' ('..util.humanize(zone)..')'end
        return label or util.humanize(zone or'')
    end
end
M.zone_namer=zone_namer

------------------------------------------------------------------------------------------------ stratagems --
local PATH_LABELS={stratagem='Call-in',eagle_rearm='Eagle Rearm',deployed_entity='Deployed Entity',shield='Shield',
    turret='Turret',targeting='Targeting',minefield='Minefield',weapon='Mounted Weapon'}
-- Read-only choices shown locked with the Runtime's reason (HD2Runtime 0.31.0: the Eagles' rearm pool)
local READ_ONLY_CHOICES={['stratagem.rearm_pool']=true}
-- A mounted weapon's field section: 'Mounted Weapon', or 'Mounted Weapon · Heat' (Wind-up, Beam, Handling ...)
local function mounted_section(id)
    local label=domain_label(id)
    if label=='Weapon'then return 'Mounted Weapon'end
    return join('Mounted Weapon',label)
end
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
    local zone_name=zone_namer(entry.damageZones)
    -- in the Eagle Rearm pool (the Eagles): its uses are charges, never unlimited (REARM_POOL_UNLIMITED)
    local pooled=false
    for _,f in ipairs(entry.fields or{})do
        if f.semanticFieldId=='stratagem.rearm_pool'and(f.currentDefault==49 or f.currentDefault=='eagle_rearm')then
            pooled=true
        end
    end
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
            if pooled and vanilla~='unlimited'then unlimited=false end
            rows[#rows+1]=make_value_row(object,{id=f.instanceKey or'stratagem.max_uses',kind='uses',
                label='Mission uses (next launch)',field=f.semanticFieldId,target=stratagem_target(hd2,name,t),
                vanilla=vanilla,descriptor=f,section='Call-in',min=f.min or 1,max=f.max or 100,unlimited=unlimited,
                unverified=unverified(f),note=f.caveat or'Apply on the ship before launch. Current mission counters keep their old uses.',
                labels={{value='unlimited',label='Unlimited'}}})
        elseif f.type=='enum'and type(f.allowedValues)=='table'and(f.editable or READ_ONLY_CHOICES[f.semanticFieldId])then
            -- (an option's own label first: the rearm pool's 'Own cooldown (mission uses)')
            local labels={}
            for _,v in ipairs(f.allowedValues)do
                if type(v)=='table'then
                    labels[#labels+1]={value=v.value,label=v.label or util.humanize(v.name or tostring(v.value))}
                else labels[#labels+1]={value=v,label=tostring(v)}end
            end
            local target=stratagem_target(hd2,name,t)
            if target then
                -- HD2Runtime 0.31.0 stratagem.rearm_pool: joining the Eagle Rearm pool needs a finite use count (the
                -- Runtime refuses REARM_POOL_UNLIMITED); read-only on the Eagles, with the Runtime's reason
                local note=f.semanticFieldId=='stratagem.rearm_pool'and f.editable
                    and'Eagle Rearm pool: Mission uses become charges and must be a number, not unlimited'or nil
                rows[#rows+1]=make_value_row(object,{id=f.instanceKey or(f.semanticFieldId..'@'..tostring(t.path)),
                    kind='choice',label=f.displayName,field=f.semanticFieldId,target=target,vanilla=f.currentDefault,
                    descriptor=f,section=PATH_LABELS[t.path]or util.humanize(t.path or''),labels=labels,
                    options=static_options(labels),shared=shared_ack(f),unverified=unverified(f),note=note,
                    editable=f.editable==true,reason=not f.editable and tostring(f.reason or'read-only')or nil})
            end
        elseif f.editable and numeric(f.type,f.currentDefault)then
            local target=stratagem_target(hd2,name,t)
            if target then
                local section=PATH_LABELS[t.path]
                local group
                if t.path=='weapon'then section=mounted_section(f.semanticFieldId)
                elseif t.path=='damage_zone'then section=zone_name(t.zone);group='Damage Zones'
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
    -- HD2Runtime 0.31.0: the rearm pool and the mission uses depend on each other (a pool member keeps a finite use
    -- count, REARM_POOL_UNLIMITED): the layer orders their ensures (editor/layer.lua rearm_wait)
    local uses,pool
    for _,r in ipairs(rows)do
        if r.editable and r.field=='stratagem.max_uses'then uses=r end
        if r.editable and r.field=='stratagem.rearm_pool'then pool=r end
    end
    if uses and pool then pool.uses_row,uses.pool_row=uses,pool end
    return rows
end
M.EAGLE_REARM=49

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
-- A vehicle's mounts by what they are (the Runtime names them by their mount node or slot only: "slot_3"): the
-- TD-110 Maelstrom's two pods fire the MLS-4X Commando's seeking missile. Unlisted mounts keep the humanized node name.
local MOUNT_LABELS={
    ['TD-110 Maelstrom']={attach_tank_gun='Main cannon',slot_0='Main cannon',slot_2='Driver gun',
        slot_3='Missile pods (slot 3)',slot_4='Missile pods (slot 4)'},
    ['TD-220 Bastion MK XVI']={attach_tank_gun='Cannon',attach_tank_gun_mg='Coaxial MG',slot_0='Cannon',
        slot_1='Coaxial MG'}}
local function mount_label(vehicle,mount,slot)
    local labels=MOUNT_LABELS[vehicle]or{}
    return labels[mount or'']or(slot~=nil and labels['slot_'..tostring(slot)])or util.humanize(mount or slot or'')
end
M.mount_label=mount_label
-- Notes on a vehicle weapon's field, by the weapon (vehicle_weapon_authoring key) and field.
local VW_NOTES={['TD-220 Bastion MK XVI / attach_tank_gun_mg']={
    ['weapon.capacity']='Single belt, no reload: at most 2047 rounds (the game\'s network limit)'}}
-- (the Runtime's own note is a paragraph; the status line shows this short form of it)
local VW_NO_RELOAD_NOTES={no_reload='No reload on this mount: expected to have no effect (HD2Runtime, not proven). '
    ..'Magazine capacity is its whole supply'}
local VW_NO_RELOAD_NOTE=VW_NO_RELOAD_NOTES.no_reload
local function vehicle_rows(hd2,object,entry)
    local rows={}
    local name=entry.name
    local zone_name=zone_namer(entry.zones)
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
                label=mount_label(name,info.role or slot,info.slot),field=f.semanticFieldId,descriptor=f,
                section='Mounted Weapons',
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
                section=zone_name(zone)
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
-- A field the Runtime marks dormant on this item ({kind='dormant', text}: the Hover Pack never reads the launch thrust)
local function dormant_notice(f)
    for _,n in ipairs(type(f.notices)=='table'and f.notices or{})do
        if type(n)=='table'and n.kind=='dormant'then return n.text or'the game does not read it on this item'end
    end
end
-- Hover Pack height (HD2Runtime 0.31.0, docs/backpack-authoring.md "How high the Hover Pack flies"): gravity keeps
-- acting while hovering, so the lift is what makes the pack climb; the duration is the climb window, not the hover time.
local HOVER_LABELS={['hover.vertical_acceleration_low_speed']='Lift (climbs when above 9.82)',
    ['hover.vertical_acceleration_high_speed']='Lift at high climb speed',
    ['hover.vertical_speed_range_end']='Lift fade speed',['hover.max_vertical_speed']='Max climb speed (cap only)',
    ['hover.duration']='Climb window (seconds in the air)'}
local function backpack_rows(hd2,object,entry,cat)
    local rows={}
    local name=entry.name
    if name=='B-1 Supply Pack'then
        local refill_note='These controls also affect ordinary resupply. Actual amounts are capped by capacity and may depend on attachments or armor.'
        local player=cat and cat:object('hd|Helldiver')
        if player then
            cat:open(player)
            for _,original in ipairs(player.rows or{})do
                if original.field=='helldiver.supply.stims_from_supply'then
                    local row=setmetatable({canonical=original,object=object,section='Player refill'},
                        {__index=original})
                    rows[#rows+1]=row
                end
            end
        end
        -- Canonical views: editing here is the same preset operation as editing
        -- the equipped item's own page, including its magazine attachments.
        for _,category in ipairs({'primary','secondary','throwables','support_weapons'})do
            for _,item in ipairs(cat and cat:objects(category)or{})do
                for _,original in ipairs(cat:refill_rows(item))do
                    local id=original.field or''
                    if original.editable and(id:match('from_supply$'))then
                        rows[#rows+1]=setmetatable({canonical=original,object=object,
                            section=join(util.display_name(item),original.section),group='Supplies delivered',note=refill_note},
                            {__index=original})
                    end
                end
            end
        end
    end
    local zone_names={}
    local function zone_name(linked,zone)
        local key=linked or''
        if not zone_names[key]then
            local zones=entry.zones
            if linked then zones=type(entry.linked)=='table'and type(entry.linked[linked])=='table'and entry.linked[linked].zones end
            zone_names[key]=zone_namer(zones)
        end
        return zone_names[key](zone)
    end
    -- the Hover Pack shares the jump packs' JumppackComponent: its jump.* landing and air-control members drive the
    -- hover flight too, so they are "Flight" there, not a "Jump Pack" section on a pack that cannot jump
    local hovers=false
    for _,f in ipairs(entry.fields or{})do
        if domain_of(f.semanticFieldId)=='hover'then hovers=true break end
    end
    for _,f in ipairs(entry.fields or{})do
        local t=f.target or{}
        if f.editable and numeric(f.type,f.currentDefault)then
            local target,section
            if t.path=='backpack'then
                target=function()return hd2.backpack(name)end
                section=(f.uiGroup and(UI_GROUPS[f.uiGroup]or util.humanize(f.uiGroup)))
                    or(f.semanticFieldId:match('^jump%.sustain_')and'Landing thrust')
                    or(hovers and domain_of(f.semanticFieldId)=='jump'and'Flight')
                    or domain_label(f.semanticFieldId)
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
                section=join(linked and util.humanize(linked)or nil,zone_name(linked,zone))
            end
            if target then
                rows[#rows+1]=make_row(object,{id=f.instanceKey or(f.semanticFieldId..'@'..tostring(t.path)),
                    label=HOVER_LABELS[f.semanticFieldId]or f.displayName,unit=f.unit,vanilla=f.currentDefault,
                    min=f.min,max=f.max,type=f.type,
                    storage=(f.backing or{}).storage,field=f.semanticFieldId,target=target,shared=shared_ack(f),
                    unverified=unverified(f),descriptor=f,section=section,
                    note=name=='B-1 Supply Pack'and'New packs use starting boxes (-1 = full). Resupply adds at least one box up to capacity. A pack cannot refill itself.'or nil,
                    group=t.path=='damage_zone'and'Damage Zones'or nil})
                -- shown locked with the Runtime's reason, so nobody edits a value the game ignores
                local why=dormant_notice(f)
                if why then
                    rows[#rows].editable,rows[#rows].reason=false,'no effect on this pack (HD2Runtime: '
                        ..util.plain(tostring(why),120)..')'
                end
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
    -- HD2Runtime 0.31.0: a mount that holds a shield arm, not a weapon (the EXO-55 Breakthrough's left mount) is
    -- reached through the vehicle's :shield(), never :weapon(mount)
    local shield=entry.mountedShield==true
    -- (a mount's swap and the rows that follow it, apart from the other mounts of the same page)
    local function mount_scope(scope)return scope and(tostring(entry.name)..'|'..scope)or nil end
    local function base()
        if drone then return hd2.backpack(carrier):drone():weapon()end
        if shield then return hd2.vehicle(carrier):shield()end
        return hd2.vehicle(carrier):weapon(mount)
    end
    for _,f in ipairs(entry.fields or{})do
        local t=f.target or{}
        -- a status a mount's attack or explosion applies (HD2Runtime status slots), as the primaries have it
        local status=f.type=='status_reference'and type(f.allowedValues)=='table'
        if f.editable and not f.derivedReadOnly and(numeric(f.type,f.currentDefault)or status)then
            local role=t.attack
            local target,section
            if t.path=='weapon'then
                target=base
                section=shield and'Shield'or domain_label(f.semanticFieldId)
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
                if status then
                    local labels={}
                    if f.allowNone then labels[1]={value='none',label='None'}end
                    for _,v in ipairs(f.allowedValues)do labels[#labels+1]={value=v,label=util.humanize(v)}end
                    rows[#rows+1]=make_value_row(object,{id=f.semanticFieldId..(role and('@'..role)or''),kind='choice',
                        label=f.displayName,field=field,target=target,vanilla=f.currentDefault,labels=labels,
                        options=static_options(labels),descriptor=f,shared=shared_ack(f),unverified=unverified(f),
                        section=join(section,'Status'),fires_scope=mount_scope(support_fires(f))})
                else
                    rows[#rows+1]=make_row(object,{id=f.semanticFieldId..(role and('@'..role)or''),label=f.displayName,
                        unit=f.unit,vanilla=f.currentDefault,min=f.min,max=f.max,type=f.type,
                        storage=(f.backing or{}).storage,field=field,target=target,shared=shared_ack(f),
                        unverified=unverified(f),descriptor=f,section=section,fires_scope=mount_scope(support_fires(f))})
                end
            end
        end
    end
    -- ModBuilder's identity (entityChanges: resource vehicle_weapon, entity = the weapon's catalogue name)
    local notes=VW_NOTES[entry.name]or{}
    for _,r in ipairs(rows)do
        r.mb_resource,r.mb_entity,r.mb_where='vehicle_weapon',entry.name,''
        if notes[r.field]and not r.note then r.note=notes[r.field]end
        -- HD2Runtime 0.31.3: a mount without a WeaponReload (the Bastion coax, the magazine Exosuit arms) flags its
        -- spare-magazine fields reloadComponent.present = false: writable, but expected to have no effect
        local reload=r.descriptor and r.descriptor.reloadComponent
        if type(reload)=='table'and reload.present==false and not r.note then r.note=VW_NO_RELOAD_NOTE end
    end
    -- Its projectile swap, as the primaries have it (HD2Runtime 0.30.x mounted projectile hosts: the EXO-45 Patriot
    -- minigun, both EXO-49 Emancipator autocannons, the EXO-51 Lumberer cannon, the FRV and GATER Oil Rig guns, the
    -- Guard Dog's gun), through the mount's projectile_source(). A mount that fires another way (the Patriot's rocket
    -- pod spawns missile entities, the Breakthrough's magazine picks its round) shows the Runtime's reason read-only;
    -- one with no projectile at all (a flamethrower) gets no row. Like the sentry swap, its target is a handle no hd2
    -- call chain builds, so the row carries the Lua that reaches it for the exporter.
    if shield then return rows end
    -- HD2Runtime 0.31.0 beam swaps on a mounted beam host (the Rover's laser: read-only with the Runtime's reason)
    for _,f in ipairs(entry.fields or{})do
        if f.type=='beam_reference'then
            local code=drone and('hd2.backpack('..string.format('%q',carrier)..'):drone():weapon():beam_source()')
                or('hd2.vehicle('..string.format('%q',carrier)..'):weapon('..string.format('%q',mount)..'):beam_source()')
            rows[#rows+1]=source_row(object,{id='attack.beam@mount',label='Beam',section='Beam · Swap',descriptor=f,
                field='attack.beam',code=code,source=function()return base():beam_source()end,
                options=function(row)return beam_options(hd2,row)end,own_label='Own beam'})
            break
        end
    end
    local ok,src=pcall(function()return base():projectile_source()end)
    if ok and type(src)=='table'and(src.writable or src.status)then
        local f
        for _,x in ipairs(entry.fields or{})do
            if x.type=='projectile_reference'and(x.target or{}).path=='attack'then f=x;break end
        end
        f=f or{type='projectile_reference',semanticFieldId='attack.projectile'}
        local function source()return base():projectile_source()end
        local code=drone and('hd2.backpack('..string.format('%q',carrier)..'):drone():weapon():projectile_source()')
            or('hd2.vehicle('..string.format('%q',carrier)..'):weapon('..string.format('%q',mount)..'):projectile_source()')
        local common={id='attack.projectile@mount',kind='reference',label='Projectile',field='attack.projectile',
            section='Projectile · Swap',descriptor=f,unverified=true,
            target=function()return source().target end,expect=function()return source().expect end,
            options=function(row)return projectile_options(hd2,row)end}
        if src.writable and src.expect then
            common.vanilla=src.expect
            common.swap_scope=mount_scope('attack:primary')
        else
            common.editable=false
            common.reason=tostring(src.reason or'read-only in this HD2Runtime')
            common.vanilla='own'
            common.labels={{value='own',label='Own round'}}
        end
        local row=make_value_row(object,common)
        row.target_code,row.expect_code=code..'.target',code..'.expect'
        rows[#rows+1]=row
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
    if path=='arc'then return function()return hd2.throwable(name):explosion():arc()end end
    return function()local th=hd2.throwable(name);return th[path](th)end
end
local function throwable_rows(hd2,object,entry)
    local rows={}
    local name=entry.name
    local paths=util.sorted_keys(entry.targets or{})
    for _,key in ipairs(paths)do
        local t=entry.targets[key]
        if not object.refill_only or t.path=='throwable'then
        local target=throwable_target(hd2,name,t)
        local section=t.label and join(util.humanize(t.path),t.label)or util.humanize(t.path or key)
        if t.path=='throwable'then section='Throwable'end
        if t.path=='arc'then section='Explosion Arc'end
        if t.path=='flight'then
            rows[#rows+1]=M.info_row(object,{id='flight:help',label='Launch controls',section=section,
                text='A positive speed override bypasses the curve',
                note='Curve: sqrt(18 * max(0, min + (max-min) * strength)). Movement adjusts strength. '
                    ..'Spin uses native angular-velocity units; a zero minimum vector disables spin setup. '
                    ..'These controls do not set trajectory gravity or drag.'})
        end
        if t.path=='shield'then
            rows[#rows+1]=M.info_row(object,{id='shield:help',label='Recharge',section=section,
                text='Set a positive recharge rate to enable regeneration',
                note='The native rate is zero. Delays alone do not enable recharge; the deployed device still has its own expiry timer.'})
        end
        for _,id in ipairs(util.sorted_keys(t.fields or{}))do
            local f=t.fields[id]
            if not object.refill_only or id:match('from_supply$')then
            local min,max,integer=range_of(f)
            -- HD2Runtime 0.31.1: the explosion's status slots (each used slot's status, and the first empty slot's
            -- status and strength), as the primaries have them
            local slot_section=f.statusSlot and join(section,'Status')or section
            if f.editable and f.type=='explosion_reference'then
                local function value()return f.currentDefault=='none'and'none'or hd2.explosion(f.currentDefault)end
                local row=make_value_row(object,{id=f.instanceKey,kind='reference',label='Explosion payload',
                    field=f.semanticFieldId,target=target,expect=value,vanilla=value(),
                    shared=shared_ack(f),unverified=true,unverified_reference=true,descriptor=f,section='Explosion',
                    note='Changes the native detonation payload. Separate scripted pulses and lingering effects may still occur.'})
                row.options=function()return payload_options(row)end
                row.throwable_payload=true
                rows[#rows+1]=row
            elseif f.editable and f.type=='explosion_payload'then
                local options={}
                for _,name in ipairs(f.allowedValues or{})do
                    local handle=hd2.explosion(name);local info=handle:describe()
                    options[#options+1]={value=handle,label=info.label,
                        acks={allow_shared=true,allow_unverified_effect=true,allow_unverified_reference=true}}
                end
                local vanilla=hd2.explosion(f.currentDefault)
                rows[#rows+1]=make_value_row(object,{id=f.instanceKey,kind='reference',label='Pulse explosion payload',
                    field=f.semanticFieldId,target=target,expect=function()return hd2.explosion(f.currentDefault)end,vanilla=vanilla,
                    shared=true,unverified=true,unverified_reference=true,descriptor=f,section='Pulse payload',
                    options=function()return options end,
                    note='Replaces the pulse definition for all Urchins; keeps sticking and repeated discharges. '
                        ..'Choose the Epoch impact payload for its small plasma burst. Original explosion edits can conflict with this override.'})
            elseif f.editable and f.type=='status_reference'and type(f.allowedValues)=='table'then
                local labels={}
                if f.allowNone then labels[1]={value='none',label='None'}end
                for _,v in ipairs(f.allowedValues)do labels[#labels+1]={value=v,label=util.humanize(v)}end
                rows[#rows+1]=make_value_row(object,{id=f.instanceKey or(key..':'..id),kind='choice',
                    label=f.displayName,field=f.semanticFieldId or id,target=target,vanilla=f.currentDefault,
                    labels=labels,options=static_options(labels),descriptor=f,shared=shared_ack(f),
                    unverified=unverified(f),section=slot_section})
            elseif f.editable and numeric(f.type,f.currentDefault)then
                rows[#rows+1]=make_row(object,{id=f.instanceKey or(key..':'..id),label=f.displayName,unit=f.unit,
                    vanilla=f.currentDefault,min=min,max=max,type=integer and'integer'or f.type,
                    storage=(f.backing or{}).storage,field=f.semanticFieldId or id,target=target,
                    shared=shared_ack(f),unverified=unverified(f),descriptor=f,section=slot_section})
            end
        end
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
            rows[#rows+1]=make_row(object,{id=field_id,label=label,unit=f.unit or(field_id=='attachment.reload_duration'and'seconds'),
                vanilla=f.currentDefault,min=f.min,max=f.max,
                type=INTEGER_STORAGE[f.storage or'']and'integer'or'number',storage=f.storage,field=field_id,
                target=function()return hd2.weapon_attachment(id)end,shared=true,unverified=true,descriptor=f,
                section=util.humanize(entry.slot or'magazine')})
        end
    end
    if entry.kind=='heatsink'and#rows==0 then
        rows[#rows+1]=info_row(object,{id='attachment.inherited',label='Uses weapon values',
            text='Inherited',info=true,reason='Uses the weapon base heat and heatsink values.'})
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

------------------------------------------------------------------------------------------- beam conversion --
-- HD2Runtime beam conversion (0.31.0; docs/beam-conversion.md), feature-detected: a projectile weapon
-- made to fire LAS-13 Trident pulses, through hd2.beam_conversion(name). Rows of a "Beam Conversion" group on the
-- weapon: the verdict and caveats (a refused weapon shows only its reason), the layout and its multiplayer rule, the
-- enable toggle, its own rate / beams / pulse and the interim per-weapon damage, AP and range rows. Every request needs
-- allow_component_swap and allow_unverified_effect. Not a plan operation: the layer writes each field as its own
-- ensure (settings only once the conversion is on, editor/layer.lua), and the exporter writes one transaction per
-- weapon (editor/export.lua). Without the API (HD2Runtime 0.30.3 and older) a weapon gets no such rows.
local CONVERSION_VERDICTS={supported='Supported',supported_with_caveats='Supported with caveats',refused='Refused',
    out_of_scope='Out of scope'}
local conversion_index
local function conversion_entry(name)
    if conversion_index==nil then
        local C=load('beam_conversion')
        conversion_index=false
        if C and type(C.weapons)=='table'and type(C.fields)=='table'then
            conversion_index={module=C,by_name={}}
            for _,w in ipairs(C.weapons)do if type(w)=='table'and w.name then conversion_index.by_name[w.name]=w end end
        end
    end
    return conversion_index and conversion_index.by_name[name],conversion_index and conversion_index.module
end
M.conversion_entry=conversion_entry
local CONVERSION_GROUP='Beam Conversion'
local function beam_conversion_rows(cat,object,name)
    if object.refill_only then return {}end
    if type(cat.real_hd2)~='table'or type(cat.real_hd2.beam_conversion)~='function'then return {}end
    local w,C=conversion_entry(name)
    -- not a projectile weapon, or already a beam: nothing to convert, nothing to show
    if not w or w.verdict=='out_of_scope'then return {}end
    local hd2=cat.hd2
    local target=function()return hd2.beam_conversion(name)end
    local rows={}
    local section=CONVERSION_GROUP
    local function info(id,label,text,reason)
        rows[#rows+1]=info_row(object,{id='bc:'..id,label=label,text=text,reason=reason,section=section,
            field='beam_conversion.'..(id:match('^[%a_]+')or'info'),
            group=CONVERSION_GROUP,info=true,target=target})
    end
    local verdict=(CONVERSION_VERDICTS[w.verdict]or util.humanize(tostring(w.verdict)))
        ..(w.layout and(' · '..w.layout..' layout')or'')
    info('verdict','Verdict',verdict,(w.reasonCode and(w.reasonCode..': ')or'')..tostring(w.reason or''))
    if not w.supported then return rows end
    for i,c in ipairs(type(w.caveats)=='table'and w.caveats or{})do
        info('caveat:'..i,'Caveat: '..util.humanize(tostring(c.code or i):lower()),'Caveat',tostring(c.text or c.code))
    end
    local add=w.layout=='add'
    info('layout','Layout',add and'Add: identical lobbies only'or'Swap: solo only, then restart',
        add and('Add layout: the weapon keeps its projectile component (type 0) and gains a beam. With other players '
            ..'only when every member runs HD2Runtime holding the identical conversion; a player without it sees '
            ..'bullets where you see beams.')
        or('Swap layout: the projectile component is swapped for a beam. Solo only (refused with other players: a '
            ..'remote weapon of this type would crash the game). Restart the game after using it.'))
    info('unequip','Before changing it','Unequip first','Writes wait until no instance of this weapon exists on this '
        ..'machine (ship preview, armory, loadouts, pickups, other players\' weapons): equip another weapon, keep the '
        ..'armory closed, change it, wait until it applies, then equip it.')
    local enabled
    local settings={}
    for _,f in ipairs(C.fields)do
        local common={id='bc:'..tostring(f.id),label=f.displayName,unit=f.unit,field=f.id,target=target,
            component_swap=true,unverified=true,group=CONVERSION_GROUP}
        local row
        if f.type=='boolean'then
            common.kind,common.vanilla,common.labels='choice',f.default==true,bool_labels()
            common.options=static_options(common.labels)
            common.section=section
            common.note=add and'Solo, or a lobby where everyone has the identical conversion; unequip the weapon first'
                or'Solo only; unequip the weapon first; restart the game after using it'
            row=make_value_row(object,common)
            enabled=enabled or row
        elseif type(f.default)=='number'then
            common.vanilla,common.min,common.max,common.type,common.storage=f.default,f.min,f.max,f.type,f.storage
            if f.perWeapon then
                common.section=join(CONVERSION_GROUP,'Per-weapon rows (interim, max 6)')
                common.note='Interim: one of 6 borrowed rows (solo, this game build); turn the conversion on first'
            else
                common.section=join(CONVERSION_GROUP,'Rate and pulse')
                common.note=f.id=='beam.pulse_seconds'
                    and'Caps the fire rate: 600 rpm needs at most 0.067 s, 900 rpm 0.033 s (a pulse starts after the last one ended)'
                    or f.id=='beam.fire_rate'and'Turn the conversion on first; without a pulse change the pulse is fitted to the rate'
                    or'Turn the conversion on first'
            end
            row=make_row(object,common)
            settings[#settings+1]=row
        end
        if row then
            -- one descriptor per field for every weapon: identity by the row's own key, not by the shared table
            row.descriptor,row.no_inspect,row.conversion=f,true,name
            rows[#rows+1]=row
        end
    end
    if enabled then
        enabled.conversion_rows=settings
        for _,r in ipairs(settings)do r.conversion_enabled=enabled end
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
-- The catalogue explosions an object sets off itself (owner role 'behavior': a Hellbomb's detonation) and what they
-- spawn, as "Explosion · Detonation" rows.
local function detonation_rows(hd2,object,name,rows)
    return catalogue_explosion_rows(hd2,object,name,rows,{roles={behavior=true},
        section=function(_,e,_,chained)return join('Explosion',chained and chain_label(e)or'Detonation')end})
end
-- Objects that are only their explosion (the NUX-223 Hellbomb: a mission stratagem the Runtime has no stratagem data
-- for, whose detonation the explosion catalogue holds). Listed only when the installed Runtime catalogues it.
local EXPLOSION_OBJECTS={{name='NUX-223 Hellbomb',explosion='stratagem/nux223_hellbomb/behavior',
    subtitle='Mission stratagem',detail='its explosion'}}

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
        for id,entry in pairs(by_slot[g.key]or{})do list[#list+1]={id=id,entry=entry,group=entry.kind=='heatsink'and'Heatsinks'or g.label}end
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
            -- (an empty slot is 'empty', which is not a pickup: hd2.pickup('empty') raises, and every empty slot was
            -- left out, the EAT-411's active second slot too)
            local expect=function()
                if current and current~='empty'then return hd2.pickup(current)end
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
                        append(rows,beam_conversion_rows(cat,object,name))
                        for _,m in ipairs(weapon_attachments(name))do
                            local label=util.plain((m.entry.name or m.id):gsub('%s+',' '),60)
                            append(rows,part_rows(object,'mag:'..m.id,function(proxy)
                                return attachment_rows(cat.hd2,proxy,m.entry)
                            end,function(row)row.group=m.group;row.section=label;row.derived_context=m.id end))
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
-- A sentry's or emplacement's projectile swap (HD2Runtime 0.30.2): its deployed entity's ProjectileWeapon record,
-- through hd2.stratagem(name):attack('primary'):projectile_source() (the host '<name> / weapon' in
-- vehicle_weapon_authoring). The target is a handle no hd2 call chain builds, so the row carries the Lua that reaches it
-- (target_code / expect_code) for the exporter and the ModBuilder import. MG-43 and G-16 stay read-only with the reason.
local function sentry_swap_rows(hd2,object,name)
    local VW=load('vehicle_weapon_authoring')
    local host=VW and type(VW.weapons)=='table'and VW.weapons[name..' / weapon']
    if not host or host.stratagemHost~=name then return {}end
    local rows={}
    local attack='hd2.stratagem('..string.format('%q',name)..'):attack("primary")'
    local function primary()return hd2.stratagem(name):attack('primary')end
    local beam=false
    for _,f in ipairs(host.fields or{})do if f.type=='beam_reference'then beam=true end end
    for _,f in ipairs(host.fields or{})do
        if f.type=='projectile_reference'then
            rows[#rows+1]=source_row(object,{id='attack.projectile@stratagem',label='Projectile',section='Projectile · Swap',
                descriptor=f,field='attack.projectile',code=attack..':projectile_source()',
                source=function()return primary():projectile_source()end,
                options=function(row)return projectile_options(hd2,row)end,own_label='Own round'})
        elseif f.type=='beam_reference'then
            -- HD2Runtime 0.31.0: the Laser Sentry fires any catalogued beam
            rows[#rows+1]=source_row(object,{id='attack.beam@stratagem',label='Beam',section='Beam · Swap',descriptor=f,
                field='attack.beam',code=attack..':beam_source()',source=function()return primary():beam_source()end,
                options=function(row)return beam_options(hd2,row)end,own_label='Own beam'})
        elseif f.editable and not f.derivedReadOnly and numeric(f.type,f.currentDefault)and(f.target or{}).path=='weapon'then
            -- the host's own record (the Laser Sentry's beam fire mode and pulse), the target its source names
            local via=beam and':beam_source()'or':projectile_source()'
            local row=make_row(object,{id=f.semanticFieldId..'@stratagem',label=f.displayName,unit=f.unit,
                vanilla=f.currentDefault,min=f.min,max=f.max,type=f.type,storage=(f.backing or{}).storage,
                field=f.semanticFieldId,target=function()
                    local a=primary()
                    return(beam and a:beam_source()or a:projectile_source()).target
                end,shared=shared_ack(f),unverified=true,descriptor=f,section=mounted_section(f.semanticFieldId)})
            row.target_code=attack..via..'.target'
            rows[#rows+1]=row
        end
    end
    return rows
end
local function stratagem_category(families,subtitles)
    return function(cat)
        local ST,why=load('stratagem_authoring')
        if not ST then return nil,why end
        local list={}
        for name,entry in pairs(ST.stratagems or{})do
            if families[entry.family]then
                list[#list+1]={key='st|'..name,name=name,subtitle=subtitles[entry.family]or util.humanize(entry.family),
                    build=function(object)
                        return append(stratagem_rows(cat.hd2,object,entry),sentry_swap_rows(cat.hd2,object,name))
                    end}
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
                if stratagem and not object.refill_only then append(rows,part_rows(object,'st',function(p)return stratagem_rows(cat.hd2,p,stratagem)end))end
                append(rows,part_rows(object,'sw',function(p)return support_rows(cat.hd2,p,weapon)end))
                append(rows,beam_conversion_rows(cat,object,name))
                if backpack and not object.refill_only then
                    append(rows,part_rows(object,'bp',function(p)return backpack_rows(cat.hd2,p,backpack,cat)end,
                        function(row)if not row.group then row.section=join('Backpack',row.section)end end))
                end
                if rack and not object.refill_only then append(rows,part_rows(object,'pod',function(p)return pod_rows(cat.hd2,p,rack)end))end
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
                    if backpack then append(rows,part_rows(object,'bp',function(p)return backpack_rows(cat.hd2,p,backpack,cat)end))end
                    for _,d in ipairs(drones)do
                        append(rows,part_rows(object,'vw:'..(d.entry.mount or'gun'),function(p)
                            return vehicle_weapon_rows(cat.hd2,p,d.entry)end,
                            function(row)row.group='Drone Weapon';row.vw_key=d.key end))
                    end
                    if rack then append(rows,part_rows(object,'pod',function(p)return pod_rows(cat.hd2,p,rack)end))end
                    -- the explosion it sets off (the B-100 Portable Hellbomb's detonation)
                    append(rows,part_rows(object,'ex',function(p)return detonation_rows(cat.hd2,p,name,rows)end))
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
                    local what=mount_label(name,m.entry.mount or m.key,m.entry.slot)
                    local label='Weapon · '..what
                    if m.entry.mountedShield then label='Shield · '..what end
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
-- Mission stratagems: Resupply and its pod; the NUX-223 Hellbomb's explosion (HD2Runtime explosion catalogue).
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
    local explosions=type(cat.real_hd2.explosion)=='function'and explosion_api()
    for _,x in ipairs(explosions and EXPLOSION_OBJECTS or{})do
        if explosions.explosions[x.explosion]and not ST.stratagems[x.name]then
            local name=x.name
            list[#list+1]={key='ex|'..name,name=name,subtitle=x.subtitle,detail=x.detail,
                build=function(object)return detonation_rows(cat.hd2,object,name,{})end}
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
-- Preserve legacy me|... row keys so saved sessions/presets keep targeting the same native fields.
-- Their object is now the weapon's normal armory page, with its ordinary icon and category.
local function melee_entry(name)
    local D=load('melee_authoring')
    return D and D.entries and D.entries[name]
end
local function melee_rows(hd2,host)
    local name=host.name
    local e=melee_entry(name)
    if not e then return {}end
    local object=setmetatable({key='me|'..name},{__index=host})
                local rows={}
                for _,key in ipairs(util.sorted_keys(e.targets))do
                    local t=e.targets[key]
                    local target=function()
                        local m=hd2.melee(name)
                        return key=='tuning'and m or m:zone(key)
                    end
                    if t.consumers then
                        rows[#rows+1]=M.info_row(object,{id=key..':scope',label='Shared with',section=t.label or'Melee',
                            text=tostring(#t.consumers)..' weapons',note=table.concat(t.consumers,', ')})
                    end
                    for _,id in ipairs(util.sorted_keys(t.fields))do
                        local f=t.fields[id]
                        rows[#rows+1]=make_row(object,{id=key..':'..id,field=id,label=f.displayName,unit=f.unit,
                            vanilla=f.currentDefault,min=f.min,max=f.max,type=f.type,storage=f.backing.storage,
                            target=target,descriptor=f,shared=f.shared,unverified=true,editable=f.editable,
                            exact=true,reason=f.reason,note=f.lifecycle,section=t.label or'Melee',
                            group='Melee'})
                    end
                end

    for _,row in ipairs(rows)do row.object=host;row.group='Melee' end
    return rows
end
-- Status effects (HD2Runtime 0.31.0 hd2.status_effect): each status's own definition, for every attack that applies
-- it: how long it lasts (status.duration) and the damage row it deals while active (:damage()).
function CATEGORY.status_effects(cat)
    local D,why=load('status_effect_authoring')
    -- (an older HD2Runtime has no such module: say which version adds it, not the loader's search path)
    if not D or type(D.statuses)~='table'then
        if why and not tostring(why):find('not found',1,true)then return nil,why end
        return nil,'this HD2Runtime has no status effect stats (HD2Runtime 0.31.0)'
    end
    local hd2=cat.hd2
    local list={}
    for id,entry in pairs(D.statuses)do
        local status=id
        list[#list+1]={key='se|'..id,name=entry.name or util.humanize(id),subtitle=util.humanize(entry.family or'status'),
            build=function(object)
                local rows={}
                local function add(path,section,target)
                    local t=type(entry.targets)=='table'and entry.targets[path]
                    if type(t)~='table'then return end
                    for _,fid in ipairs(util.sorted_keys(t.fields or{}))do
                        local f=t.fields[fid]
                        if f.editable and numeric(f.type,f.currentDefault)then
                            rows[#rows+1]=make_row(object,{id=path..':'..f.semanticFieldId,label=f.displayName,unit=f.unit,
                                vanilla=f.currentDefault,min=f.min,max=f.max,type=f.type,storage=(f.backing or{}).storage,
                                field=f.semanticFieldId,target=target,shared=f.shared==true,unverified=unverified(f),
                                descriptor=f,section=section})
                        end
                    end
                end
                add('status','Status',function()return hd2.status_effect(status)end)
                add('damage','Damage while active',function()return hd2.status_effect(status):damage()end)
                return rows
            end}
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
        local expanded=require('mods/skyeshade/hd2runtime_editor/editor/enemies').entities(cat,M,filter)
        if expanded then return expanded end
        local EN,why=load('enemy_authoring')
        if not EN then return nil,why end
        local list={}
        for class,entry in pairs(EN.enemies or{})do
            if filter(entry)then
                entry.className=entry.className or class
                local name=entry.wikiName or entry.name or class
                if name:find('_')or name==name:lower()then name=util.humanize(name)end
                local ik,iname,ifaction=require('mods/skyeshade/hd2runtime_editor/editor/icons').entity(class,entry)
                list[#list+1]={key='en|'..class,name=name,iconKind=ik,iconName=iname,iconFaction=ifaction,
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
    affects_main_health='Main health share',health='Health',stims_from_supply='Stims from supply'}
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
            or id:find('^helldiver%.supply%.')and'Player refill'or'Damage'
        local note=section=='Player refill'and'Shared by all Helldivers and supply sources. Capped by stim capacity; armor bonuses and private inventory copies can alter the result.'
            or(section=='Damage'and'Live, every Helldiver'or ship)
        rows[#rows+1]=helldiver_field_row(object,f,entity,section,nil,note)
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
        local r=make_value_row(object,{id=id,kind='choice',label=label,field='player_passives.'..id,vanilla=vanilla,
            labels=labels,options=static_options(labels),section='Armor perks',unverified=true,controller='passives',
            note=note,export_reason=why,target=function()return hd2.player_passives end})
        -- Preserve old presets and the controller's storage identity after moving to Helldiver.
        r.key='hd|Armor perks|'..id;r.loc='row:'..r.key
        return r
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
        list[#list+1]={key='hd|Helldiver',name='Helldiver',subtitle='Every Helldiver',aliases={'hd|Armor perks'},
            build=function(object)
                local rows=helldiver_rows(cat.hd2,object)
                for _,row in ipairs(rows)do
                    if row.editable and not row.info then row.risk,row.risk_note='gameguard',M.HELLDIVER_GAMEGUARD_RISK end
                end
                if type(cat.real_hd2.passives)=='table'and type(cat.real_hd2.player_passives)=='table'then
                    append(rows,passive_rows(cat.real_hd2,object))
                end
                return rows
            end}
    end
    return list
end

function CATEGORY.armor_perks(cat)
    local P=cat.real_hd2.passives
    if type(P)~='table'or type(P.perk)~='function'then return nil,'Armor perk editing requires HD2Runtime 0.40.0 RC10 or later.'end
    local list={}
    for _,p in ipairs(P.list())do
        local perk=p;local d=P.perk(p.id):describe()
        list[#list+1]={key='ap|'..p.id,name=title_case(p.name),game_name_key=p.name,subtitle='Armor perks',
            iconKind='passive',iconName=p.name,detail=p.description,
            build=function(object)
                local rows={}
                for _,f in ipairs(d.fields)do
                    rows[#rows+1]=make_row(object,{id=f.semanticFieldId,field=f.semanticFieldId,label=f.label,
                        vanilla=f.currentDefault,min=f.min,max=f.max,type=f.unit=='count'and'integer'or f.type,
                        storage='f32',unit=f.unit=='seconds'and's'or f.unit=='multiplier'and'x'or nil,
                        shared=true,unverified=true,descriptor=f,section=f.section,note=f.lifecycle,
                        target=function()return cat.hd2.passives.perk(perk.id)end})
                end
                rows[#rows+1]=info_row(object,{id='description',label='Perk description',text=perk.description,
                    info=true,section='Perk details',note='Vanilla description; edited values are shown in the fields above.'})
                if#d.fields==0 then rows[#rows+1]=info_row(object,{id='no-fields',label='Perk bonuses',
                    text='No numeric gameplay fields mapped for this perk.',info=true,section='Perk details'})end
                return rows
            end}
    end
    return sorted_objects(list)
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
-- The Helldiver's own stats (every Helldiver: health, stamina, speeds...): players reported GameGuard closing the game
-- after tuning them (2026-10-14). Same risk marking, with its own reason (row.risk_note).
M.HELLDIVER_GAMEGUARD_RISK='Players reported GameGuard closing the game after tuning the Helldiver\'s stats.'
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
CATEGORY.enemy_entities=enemy_category(function(e)return e.kind~='structure'and(e.kind~='enemy'
    or(e.faction~='terminids'and e.faction~='automatons'and e.faction~='illuminate'))end)
for category,kind in pairs({enemy_difficulty='difficulty',enemy_rosters='roster',enemy_compositions='composition',
    demolition_templates='demolition_template'})do
    local k=kind
    CATEGORY[category]=function(cat)return require('mods/skyeshade/hd2runtime_editor/editor/enemies').director(cat,M,k)end
end
CATEGORY.destruction_models=function(cat)return require('mods/skyeshade/hd2runtime_editor/editor/enemies').models(cat,M)end
CATEGORY.enemy_overview=function(cat)return require('mods/skyeshade/hd2runtime_editor/editor/enemies').overview(cat,M)end
CATEGORY.mission_overview=function(cat)return require('mods/skyeshade/hd2runtime_editor/editor/missions').overview(cat)end
CATEGORY.mission_timer=function(cat)return require('mods/skyeshade/hd2runtime_editor/editor/missions').timer(cat)end
M.CATEGORY=CATEGORY
for _,name in ipairs({'terminids','automatons','illuminate'})do
    local faction=name
    CATEGORY['missions_'..faction]=function(cat)
        return require('mods/skyeshade/hd2runtime_editor/editor/missions').category(cat,M,faction)
    end
end

-- The categories that can hold an object key's family (presets name rows by key; mods' claims name family objects).
local FAMILY_CATEGORIES={pw={'primary','secondary'},th={'throwables'},me={'primary','secondary','support_weapons'},bo={'boosters'},
    mi={'missions_terminids','missions_automatons','missions_illuminate'},mo={'mission_overview'},mt={'mission_timer'},ap={'armor_perks'},
    st={'offensive','defensive','support_weapons','support_backpacks','vehicles','resupply'},
    sw={'support_weapons'},sp={'support_weapons'},bp={'support_weapons','support_backpacks'},sb={'support_backpacks'},
    vh={'vehicles'},ve={'vehicles'},vw={'vehicles','support_backpacks'},rs={'resupply'},ex={'resupply'},
    en={'terminids','automatons','illuminate','structures','enemy_entities'},hd={'helldiver'},ar={'armor'},se={'status_effects'},
    ed={'enemy_difficulty','enemy_rosters','enemy_compositions','demolition_templates'},dm={'destruction_models'},eo={'enemy_overview'}}

------------------------------------------------------------------------------ what a swapped weapon fires --
-- After a projectile swap (staged or applied) the weapon fires the donor's projectile, and HD2Runtime refuses the
-- rows it reaches through its own projectile: flight, direct-hit damage, impact and expiry explosions and their
-- statuses (COMPOSITION_TARGET_CHANGED). Those rows carry fires_scope ('attack:<role>', 'function:programmable'), the
-- swap row swap_scope; Catalog:open links them (row.fires_from = the swap row, swap.fires_rows, object.swap_rows) and
-- the window sets them aside while the swap names a donor (ui/app.lua fires_sections). In their place it shows the
-- donor's stats (HD2Runtime 0.31.2 hd2.attack_output(id):stats(): vanilla game data, read-only) and, when the donor is
-- its owner's own editable projectile (:owner_projectile()), a link to the owner's page, where an edit is shared.
-- The texts of these rows (shown through L()).
local FIRES_TEXTS={fires='Fires',feed='Donor\'s projectile (vanilla)',link='Edit the donor\'s projectile',open='OPEN',
    fires_note='The donor\'s projectile replaces this weapon\'s own: its own projectile, damage and explosion rows are set '
        ..'aside until the swap is reset (HD2Runtime refuses them while it fires another projectile: '
        ..'COMPOSITION_TARGET_CHANGED)',
    values_note='The donor\'s own values from the game data (vanilla), read-only: an edit a mod or you made to them is '
        ..'not shown here'}
M.FIRES_TEXTS=FIRES_TEXTS
local FIRES_FLIGHT={{key='velocity',label='Projectile velocity'},{key='mass',label='Projectile mass'},
    {key='drag',label='Projectile drag'},{key='gravity',label='Projectile gravity'},
    {key='lifetime',label='Projectile lifetime'},{key='pellet_count',label='Pellet count'},
    {key='diameter',label='Diameter'},{key='lifetime_variance',label='Lifetime variance'},
    {key='penetration_slowdown',label='Penetration slowdown'}}
local FIRES_DAMAGE={{key='standard_damage',label='Standard damage'},{key='durable_damage',label='Durable damage'},
    {key='ap_direct',label='Armor penetration: direct'},{key='ap_slight',label='Armor penetration: slight angle'},
    {key='ap_large',label='Armor penetration: large angle'},{key='ap_extreme',label='Armor penetration: extreme angle'},
    {key='demolition',label='Demolition'},{key='stagger',label='Stagger'},{key='push_force',label='Push force'}}
local FIRES_EXPLOSION={{key='inner_radius',label='Explosion inner radius'},
    {key='outer_radius',label='Explosion outer radius'},{key='shockwave_radius',label='Explosion shockwave radius'},
    {key='shrapnel_count',label='Shrapnel count'},{key='arc',label='Arc explosion'}}
local FIRES_EXPLOSION_DAMAGE={{key='standard_damage',label='Explosion standard damage'},
    {key='durable_damage',label='Explosion durable damage'},{key='ap_direct',label='Explosion AP: direct'},
    {key='ap_slight',label='Explosion AP: slight angle'},{key='ap_large',label='Explosion AP: large angle'},
    {key='ap_extreme',label='Explosion AP: extreme angle'},{key='demolition',label='Explosion demolition'},
    {key='stagger',label='Explosion stagger'},{key='push_force',label='Explosion push force'}}
-- The output id a swap row's value names when it is a donor (not the weapon's own projectile), else nil.
function M.donor_of(row,value)
    if type(row)~='table'or not row.swap_scope or type(value)~='table'then return nil end
    local id=rawget(value,'output')
    if type(id)~='string'or util.same(value,row.vanilla)then return nil end
    -- (the weapon's own output picked from the list fires its own projectile)
    local A=load('attack_outputs')
    local o=A and type(A.outputs)=='table'and A.outputs[id]
    if o and type(o.owner)=='table'and row.object and o.owner.name==row.object.name
        and row.swap_scope=='attack:primary'then return nil end
    return id
end
-- The owner of an output ({name, kind}) and the catalogue key of its page ('sp|' support, 'pw|' player weapons).
local OWNER_FAMILY={support_weapon='sp',player_weapon='pw'}
local function output_owner(id)
    local A=load('attack_outputs')
    local o=A and type(A.outputs)=='table'and A.outputs[id]
    local owner=o and type(o.owner)=='table'and o.owner or nil
    return owner
end
M.output_owner=output_owner
local function number_text(v)
    if type(v)=='number'then return util.format(v)end
    if type(v)=='boolean'then return v and'On'or'Off'end
    return v~=nil and tostring(v)or'-'
end
-- The donor's sections for a swap row on its object: {{label, rows}} (info rows; a link row). hd2: the real hd2.
local function donor_sections(hd2,object,swap,id)
    local units={}
    for _,r in ipairs(object.rows or{})do if r.field and r.unit and not units[r.field]then units[r.field]=r.unit end end
    -- "Projectile · Flak · Swap" -> "Flak": the round or feed the swap is on
    local middle=tostring(swap.section):gsub('^Projectile',''):gsub(' · Swap$',''):gsub('^ · ','')
    if middle==''then middle=nil end
    local feed=join(middle,FIRES_TEXTS.feed)
    local base='fires|'..tostring(swap.swap_scope)..'|'..id..'|'
    local sections,by={},{}
    local function add(section,row)
        local s=by[section]
        -- (a mount's donor in the mount's own group)
        if not s then s={label=section,group=swap.group,rows={}};by[section]=s;sections[#sections+1]=s end
        row.group=swap.group
        s.rows[#s.rows+1]=row
    end
    local function info(section,part,label,text,reason,unit)
        local row=info_row(object,{id=base..part,label=label,field='info',section=section,text=text,
            reason=reason or FIRES_TEXTS.values_note,info=true})
        row.unit,row.fires_info=unit,true
        add(section,row)
        return row
    end
    local owner=output_owner(id)
    local donor=owner and owner.name or id
    local fires=info(swap.section,'fires',FIRES_TEXTS.fires,donor,FIRES_TEXTS.fires_note)
    fires.donor=id
    local okh,handle=pcall(function()return hd2.attack_output(id)end)
    if not okh or type(handle)~='table'then return sections end
    -- the owner's own editable projectile (edits there are shared with the owner and every weapon that fires it)
    local family=owner and OWNER_FAMILY[owner.kind]
    if family and type(handle.owner_projectile)=='function'then
        local okp,projectile=pcall(handle.owner_projectile,handle)
        if okp and type(projectile)=='table'then
            local link=info(swap.section,'link',FIRES_TEXTS.link,FIRES_TEXTS.open,FIRES_TEXTS.values_note)
            link.link={key=family..'|'..owner.name,owner=owner.name,scope='attack:primary'}
        end
    end
    if type(handle.stats)~='function'then return sections end
    local oks,stats=pcall(handle.stats,handle)
    if not oks or type(stats)~='table'then return sections end
    if type(stats.consumers)=='number'then
        for _,s in ipairs(sections)do for _,r in ipairs(s.rows)do if r.link then r.link.consumers=stats.consumers end end end
    end
    local flight=join('Projectile',feed)
    for _,f in ipairs(FIRES_FLIGHT)do
        local v=type(stats.flight)=='table'and stats.flight[f.key]
        if v~=nil and v~=false then info(flight,'flight.'..f.key,f.label,number_text(v),nil,units['projectile.'..f.key])end
    end
    local hit=join('Damage',feed..' direct hit')
    local d=type(stats.direct_damage)=='table'and stats.direct_damage
    if d then
        for _,f in ipairs(FIRES_DAMAGE)do
            if d[f.key]~=nil then info(hit,'damage.'..f.key,f.label,number_text(d[f.key]),nil,units['damage.'..f.key])end
        end
        for i,s in ipairs(type(d.statuses)=='table'and d.statuses or{})do
            if type(s)=='table'and s.status then
                info(join(hit,'Status'),'damage.status_'..i,'Status '..i,util.humanize(s.status)
                    ..(type(s.strength)=='number'and(' ('..util.format(s.strength)..')')or''))
            end
        end
    end
    for _,phase in ipairs({'impact','expiry'})do
        local e=type(stats[phase])=='table'and stats[phase]
        if e then
            local section=join('Explosion',feed,util.humanize(phase))
            info(section,phase..'.name','Explosion',tostring(e.label or e.name or'-'))
            for _,f in ipairs(FIRES_EXPLOSION)do
                if e[f.key]~=nil then
                    info(section,phase..'.'..f.key,f.label,number_text(e[f.key]),nil,units['explosion.'..f.key])
                end
            end
            local ed=type(e.damage)=='table'and e.damage
            for _,f in ipairs(ed and FIRES_EXPLOSION_DAMAGE or{})do
                if ed[f.key]~=nil then
                    info(section,phase..'.damage.'..f.key,f.label,number_text(ed[f.key]),nil,
                        units['explosion.damage.'..f.key])
                end
            end
        end
    end
    return sections
end

------------------------------------------------------------------------------ what a payload slot sets off --
-- An impact or expiry payload slot (a terminal.explosion row, "Impact payload") names the explosion the projectile
-- sets off: the weapon's own, none, another weapon's terminal explosion (hd2.weapon(w):attack(a):projectile()
-- :terminal_action(p):explosion(), what the editor offers) or a catalogued explosion (hd2.explosion(name): a mod's
-- value). The window shows the named explosion's settings under the slot, in the slot's own subsection (ui/app.lua
-- payload_sections): the rows its owner's page has for it (the same keys, native bytes, descriptors and
-- acknowledgements, so an edit made there and one made here are one field in pending values, Changes, presets, the
-- saved session and exports), as views of them (row.canonical = the owner's row, row.shown_by = the slot). They edit
-- the explosion's own definition, shared with every weapon that sets it off. An explosion no page has a row for is
-- edited through hd2.explosion(id), keyed by the explosion itself ('ex|<id>|<field>'). While a slot names another
-- explosion than the weapon's own, HD2Runtime refuses the weapon's own explosion rows (their settings record changed,
-- its reset included): Catalog:open links them to the slot (row.payload_from, slot.payload_rows), and the window sets
-- them aside as it does for a projectile swap.
-- The texts of these rows (shown through L()).
local PAYLOAD_TEXTS={settings='Explosion settings',not_shown='Not shown',
    unknown='HD2Runtime\'s explosion catalogue does not know this explosion, so its settings cannot be shown here',
    package='No package that ships this explosion\'s effect is known to HD2Runtime: it refuses it as a payload '
        ..'(ASSET_UNAVAILABLE), so its settings are not shown here',
    none='HD2Runtime publishes no editable settings for this explosion',
    explosion='Explosion'}
M.PAYLOAD_TEXTS=PAYLOAD_TEXTS
-- What a payload slot's value names: a key ('w|...' another weapon's terminal explosion, 'x|<id>' a catalogued one,
-- '?' something else) and its parts; nil for no explosion.
function M.payload_identity(value)
    if type(value)~='table'then return nil end
    if rawget(value,'path')=='no_explosion'then return nil end
    local resource=rawget(value,'resource')
    local id=rawget(value,'explosion')
    if resource=='explosion'and type(id)=='string'then return 'x|'..id,{explosion=id}end
    local w,a,p=rawget(value,'weapon'),rawget(value,'attack'),rawget(value,'phase')
    if type(w)=='string'and type(p)=='string'then
        a=type(a)=='string'and a or'primary'
        return 'w|'..tostring(resource)..'|'..w..'|'..a..'|'..p,{weapon=w,attack=a,phase=p,resource=resource}
    end
    return '?',{}
end
-- Whether a payload slot's value sets off another explosion than the weapon's own (its own explosion rows are then
-- refused), where no catalogue instance is at hand (exports): as its view said (Catalog:payload_view), else whether it
-- names an explosion other than the slot's own value.
function M.payload_other(slot,value)
    if slot and slot.throwable_payload and value=='none'then return slot.vanilla~='none'end
    local key=M.payload_identity(value)
    if not key or type(slot)~='table'then return false end
    local said
    if type(slot.payload_other)=='table'then said=slot.payload_other[key]end
    if said~=nil then return said end
    return not util.same(value,slot.vanilla)
end
-- The catalogue explosion a weapon's terminal explosion is (owner name and role 'impact' / '<attack>_impact'), or nil.
local function catalogue_id_of(id)
    local explosions=explosion_api()
    if not explosions then return nil end
    local roles={[id.phase]=true,[id.attack..'_'..id.phase]=true}
    for _,eid in ipairs(util.sorted_keys(explosions.explosions))do
        for _,o in ipairs(owners_of(explosions.explosions[eid]))do
            if o.name==id.weapon and roles[o.role]and tostring(o.category):find('^player weapon')then return eid end
        end
    end
    return nil
end
-- The pages an owner of a catalogue explosion can be on (any family; an underbarrel on its host's page).
local OWNER_FAMILIES={'pw','sp','th','sb','st','ve','rs'}

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
        if(key=='enemies'or key=='melee'or key=='passives')and type(hd2[key])=='table'then
            return setmetatable({},{__index=function(_,method)
                if export_module.tracing and type(hd2[key][method])=='function'then
                    return export_module.tracing(key..'.'..method)
                end
                return hd2[key][method]
            end,__call=function(_,...)
                if export_module.tracing then return export_module.tracing(key)(...)end
                return hd2[key](...)
            end})
        end
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
        if(category=='primary'or category=='secondary'or category=='support_weapons')and melee_entry(object.name)then
            object.has_melee=true;self.aliases['me|'..object.name]=object
        end
        self.by_key[object.key]=object
        for _,alias in pairs(object.aliases or{})do self.aliases[alias]=object end
    end
    self.lists[category]=list
    self.errors[category]=result==nil and tostring(why or'unavailable')or nil
    return list,self.errors[category]
end
function Catalog:count(category)return#(self:objects(category))end
-- Values another mod owns (HD2Runtime 0.31.0+: hd2.inspect). A mod outside HD2Runtime (a data-file mod, or one that
-- writes game memory itself, such as one rebuilding a weapon's components) owns a value HD2Runtime refuses to write;
-- its row is locked with that reason instead of failing when it is edited. Values another HD2Runtime mod holds stay
-- editable (the editor takes such an operation over). Once per object, read only, in the background: one request per
-- target, at most 64 fields each. Without hd2.inspect (an older HD2Runtime) nothing changes.
local function handle_key(handle)
    local parts={}
    for k,v in pairs(type(handle)=='table'and handle or{})do
        if type(v)=='string'or type(v)=='number'or type(v)=='boolean'then parts[#parts+1]=tostring(k)..'='..tostring(v)end
    end
    table.sort(parts)
    return table.concat(parts,'|')
end
-- held(row): whether HD2Runtime itself holds the field's bytes as far as the editor knows (the editor's own ensure, or a
-- value an HD2Runtime mod applied). Bytes without a native record identity (booster tables, entity deltas: HD2Runtime's
-- core/shared_records keeps no claim for them) are reported 'changed' with no owner and no reason even when an
-- HD2Runtime operation wrote them, so such a field is locked only when nothing in HD2Runtime explains its value: an
-- applied booster edit was shown LOCKED, its own value taken for another mod's.
local function owner_results(g,result,held)
    for i,f in ipairs(result.fields or{})do
        local row=g.rows[i]
        local untracked=f.state=='changed'and f.owner==nil and f.reason==nil
        local ours=untracked and type(held)=='function'and select(2,pcall(held,row))==true
        if row and not ours and(f.state=='foreign'or f.state=='changed')then
            row.editable=false
            row.foreign=true
            -- foreign: a value (or a whole component table another mod moved: no value then); changed with
            -- owner unknown: the item's entity map row another mod rebuilt; changed otherwise: a structural
            -- part (a link, a slot) is not as reviewed, in the Runtime's own words
            if f.state=='foreign'then
                row.reason='changed by another mod (not HD2Runtime)'..(f.value~=nil and(': it is '..tostring(f.value))
                    or'')..'; HD2Runtime leaves it as it is'
            elseif f.owner=='unknown'then
                row.reason='another mod (not HD2Runtime) changed the data of this item; HD2Runtime leaves it as it is'
            elseif untracked then
                -- (no claim to name: neither the editor nor an HD2Runtime mod applied a value here)
                row.reason='the game holds '..(f.value~=nil and util.format(f.value)or'another value')
                    ..' here, not the reviewed '..util.value_text(row.vanilla)..', and no HD2Runtime mod applied '
                    ..'it: another mod (not HD2Runtime) changed it; HD2Runtime leaves it as it is'
            else
                row.reason='its game data is not as HD2Runtime reviewed it'..(f.reason and(' ('
                    ..util.plain(tostring(f.reason),160)..')')or'')
            end
        end
    end
end
-- Build the request list without reading the game. Only the selected page advances it;
-- completed groups remain cached on the object, and a cancelled group resumes on revisit.
function Catalog:check_owners(object,held)
    local hd2=self.real_hd2
    if object.owners_checked or type(hd2)~='table'or type(hd2.inspect)~='function'then return end
    if object.owner_scan and not object.owner_scan.complete then return end
    local scan={object=object,groups={},cursor=1,done=0,total=0,held=held,token=0}
    object.owner_scan=scan
    scan.build=coroutine.create(function()
        local groups={}
        for index,row in ipairs(object.rows or{})do
            if row.editable and not row.no_inspect and type(row.target)=='function'and type(row.field)=='string'then
                local ok,target=pcall(row.target)
                local okx,expect=pcall(M.expect,row)
                if ok and type(target)=='table'and okx and expect~=nil then
                    local key=handle_key(target)
                    local g=groups[key]
                    -- Split overflowing targets instead of dropping field 65 and beyond.
                    if not g or#g.fields>=64 then
                        g={target=target,rows={},fields={}};groups[key]=g;scan.groups[#scan.groups+1]=g
                    end
                    g.rows[#g.rows+1]=row;g.fields[#g.fields+1]={field=row.field,expect=expect}
                    scan.total=scan.total+1
                end
            end
            if index%16==0 then coroutine.yield()end
        end
    end)
end
function Catalog:pause_owners()
    local scan=self.owner_active
    if not scan then return end
    scan.token=scan.token+1
    if scan.job and type(scan.job.cancel)=='function'then pcall(scan.job.cancel)end
    if scan.group_done then scan.cursor=scan.cursor+1;scan.group_done=nil end
    scan.job=nil
    self.owner_active=nil
end
function Catalog:owners_step(object,held)
    local active=self.owner_active
    if active and(active.object~=object or object.owners_checked)then self:pause_owners()end
    if not object or object.owners_checked then return end
    self:check_owners(object,held)
    local scan=object.owner_scan
    if not scan or scan.complete then return end
    self.owner_active=scan
    if scan.build then
        local ok,why=coroutine.resume(scan.build)
        if not ok then
            scan.error=tostring(why);scan.build=nil;scan.complete=true;object.owners_checked=true
            return
        end
        if coroutine.status(scan.build)~='dead'then return end
        scan.build=nil
        return
    end
    if scan.job then
        if scan.job.status=='running'or scan.job.status=='waiting'then return end
        -- A cancelled/rejected adapter never calls on_result. Advance once, without retrying each frame.
        if not scan.group_done then scan.done=scan.done+#scan.groups[scan.cursor].fields end
        scan.cursor=scan.cursor+1;scan.job=nil;scan.group_done=nil
    end
    local g=scan.groups[scan.cursor]
    if not g then scan.complete=true;object.owners_checked=true;self.owner_active=nil;return end
    scan.token=scan.token+1
    local token=scan.token
    local ok,job=pcall(self.real_hd2.inspect,{target=g.target,fields=g.fields,on_result=function(result)
        if self.owner_active~=scan or scan.token~=token then return end
        owner_results(g,result,scan.held)
        scan.done=scan.done+#g.fields;scan.group_done=true
    end})
    -- Even an immediate completion waits for the next UI frame before starting another target.
    scan.job=ok and type(job)=='table'and job or{status='rejected'}
    if scan.group_done then scan.job.status='complete'end
end
-- Status slots (HD2Runtime 0.31.2: every empty slot of a damage row, up to 4; older Runtimes offer the first empty
-- one): a row's slots stay packed from slot 1 (the Runtime refuses a gap, STATUS_SLOT_GAP). Each slot's status and
-- strength are shown together, in slot order, as "Status 1", "Status 1 strength", "Status 2" ... under the row's
-- "· Status" section, and linked so the window and the layer keep the order: row.status_slot = {n, kind = 'type' |
-- 'strength', prev = the status row of slot n-1, later = every row of the slots after n, strength = a status row's
-- own strength row}. The rows of one damage row
-- are those of one object part (group), one section and one field prefix ('damage.', 'explosion.damage.').
local function status_slots(rows)
    local groups,first={},{}
    for i,r in ipairs(rows)do
        local prefix,n,what=tostring(r.field):match('^(.-)status_(%d)_(%a+)$')
        if prefix and(what=='type'or what=='strength')and(what=='strength'or r.kind=='choice')then
            local base=tostring(r.section):gsub(' · Status$','')
            local key=tostring(r.group)..'\0'..base..'\0'..prefix
            local g=groups[key]
            if not g then g={base=base,slots={},rows={}};groups[key]=g;first[i]=g end
            n=tonumber(n)
            g.slots[n]=g.slots[n]or{}
            if not g.slots[n][what]then
                g.slots[n][what]=r
                g.rows[#g.rows+1]=r
                r.status_slot={n=n,kind=what,group=g}
            end
        end
    end
    if next(groups)==nil then return rows end
    for _,g in pairs(groups)do
        table.sort(g.rows,function(a,b)
            local x,y=a.status_slot,b.status_slot
            if x.n~=y.n then return x.n<y.n end
            return x.kind=='type'and y.kind~='type'
        end)
        for _,r in ipairs(g.rows)do
            local s=r.status_slot
            r.section=join(g.base,'Status')
            r.label=s.kind=='type'and('Status '..s.n)or('Status '..s.n..' strength')
            s.prev=g.slots[s.n-1]and g.slots[s.n-1].type or nil
            if s.kind=='type'then s.strength=g.slots[s.n].strength end
            s.later={}
            for _,o in ipairs(g.rows)do if o.status_slot.n>s.n then s.later[#s.later+1]=o end end
            s.group=nil
        end
    end
    -- each damage row's slot rows together, where its first one was
    local out,placed={},{}
    for i,r in ipairs(rows)do
        local g=first[i]
        if g then for _,x in ipairs(g.rows)do out[#out+1]=x;placed[x]=true end end
        if not placed[r]then out[#out+1]=r end
    end
    return out
end
M.status_slots=status_slots
-- A used status slot's own stats, under the slot. The Runtime publishes a damage row's used slots as a status only
-- (status_k_type) and reaches their strength and the status's duration through a child status attack of their own
-- (support weapons: "primary_status_43", the native status type; stratagems: "... damage status 1"; throwables:
-- "Status effect · Gas"). The child's strength IS slot k's strength (the same 4 bytes of the DamageInfo row, offset 48 +
-- 8 (k - 1)), and its duration is the status's own definition (StatusEffectSettings +40), shared by every attack that
-- applies that status (the same bytes as the Status Effects category's row). So each child is matched to its slot by
-- native identity (its strength's bytes against the slot's status bytes, 4 before them), never by order, and shown under
-- it as "Status k strength" and "Status k duration (Gas 2, all uses)" (the status it was published for); a damage row
-- without status rows (a stratagem's) gets its children together under one "· Status" section. Keys, targets and
-- fields stay as they are (presentation only); a child gets row.status_child = {n, kind = 'strength' | 'duration',
-- type_row, status}, and never row.status_slot (the slot order rules are the type and own strength rows').
local function damage_slot(loc)
    local record,offset=tostring(loc):match('^(settings/damage/%d+)@(%d+)$')
    offset=tonumber(offset)
    if not offset or offset<48 or offset>72 or(offset-48)%8~=0 then return nil end
    return record,(offset-48)/8+1,offset
end
local status_names
local function status_by_row(record)
    if status_names==nil then
        status_names=false
        local D=load('status_effect_authoring')
        if D and type(D.statuses)=='table'then
            status_names={}
            for id,entry in pairs(D.statuses)do
                if type(entry)=='table'and entry.row~=nil then status_names[tonumber(entry.row)or entry.row]=id end
            end
        end
    end
    local row=tonumber(tostring(record):match('^settings/status/(%d+)@40$'))
    return status_names and row and status_names[row]or nil
end
local function status_children(rows)
    local types,by_section={},{}
    for _,r in ipairs(rows)do
        if r.status_slot and r.status_slot.kind=='type'then types[r.loc]=r end
        if(r.field=='status.strength'or r.field=='status.duration')and not r.status_slot then
            local key=tostring(r.group)..'\0'..tostring(r.section)
            local s=by_section[key]or{}
            by_section[key]=s
            s[r.field]=s[r.field]or r
        end
    end
    local after,moved={},{}
    for _,s in pairs(by_section)do
        local strength,duration=s['status.strength'],s['status.duration']
        local record,n,offset=damage_slot(strength and strength.loc)
        if record then
            local t=types[record..'@'..(offset-4)]
            local status=t and t.vanilla
            if not t then status=duration and status_by_row(duration.loc)end
            if t and duration and status_by_row(duration.loc)and status_by_row(duration.loc)~=status then
                duration=nil   -- (a duration of another status than the slot's: left where it is)
            end
            local name=status and status~='none'and util.humanize(status)or nil
            for _,l in ipairs(t and t.labels or{})do if l.value==status then name=l.label end end
            strength.status_child={n=n,kind='strength',type_row=t,status=status}
            strength.label='Status '..n..' strength'
            if duration then
                duration.status_child={n=n,kind='duration',type_row=t,status=status}
                duration.label='Status '..n..' duration'..(name and(' ('..name..', all uses)')or' (all uses)')
            end
            if t then
                -- under the slot: after its own strength row when it has one, else after its status
                local anchor=t.status_slot.strength or t
                local list=after[anchor]or{}
                after[anchor]=list
                for _,c in ipairs({strength,duration})do
                    local own=t.status_slot.strength
                    if c==strength and own and own.loc==c.loc then
                        -- The new direct slot strength and the legacy named-status target are the same bytes.
                        -- Keep old preset keys as aliases without drawing a second strength control.
                        own.alias_keys=own.alias_keys or{}
                        own.alias_keys[#own.alias_keys+1]=c.key
                        for _,alias in ipairs(c.alias_keys or{})do own.alias_keys[#own.alias_keys+1]=alias end
                        if c.delivery_aliases then
                            own.delivery_aliases=own.delivery_aliases or{}
                            for _,alias in ipairs(c.delivery_aliases)do
                                own.delivery_aliases[#own.delivery_aliases+1]=alias
                            end
                        end
                    else
                        c.section,c.group=t.section,t.group
                        list[#list+1]=c
                    end
                    moved[c]=true
                end
            else
                -- no status rows for this damage row: its children together, "... damage status 1 · Status" ->
                -- "... damage · Status"
                local section=tostring(strength.section):gsub(' status %d+',''):gsub('  +',' ')
                strength.section=section
                if duration then duration.section=section end
            end
        end
    end
    if next(moved)==nil then return rows end
    local out={}
    for _,r in ipairs(rows)do
        if not moved[r]then
            out[#out+1]=r
            for _,c in ipairs(after[r]or{})do out[#out+1]=c end
        end
    end
    return out
end
M.status_children=status_children
-- The ammunition rows of each section in their order (ammo_rank: capacity, spare, starting, supply, reload), in the
-- places those rows already hold: any other row of the section (a magazine's ergonomics) stays where it is.
local function ammo_order(rows)
    local by={}
    for i,r in ipairs(rows)do
        local rank=r and ammo_rank(r.field)
        if rank then
            local key=tostring(r.group or'')..'\0'..tostring(r.section)
            local list=by[key]
            if not list then list={};by[key]=list end
            list[#list+1]={i=i,rank=rank,row=r}
        end
    end
    for _,list in pairs(by)do
        if#list>1 then
            local sorted={}
            for n,e in ipairs(list)do sorted[n]=e end
            table.sort(sorted,function(a,b)
                if a.rank~=b.rank then return a.rank<b.rank end
                return a.i<b.i
            end)
            for n,e in ipairs(list)do rows[e.i]=sorted[n].row end
        end
    end
    return rows
end
M.ammo_order=ammo_order
-- Repeated delivery paths can resolve to the same native settings bytes. Keep one control per proven
-- location and role suffix, with old preset keys resolving to it. Equal defaults alone prove nothing.
local function delivery_rows(rows)
    local owners,out={},{}
    for _,row in ipairs(rows)do
        local t=row.descriptor and row.descriptor.target or{}
        local delivery,suffix=tostring(t.attack or''):match('^delivery_(%d+)_(.+)$')
        local key
        if t.path=='attack'and delivery and row.editable and row.loc:match('^settings/')then
            key=table.concat({row.loc,row.field,suffix,row.group or'',row.kind or'',row.storage or''},'\0')
        end
        local owner=key and owners[key]
        if owner and owner.min==row.min and owner.max==row.max and owner.shared==row.shared
            and owner.unverified==row.unverified and util.same(owner.vanilla,row.vanilla)then
            owner.alias_keys=owner.alias_keys or{}
            owner.alias_keys[#owner.alias_keys+1]=row.key
            for _,alias in ipairs(row.alias_keys or{})do owner.alias_keys[#owner.alias_keys+1]=alias end
            owner.delivery_aliases=owner.delivery_aliases or{}
            owner.delivery_aliases[#owner.delivery_aliases+1]=row
            owner.deliveries[tonumber(delivery)]=true
        else
            out[#out+1]=row
            if key then owners[key]=row;row.deliveries={[tonumber(delivery)]=true}end
        end
    end
    for _,row in ipairs(out)do if row.deliveries then
        local numbers={};for n in pairs(row.deliveries)do numbers[#numbers+1]=n end;table.sort(numbers)
        if#numbers>1 then
            row.section=row.section:gsub('Delivery %d+ ',function()
                return Lf('Deliveries %s',table.concat(numbers,', '))..' '
            end,1)
        end
    end end
    return out
end
M.delivery_rows=delivery_rows
-- An object's rows and sections (built once): object.rows, object.sections = {{label, rows}}.
function Catalog:refill_rows(object)
    if object.rows then return object.rows end
    if object.refill_cache then return object.refill_list end
    local proxy=setmetatable({refill_only=true},{__index=object})
    local ok,rows=pcall(object.build,proxy)
    if not ok then return {}end
    object.refill_cache,object.refill_list={},{}
    for _,row in ipairs(rows or{})do
        if row.editable and tostring(row.field):match('from_supply$')then
            row.object=object
            object.refill_cache[row.key]=row
            object.refill_list[#object.refill_list+1]=row
        end
    end
    return object.refill_list
end
-- Runs fn once no object is being built (at once when none is): work that opens other objects must not run inside a
-- build, where it could reach an object whose build is still on the stack and build that object a second time.
function Catalog:after_build(fn)
    if(self.building or 0)==0 then return fn()end
    self.after_builds=self.after_builds or{}
    self.after_builds[#self.after_builds+1]=fn
end
function Catalog:open(object)
    if object.rows then return object end
    self.building=(self.building or 0)+1
    local ok,rows=pcall(object.build,object)
    self.building=self.building-1
    self:open_built(object,ok,rows)
    -- the outermost build is done and its rows are in place: run the work deferred meanwhile
    local queued=self.building==0 and self.after_builds
    if queued then
        self.after_builds=nil
        for _,fn in ipairs(queued)do fn()end
    end
    return object
end
function Catalog:open_built(object,ok,rows)
    if not ok then
        object.rows,object.sections,object.error={},{},tostring(rows)
        return object
    end
    if object.has_melee then append(rows,melee_rows(self.hd2,object))end
    rows=require('mods/skyeshade/hd2runtime_editor/editor/derived').add(object,rows,M)
    rows=ammo_order(status_children(status_slots(delivery_rows(rows))))
    object.rows,object.sections={},{}
    local by_label={}
    for _,row in ipairs(rows)do
        local cached=row and object.refill_cache and object.refill_cache[row.key]
        if cached then row=cached end
        if row and(not self.rows[row.key]or row.canonical or cached)then
            object.rows[#object.rows+1]=row
            self.rows[row.key]=row.canonical or row
            for _,alias in ipairs(row.alias_keys or{})do self.rows[alias]=row end
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
    -- the rows each projectile swap sets aside while it names a donor ("What a swapped weapon fires"); a status slot's
    -- strength and duration follow their slot
    local swaps={}
    for _,row in ipairs(object.rows)do
        if row.swap_scope and row.editable and not swaps[row.swap_scope]then swaps[row.swap_scope]=row end
    end
    if next(swaps)then
        object.swap_rows={}
        for _,row in ipairs(object.rows)do
            local c=row.status_child
            local scope=row.fires_scope or(c and c.type_row and c.type_row.fires_scope)
            local swap=scope and swaps[scope]
            if swap and row~=swap then
                row.fires_from=swap
                swap.fires_rows=swap.fires_rows or{}
                swap.fires_rows[#swap.fires_rows+1]=row
            end
            if swaps[row.swap_scope or'']==row then object.swap_rows[#object.swap_rows+1]=row end
        end
    end
    -- the impact and expiry payload slots, each with the rows of its own explosion (its section and that section's
    -- status, of the same weapon and part): "What a payload slot sets off"
    for _,slot in ipairs(object.rows)do
        if(slot.field=='terminal.explosion'or slot.throwable_payload)and slot.kind=='reference'then
            object.payload_slots=object.payload_slots or{}
            object.payload_slots[#object.payload_slots+1]=slot
            slot.payload_rows={}
            local status=join(slot.section,'Status')
            for _,r in ipairs(object.rows)do
                local throwable_child=false
                if slot.throwable_payload and r.field~='throwable.explosion'and not r.info and r.target then
                    local ok,t=pcall(r.target)
                    throwable_child=ok and t.resource=='throwable'and
                        (t.path=='explosion'or t.path=='arc'or t.path=='shrapnel'or t.path=='bomblets'
                        or t.path=='bomblet_explosion'or t.path=='status_effect')
                end
                if r~=slot and r.field~='terminal.explosion'and r.group==slot.group and r.weapon_name==slot.weapon_name
                    and(r.section==slot.section or r.section==status or throwable_child)and not r.info then
                    if r.catalogue_explosion then
                        -- (a catalogued explosion's own row, edited through hd2.explosion(name): HD2Runtime keeps
                        -- taking it whatever the slot sets off, so it is only set aside from view, never locked)
                        slot.payload_soft=slot.payload_soft or{}
                        slot.payload_soft[#slot.payload_soft+1]=r
                    else
                        r.payload_from=slot
                        slot.payload_rows[#slot.payload_rows+1]=r
                    end
                end
            end
        end
    end
    return object
end
-- A catalogue explosion's object of its own (an explosion no page has a row for): its rows are keyed by the explosion
-- ('ex|<id>|<field>'). Not listed in any category.
function Catalog:explosion_object(eid)
    self.explosion_objects=self.explosion_objects or{}
    local object=self.explosion_objects[eid]
    if object then return object end
    local explosions=explosion_api()
    local e=explosions and explosions.explosions[eid]
    if not e then return nil end
    object={key='ex|'..eid,name=tostring(e.label or eid),subtitle=PAYLOAD_TEXTS.explosion,rows={},sections={},
        explosion=eid}
    self.explosion_objects[eid]=object
    return object
end
-- The row of field `field_id` of catalogue explosion `eid` on its own object (built and indexed once), or nil.
function Catalog:explosion_row(eid,field_id)
    local object=self:explosion_object(eid)
    if not object then return nil end
    local key=object.key..'|'..tostring(field_id)
    if self.rows[key]then return self.rows[key]end
    local explosions,writes=explosion_api()
    for _,field in ipairs(explosions.fields or{})do
        if field.id==field_id then
            local row=explosion_field_row(self.hd2,object,writes,explosions.explosions[eid],eid,field,
                PAYLOAD_TEXTS.explosion,'')
            if not row then return nil end
            object.rows[#object.rows+1]=row
            self.rows[row.key]=row
            local list=self.by_loc[row.loc]
            if not list then list={};self.by_loc[row.loc]=list end
            list[#list+1]=row
            return row
        end
    end
    return nil
end
-- The rows of catalogue explosion `eid` where they are edited: an owner's page that has them (the same native bytes;
-- what spawns a chained explosion counts as its owner), else the explosion's own object. Returns rows, a note (why
-- none are shown) or nil.
function Catalog:explosion_rows_of(eid)
    local explosions,writes=explosion_api()
    local e=explosions and explosions.explosions[eid]
    if not e then return {},PAYLOAD_TEXTS.unknown end
    if e.payload~=true then return {},PAYLOAD_TEXTS.package end
    -- open the owners' pages (and those of what spawns it), so their rows are indexed by native bytes
    local seen={}
    local function open_owners(id,depth)
        if seen[id]or depth>3 then return end
        seen[id]=true
        local entry=explosions.explosions[id]
        for _,o in ipairs(entry and owners_of(entry)or{})do
            if o.category=='explosion'and type(o.name)=='string'then open_owners(o.name,depth+1)
            elseif type(o.name)=='string'then
                local host=o.name:match('^(.-) / [^/]+$')
                for _,family in ipairs(OWNER_FAMILIES)do
                    local object=self:object(family..'|'..o.name)or(host and self:object(family..'|'..host))
                    if object then self:open(object)end
                end
            end
        end
    end
    open_owners(eid,0)
    local out={}
    for _,field in ipairs(explosions.fields or{})do
        local okd,d=pcall(writes.descriptor,e,eid,field.id)
        if okd and type(d)=='table'and d.editable and numeric(d.type,d.currentDefault)then
            local found
            for _,r in ipairs(self.by_loc[location(d)]or{})do
                if r.field==field.id and not r.kind then found=r;break end
            end
            found=found or self:explosion_row(eid,field.id)
            if found then out[#out+1]=found end
        end
    end
    if#out==0 then return out,PAYLOAD_TEXTS.none end
    return out,nil
end
-- The explosion a payload value names, as its rows are edited: {rows, owner (an object), label, note}; cached.
function Catalog:payload_explosion(key,id)
    self.payload_explosions=self.payload_explosions or{}
    local cached=self.payload_explosions[key]
    if cached then return cached end
    local result={rows={}}
    if id.explosion then
        local explosions=explosion_api()
        local e=explosions and explosions.explosions[id.explosion]
        if not e and explosions then
            local aliased=(explosions.aliases or{})[id.explosion]
            if aliased then id={explosion=aliased};e=explosions.explosions[aliased]end
        end
        result.label=e and e.label or id.explosion
        result.rows,result.note=self:explosion_rows_of(id.explosion)
    elseif id.weapon and id.resource=='support_weapon'then
        -- a support weapon's own terminal explosion (HD2Runtime 0.31.2): the rows its payload slot holds, else the
        -- catalogue's entry of the explosion that slot sets off natively
        local page=self:object('sp|'..id.weapon)
        local eid
        if page then
            self:open(page)
            for _,s in ipairs(page.payload_slots or{})do
                if s.swap and s.swap.role==id.attack and s.swap.phase==id.phase then
                    for _,r in ipairs(s.payload_rows or{})do result.rows[#result.rows+1]=r end
                    for _,r in ipairs(s.payload_soft or{})do result.rows[#result.rows+1]=r end
                    local p=type(s.descriptor)=='table'and type(s.descriptor.payload)=='table'and s.descriptor.payload
                    eid=p and p.current
                end
            end
        end
        result.owner,result.label=page,id.weapon
        if#result.rows==0 then
            if type(eid)=='string'then result.rows,result.note=self:explosion_rows_of(eid)
            else result.note=PAYLOAD_TEXTS.unknown end
        end
    elseif id.weapon then
        -- another weapon's terminal explosion: that weapon's own rows of it (a sub-weapon's on its host's page)
        local family=id.resource=='support_weapon'and'sp'or'pw'
        local host=id.weapon:match('^(.-) / [^/]+$')
        local own=self:object(family..'|'..id.weapon)
        local page=own or(host and self:object(family..'|'..host))
        local section=join('Explosion',role_label(id.attack),util.humanize(id.phase))
        local status=join(section,'Status')
        if page then
            self:open(page)
            for _,r in ipairs(page.rows)do
                if r.field~='terminal.explosion'and r.weapon_name==id.weapon and(r.section==section or r.section==status)then
                    result.rows[#result.rows+1]=r
                end
            end
        end
        result.owner,result.label=own,id.weapon
        if#result.rows==0 then
            -- (no page has it: the explosion catalogue's entry of it)
            local eid=catalogue_id_of(id)
            if eid then result.rows,result.note=self:explosion_rows_of(eid)
            else result.note=PAYLOAD_TEXTS.unknown end
        end
    else
        result.note=PAYLOAD_TEXTS.unknown
    end
    self.payload_explosions[key]=result
    return result
end
-- What a payload slot shows for `value` (its pending, applied or a mod's value): nil for no explosion, else
-- {key, rows (views of the explosion's rows, under the slot), note (an info row instead of rows), other (it names
-- another explosion than the weapon's own: its own explosion rows are set aside)}. Cached per slot and explosion.
function Catalog:payload_view(slot,value)
    if slot.throwable_payload and value=='none'then
        slot.empty_payload_view=slot.empty_payload_view or{key='none',rows={},label='None',other=slot.vanilla~='none'}
        return slot.empty_payload_view
    end
    local key,id=M.payload_identity(value)
    if not key then return nil end
    self.payload_views=self.payload_views or{}
    local ck=slot.key..'\0'..key
    local view=self.payload_views[ck]
    if view then return view end
    local x=self:payload_explosion(key,id)
    view={key=key,rows={},label=x.label,owner=x.owner}
    local own={}
    for _,r in ipairs(slot.payload_rows or{})do own[r.loc]=true end
    for _,r in ipairs(slot.payload_soft or{})do own[r.loc]=true end
    -- (the weapon's own explosion, also when another weapon's handle names the same rows)
    local all_own=#x.rows>0 and not x.note
    for _,canonical in ipairs(x.rows)do
        if not own[canonical.loc]then all_own=false end
        -- (a view: everything else is read from the owner's row as it is now, its lock by another mod included)
        view.rows[#view.rows+1]=setmetatable({object=slot.object,section=slot.section,group=slot.group,
            canonical=canonical,shown_by=slot,payload_owner=x.owner,payload_label=x.label},{__index=canonical})
    end
    if x.note then
        local note=info_row(slot.object,{id='payload:'..tostring(slot.key)..':'..key,label=PAYLOAD_TEXTS.settings,
            section=slot.section,group=slot.group,text=PAYLOAD_TEXTS.not_shown,reason=x.note,info=true})
        note.shown_by,note.payload_owner,note.payload_label=slot,x.owner,x.label
        view.note=note
    end
    view.other=not(all_own or util.same(value,slot.vanilla))
    slot.payload_other=slot.payload_other or{}
    slot.payload_other[key]=view.other
    self.payload_views[ck]=view
    return view
end
-- The donor's sections of a swap row naming output `id` (built once per donor).
function Catalog:donor_sections(object,swap,id)
    object.donor_cache=object.donor_cache or{}
    local key=tostring(swap.key)..'\0'..id
    local cached=object.donor_cache[key]
    if not cached then
        local ok,sections=pcall(donor_sections,self.real_hd2,object,swap,id)
        cached=ok and sections or{}
        object.donor_cache[key]=cached
    end
    return cached
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
    if not object then
        -- a catalogue explosion's own row ('ex|<id>|<field>': one no page has, shown under a payload slot)
        if family=='ex'then return self:explosion_row(name,tostring(key):match('|([^|]+)$'))end
        return nil
    end
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
-- true once every object is open, and the objects this step opened. With `seconds`, it also stops once that much CPU
-- time has passed (after at least one object). The editor calls it every frame with a few milliseconds, so the full
-- index (about 20,000 rows) builds in the background without a hitch.
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
    local opened,list=0,{}
    while opened<(budget or 4)do
        if#self.index_queue==0 then
            local category=table.remove(self.index_categories,1)
            if not category then self.indexed=true;return true,list end
            for _,object in ipairs((self:objects(category)))do self.index_queue[#self.index_queue+1]=object end
        else
            local object=table.remove(self.index_queue,1)
            if not object.rows then self:open(object);opened=opened+1;list[opened]=object end
            if started and opened>0 and os.clock()-started>=seconds then return false,list end
        end
    end
    return false,list
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
                for _,row in ipairs(object.rows or{})do if not row.canonical then
                    lookup.rows[#lookup.rows+1]=row
                    local d=type(row.descriptor)=='table'and row.descriptor or{}
                    if d.instanceKey and not lookup.instance[d.instanceKey]then lookup.instance[d.instanceKey]=row end
                    for _,alias in ipairs(row.delivery_aliases or{})do
                        local ad=alias.descriptor or{}
                        if ad.instanceKey then lookup.instance[ad.instanceKey]=row end
                        -- Lua imports may name any delivery path, while edits use the retained key.
                        lookup.rows[#lookup.rows+1]=setmetatable({target=alias.target,target_code=alias.target_code},
                            {__index=row})
                    end
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
                end end -- presentation aliases use the canonical roster/payload entry
            end
        end
    end
    self.import_lookup=lookup
    return lookup
end
-- Every text the window can show from the catalogue, for the localisation template (editor/i18n.lua write_template):
-- category labels, object names, subtitles and details, sections, groups (and each " · " part of them), field labels,
-- value labels, traits, notes and reasons. Opens the whole catalogue first. Sorted, each text once.
function Catalog:texts()
    while not self:index_step(500)do end
    local seen,out={},{}
    local function add(text)
        if type(text)~='string'then return end
        text=text:gsub('^%s+',''):gsub('%s+$','')
        if text==''or seen[text]or text:find('[\r\n]')or not text:find('%a')then return end
        seen[text]=true
        out[#out+1]=text
    end
    local function add_parts(text)
        add(text)
        if type(text)=='string'and text:find(' · ',1,true)then
            for part in(text..' · '):gmatch('(.-) · ')do add(part)end
        end
    end
    for _,group in ipairs(M.GROUPS)do
        add(group.label)
        for _,item in ipairs(group.items)do
            add(item.label)
            for _,object in ipairs((self:objects(item.id))or{})do
                add(object.name);add(object.subtitle);add(object.detail)
                for _,section in ipairs(object.sections or{})do
                    add_parts(section.label);add_parts(section.group)
                    -- (the page's category and subsection titles: ui/sections.lua)
                    local ok,sections=pcall(require,'mods/skyeshade/hd2runtime_editor/editor/ui/sections')
                    if ok then for _,t in ipairs(sections.titles(section.label))do add_parts(t)end end
                end
                for _,row in ipairs(object.rows or{})do
                    add(row.label);add(row.note);add(row.reason)
                    for _,l in ipairs(row.labels or{})do add(l.label)end
                    for _,t in ipairs(row.traits or{})do add(t.label)end
                end
            end
        end
    end
    table.sort(out,function(a,b)return a:lower()<b:lower()end)
    return out
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

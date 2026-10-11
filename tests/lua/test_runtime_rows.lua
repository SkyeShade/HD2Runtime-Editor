-- The rows HD2Runtime 0.31.0 (beam conversion included) adds, each checked only where the Runtime under test
-- publishes it: sections, labels, locks and acknowledgements. Returns one line per check that ran.
local hd2=require('hd2runtime/api/hd2')
local catalog=require('mods/skyeshade/hd2runtime_editor/editor/catalog')
local cat=catalog.new(hd2)
local out={}
local function check(cond,msg)if not cond then error('FAILED: '..msg,2)end end
local function rows(key)
    local object=cat:object(key)
    if not object then return nil end
    cat:open(object)
    check(not object.error,key..': '..tostring(object.error))
    return object.rows
end
local function find(list,fn)for _,r in ipairs(list or{})do if fn(r)then return r end end end
local function has(module)return(pcall(require,'hd2runtime/domains/'..module))end

-- beam swaps (0.31.0): the LAS-5 Scythe's beam is swapped on its muzzle (allow_shared), the Rover's is read-only
local A=has('attack_outputs')and require('hd2runtime/domains/attack_outputs')
if A and type(A.beamHosts)=='table'and A.beamHosts['player_weapon:LAS-5 Scythe']then
    local swap=find(rows('pw|LAS-5 Scythe'),function(r)return r.field=='attack.beam'end)
    check(swap and swap.editable and swap.shared,'Scythe beam swap on its muzzle')
    local rover=find(rows('sb|AX/LAS-5 Rover'),function(r)return r.field=='attack.beam'end)
    check(rover and not rover.editable and rover.reason,'Rover beam swap shown read-only')
    out[#out+1]='beam swaps ok'
end
-- the beam fire mode by name
local mode=find(rows('pw|LAS-13 Trident'),function(r)return r.field=='beam.fire_mode'end)
if mode then
    check(mode.kind=='choice'and catalog.text(mode,6):find('Pulsed',1,true),'beam fire mode by name')
    local pulse=find(rows('pw|LAS-13 Trident'),function(r)return r.field=='beam.pulse_seconds'end)
    check(pulse and pulse.note and pulse.note:find('caps the fire rate',1,true),'the pulse limits the rate')
    out[#out+1]='beam fire mode ok'
end
-- missiles (0.31.0)
local missile=find(rows('sp|StA-X3 W.A.S.P. Launcher'),function(r)return r.field=='function_missile.acceleration'end)
if missile then
    check(missile.section=='Function Missile','missile section: '..missile.section)
    out[#out+1]='missiles ok'
end
-- team-reload weapons (0.31.0): own spares editable with a note; the AC-8's own rounds locked while the Runtime flags
-- them noEffect (0.31.0 rc1), editable with their own-rounds note since the rc2 (teamReload.ownSpares)
local spares=find(rows('sp|GR-8 Recoilless Rifle'),function(r)return r.field=='magazine.spare_magazines'end)
if spares and spares.editable then
    check(spares.note,'own spares explained')
    local start=find(rows('sp|GR-8 Recoilless Rifle'),function(r)return r.field=='deposit.start_amount'end)
    check(start and start.min==-1 and start.section=='Backpack · Ammo','deposit -1 = full, its section: '
        ..tostring(start and start.section))
    local rounds=find(rows('sp|AC-8 Autocannon'),function(r)return r.field=='rounds.spare_rounds'end)
    local own=rounds and type(rounds.descriptor)=='table'and type(rounds.descriptor.teamReload)=='table'
        and rounds.descriptor.teamReload.ownSpares==true
    if own then
        check(rounds.editable and rounds.note and rounds.note:find('5-round clip',1,true),'AC-8 own rounds editable: '
            ..tostring(rounds.note))
        check(rounds.acks and rounds.acks.allow_unverified_effect or rounds.unverified,
            'AC-8 own rounds carry allow_unverified_effect')
        out[#out+1]='team reload ok (AC-8 own rounds editable)'
    else
        check(rounds and not rounds.editable,'AC-8 own rounds locked')
        out[#out+1]='team reload ok'
    end
end
-- the rearm pool (0.31.0): read-only on the Eagles with the Runtime's reason, labelled options elsewhere
local pool=find(rows('st|Eagle 500kg Bomb'),function(r)return r.field=='stratagem.rearm_pool'end)
if pool then
    check(not pool.editable and pool.reason,'Eagle rearm pool read-only')
    local other=find(rows('st|Orbital Railcannon Strike'),function(r)return r.field=='stratagem.rearm_pool'end)
    check(other.editable and catalog.text(other,49):find('Eagle Rearm',1,true),'rearm pool labels')
    out[#out+1]='rearm pool ok'
end
-- derived heat values (0.31.0) shown read-only, naming the fields to edit
local warmup=find(rows('pw|LAS-16 Sickle'),function(r)return r.field=='heat.warmup'end)
if warmup then
    check(not warmup.editable and warmup.section=='Wind-up'and warmup.reason~='','derived warm-up')
    out[#out+1]='derived heat ok'
end
-- sentries: their weapon's heat under the mounted weapon
local heat=find(rows('st|A/LAS-98 Laser Sentry'),function(r)return r.field=='heat.capacity'end)
if heat then
    check(heat.section=='Mounted Weapon · Heat','sentry heat section: '..heat.section)
    out[#out+1]='mounted sections ok'
end
-- beam conversion (feature branch): present only with the API
local bc=find(rows('pw|AR-23 Liberator'),function(r)return r.conversion~=nil end)
if type(hd2.beam_conversion)=='function'and has('beam_conversion')then
    check(bc and bc.group=='Beam Conversion','conversion rows on the Liberator')
    local refused=rows('pw|DBS-2 Double Freedom')
    local verdict=find(refused,function(r)return r.key:find('bc:verdict',1,true)end)
    check(verdict and not verdict.editable and verdict.reason:find('ROUNDS_NO_BEAM_RELOAD',1,true),'refused verdict')
    check(not find(refused,function(r)return r.conversion and r.editable end),'a refused weapon has no conversion fields')
    check(not find(rows('pw|LAS-13 Trident'),function(r)return r.group=='Beam Conversion'end),'out of scope: none')
    local per=find(rows('pw|AR-23 Liberator'),function(r)return r.key:find('bc:damage.standard_damage',1,true)end)
    check(per and per.section:find('interim, max 6',1,true)and per.acks.allow_component_swap,'per-weapon rows')
    out[#out+1]='beam conversion ok'
else
    check(not bc,'no conversion rows without the API')
    out[#out+1]='no beam conversion ok'
end
-- the ammunition swap (HD2Runtime 0.30.x: weapon:projectile_source() names the default ammunition): on the ammunition,
-- shared, not on the dormant base member
if A and type(A.ammunition)=='table'and A.ammunition['AR-23 Liberator']then
    for _,key in ipairs({'pw|AR-23 Liberator','pw|P-2 Peacemaker'})do
        local swap=find(rows(key),function(r)return r.field=='ammunition.projectile'end)
        check(swap and swap.editable and swap.shared and swap.section=='Projectile · Swap'
            and swap.note:find('default ammunition',1,true),key..' ammunition swap')
    end
    check(not find(rows('pw|SMG-32 Reprimand'),function(r)return r.field=='ammunition.projectile'end),
        'a component host has no ammunition swap')
    out[#out+1]='ammunition swap ok'
end
-- HD2Runtime 0.31.1: the Peacemaker's ammunition row, the missile direct hit and the ProgrammableAmmo rows
local peacemaker=find(rows('pw|P-2 Peacemaker'),function(r)return r.field=='damage.player_standard_damage'
    or r.field=='damage.standard_damage'end)
local hit=find(rows('sp|FAF-14 Spear'),function(r)return r.descriptor and r.descriptor.missileHit end)
local flak=find(rows('sp|AC-8 Autocannon'),function(r)return r.descriptor and r.descriptor.programmableFeed end)
-- On a Runtime that has them (0.31.1 and later), all three must be there: never skipped silently.
local version=tostring(hd2.version or'')
local major,minor,patch=version:match('^(%d+)%.(%d+)%.(%d+)')
local has_0_31_1=major and(tonumber(major)*1e6+tonumber(minor)*1e3+tonumber(patch))>=31001
if has_0_31_1 then
    -- the G-4 Gas explosion's status slots: Gas and Gas Confusion, and a third status with its strength
    local gas=rows('th|G-4 Gas')
    local function slot(field)return find(gas,function(r)return r.field==field end)end
    local third,strength=slot('explosion.damage.status_3_type'),slot('explosion.damage.status_3_strength')
    check(third and strength and slot('explosion.damage.status_1_type'),'G-4 Gas status slot rows')
    check(third.section=='Explosion · Status'and third.vanilla=='none'and third.shared and third.unverified,
        'G-4 Gas third status: '..tostring(third.section))
    local offered={}
    for _,o in ipairs(third.labels or{})do offered[o.value]=true end
    -- (acid_storm only where the Runtime's status catalogue makes it attachable: HD2Runtime 0.31.2)
    local SC=has('status_catalog')and require('hd2runtime/domains/status_catalog')
    local storm=SC and SC.statuses and SC.statuses.acid_storm
    check(offered.none and offered.fire and(offered.acid_storm or false)==(storm and storm.attachable==true or false),
        'G-4 Gas third status choices')
    check(peacemaker and hit and flak,('0.31.1 rows on %s: Peacemaker %s, Spear direct hit %s, AC-8 flak %s'):format(
        version,tostring(peacemaker~=nil),tostring(hit~=nil),tostring(flak~=nil)))
end
if peacemaker and hit and flak then
    check(peacemaker.section=='Damage · Direct hit'and peacemaker.vanilla==100 and peacemaker.unverified and peacemaker.shared,
        'Peacemaker damage: '..tostring(peacemaker.section))
    check(hit.section:find('^Damage · Missile direct hit')and hit.unverified,'Spear direct hit: '..hit.section)
    local ac8=rows('sp|AC-8 Autocannon')
    local function section(label)return find(ac8,function(r)return r.section==label end)end
    check(section('Projectile · Flak')and section('Damage · Flak direct hit')and section('Projectile · Flak · Swap')
        and section('Explosion · Flak'),'AC-8 flak sections')
    local burst=find(ac8,function(r)return r.section=='Explosion · Flak'and r.field=='explosion.damage.standard_damage'end)
    check(burst and burst.vanilla==190 and burst.unverified,'the flak burst from the explosion catalogue')
    -- the RL-77 cluster rocket's burst damage is its primary rocket's row: shown once, under the primary impact
    local rl77=rows('sp|RL-77 Airburst Rocket Launcher')
    check(find(rl77,function(r)return r.section=='Explosion · Cluster Bomb'and r.field=='explosion.inner_radius'end)
        and not find(rl77,function(r)return r.section=='Explosion · Cluster Bomb'
            and r.field=='explosion.damage.standard_damage'end),'RL-77 burst rows not shown twice')
    -- a projectile's own damage is its direct hit (a player took the RL-77's 350 for its blast); the cluster rocket's
    -- is the very same row as the rocket's, and says so
    local rocket=find(rl77,function(r)return r.field=='damage.standard_damage'and r.section=='Damage · Direct hit'end)
    local cluster=find(rl77,function(r)return r.field=='damage.standard_damage'and r~=rocket end)
    check(rocket and rocket.vanilla==350,'RL-77 rocket direct hit')
    check(cluster and cluster.loc==rocket.loc
        and cluster.section=='Damage · Cluster rocket direct hit (same row as the rocket)','RL-77 cluster: '
        ..tostring(cluster and cluster.section))
    out[#out+1]='0.31.1 damage rows ok'
else
    check(not hit and not flak,'no 0.31.1 rows without the Runtime fields')
    out[#out+1]='no 0.31.1 rows ok'
end
-- vehicle mounts by what they are (the Runtime names them "slot_3"), the Bastion MG's belt, the network maxima
do
    local VW=require('hd2runtime/domains/vehicle_weapon_authoring')
    if VW.weapons['TD-110 Maelstrom / slot_3']and VW.weapons['TD-220 Bastion MK XVI / attach_tank_gun_mg']then
        local groups={}
        for _,r in ipairs(rows('ve|TD-110 Maelstrom'))do if r.group then groups[r.group]=true end end
        check(groups['Weapon · Driver gun']and groups['Weapon · Missile pods (slot 3)']
            and groups['Weapon · Missile pods (slot 4)']and not groups['Weapon · Slot 3'],'Maelstrom mounts named')
        check(groups['Weapon · Main cannon']and not groups['Weapon · Attach tank gun'],'Maelstrom main cannon named')
        local mount=find(rows('ve|TD-110 Maelstrom'),function(r)return r.mount_slot=='slot_0'end)
        check(not mount or mount.label=='Main cannon','Maelstrom main mount row: '..tostring(mount and mount.label))
        local bastion=rows('ve|TD-220 Bastion MK XVI')
        local mg=find(bastion,function(r)return r.group=='Weapon · Coaxial MG'and r.field=='weapon.capacity'end)
        check(find(bastion,function(r)return r.group=='Weapon · Cannon'end),'Bastion cannon named')
        check(mg and mg.note and mg.note:find('2047',1,true),'Bastion MG belt note')
        -- an older Runtime publishes no maximum: the editor holds the network's; HD2Runtime 0.31.2+ publishes its own
        check(mg.max and mg.max<=2047,'Bastion MG capacity max: '..tostring(mg.max))
        local mags=find(bastion,function(r)return r.group=='Weapon · Coaxial MG'and r.field=='magazine.magazines_from_supply'end)
        check(not mags or(mags.max and mags.max<=31),'magazine count max: '..tostring(mags and mags.max))
        out[#out+1]='vehicle mounts ok'
    end
end
-- damage zones by their native names where the Runtime's entity data has one ("Zone N" otherwise)
do
    local E=require('hd2runtime/domains/entity_authoring')
    local exo=E.vehicles and E.vehicles['EXO-55 Breakthrough Exosuit']
    if exo and exo.zones and exo.zones.zone_2 and exo.zones.zone_2.name=='cockpit_rear'then
        local sections={}
        for _,r in ipairs(rows('ve|EXO-55 Breakthrough Exosuit'))do
            if r.group=='Damage Zones'then sections[r.section]=true end
        end
        check(sections['Cockpit rear']and not sections['Zone 2']and sections['Zone 0'],'vehicle zone names')
        local namer=catalog.zone_namer({zone_1={index=1,name='leg'},zone_2={index=2,name='leg'},zone_3={index=3}})
        check(namer('zone_1')=='Leg (Zone 1)'and namer('zone_3')=='Zone 3','a shared zone name keeps its number')
        out[#out+1]='zone names ok'
    end
end
-- the Sterilizer's status slots point to the acid statuses for its spray
do
    local sterilizer=rows('sp|TX-41 Sterilizer')
    local slot=find(sterilizer,function(r)return r.field=='damage.status_1_type'end)
    local offered=false
    for _,l in ipairs(slot and slot.labels or{})do if l.value=='acid_stream'then offered=true end end
    if offered then
        check(slot.note and slot.note:find('acid_splash',1,true),'Sterilizer status slot note')
        out[#out+1]='sterilizer note ok'
    end
end
-- the localisation template's catalogue part: every object name, section, group and field label it shows, once
do
    local texts,seen=cat:texts(),{}
    for _,t in ipairs(texts)do check(not seen[t],'text listed twice: '..t);seen[t]=true end
    for _,t in ipairs({'AR-23 Liberator','Health & Armor','Damage Zones','Fire rate','Support weapon','Explosion'})do
        check(seen[t],'template text missing: '..t)
    end
    out[#out+1]='catalogue texts ok ('..#texts..')'
end
return table.concat(out,'\n')

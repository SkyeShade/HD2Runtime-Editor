-- The rows HD2Runtime 0.31.0 (beam conversion included) adds, each checked only where the Runtime under test
-- publishes it: sections, labels, locks and acknowledgements. Returns one line per check that ran.
local hd2=require('hd2runtime/api/hd2')
local catalog=require('mods/skyeshade/hd2runtime_editor/editor/catalog')
local sections=require('mods/skyeshade/hd2runtime_editor/editor/ui/sections')
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
    -- (HD2Runtime 0.31.2: the burst is the flak's own impact explosion, under its payload slot)
    local payloads=find(ac8,function(r)return r.field=='terminal.explosion'end)~=nil
    local flak_burst=payloads and'Explosion · Flak · Impact'or'Explosion · Flak'
    check(section('Projectile · Flak')and section('Damage · Flak direct hit')and section('Projectile · Flak · Swap')
        and section(flak_burst),'AC-8 flak sections')
    local burst=find(ac8,function(r)return r.section==flak_burst and r.field=='explosion.damage.standard_damage'end)
    check(burst and burst.vanilla==190 and burst.unverified,'the flak burst from the explosion catalogue')
    -- the RL-77 cluster rocket's burst damage is its primary rocket's row: shown once, under the primary impact
    local rl77=rows('sp|RL-77 Airburst Rocket Launcher')
    local cluster_burst=payloads and'Explosion · Cluster Bomb · Impact'or'Explosion · Cluster Bomb'
    check(find(rl77,function(r)return r.section==cluster_burst and r.field=='explosion.inner_radius'end)
        and not find(rl77,function(r)return r.section==cluster_burst
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
-- the ammunition supply together (0.9.4): the magazine capacity (a weapon field) in "Ammo & Magazine" with the spare,
-- starting and supply counts and the reload, in that order, on vehicle mounts, sentries and support weapons; the other
-- weapon fields stay in Handling / Fire; row keys unchanged
do
    local RANK={'capacity','spare','starting','supply','reload'}
    local function kind(field)
        local rank=catalog.ammo_rank(field)
        return rank and RANK[rank]or nil
    end
    -- the rows of one section, in order, by kind
    local function order(list,group,field)
        local anchor=find(list,function(r)return r.group==group and r.field==field end)
        if not anchor then return nil end
        local kinds={}
        for _,r in ipairs(list)do
            if r.group==group and r.section==anchor.section and kind(r.field)then kinds[#kinds+1]=kind(r.field)end
        end
        return table.concat(kinds,' '),anchor
    end
    local checked=0
    for _,item in ipairs({{'ve|TD-220 Bastion MK XVI','Weapon · Cannon'},
        {'ve|TD-220 Bastion MK XVI','Weapon · Coaxial MG'},{'ve|EXO-45 Patriot Exosuit','Weapon · Left gun'},
        {'sp|MG-43 Machine Gun'},{'st|A/MG-43 Machine Gun Sentry'}})do
        local list=rows(item[1])
        local text,anchor=order(list or{},item[2],'weapon.capacity')
        if text then
            checked=checked+1
            local where=item[1]..(item[2]and(' / '..item[2])or'')
            check(sections.classify(anchor.section)=='ammo','capacity in Ammunition on '..where..': '..anchor.section)
            check(anchor.section:find('Ammo & Magazine$'),'capacity in Ammo & Magazine on '..where..': '..anchor.section)
            check(text:find('^capacity'),'capacity first on '..where..': '..text)
            local last=0
            for word in text:gmatch('%S+')do
                local r
                for i,k in ipairs(RANK)do if k==word then r=i end end
                check(r>=last,'ammunition order on '..where..': '..text)
                last=r
            end
            check(anchor.key:find('weapon.capacity',1,true)and not anchor.key:find('Ammo',1,true),
                'row key unchanged: '..anchor.key)
            -- the remaining weapon rows of the same object in Handling / Fire
            local rate=find(list,function(r)return r.group==item[2]and r.field=='weapon.fire_rate'end)
            check(not rate or sections.classify(rate.section)=='fire','fire rate in Handling / Fire on '..where)
        end
    end
    check(checked>0,'no page with weapon.capacity')
    -- rounds-fed weapons: the feed capacity first (the AC-8 and, HD2Runtime 0.31.3, the EXO-55 Breakthrough cannon)
    for _,item in ipairs({{'sp|AC-8 Autocannon'},{'ve|EXO-55 Breakthrough Exosuit','Weapon · Right gun'}})do
        local text=order(rows(item[1])or{},item[2],'rounds.spare_rounds')
        if text then
            check(text:find('^capacity')and text:find('spare starting supply',1,true),item[1]..' rounds order: '..text)
        end
    end
    -- a mount without a reload (HD2Runtime 0.31.3 reloadComponent.present = false): its spare counts say so
    local mg=rows('ve|TD-220 Bastion MK XVI')
    local spare=find(mg,function(r)return r.group=='Weapon · Coaxial MG'and r.field=='magazine.spare_magazines'end)
    if spare and type(spare.descriptor.reloadComponent)=='table'and spare.descriptor.reloadComponent.present==false then
        check(spare.note and spare.note:find('expected to have no effect',1,true),'no-reload note: '..tostring(spare.note))
        local cannon=find(mg,function(r)return r.group=='Weapon · Cannon'and r.field=='magazine.spare_magazines'end)
        check(cannon and not cannon.note,'the cannon reloads: no note')
        out[#out+1]='no reload note ok'
    end
    out[#out+1]='ammunition together ok'
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
-- status slots: each slot's status and strength together, in slot order, linked to their neighbours; every slot the
-- Runtime publishes (HD2Runtime 0.31.2: up to 4 on every damage row; older ones the first empty slot)
do
    local evictor=rows('pw|GL-15 Evictor')
    local slots={}
    for _,r in ipairs(evictor or{})do
        if r.status_slot and r.field:find('^explosion%.')then slots[#slots+1]=r end
    end
    if#slots>0 then
        local section=slots[1].section
        check(section:find(' · Status$'),'status slots in the Status section: '..section)
        for i,r in ipairs(slots)do
            local n,kind=math.floor((i+1)/2),i%2==1 and'type'or'strength'
            check(r.section==section and r.status_slot.n==n and r.status_slot.kind==kind,'slot order: '..r.key)
            check(r.label==(kind=='type'and('Status '..n)or('Status '..n..' strength')),'slot label: '..r.label)
            check(n==1 and r.status_slot.prev==nil or r.status_slot.prev==slots[2*n-3],'slot link: '..r.key)
        end
        -- the rows of one section follow each other on the page
        local o=cat:object('pw|GL-15 Evictor')
        for _,s in ipairs(o.sections)do
            if s.label==section then
                for i,r in ipairs(slots)do check(s.rows[i]==r,'section rows in slot order')end
            end
        end
        if#slots>=4 then
            -- a second attached status is not live-tested: allow_unverified_effect even on a direct-hit row
            local hit
            for _,r in ipairs(evictor)do if r.field=='damage.status_2_type'then hit=r end end
            check(hit and hit.acks.allow_unverified_effect and hit.status_slot.n==2,'direct hit slot 2 acknowledgement')
            local ok=catalog.probe(slots[3],'gas_confusion')
            check(ok,'slot 2 takes gas_confusion')
            out[#out+1]='status slots ok ('..#slots/2 ..' on the Evictor blast)'
        else
            out[#out+1]='status slot ok (first empty slot only)'
        end
    end
end
-- catalogue explosions on the page of what sets them off: the RL-77's bomblets (spawned by both its rockets' bursts)
-- and the Hellbombs' detonation (HD2Runtime 0.31.1+ hd2.explosion; the NUX-223 has no stratagem data of its own)
do
    local E=has('explosion_catalogue')and require('hd2runtime/domains/explosion_catalogue')
    local all=E and type(hd2.explosion)=='function'and E.explosions or{}
    local bomblets=all['support_weapon/rl77_airburst_rocket_launcher/function_expiry/shrapnel_expiry']
    if bomblets then
        local rl77=rows('sp|RL-77 Airburst Rocket Launcher')
        -- (named by the Runtime's owner-neutral alias, HD2Runtime 0.31.2; shrapnel before it)
        local section=bomblets.aliases and'Explosion · Bomblets'or'Explosion · Shrapnel'
        local function bomblet(field)
            return find(rl77,function(r)return r.section==section and r.field==field end)
        end
        local damage,outer=bomblet('explosion.damage.standard_damage'),bomblet('explosion.outer_radius')
        check(damage and damage.vanilla==500 and damage.shared and damage.unverified and damage.acks.allow_shared,
            'RL-77 bomblet damage')
        check(outer and outer.vanilla==6 and bomblet('explosion.inner_radius').vanilla==4
            and bomblet('explosion.shockwave_radius').vanilla==8,'RL-77 bomblet radii')
        check(require('mods/skyeshade/hd2runtime_editor/editor/export').trace(damage.target)
            =='hd2.explosion("support_weapon/rl77_airburst_rocket_launcher/function_expiry/shrapnel_expiry")',
            'bomblet target')
        local seen={}
        for _,r in ipairs(rl77)do
            if r.section:find('^Explosion')then
                check(not seen[r.loc],'one explosion row per native field: '..r.key);seen[r.loc]=true
            end
        end
        out[#out+1]='rl77 bomblets ok'
    end
    if all['backpack/b100_portable_hellbomb/behavior']and all['stratagem/nux223_hellbomb/behavior']then
        local nux=cat:object('ex|NUX-223 Hellbomb')
        check(nux and nux.category=='resupply','NUX-223 Hellbomb listed under Mission')
        local function detonation(key,field)
            return find(rows(key),function(r)return r.section=='Explosion · Detonation'and r.field==field end)
        end
        local a=detonation('sb|B-100 Portable Hellbomb','explosion.damage.standard_damage')
        local b=detonation('ex|NUX-223 Hellbomb','explosion.damage.standard_damage')
        check(a and b and a.vanilla==10000 and a.loc==b.loc,'both Hellbombs write one damage row')
        local ap=detonation('ex|NUX-223 Hellbomb','explosion.damage.ap_direct')
        check(ap and ap.vanilla==10,'Hellbomb armor penetration')
        for _,r in ipairs({a,b,ap})do
            check(r.acks.allow_shared and r.acks.allow_unverified_effect and r.note:find('both Hellbombs',1,true),
                'Hellbomb acknowledgements and note: '..r.key)
        end
        out[#out+1]='hellbombs ok'
    else
        check(not cat:object('ex|NUX-223 Hellbomb'),'no NUX-223 entry without its catalogued explosion')
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
-- hellpods: an empty slot is shown as Empty (hd2.pickup('empty') raises; every empty slot used to be left out), and a
-- rack HD2Runtime publishes read-only is locked with its own reason, not as another mod's value
do
    local P=has('pod_payload_authoring')and require('hd2runtime/domains/pod_payload_authoring')
    local rack=P and P.racks and P.racks['EAT-411 Leveller pod']
    local second=rack and rack.slots and(rack.slots['2']or rack.slots[2])
    if type(second)=='table'and second.current=='empty'then
        local slot2=find(rows('sp|EAT-411 Leveller'),function(r)return r.key:find('payload.slot_2',1,true)end)
        check(slot2 and slot2.editable and slot2.vanilla=='empty'and catalog.text(slot2,'empty')=='Empty',
            'EAT-411 empty slot 2 shown: '..tostring(slot2 and catalog.text(slot2,slot2.vanilla)))
        out[#out+1]='empty hellpod slots ok'
    end
    local tx=P and P.racks and P.racks['TX-41 Sterilizer pod']
    if type(tx)=='table'and tx.writable==false then
        local count=find(rows('sp|TX-41 Sterilizer'),function(r)return r.field=='payload.spawn_count'end)
        check(count and not count.editable and count.reason==tx.reason and not count.foreign and not count.editor_lock,
            'TX-41 Items spawned locked with the Runtime reason')
        out[#out+1]='read-only hellpod ok'
    end
    -- HD2Runtime 0.31.2: the TX-41's rack is writable: its items spawned and slots in the Hellpod section, in the
    -- Hellpod / Call-in category (last on a weapon's page)
    if type(tx)=='table'and tx.writable==true then
        local object=cat:object('sp|TX-41 Sterilizer')
        local list=rows('sp|TX-41 Sterilizer')
        local count=find(list,function(r)return r.field=='payload.spawn_count'end)
        local slot1=find(list,function(r)return r.field=='payload.entity'and r.label=='Slot 1'end)
        check(count and count.editable and slot1 and slot1.editable,'TX-41 items spawned and slot 1 editable')
        check(count.section=='Hellpod'and slot1.section=='Hellpod','in the Hellpod section: '..count.section)
        local plain={}
        for _,s in ipairs(object.sections)do if not s.group then plain[#plain+1]=s end end
        local cats=sections.layout(plain,object.category)
        local last=cats[#cats]
        check(last.id=='call_in'and last.title=='Hellpod / Call-in','Hellpod / Call-in last: '..tostring(last.title))
        local pod
        for _,sub in ipairs(last.subs)do if sub.title=='Hellpod'then pod=sub end end
        local has_count,has_slot=false,false
        for _,r in ipairs(pod and pod.rows or{})do
            if r==count then has_count=true end
            if r==slot1 then has_slot=true end
        end
        check(has_count and has_slot,'both in its Hellpod subsection')
        check(catalog.text(slot1,slot1.vanilla)~='Empty'and#slot1.options(slot1)>1,'slot 1 holds the TX-41, others offered')
        out[#out+1]='sterilizer hellpod ok'
    end
end
-- HD2Runtime 0.31.2: projectile swaps on the LAS-99 Quasar and the RS-422 Railgun (the fired-type trace), first in the
-- Projectile category; every donor needs allow_unverified_reference (HOST_STRUCTURE_UNVERIFIED) and the own projectile
-- needs nothing. The swap's own rows (projectile, direct hit, impact explosion, their statuses) follow it; the heat,
-- charge and the Railgun's overcharge explosion do not. The M-1000 Maxigun and the GL-28 stay read-only with the
-- Runtime's reason, shown where the swap would be.
local function first_projectile_row(key)
    local object=cat:object(key)
    local plain={}
    for _,s in ipairs(object.sections)do if not s.group then plain[#plain+1]=s end end
    local cats=sections.layout(plain,object.category)
    return cats[1].id=='projectile'and cats[1].subs[1].title=='Projectile type'and cats[1].rows[1]or nil
end
do
    local traced,read_only=0,0
    for _,item in ipairs({{'LAS-99 Quasar Cannon','EAT-17 Expendable Anti-Tank'},{'RS-422 Railgun','APW-1 Anti-Materiel Rifle'}})do
        local name,donor_name=item[1],item[2]
        local ok,src=pcall(function()return hd2.support_weapon(name):projectile_source('primary')end)
        local swap=find(rows('sp|'..name),function(r)return r.field=='attack.projectile'end)
        if ok and type(src)=='table'and src.writable then
            check(swap and swap.editable and swap.swap_scope=='attack:primary',name..' swap writable')
            check(first_projectile_row('sp|'..name)==swap,name..' swap first in Projectile')
            local donor
            for _,o in ipairs(swap.options(swap))do if o.label==donor_name then donor=o.value end end
            check(donor,name..' offers '..donor_name)
            local okp,acks=catalog.probe(swap,donor)
            check(okp and acks.allow_unverified_reference and acks.allow_unverified_effect,
                name..' donor needs allow_unverified_reference: '..tostring(acks))
            check(catalog.probe(swap,swap.vanilla),name..' own projectile restores')
            local follows={}
            for _,r in ipairs(swap.fires_rows or{})do
                follows[r.field]=true
                check(not tostring(r.field):find('^heat')and not tostring(r.field):find('^charge')
                    and not tostring(r.section):find('Overcharge',1,true),name..' swap takes only projectile rows: '..r.key)
                check(r.fires_from==swap,name..' row linked to its swap')
            end
            check(follows['projectile.velocity']and follows['damage.standard_damage']and follows['damage.status_1_type'],
                name..' projectile, direct hit and status rows follow the swap')
            if name=='LAS-99 Quasar Cannon'then
                check(follows['explosion.inner_radius']and follows['explosion.damage.status_1_type'],
                    'the Quasar impact explosion follows the swap')
            end
            traced=traced+1
        elseif ok and type(src)=='table'and src.status and swap then
            check(not swap.editable and swap.reason==src.reason,name..' read-only with the Runtime reason')
        end
    end
    if traced==2 then out[#out+1]='traced hosts ok'end
    for _,name in ipairs({'M-1000 Maxigun','GL-28 Belt-Fed Grenade Launcher'})do
        local ok,src=pcall(function()return hd2.support_weapon(name):projectile_source('primary')end)
        if ok and type(src)=='table'and src.status and not src.writable then
            local swap=find(rows('sp|'..name),function(r)return r.field=='attack.projectile'end)
            check(swap and not swap.editable and swap.reason==src.reason and swap.section=='Projectile · Swap'
                and not swap.foreign and not swap.editor_lock and catalog.text(swap,swap.vanilla)=='Own projectile',
                name..' swap shown read-only with the Runtime reason')
            check(first_projectile_row('sp|'..name)==swap,name..' read-only swap first in Projectile')
            read_only=read_only+1
        end
    end
    if read_only==2 then out[#out+1]='read-only swaps ok'end
end
-- player weapons: the swap on the attack, or on the default ammunition (the Liberator), takes the projectile rows
do
    local adj=find(rows('pw|BR-14 Adjudicator'),function(r)return r.swap_scope=='attack:primary'end)
    local lib=find(rows('pw|AR-23 Liberator'),function(r)return r.swap_scope=='attack:primary'end)
    for _,swap in ipairs({adj,lib})do
        check(swap.fires_rows and#swap.fires_rows>0,swap.key..' has own projectile rows')
        for _,r in ipairs(swap.fires_rows)do
            check(tostring(r.field):find('^projectile%.')or tostring(r.field):find('^damage%.')
                or tostring(r.field):find('^explosion%.')or tostring(r.field):find('^terminal%.')
                or tostring(r.field):find('^status%.'),swap.key..' follows only projectile rows: '..r.key)
        end
    end
    check(find(rows('pw|AR-23 Liberator'),function(r)return r.field=='weapon.fire_rate'end).fires_from==nil,
        'the fire rate follows no swap')
    -- a vehicle's mounts: each swap takes its own mount's rows only, and its donor shows in the mount's group
    local exo=cat:object('ve|EXO-49 Emancipator Exosuit')
    if exo then
        cat:open(exo)
        local mounts=0
        for _,swap in ipairs(exo.swap_rows or{})do
            mounts=mounts+1
            check(swap.group and swap.fires_rows and#swap.fires_rows>0,swap.key..' has its mount rows')
            for _,r in ipairs(swap.fires_rows)do check(r.group==swap.group,swap.key..' takes only its mount: '..r.key)end
            local donor
            for _,o in ipairs(swap.options(swap))do
                local id=catalog.donor_of(swap,o.value)
                if id then donor=id;break end
            end
            for _,s in ipairs(cat:donor_sections(exo,swap,donor))do
                check(s.group==swap.group,'donor in the mount group: '..tostring(s.group))
            end
        end
        check(mounts==0 or mounts==2,'both Emancipator mounts swap: '..mounts)
        if mounts==2 then out[#out+1]='mount swap scopes ok'end
    end
    out[#out+1]='swap scopes ok'
end
-- HD2Runtime 0.31.2: the LAS-99 Quasar's cooling while overheated, right after the cooling rate in Heat, with its note
do
    local list=rows('sp|LAS-99 Quasar Cannon')
    local at
    for i,r in ipairs(list or{})do if r.field=='heat.cool_per_second_overheated'then at=i end end
    if at then
        local row=list[at]
        check(list[at-1].field=='heat.cool_per_second','right after the cooling rate: '..tostring(list[at-1].field))
        check(row.editable and row.section=='Heat'and sections.classify(row.section)=='heat','in Heat / Charge')
        check(row.label=='Cooling rate while overheated','its label: '..tostring(row.label))
        check(row.note and row.note:find('100 / this value',1,true)and row.note:find('15 s',1,true),'its note')
        check(row.acks.allow_unverified_effect,'needs allow_unverified_effect')
        check(row.min==0.1 and row.max==1000,'range 0.1 to 1000: '..tostring(row.min)..' '..tostring(row.max))
        out[#out+1]='quasar overheated cooling ok'
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

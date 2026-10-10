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
return table.concat(out,'\n')

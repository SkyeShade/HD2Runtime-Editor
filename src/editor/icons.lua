-- Game atlas handles, with locally generated images retained for older icon categories.
local M={}
local KINDS={stratagem='stratagems',booster='boosters',weapon='weapons',throwable='throwables',
    faction='factions',objective='objectives'}
function M.load(hd2,generated)
    local resources=hd2.resources
    if type(resources)~='table'then return nil,0 end
    local icons,count={},0
    for _,key in pairs(KINDS)do icons[key]={}end
    if generated and type(resources.image)=='function'then
        for _,key in pairs(KINDS)do for name,entry in pairs(generated[key]or{})do
            local ok,handle=pcall(resources.image,entry.image)
            if ok and handle then
                icons[key][name]={handle=handle,accent=entry.accent,dark=entry.dark,aspect=entry.aspect}
                count=count+1
            end
        end end
    end
    if type(resources.game_icon)=='function'and type(resources.game_icons)=='function'then
        for kind,key in pairs(KINDS)do
            local ok,names=pcall(resources.game_icons,kind)
            for _,name in ipairs(ok and type(names)=='table'and names or{})do if not icons[key][name]then
                local got,handle=pcall(resources.game_icon,kind,name)
                if got and handle then
                    local info={}
                    if type(handle.describe)=='function'then
                        local good,d=pcall(handle.describe,handle);if good then info=d end
                    end
                    icons[key][name]={handle=handle,game=true,atlas=kind~='stratagem'and kind~='booster',
                        monochrome=info.mode=='mask',
                        aspect=info.width and info.height and info.width/info.height or 1}
                    count=count+1
                end
            end end
        end
    end
    return icons,count
end
local STRATAGEM={st=true,sp=true,sb=true,ve=true,rs=true,ex=true}
function M.entry(icons,object)
    if not icons then return nil end
    if object.iconKind then
        local entry=(icons[KINDS[object.iconKind]]or{})[object.iconName]
        if entry then return entry end
        if object.iconKind=='objective'then return(icons.factions or{})[object.iconFaction] end
    end
    local family=tostring(object.key):match('^(%a+)|')
    if family=='pw'or family=='sp'or family=='sw'then
        local entry=(icons.weapons or{})[object.name];if entry then return entry end
    elseif family=='th'then return(icons.throwables or{})[object.name]
    elseif family=='bo'then return(icons.boosters or{})[object.name]end
    if STRATAGEM[family]then return(icons.stratagems or{})[object.stratagem or object.name]end
end
-- Explicit display assignments to reviewed objective symbols; no gameplay relationship is implied.
local OBJECTIVES={
    cy_stratagem_blocker='cy_destroy_stratagem_blocker',spawner_jammer='cy_destroy_stratagem_blocker',
    cy_detector_tower='cy_destroy_detector_tower',
    cyborg_gunship_spawner='cy_destroy_gunship',
    il_scrambler_battery='il_disable_stratagem_scrambler',
    il_spawner_ship='il_destroy_spawners',il_spawner_portal='il_destroy_portals',
    il_weather_device_tower='il_destroy_weather_device',il_weather_device_battery='il_destroy_weather_device',
    cyborg_cooling_structure='cy_destroy_cooling_structure',
    gen_radar_terminal='gen_radar_station',radar_station='gen_radar_station',radar_tower='gen_radar_station',
    bug_fog_generator='bug_foggenerator',bug_fog_generator_large='bug_foggenerator',
    bug_fog_generator_tcs='bug_foggenerator',spore_lung='bug_hive_world_destroy_spore_lung',
    bug_spawner_shrieker='bug_shrieker_nest',bug_spawner_stalker='bug_destroy_stalker_lair',
    bug_spawner_base='bug_destroy_spawners',bug_spawner_scavenger='bug_destroy_spawners',
    turret_mortar='cy_mortar_emplacement',turret_antiair='cy_aa_emplacement',turret_anti_air='cy_aa_emplacement',
    idle_sam_site='gen_samsite',sam_site='gen_samsite',sam_site_launcher='gen_samsite',
    sam_site_foundation='gen_samsite',sam_site_launcher_terminal='gen_samsite',
    seaf_artillery='gen_seaf_gun',icbm_silo='gen_icbm',icbm_silo_wide='gen_icbm',
    spawner_factory_conscript_base='cy_destroy_spawners',spawner_factory_conscript_assault='cy_destroy_spawners',
    cy_destroy_factories='cy_destroy_spawners',command_bunker='cy_destroy_command_bunker',
    command_bunker_side='cy_destroy_command_bunker',
    encounter_ship_landed='il_destroy_spawners',encounter_ship_landed_door_shield='il_destroy_spawners',
    illuminate_invasionship='il_shoot_down_mothership',il_monolith='il_destroy_monolith',
    il_obj_asset_weather_device_core='il_destroy_weather_device',
    il_obj_asset_weather_device_generic_shield='il_destroy_weather_device',
    turret_tactical_obj='il_orbital_cannon',il_city_cannon_terminal='il_orbital_cannon',
    city_cannon_lock='il_orbital_cannon',
    truth_transmitter_tower_terminal='gen_truth_transmitter',truth_transmitter_tower_speakers='gen_truth_transmitter',
    central_core_drill_01='bug_central_core',central_core_hole_plug_nav='bug_central_core',
    bug_central_core_hole='bug_central_core',
}
function M.entity(name,entry)
    local leaf=name:match('([^/]+)$')or name
    local objective=OBJECTIVES[name]or OBJECTIVES[entry.className]or OBJECTIVES[leaf]
    if not objective and leaf:match('^spawner_factory_conscript_')then objective='cy_destroy_spawners'end
    if not objective and leaf:match('^bug_spawner_')then objective='bug_destroy_spawners'end
    local faction=entry.faction
    if faction=='helldivers'then faction='super_earth'end
    if faction~='automatons'and faction~='terminids'and faction~='illuminate'and faction~='super_earth'then faction=nil end
    if objective or entry.kind=='structure'then return'objective',objective or leaf,faction end
    if faction=='automatons'or faction=='terminids'or faction=='illuminate'or faction=='super_earth'then
        return'faction',faction
    end
end
return M

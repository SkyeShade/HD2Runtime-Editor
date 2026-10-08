# HD2Runtime work the editor is waiting on

Collected from player reports and editor work up to editor main `601a0ae`, checked against the HD2Runtime branch
`wip/custom-projectile-rows` at `37f8c8a` (0.30.2 in development). Each item says what players asked for, what the
Runtime has today, and the evidence. The second part lists what 0.30.2 already gives the editor, and the editor-only
work.

## Runtime work

### R1. Weapons blocked by a duplicate identity (7)

`ordinaryWritesBlocked` in `sdk/PlayerWeaponAuthoringCapabilities.json`. The editor shows their stats read-only with
"HD2Runtime blocks this weapon for now".

| Weapon | Roots | State |
|---|---|---|
| GP-31 Grenade Pistol | 0x52E4334E6A128CAF, 0x02CD7321CD8445F5 | **Known fix.** The second root is the AR/GL-21 One-Two underbarrel (`research/underbarrel-weapons-F5FEE03DCFDB.json` `catalogCorrections`); keep 0x52E4334E6A128CAF. |
| P-72 Crisper | 0x3F92BA65EF65CCA9, 0x992B6F65A5BAB53D | **Known fix.** The second root is the SMG/FLAM-34 Stoker underbarrel; keep 0x3F92BA65EF65CCA9. |
| LAS-5 Scythe | 0x27EE1ED8F6FB6356, 0x7E3145A5BAA4B948 | `laser_rifle` and `laser_rifle_charge` fire the same BeamSettings row; the published heat data matches `laser_rifle` only. `docs/player-weapon-authoring.md`: "would touch about 45 generated catalogs", left for a reviewed disambiguation. |
| LAS-7 Dagger | 0x2B3C367B280F4094, 0x7B06196E90154C88 | Ambiguous; also "unresolved scale/count disagreements" (`docs/player-weapon-composition.md`). |
| CQC-42 Machete | 0x792D5D2A340FD6E6, 0x5F3EC9BDA2BD8553 | Ambiguous. |
| CQC-73 Entrenchment Tool | 0x7E1F76163C667E4B, 0xE85E623F93F96FB3 | Ambiguous. |
| SMG-37 Defender | 0x4E4A613EB9BF5C24, 0xCA4BBEF63C869C18 | Ambiguous. |

Players asked for the LAS beam weapons' stats (Scythe, Dagger) by name. GP-31 and P-72 only need the generator
(`scripts/generate_weapon_authoring.py`) to drop the misattributed root. The editor unlocks a weapon by itself once
it is `UNIQUE`.

### R2. MG-43 and G-16 sentry projectile swaps

Request: "change the projectile type of the machine gun turret to re-educator rounds" (as Shodan's editor does).
0.30.2 made 7 sentries and emplacements projectile hosts (`6466da4`). The A/MG-43 Machine Gun Sentry and A/G-16
Gatling Sentry stay read-only: "The magazine names each round (a pattern with tracers), not ProjectileWeapon +0; a
swap needs the pattern rewritten too (planned)." This is the exact turret the player asked about.

### R3. P-2 Peacemaker and P-19 Redeemer damage (and the MP-98 Knight)

Request: "not able to change the dmg on the peace maker or the redeemer".
Both are `INDIRECT` ammunition hosts (`AttackOutputCapabilities.json` `projectileSources`): the default ammunition
patches ProjectileWeapon +0 at weapon build. Their catalogue entries have no `projectile.*` or `damage.*` fields at
all (domains: fire_mode, fire_rate, function_ammo, magazine, presentation, weapon, weapon_function), unlike the
Liberator, which is also an ammunition host. The ammunition is shared:

- P-2 Peacemaker: PISTOL-SMG 9x20mm. HOLLOW POINT, also on the MP-98 Knight and the P-19 Redeemer;
- P-19 Redeemer: PISTOL-SMG 9x20mm. FULL METAL JACKET, also on the MP-98 Knight.

Wanted: the default ammunition projectile's projectile and damage fields on `weapon:ammunition():projectile()`,
with `allow_shared` naming the other weapons. The Knight is `UNPROVEN_PROJECTILE_SOURCE` (equippable ammunition).

### R4. Reload time for most primaries and secondaries

Request: "reload speed for support weapons but not primaries".
- `reload.duration` (WeaponReloadComponentData +56) is defined for player weapons, but no player weapon has it: +56
  is 0 on them, and the reload ability's own duration applies (`docs/support-weapon-api.md`: "A 0 duration means
  the reload ability's default applies and stays read-only").
- 19 of 80 primaries and secondaries get a reload time through their magazine attachment
  (`attachment.reload_duration`, `docs/magazine-attachments.md`). That value is shared by every weapon that can
  mount the magazine.
- The other 61 have none. Wanted: the reload ability duration as a field, per weapon where it is the weapon's own.
- The underbarrel weapons (One-Two, Arbitrator, Stoker) list the same gap in `notExposed`: "reload time (the reload
  ability's duration; WeaponReload +56 is 0)".

### R5. LAS-16 Sickle and LAS-17 Double-Edge Sickle wind-up / wind-down

Request: "Sickle/Dickle are missing the wind-up/down".
- `windup.wind_up_seconds` / `windup.wind_down_seconds` (WeaponWindUpComponentData +0 / +4) are defined for player
  weapons, but only the M-1000 Maxigun, the EXO-45 Patriot right gun and the TD-110 Maelstrom tank gun have a
  WeaponWindUp component (`AttackOutputCapabilities.json` `ownerFireResource`). No player weapon does.
- The Sickles' heat fields include `heat.warmup`, read-only: "No owned WeaponHeat scalar reproduced warmup across
  beam and projectile heat families."

Worth confirming first which in-game mechanic the player means (a fire-rate ramp, or the heat warm-up), then where
it lives.

### R6. Team-reload backpack ammunition (AC-8 Autocannon, GR-8 Recoilless Rifle, FAF-14 Spear, airburst launcher)

Request: "backpack weapons like autocannon, you cannot manually edit ammo for them like starting rounds or max spare
rounds like in Shodan".
- `docs/backpack-ammo.md` "Not covered": these backpacks use deposits through `assisted_reload_weapon_path`, their
  start amount is the `-1` sentinel, and they "stay read-only". Only the Maxigun, Cremator and Belt-Fed Grenade
  Launcher backpacks are authorable.
- **Misleading catalogue rows:** the AC-8 Autocannon's weapon carries `rounds.spare_rounds`, `rounds.starting_rounds`
  and `rounds.rounds_from_supply` as writable, with 0 defaults, while the backpack holds its ammunition. Players
  edit them and nothing happens. Either a reason saying the backpack holds the ammunition, or read-only.

### R7. Fire-mode write refused: "invalid/ambiguous bounded pointer"

A player's log (HD2Runtime 0.30.1):

```
patch hd2editor-2-fire-mode-modes REJECTED code=VALIDATION_FAILED reason=hd2runtime/core/bytes.lua:77: invalid/ambiguous bounded pointer
```

`core/entity.lua:24`: the entity map's membership pointer was neither an offset in the bounded body nor a pointer
relocated to the same body. The same session ran two mods that load many weapon packages at startup (bfgl grenade
rounds and the Evictor "kitchen sink": 28 asset gates). One guess, not verified: a weapon package loaded or reloaded
by them leaves the map elsewhere. The weapon is unknown: the editor's log lines did not name it. From editor `601a0ae`
they do (`field <weapon> · Fire modes: ...`), so the next report will say which.

### R8. Not live-tested yet (every write needs `allow_unverified_effect`)

The editor offers these, and players will try them:
- the underbarrel weapons' fields (`hd2.weapon(host):underbarrel()`): "whether a built underbarrel keeps a copy of it
  and the gameplay effect of an edit are not yet shown in game";
- the 0.30.2 sentry and emplacement swaps (`6466da4`) and player-weapon explosion statuses (`74494b7`);
- the 15 `other_system` statuses (`c591d1b`, experimental).

### R10. GameGuard kill after armor class writes (high priority)

Report: "When I modified light, medium and heavy armour to have +50 armour rating and for heavy armour to have 75
stamina regen the game got killed by gameguard." Log: `HD2Runtime (9).log` (0.30.1).

What the log shows:
- The edits came from a ModBuilder-built mod, not the editor (no HD2R Editor lines; operation ids `entity-...`).
  They applied at startup: `armor_class.rating` light 0 -> 1, medium 1 -> 2, heavy 2 -> 3, and heavy
  `armor_class.stamina` 1.5 -> 1.25 (stamina regen 50 -> 75). 41 operations applied, none rejected.
- **The wheel hook was never installed:** no `wheel: native message hook installed` line, and no mod window opened.
  The hook only installs on a mod window's first wheel or block query. So the hook is not the cause here.
- The log ends right after the lobby post, with no error: the process was killed from outside.

The lead: these are the only writes in the log **into game.dll's image**. `docs/armor-stats.md` "Class tables:
reviewed executable data": the class tables (armor `0x21CB160`, speed `0x2160678`, stamina `0x21C6F78`) and the
damage curve are in game.dll's read-only initialized-data section, mapped PAGE_EXECUTE_READWRITE, written under the
2026-10-08 exception. Every other write in the log is to resource records. An anti-cheat that hashes the module image
would see exactly these bytes change. Not proven: worth a test with the same mod minus the four `armor_class` writes,
and with only them.

If confirmed:
- The class tables and the curve should not be written in place. Kit piece weights (light / medium / heavy only) and
  the local player's armor bonus and stamina factor (`hd2.armor_stats.player()`) reach similar results without
  touching the image; a class beyond heavy, as here, would need another non-image lever.
- The editor offers the class tables and the curve today (Helldiver → Armor). Until then it could warn on those rows
  or hide them.

### R9. Smaller

- `core/shared_records` builds its whole index on first use: 60 to 130 ms in one call (a 131.8 ms frame in the
  player's log). The editor now triggers it while the mod loads; building it per resource on demand would remove
  the spike for every caller.
- The underbarrel weapons' fired projectile is unproven (`notExposed`: "ProjectileWeapon +0 and WeaponRounds +64
  hold the same projectile"), so their projectile cannot be swapped.

## What 0.30.2 gives the editor

| Change | Editor today | Editor work |
|---|---|---|
| Player-weapon explosion statuses (`74494b7`, 26 fields) | Shows all 26 already (status choice rows) | None |
| 23 more attachable statuses (`c591d1b`) | The status choices list them already | None; the experimental tier could be labelled |
| Sentry and emplacement swaps (`6466da4`, 7 writable) | None shown | A Projectile · Swap row on each, through `hd2.stratagem(name):attack('primary'):projectile_source()`; MG-43 / G-16 read-only with the reason |
| Wheel hook as an install choice (`b6cf2cc`, `caed769`, `ab2e937`) | Scrolls with `hd2.input.wheel`; with the hook off, `hd2.input.block()` refuses, so the "Keep keys, clicks and the wheel from the game" setting does nothing, silently | Show `wheel_status().notice`; say why that setting is off |
| Mouse focus kept over a game menu (`88e3648`) | Nothing to do | None |

## Editor-only work (the Runtime has it already)

- Support weapon projectile swaps (8 hosts, `hd2.support_weapon(name):attack(role)`).
- Vehicle, Exosuit and Guard Dog gun swaps (9 hosts, `hd2.vehicle(name):weapon(mount):projectile_source()`).
- Ammunition-host swaps for the AR-23 Liberator, JAR-5 Dominator, R-63 Diligence, SG-225 Breaker, P-2 Peacemaker and
  P-19 Redeemer (`weapon:ammunition():projectile()`, `hd2.fields.ammunition.projectile`).
- Weapon functions: `weapon_function.left` / `.right` (none, rate_of_fire, programmable_ammo) and
  `function_ammo.projectile` (types `weapon_function`, `function_projectile_reference`), which ModBuilder projects
  use.
- Mounted weapon swaps in the ModBuilder import.
- A primary's magazine reload time near the top of its Ammo section (it now sits inside Magazines), and the
  backpack-fed weapons' zero rounds rows marked as backpack-owned (until R6).
- ModBuilder: an importer that turns an editor custom-Lua block back into rows (ModBuilder repo).

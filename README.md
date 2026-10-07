<p align="center"><img src="assets/HD2Editor%20%C2%B7%20icon%401x.png" width="96" alt="HD2Runtime Editor icon"></p>

# HD2Runtime Editor

**Live, in-game editing of every value [HD2Runtime](https://github.com/SkyeShade/HD2Runtime) exposes, on top of the mods you have installed.**

HD2Runtime Editor is a Helldivers 2 mod with its own in-game window. It shows which HD2Runtime mods you have installed and what each one changes. You can edit any field HD2Runtime can write, including fields a mod already sets, and apply the edits live. Reset to defaults gives everything back exactly as your mods and the game had it.

- **See what your mods do.** The Mods tab lists every installed HD2Runtime mod with the values it applied this session, and any operation the Runtime refused, with the reason. Select a value to jump to that field.
- **Every writable field, in familiar categories.** Weapons (Primary, Secondary, Throwables), Stratagems colour-coded like the game (Offensive in red, Defensive in green, and in blue Support Weapons, Support Backpacks, Vehicles and Resupply), Equipment (Boosters) and Enemies (Terminids, Automatons, Illuminate, Structures). That is about 17,300 fields, read from the installed Runtime's own catalogues, so the defaults, ranges and safety flags always match your Runtime.
- **One stratagem, one place.**
  - A support weapon holds its call-in, the weapon, the backpack it comes with and its hellpod.
  - A support backpack holds its call-in, the backpack, its drone weapon (Guard Dogs) and its hellpod.
  - A vehicle holds its call-in, the vehicle and every mounted weapon.
  - A vehicle's mounts can hold another weapon, as in ModBuilder (the Patriot's left arm with the Emancipator's
    autocannon, for example). Once a mount is swapped, its weapon group shows the weapon it now holds, so the
    projectile and stats you edit are that weapon's. The group says which other vehicle shares those records.
  - A backpack that comes with a support weapon is never shown on its own.
  - Magazine options sit inside each weapon that uses them.
- **Weapon groups.** Primary and Secondary have a filter under the search box with the armory's groups (Assault
  Rifle, Marksman Rifle, Submachine Gun, Shotgun, Explosive, Energy-Based, Special; Pistol, Melee, Special).
- **Tidy long lists.** Damage zones (vehicles, deployables, enemies), enemy attacks, magazines and vehicle weapons are groups that start closed. Each part inside them opens on its own.
- **More than numbers.**
  - **Calldown codes:** an arrow-key code editor. Right-click an arrow to remove it; DEFAULT restores the game's code.
  - **Fire modes and rate-of-fire modes**, as in ModBuilder.
  - **Mission uses:** a count or unlimited.
  - **Hellpod contents:** the items a support weapon, backpack or Resupply pod drops, and how many.
  - **Projectile swaps and terminal explosion payloads**, from a searchable donor list.
  - **Statuses, on/off switches and enums.**

  Every value is checked with the Runtime's own validator before it is staged. A refused value shows the Runtime's reason.
- **The game's own icons.** Every stratagem and booster shows its icon from your installed game, coloured as on the loadout screen (an opt-in local build step, see [Game icons](#game-icons)). Only SG-88 and CQC-72 show a category glyph instead: they have no call-in stratagem, so the game has no icon for them. Values a mod sets carry a mod icon.
- **Edit over mods, safely.** If a mod sets the Liberator's fire rate to 1200 and you set 1300, the editor takes that field over through the Runtime's guarded writes, and 1300 applies. **Reset to defaults** puts it back to 1200, the mod's value, not the game's.
- **Optimised apply.** Edits are staged as pending changes and applied together. Only fields whose value changed are written, and each change is a single guarded write.
- **Presets.** Save the current values as a named preset, then load, overwrite, rename or delete it. The values you applied last can be restored automatically when the game starts.
- **No custom Lua.** The editor only changes fields HD2Runtime already exposes. For new behaviour, custom stratagems or a mod to share, use [HD2Runtime ModBuilder](https://github.com/SkyeShade/HD2Runtime-ModBuilder).

> **Status: 0.4.0, development build for HD2Runtime r51.** Everything is tested offline against the real HD2Runtime source (see [Tests](#tests)). 0.2.0 on r50 was seen in game (text placement, icons, value editing). The 0.3.0 and 0.4.0 changes (categories, groups, fire modes, hellpods, the wheel, the weapon filter, mount swaps, HUD icons) are not live-tested yet.

## Requirements

- Helldivers 2
- Bingus Shared Loader v15+
- **HD2Runtime 0.30.0-dev r51 or later.**
  - r50 adds script choices (`mod:choice`, for non-numeric fields), overlay images (`d:image`, for icons), cursor capture (`overlay:free_cursor`), the overlay text placement fix, and naming the mod behind each applied value for mods built without the SDK wrapper.
  - r51 adds the mouse wheel (`hd2.input.wheel`) and, in its SDK, the HUD icon extractor that [Game icons](#game-icons) uses. On r50 everything else works; the lists scroll with the scrollbar only.
  - On an older 0.30.0-dev with the UI services (`hd2.ui.overlay`, `hd2.store`, `hd2.on_frame`, `hd2.input.pressed`), numbers still edit. Non-numeric fields then explain that they need r50, and icons and cursor capture are simply absent.
  - Without the UI services at all, the editor stays inactive and writes the reason to `HD2Runtime.log`.

## Installation

Install `HD2RuntimeEditor-<version>.zip` with your mod manager (HD2 Arsenal shows its icon and description), next to HD2Runtime. Like every HD2Runtime mod, it does not bundle the Runtime.

## Using it

Press **F8** in game to open or close the editor, or **Esc** to close it (the game's pause menu also opens on Esc). The window is centred on the screen.

While it is open, the editor asks the engine to free the mouse from the camera: show the cursor, stop clipping it, and drop the camera's mouse focus. This is experimental in r50; turn it off in Presets → settings if it misbehaves. Keys and clicks still also reach the game, because HD2Runtime cannot block input, so the ship is the most comfortable place to edit.

| Key | Action |
| --- | --- |
| F8 | Open or close the editor |
| ↑ ↓, PgUp PgDn, Home End | Move in the focused list |
| → / ← | Go deeper or back (categories, objects, fields). In the field list: nudge the value (Shift ×10, Ctrl ÷10) |
| Tab / Shift+Tab | Next pane / next tab (Browse, Mods, Presets) |
| Digits, `.`, `-` | Type a value for the selected field. Tab, ↑ or ↓ confirms; Del cancels |
| Enter | Choose a value for a non-numeric field (picker, code, fire mode or rate editor); open a group |
| → / ← on a group | Open / close it (← on a field inside it jumps back to its group) |
| Right-click | Remove an arrow in the calldown code editor |
| Del | Remove a field's pending change, or stage it back to its default |
| Ctrl+F | Search the object list |
| Ctrl+← / Ctrl+→ | Previous / next weapon group (Primary, Secondary) |
| F9 | Apply pending changes |
| F10 | Reset to defaults (asks first) |
| Ins | Save a new preset (Presets tab) |

Wherever the cursor is free, the mouse works too: click tabs, rows, groups, value boxes and buttons. To scroll a list, drag its scrollbar, click the track, or use the wheel (r51). The window and every popup have an × to close them.

What each field shows:

| Source | Meaning |
| --- | --- |
| *(none)* | The game's own value |
| `MOD` (blue) | A value an installed mod applied |
| `PENDING` (orange) | Your staged change; press Apply |
| `APPLYING` | Being written through HD2Runtime |
| `EDITED` (yellow) | Your value is live |
| `ERROR` | HD2Runtime refused the change; the status bar says why |
| `LOCKED` | This value cannot be held exactly (more than 3 decimals) |

The status bar shows the selected field's id and range, whether it is **SHARED** (other weapons or objects use the same record), whether its effect is unverified in game, and which mod set it.

## How edits stay safe

HD2Runtime refuses to let one mod overwrite another mod's value. That is a deliberate guard, and the editor keeps it. It never writes over a value. Instead, for each field you change:

1. **Adopt.** The editor registers its own HD2Runtime `ensure` for the field. The ensure's value is a live handle set to the value the game holds now (vanilla, or the mod's), so the first guarded check finds the bytes already as desired, and from then on the ensure owns them.
2. **Hand-over.** If a mod's `ensure` holds that field, every field of that mod's operation is adopted first. Only then is the mod's ensure stopped, so nothing it maintained is dropped. A mod's one-time patch has nothing to stop.
3. **Steer.** The handle moves to your value, and HD2Runtime re-applies it as an owned change: same guards, fingerprints and rollback as any mod write.
4. **Reset.** The handle moves back to the mod's value (or vanilla). If the base is vanilla or a mod's one-time patch, the editor then lets go of the field. If the field came from a mod's ensure, the editor keeps holding the mod's value for the rest of the session, in that ensure's place.

The details, and the HD2Runtime internals this relies on, are in [docs/how-it-works.md](docs/how-it-works.md).

## Limitations

- **Not every value type.** Traits, sounds, weapon functions, function projectiles and stratagem presentation stay with ModBuilder.
- **Two field rules need more than one field at a time.**
  - The default fire mode can only be reordered, never held at its own value, so it is left out.
  - Filling an empty rate-of-fire slot on a weapon without a rate selector needs the selector bound in the same write. The editor shows the Runtime's reason, so change the slots the weapon already has.
- **Three decimals.** Values are held with at most three decimals (the Runtime's live-value precision). A float32 default such as `0.30000001192` is the same stored value as `0.3`, so every catalogued default qualifies.
- **When values apply.** Some values (fire rate, magazines, heat) are copied when the game builds a weapon, so a weapon you are holding may keep its old value until it is re-equipped or the next mission. Projectile, damage and explosion values apply on the next shot.
- **A mod's in-game options after a takeover.** Once the editor has taken a field over from a mod's `ensure`, that mod's Mod Options sliders no longer move that field for the rest of the session.
- **Swapped mounts share records.** A mounted weapon's stats are one set of records, so a swapped mount edits the same weapon on its own vehicle too (the group says which). A mount without its own catalogued weapon shows that its stats are not editable.
- **Multiplayer.** Writes follow HD2Runtime's rules. They change this machine's game data; what the host decides still wins.

## Game icons

`py tools/game_icons.py` reads icons from your installed game, read-only, through the HD2Runtime SDK, and the next build packs them in.

- **Sources.** First, the loadout screen's vector icon libraries. Then, for every stratagem and booster those leave out, the item's own HUD icon from the game's texture atlases (the SDK's `tools/hd2_hud_icons.py`, HD2Runtime r51). The HUD icons cover Maxigun, Meltagun, Jump Pack, Rover, Hot Dog, Supply FRV, Maelstrom, Eagle Gas Airstrike, Resupply, Integrated Extinguishers and Surplus EAT Allocation.
- **Output.** The game's icon masks go under `images/`, with a map in `src/editor/generated/`.
- **Removing them.** `py tools/game_icons.py --clean` deletes them again.

The icons are derived from Arrowhead's artwork. They are git-ignored and only end up in builds you make yourself, so publish such a build only if you are allowed to redistribute them. Without them the editor simply shows no icons.

## UI art

`tools/ui-art/art.html` is a page of HTML/CSS artboards in the editor's look: the mark, category and tab icons, buttons, chips and a README banner. `py tools/ui-art/export.py` renders each artboard to a transparent PNG (`@1x` and `@2x`) with headless Microsoft Edge, into `assets/ui/`. With `--game`, the 256 × 256 icon artboards also go to `images/`, ready for `d:image`.

## Building

The build uses the HD2Runtime SDK (the `sdk/` folder of an HD2Runtime checkout, or the extracted SDK ZIP).

```powershell
py build.py      # or double-click build.cmd
```

`build.py` finds the SDK through `HD2RUNTIME_SDK`, then the `sdk` path in `hd2runtime.json` (`../HD2Runtime/sdk`), then the parent folders. It runs `hd2.py build`, which packs every `src/**/*.lua` and ships the icon as `thumbnail.png` (the manifest's `IconPath`). It then writes the Arsenal description into `manifest.json`. The result is `build/HD2RuntimeEditor-<version>.zip`.

## Tests

```powershell
py -m unittest discover -s tests -v
```

The tests run on the game's own LuaJIT (`Helldivers 2/bin/lua51.dll`). Only that DLL is loaded, never the game. They load modules from an HD2Runtime checkout beside this folder (`HD2RUNTIME_ROOT` overrides the path).

- **Catalogue contract:** every one of the ~17,200 rows the editor builds passes HD2Runtime's own validator (`domains/patches.validate`) with a changed value. Non-numeric rows check their vanilla value and another value, with the acknowledgements the validator asks for.
- **Override layer:** the real `hd2.ensure`, script values, bind-time proofs and conflict rule run over a simulated byte store. The scenarios: vanilla edit and reset, taking over a mod's ensure (including its other fields), a one-time mod patch, a value outside the handle range, refusals, and reset-all.
- **Value fields:** calldown codes, mission uses, booleans, statuses, projectile swaps and terminal explosions over r50 script choices, plus a mod's calldown code taken over and given back.
- **UI:** the whole window, driven by scripted keys and clicks, including the picker, the code editor, Escape, the weapon filter and a mount swap. With generated icons, every stratagem and booster must have one. Every frame must stay within the overlay's limits: no refused items and at most 1024 primitives. `py tests/render_frames.py` renders recorded frames to PNG for review.

## License and credit

See [LICENSE](LICENSE). HD2Runtime Editor is built on [HD2Runtime](https://github.com/SkyeShade/HD2Runtime) by SkyeShade, and uses its public API and its in-game catalogues. It is an unofficial fan project, not affiliated with or endorsed by Arrowhead Game Studios or Sony Interactive Entertainment.

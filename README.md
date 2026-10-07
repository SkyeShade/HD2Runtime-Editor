<p align="center"><img src="assets/HD2Editor%20%C2%B7%20icon%401x.png" width="96" alt="HD2Runtime Editor icon"></p>

# HD2Runtime Editor

**Live, in-game editing of every value [HD2Runtime](https://github.com/SkyeShade/HD2Runtime) exposes, on top of the mods you have installed.**

HD2Runtime Editor is a Helldivers 2 mod with its own in-game window. It shows which HD2Runtime mods you have installed and what each one changes. You can edit any field HD2Runtime can write, including fields a mod already sets, and apply the edits live. Reset to defaults gives everything back exactly as your mods and the game had it.

- **See what your mods do.** The Mods tab lists every installed HD2Runtime mod with the values it applied this session, and any operation the Runtime refused, with the reason. Select a value to jump to that field.
- **Every writable field, in familiar categories.** Weapons (Primary, Secondary, Support Weapons, Throwables, Magazines), Stratagems (Offensive, Defensive, Support Call-ins), Equipment (Backpacks, Vehicles, Vehicle Weapons, Boosters) and Enemies (Terminids, Automatons, Illuminate, Structures). That is about 16,400 numeric fields, read from the installed Runtime's own catalogues, so the defaults, ranges and safety flags always match your Runtime.
- **Edit over mods, safely.** If a mod sets the Liberator's fire rate to 1200 and you set 1300, the editor takes that field over through the Runtime's guarded writes, and 1300 applies. **Reset to defaults** puts it back to 1200, the mod's value, not the game's.
- **Optimised apply.** Edits are staged as pending changes and applied together. Only fields whose value changed are written, and each change is a single guarded write.
- **Presets.** Save the current values as a named preset, then load, overwrite, rename or delete it. The values you applied last can be restored automatically when the game starts.
- **No custom Lua.** The editor only changes fields HD2Runtime already exposes. For new behaviour, custom stratagems or a mod to share, use [HD2Runtime ModBuilder](https://github.com/SkyeShade/HD2Runtime-ModBuilder).

> **Status: 0.1.0, development build.** All of this is tested offline against the real HD2Runtime source (see [Tests](#tests)). It has not been run in the game yet, and neither have the Runtime's overlay services it uses.

## Requirements

- Helldivers 2
- Bingus Shared Loader v15+
- **HD2Runtime 0.30.0-dev with the UI and game-mod services** (`hd2.ui.overlay`, `hd2.store`, `hd2.on_frame`, `hd2.input.pressed`; HD2Runtime commit `a020369` "Scripting services for UI and game mods" or later). The older `HD2Runtime-0.30.0-dev-runtime.zip` build does not have them. In that case the editor stays inactive and writes the reason to `HD2Runtime.log`.

## Installation

Install `HD2RuntimeEditor-<version>.zip` with your mod manager (HD2 Arsenal shows its icon and description), next to HD2Runtime. Like every HD2Runtime mod, it does not bundle the Runtime.

## Using it

Press **F8** in game to open or close the editor. Opening it aboard the ship is the most comfortable: the game still receives every key and click while the editor is open, because HD2Runtime cannot block input.

| Key | Action |
| --- | --- |
| F8 | Open or close the editor |
| ↑ ↓, PgUp PgDn, Home End | Move in the focused list |
| → / ← | Go deeper or back (categories, objects, fields). In the field list: nudge the value (Shift ×10, Ctrl ÷10) |
| Tab / Shift+Tab | Next pane / next tab (Browse, Mods, Presets) |
| Digits, `.`, `-` | Type a value for the selected field. Tab, ↑ or ↓ confirms; Del cancels |
| Del | Remove a field's pending change, or stage it back to its default |
| Ctrl+F | Search the object list |
| F9 | Apply pending changes |
| F10 | Reset to defaults (asks first) |
| Ins | Save a new preset (Presets tab) |

Wherever the cursor is free, the mouse works too: click tabs, rows, value boxes and buttons, and scroll lists with the wheel.

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

- **Numeric fields only.** Lists, references, status choices, traits and other non-numeric values are not editable here yet. ModBuilder covers them.
- **Three decimals.** Values are held with at most three decimals (the Runtime's live-value precision). A float32 default such as `0.30000001192` is the same stored value as `0.3`, so every catalogued default qualifies.
- **When values apply.** Some values (fire rate, magazines, heat) are copied when the game builds a weapon, so a weapon you are holding may keep its old value until it is re-equipped or the next mission. Projectile, damage and explosion values apply on the next shot.
- **A mod's in-game options after a takeover.** Once the editor has taken a field over from a mod's `ensure`, that mod's Mod Options sliders no longer move that field for the rest of the session.
- **Multiplayer.** Writes follow HD2Runtime's rules. They change this machine's game data; what the host decides still wins.

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

- **Catalogue contract:** every one of the ~16,400 rows the editor builds passes HD2Runtime's own validator (`domains/patches.validate`) with a changed value and the acknowledgements the row carries.
- **Override layer:** the real `hd2.ensure`, script values, bind-time proofs and conflict rule run over a simulated byte store. The scenarios: vanilla edit and reset, taking over a mod's ensure (including its other fields), a one-time mod patch, a value outside the handle range, refusals, and reset-all.
- **UI:** the whole window, driven by scripted keys. Every frame must stay within the overlay's limits: no refused items and at most 1024 primitives. `py tests/render_frames.py` renders recorded frames to PNG for review.

## License and credit

See [LICENSE](LICENSE). HD2Runtime Editor is built on [HD2Runtime](https://github.com/SkyeShade/HD2Runtime) by SkyeShade, and uses its public API and its in-game catalogues. It is an unofficial fan project, not affiliated with or endorsed by Arrowhead Game Studios or Sony Interactive Entertainment.

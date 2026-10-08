<p align="center"><img src="assets/HD2Editor%20%C2%B7%20icon%401x.png" width="96" alt="HD2R Editor icon"></p>

# HD2R Editor

*HD2R Editor (formerly HD2Runtime Editor) is a mod built on HD2Runtime; it is not HD2Runtime itself.*

**Live, in-game editing of every value [HD2Runtime](https://github.com/SkyeShade/HD2Runtime) exposes, on top of the mods you have installed.**

HD2R Editor is a Helldivers 2 mod with its own in-game window. It shows every mod you have deployed and what each HD2Runtime mod changes. You can edit any field HD2Runtime can write, including fields a mod already sets, and apply the edits live. Reset to defaults gives everything back exactly as your mods and the game had it.

- **See what your mods do.** The Mods tab lists every mod your mod manager (Echelon or HD2 Arsenal) deployed, with its icon (see [Mod icons](#mod-icons)): HD2Runtime mods first, then the other mods, each under its own heading.
  - HD2Runtime mods show the values they applied this session, any operation the Runtime refused (with the reason), and their in-game options with the current settings and the operations they drive. Select a value to jump to that field.
  - Other mods replace game files directly, so what they change cannot be read; their name, description and any Lua addons are shown.
  - A field a mod sets names the mod and, when its in-game options drive it, the options page.
- **Your changes in one place.** The Changes tab lists every value the editor applied or has pending (never your mods' own). Enter jumps to the field. Each change has a **RESET** button (or Backspace) that resets it right away, to the mod's value if a mod set one, else to the game's. Del or a right-click stages that reset for the next Apply instead.
- **Setting the default is a reset.** Editing a field back to its base value (the mod's value over a mod, else the game's) resets the field instead of holding an editor value equal to it. This also applies to presets and the restored session. A pending change like that shows as PENDING RESET.
- **Export your changes as a mod.** The Export tab is a three-step wizard. Pick which changes to include, give the mod a name, version, author, description and an HD2 Arsenal image from your PC, then press Export. It writes a mod ZIP, ready for your mod manager, in ModBuilder's layout (see [Exporting a mod](#exporting-a-mod)). The values are also saved as a preset.
- **The log, live.** The Logs tab follows `HD2Runtime.log` as it is written, coloured by kind (errors red, warnings orange, applied values green, the editor's own lines gold), with filters and buttons to open the file or its folder.
- **Custom stratagems.** The Custom tab lists the custom stratagems your mods registered, with their code, carrier and state, coloured like the game colours their carrier (offensive red, defensive green, support blue). Their cooldown and uses can be tuned on this machine, from the next call.
- **Every writable field, in familiar categories.** Weapons (Primary, Secondary, Throwables), Stratagems colour-coded like the game (Offensive in red, Defensive in green, and in blue Support Weapons, Support Backpacks, Vehicles and Resupply), Equipment (Boosters), Helldiver (Helldiver, Armor) and Enemies (Terminids, Automatons, Illuminate, Structures). That is about 19,800 fields, read from the installed Runtime's own catalogues, so the defaults, ranges and safety flags always match your Runtime.
- **One stratagem, one place.**
  - A support weapon holds its call-in, the weapon, the backpack it comes with and its hellpod.
  - A support backpack holds its call-in, the backpack, its drone weapon (Guard Dogs) and its hellpod.
  - A vehicle holds its call-in, the vehicle and every mounted weapon.
  - A vehicle's mounts can hold another weapon, as in ModBuilder (the Patriot's left arm with the Emancipator's
    autocannon, for example). Once a mount is swapped, its weapon group shows the weapon it now holds, so the
    projectile and stats you edit are that weapon's. The group says which other vehicle shares those records.
  - A backpack that comes with a support weapon is never shown on its own.
  - A weapon's attachments sit inside it: its magazines, muzzles, optics and underbarrels, each with its stat modifiers (sway, recoil, climb, spread, ergonomics). An attachment is shared by every weapon that can mount it.
  - A two-mode weapon holds its underbarrel weapon (the One-Two's grenade launcher, the Arbitrator's shotgun, the Stoker's flamer): its own rounds, resupply, magazine, fire rate and spread.
- **Weapon groups.** Primary and Secondary have a filter under the search box with the armory's groups (Assault
  Rifle, Marksman Rifle, Submachine Gun, Shotgun, Explosive, Energy-Based, Special; Pistol, Melee, Special).
- **Your Helldiver and their armor.**
  - **Helldiver:** movement speeds, stamina, the explosion damage share and the six body zones (damage multipliers, durable share, health). They apply to every Helldiver; speed and stamina do not reach the ship, whose Helldiver carries its own copy.
  - **Armor perks:** your own armor passive and a second passive on top of it. They are solo only and held for the session, not exported (see [Limitations](#limitations)).
  - **Armor:** every armor's piece weights (light, medium, heavy, per piece), the per-weight armor value, speed and stamina tables, and the armor damage curve. The list filters by weight; each armor shows its passive and its stats.
- **Tidy long lists.** Damage zones (vehicles, deployables, enemies, Helldivers), enemy attacks, attachments and vehicle weapons are groups that start closed. Each part inside them opens on its own.
- **More than numbers.**
  - **Calldown codes:** an arrow-key code editor. Right-click an arrow to remove it; DEFAULT restores the game's code.
  - **Fire modes and rate-of-fire modes**, as in ModBuilder. Filling an empty rate slot on a weapon without a rate selector (the Liberator, for example) binds the game's own selector in the same write.
  - **The armory's presentation:** each weapon's displayed traits (up to five, in order) and displayed armor penetration.
  - **Mission uses:** a count or unlimited. Type 0 or -1 for unlimited, or step below the lowest count, where the stratagem can be unlimited.
  - **Hellpod contents:** the items a support weapon, backpack or Resupply pod drops, and how many.
  - **Projectile swaps and terminal explosion payloads**, from a searchable donor list.
  - **Statuses, on/off switches and enums.**

  Every value is checked with the Runtime's own validator before it is staged. A refused value shows the Runtime's reason.
- **The game's own icons.** Every stratagem and booster shows its own HUD icon, drawn by HD2Runtime straight from the game's own atlas, with nothing shipped (or, in builds you make yourself, extracted locally; see [Game icons](#game-icons)). SG-88 and CQC-72 have no call-in stratagem, so the game has no icon for them: they show a plain square in their category colour.
- **Shared values, shown everywhere.** Some values are shared: one magazine can be mounted by several weapons, and some records are used by several enemies or stratagems. Selecting or changing such a field warns which other objects it also changes. A pending or applied change shows on every one of them, and all of them get the change markers.
- **What is changed, at a glance.** A yellow pencil piece marks what you edited, a blue piece what a mod changed, and an orange hourglass piece what is pending (not applied yet). They mark the objects in the lists, the categories that hold them, and every collapsible group and part inside an object (a vehicle weapon, a damage zone), so a change inside a closed group shows without opening it.
- **Readable on any screen.** Settings has an interface size from 90 % to 150 %: text and everything else scale together. A larger size keeps the window on screen by giving up height, never width; the lists simply show fewer rows and scroll.
- **Your language, your sounds.** The game's menu sounds play on the buttons (Settings). Every interface text can be translated with a plain text file (see [Localisation](#localisation)).
- **Edit over mods, safely.** If a mod sets the Liberator's fire rate to 1200 and you set 1300, the editor takes that field over through the Runtime's guarded writes, and 1300 applies. **Reset to defaults** puts it back to 1200, the mod's value, not the game's.
- **Optimised apply.** Edits are staged as pending changes and applied together. Only fields whose value changed are written, and each change is a single guarded write.
- **Presets.** Save the current values as a named preset, then load, overwrite, rename or delete it. The values you applied last can be restored automatically when the game starts.
- **Back and forth with ModBuilder.**
  - **Import:** the Presets tab lists your [HD2Runtime ModBuilder](https://github.com/SkyeShade/HD2Runtime-ModBuilder) projects, read from its library on your PC. A project shows its edits as editor fields; choose which to stage, then Apply. Edits the editor cannot take (scripts, custom content, a field this Runtime does not have) are listed with the reason.
  - **Export:** the Export tab's SAVE TO MODBUILDER puts your changes into ModBuilder's library as a project. ModBuilder opens and builds it, with your changes as the project's custom Lua, and the editor imports it again.
  - It never overwrites a project ModBuilder made. Reopen ModBuilder's project list to see a new one.
- **No custom Lua.** The editor only changes fields HD2Runtime already exposes. For new behaviour, custom stratagems or a mod to share, use [HD2Runtime ModBuilder](https://github.com/SkyeShade/HD2Runtime-ModBuilder).

> **Status: 0.8.3, for HD2Runtime 0.30.0.** Tested in game, and offline against the real HD2Runtime source (see [Tests](#tests)).

## Requirements

- Helldivers 2
- Bingus Shared Loader v15+
- **HD2Runtime 0.30.0 or later.**
  - Everything the editor uses is part of HD2Runtime 0.30.0: the UI overlay, script values and choices, the native mouse wheel and input blocking, every mod's options, custom stratagem tuning, and the Helldiver, armor and attachment fields.
  - If a Runtime lacks one of these, the part that needs it says so, or simply stays absent; the rest keeps working. Without the UI services at all, the editor stays inactive and writes the reason to `HD2Runtime.log`.

## Installation

Install `HD2REditor-<version>.zip` with your mod manager (HD2 Arsenal shows its icon and description), next to HD2Runtime. Like every HD2Runtime mod, it does not bundle the Runtime.

## Using it

Press **F8** in game to open or close the editor, or **Esc** to close it (the game's pause menu also opens on Esc). The window is centred on the screen. **Settings → Key to open and close the editor** picks another key or a Ctrl / Shift / Alt combination (Del on that row returns to F8).

While it is open, the editor asks the engine to free the mouse from the camera: show the cursor, stop clipping it, and drop the camera's mouse focus. This is experimental; turn it off in Settings if it misbehaves.

The tabs are Browse, Changes, Export, Mods, Custom, Presets, Logs and Settings (Shift+Tab cycles them). While it is open, key presses, mouse clicks and the wheel are kept from the game (experimental; Settings turns it off): Escape, Tab and Delete act only in the editor. Key releases still reach the game, so nothing stays held, and the game gets its input back the moment the editor closes.

| Key | Action |
| --- | --- |
| F8 | Open or close the editor (another key in Settings) |
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

- **Seven weapons are read only for now.** HD2Runtime cannot yet tell apart the two game records behind the LAS-5 Scythe, LAS-7 Dagger, CQC-42 Machete, CQC-73 Entrenchment Tool, GP-31 Grenade Pistol, P-72 Crisper and SMG-37 Defender, so it blocks writes to them. The editor still shows their stats, marked LOCKED; their attachments stay editable.
- **Not every value type.** Weapon functions, function projectiles, sounds and stratagem presentation stay with ModBuilder.
- **Fields that move together.**
  - The default fire mode can only be reordered, never held at its own value, so it is left out.
  - A weapon's displayed traits and displayed armor penetration share its five label slots: the editor holds one of them at a time (reset one to edit the other).
  - Filling an empty rate slot binds the rate selector with it; the M-1000 Maxigun's rate slots stay as the Runtime allows.
- **Three decimals.** Values are held with at most three decimals (the Runtime's live-value precision). A float32 default such as `0.30000001192` is the same stored value as `0.3`, so every catalogued default qualifies.
- **When values apply.** Some values (fire rate, magazines, heat) are copied when the game builds a weapon, so a weapon you are holding may keep its old value until it is re-equipped or the next mission. Projectile, damage and explosion values apply on the next shot.
- **A mod's in-game options after a takeover.** Once the editor has taken a field over from a mod's `ensure`, that mod's Mod Options sliders no longer move that field for the rest of the session.
- **Swapped mounts share records.** A mounted weapon's stats are one set of records, so a swapped mount edits the same weapon on its own vehicle too (the group says which). A mount without its own catalogued weapon shows that its stats are not editable.
- **Mods that are not HD2Runtime mods.** The editor lists them from your mod manager's own records; it cannot see or change what they do.
- **Custom stratagems.** Only their cooldown and uses can change after registration, and only on this machine.
- **Armor perks.** They change your own Helldiver only, in solo games, and only one mod at a time may change them. They last for the session (and come back with the session restore). They are not part of an exported mod.
- **Armor weights.** A piece's armor value changes on the next hit. Its speed and stamina change the next time the game applies the armor (a respawn or an armor change).
- **Multiplayer.** Writes follow HD2Runtime's rules. They change this machine's game data; what the host decides still wins.

## Exporting a mod

The Export tab (or **EXPORT AS MOD** in Changes) builds an HD2Runtime mod from your changes, inside the game:

1. **Changes:** every applied and pending editor value, all ticked; untick what the mod should not include.
2. **Details:**
   - the name, version (`1.0.0`), author and description the mod manager shows;
   - an Arsenal image: click the field (or press Enter) to choose a PNG or JPEG in the Windows file dialog, which opens over the game while the game keeps running. If the dialog cannot open, an in-game browser of your Pictures, Desktop, Downloads and Documents is used instead.
   The resource id is `mods/<author>/<name>`.
3. **Done:** the folder it wrote, with **OPEN EXPORT FOLDER** and **SHOW THE ZIP**. A preset named after the mod holds the exported values, so you can load them again later.

What it writes, in `Documents\HD2R Editor\Exports\<Name>-<version>\`:
- **`<Name>-<version>.zip`:** the mod, laid out as HD2Runtime ModBuilder lays out its exports.
  - `manifest.json`: name, version, description, the image as `IconPath`, and the dependency note.
  - `hd2runtime.json`, `build-report.json`, `README.md`, `src/addon.lua`, the image.
  - `mod/9ba626afa44a3aa3.patch_0`: the boot-package archive holding the addon, wrapped like the HD2Runtime SDK wraps one; byte for byte what the SDK's archive writer produces.
- **`project\`:** `hd2runtime.json`, `src/addon.lua` and the image, a project the HD2Runtime SDK can build again.

The addon has one guarded `hd2.ensure` per change:
- `expect` is the field's original value;
- the acknowledgements are the ones the Runtime's validator asks for;
- a rate list that fills an empty slot is a transaction with the rate selector binding.

Each target is written from the editor row's own target code (for example `hd2.weapon("AR-23 Liberator"):attack("primary"):projectile()`). The mod manager GUID is derived from the resource id the way ModBuilder derives it. Install the ZIP next to HD2Runtime like any HD2Runtime mod.

## Game icons

`py tools/game_icons.py` takes every stratagem's and booster's own HUD icon from your installed game, read-only, through the HD2Runtime SDK (`tools/hd2_hud_icons.py`), and the next build packs them in.

- **The game's pixels only.** A stratagem's HUD sprite is already the game's icon masks and is used as it is. A booster's sprite (a yellow plate with a dark glyph) is split onto the masks with its own measured colours, so the overlay draws the same picture. Nothing is drawn or traced; the loadout screen's vector library only supplies each stratagem's accent colour.
- **No icon:** an item the game has no sprite for (SG-88, CQC-72) gets a plain square in its category colour.
- **Removing them.** `py tools/game_icons.py --clean` deletes them again.

The icons are derived from Arrowhead's artwork. They are git-ignored and only end up in builds you make yourself, so publish such a build only if you are allowed to redistribute them.

**Without them, the editor draws the game's own icons through HD2Runtime** (`hd2.resources.game_icon`): straight from the game's own HUD atlas at run time, so nothing is shipped and nothing is written. A stratagem's category layer takes its category colour; a booster keeps its yellow plate. Booster icons are not shown during a mission, where the game unloads them. Icons you build locally take precedence.

## Mod icons

`py tools/mod_icons.py` reads the icons of the mods your mod manager deployed (Echelon or HD2 Arsenal, whichever deployed last) and packs them in at the next build. The overlay paints images as three colour masks, so each icon is reduced to its own nine most common colours and drawn as three stacked layers: the mod's own picture, with fewer colours. Mods installed after the build show the plain mod icon until you run the tool and build again. `--clean` removes them. The icons are their authors' artwork: like the game icons, they are git-ignored and stay in your own builds.

## Localisation

Every interface text goes through one lookup. To translate the editor:

1. In game, open **Settings** and press **WRITE TEMPLATE**. It writes `template.txt` (every interface text) into `%LOCALAPPDATA%\HD2REditor\localization\`.
2. Copy it to a new name ending in `.txt`, set the `@language` line, and write each translation after ` = `. Keep `%d` and `%s` where they are. Lines without a translation are ignored, and field names may be added too.
3. Press **RELOAD LANGUAGES**, then pick the language. The choice is saved.

`src/editor/strings.lua` lists the interface texts; `py tools/locale_strings.py` regenerates it, and a test keeps it current.

## UI art

`tools/ui-art/art.html` is a page of HTML/CSS artboards in the editor's look: the mark, category and tab icons, buttons, chips and a README banner. `py tools/ui-art/export.py` renders each artboard to a transparent PNG (`@1x` and `@2x`) with headless Microsoft Edge, into `assets/ui/`. With `--game`, the 256 × 256 icon artboards also go to `images/`, ready for `d:image`.

## Building

The build uses the HD2Runtime SDK (the `sdk/` folder of an HD2Runtime checkout, or the extracted SDK ZIP).

```powershell
py build.py      # or double-click build.cmd
```

`build.py` finds the SDK through `HD2RUNTIME_SDK`, then the `sdk` path in `hd2runtime.json` (`../HD2Runtime/sdk`), then the parent folders. It runs `hd2.py build`, which packs every `src/**/*.lua` and ships the icon as `thumbnail.png` (the manifest's `IconPath`). It then writes the Arsenal description into `manifest.json`. The result is `build/HD2REditor-<version>.zip`.

## Tests

```powershell
py -m unittest discover -s tests -v
```

The tests run on the game's own LuaJIT (`Helldivers 2/bin/lua51.dll`). Only that DLL is loaded, never the game. They load modules from an HD2Runtime checkout beside this folder (`HD2RUNTIME_ROOT` overrides the path).

- **Catalogue contract:** every one of the ~17,200 rows the editor builds passes HD2Runtime's own validator (`domains/patches.validate`) with a changed value. Non-numeric rows check their vanilla value and another value, with the acknowledgements the validator asks for.
- **Override layer:** the real `hd2.ensure`, script values, bind-time proofs and conflict rule run over a simulated byte store. The scenarios: vanilla edit and reset, taking over a mod's ensure (including its other fields), a one-time mod patch, a value outside the handle range, refusals, and reset-all.
- **Value fields:** calldown codes, mission uses, booleans, statuses, projectile swaps and terminal explosions over script choices, plus a mod's calldown code taken over and given back.
- **UI:** the whole window, driven by scripted keys and clicks, including the picker, the code editor, Escape, the weapon filter, a mount swap, the Changes, Mods (with in-game options), Custom (tuning) and Settings tabs, a language switch, the traits editor and the menu sounds. With generated icons, every stratagem and booster must have one.
- **Value fields** also cover filling the Liberator's empty rate slots (with its selector binding), the displayed traits and penetration (one at a time), and the steer watchdog.
- **Helpers:** the JSON reader (sliced), the mod managers' state, the localisation file format, and the interface text list. Every frame must stay within the overlay's limits: no refused items and at most 1024 primitives. `py tests/render_frames.py` renders recorded frames to PNG for review.

## License and credit

See [LICENSE](LICENSE). HD2R Editor is built on [HD2Runtime](https://github.com/SkyeShade/HD2Runtime) by SkyeShade, and uses its public API and its in-game catalogues. It is an unofficial fan project, not affiliated with or endorsed by Arrowhead Game Studios or Sony Interactive Entertainment.

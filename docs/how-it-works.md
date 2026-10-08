# How HD2R Editor works

## Modules (`src/`)

| File | Role |
| --- | --- |
| `addon.lua` | Entry point; the SDK wraps it with the dependency check and runs it as the mod (`hd2.events.run_as`). |
| `editor/main.lua` | Wiring: checks for the Runtime services, binds F8, ticks the layer every frame, restores and saves the session. Every module is required at load, because the engine resolves a mod's archived Lua only while its startup package is loaded. |
| `editor/catalog.lua` | Categories → objects → sections → rows, read from the installed Runtime's generated catalogues. One adapter per family; a family whose table changed shape is reported unavailable. |
| `editor/ledger.lua` | Which mod applied which value: an observer on `core/shared_records.claim`, plus the operation registry behind `hd2.diagnostics.operations`. |
| `editor/layer.lua` | The override layer: adopt, hand-over, steer, reset (below). |
| `editor/presets.lua` | Presets, the saved session and settings in `hd2.store`. |
| `editor/ui/*.lua` | The window: theme, canvas (scaled 1080p units, cached text metrics, hit regions), input (key repeat, typing, mouse, wheel), the app (Browse, staging, dialogs), pickers (the value picker, the code, fire mode, rate and traits editors) and views (Changes, Mods, Custom, Settings). |
| `editor/installed.lua`, `editor/json.lua` | Every deployed mod from the mod manager's own state (Echelon `state.json`, HD2 Arsenal `hd2a_data.json`), read with `io.open` and a JSON reader that yields, so the 1 MB file is parsed over a few frames. |
| `editor/i18n.lua`, `editor/strings.lua` | Localisation: `L(text)` looks every interface text up in the chosen language file; `strings.lua` lists the texts for the template. |
| `editor/sounds.lua` | The game's menu sounds on the buttons (`hd2.sounds.play('ui/generic_select')` and others), at most one per 40 ms. |
| `editor/generated/game_icons.lua` | Optional, written by `tools/game_icons.py`: stratagem and booster name → the image of its own HUD sprite (HD2Runtime SDK `tools/hd2_hud_icons.py`), its accent and, for boosters, the glyph colour. |
| `editor/generated/mod_icons.lua` | Optional, written by `tools/mod_icons.py`: a deployed mod's icon as up to three mask layers, each with its own three colours. |

## Rows

A row is one numeric field of one object, with:
- `target()`: builds the HD2Runtime target with the public builders;
- `field`: the semantic field id that target accepts;
- `vanilla`: the catalogue's `currentDefault`, which is also the request's `expect`;
- `min` / `max`: from the catalogue range, narrowed to the storage type's limits;
- acknowledgements: `allow_shared`, `allow_unverified_effect`;
- `loc`: the native record identity plus offset, from `shared_records.entry`; rows on the same bytes share it.

Its `key` (`<family>|<object>|<field>`) is stable across sessions and is what presets store.

How targets are built follows ModBuilder's rules:
- Damage and projectile rows of a player weapon target `hd2.weapon(w):attack(role):projectile()`. Weapons with no projectile attack (flame, arc, beam, melee) keep those rows on `hd2.weapon(w)`.
- Explosions target `...:terminal_action(phase):explosion()`.
- Role-scoped targets take the field id without its role and phase segments: `explosion.primary.impact.damage.standard_damage` becomes `explosion.damage.standard_damage`.
- Structures' health fields need `allow_unverified_effect` (`structureAcknowledgement`).

`tests/catalog_report.lua` validates every row with `domains/patches.validate`. Result: 16,401 of 16,402 rows. The exception is one enemy field whose reviewed domain is "-1, or above 0", and the test's sample value falls in the excluded gap.

## Non-numeric fields (r50)

Rows of kind `choice` (booleans, statuses, enums), `code` (calldown codes), `uses` (mission uses) and `reference` (projectile swaps, terminal explosions) go through the same four steps. The live handle is then a script choice (`mod:choice`, HD2Runtime r50) over just the values the change needs: the value held now, the target and the base.

- **Acknowledgements:** the ensure's bind-time proof validates every value of the choice. So before registering, the editor asks the Runtime's validator about each value and adds exactly the acknowledgements it names, for example `allow_unverified_reference` for a donor that is not live-tested, or `allow_unverified_effect` for a code equal to another stratagem's.
- **Donors:** projectile donors are the reviewed attack outputs. Terminal explosion donors are one player-weapon terminal action per reviewed explosion type, plus none. The picker offers only donors the validator accepts for that weapon.
- **Ownership:** a move between two references is an owned transition. This was proven live for projectile choices (`LiberatorAttackOutputTest`). r50 also fixed the signature of catalogue explosion donors.

## Filling empty rate slots (r52)

A `fire_rate.modes` list that fills two or more slots on a weapon whose rate selector is not bound
(`weapon:fire_rate_modes().state == 'addable'`, the Liberator for example) must bind the selector in the same write,
or the Runtime refuses it (`SELECTOR_REQUIRED`).

- **Staging:** `catalog.probe` validates such a value as the transaction the editor will register: the rates and
  `fire_rate_modes().binding`.
- **The write:** `Layer:register` registers a transaction ensure. Its rates are the usual script choice, and its binding
  is a second choice that follows it (`mod:choice{follow}`, HD2Runtime r52): bound for every value with two or more
  rates, unbound for the others. One `set` moves both, and the ensure proves them together.

## The armory's presentation

`presentation.armor_penetration` is a choice row and `presentation.traits` a `traits` row (an ordered list of up to five
trait ids, edited in a two-column picker). Both write the weapon's five label slots, so they have the same location;
`Layer:set` refuses one while the editor holds the other. Both need `allow_unverified_effect`. They are read when a menu
builds its item view.

## A first edit writes directly

A field that still holds its original value, which no mod holds and no editor ensure watches, is not adopted and then
steered. The editor registers one ensure whose script value starts at the user's value; its expect is the original
value, so its first resolution writes the change. A steer that followed an adopt was seen live to settle without
writing (r53: `applied_signature` equal to the new signature, `rebinds` 1), so a first edit never steers. Adopt and
steer remain for fields a mod holds and for later edits of a field the editor already holds.

## When a change does not confirm

The layer waits for the ensure to report `waiting` with one more completed run after a steer. If the ensure has not even
started to apply after 4 s (its `rebinds` did not move: seen live on r52), a fresh ensure takes the field over: it is
adopted again at the value it holds and steered from there, at most twice. A steer that started but has not confirmed
after 20 s shows an error with the ensure's state (`status`, `runs`, `rebinds`, `recoveries`, `error`, and on r53 its
`debug()` settle state) instead of applying forever. Every editor ensure's status
changes (`on_status`) and every steer are written to `HD2Runtime.log`.

If the stuck field still holds its original value, the stuck ensure is cancelled instead and the value is written
directly by a fresh ensure (as above).

## A steer is never skipped (0.7.1)

Live, every steer after the first edit of a field stalled (r52 to r55): the ensure's settle ran but found the rebuilt
signature equal to `applied_signature`, its record of what it last applied, so it took the no-op path (`rebinds`
unchanged, nothing written). No offline run reproduces it. The editor therefore clears that record whenever it steers,
which is what the Runtime's listener could do itself: the settle then always resolves again, and a value already in
place is just `ALREADY_DESIRED`. The record is the `applied_signature` upvalue of `watch.debug` (r53), reached with
LuaJIT's `debug` library; without either the editor behaves as before. The steer line in the log says
`re-resolve forced` when this was done.

If a steer still has not settled after 4 s, the editor first settles the same ensure again (record cleared,
`dirty` set, no debounce) and logs what it found:
- the handle's value;
- the applied and the rebuilt signature;
- `SAME` (the value did not reach the ensure) or `DIFFERENT` (the settle should have applied it).

Only then does it take the field over with a fresh ensure, as above. A failed field starts fresh on its next edit.

## Helldiver, armor and attachments (r55)

- **Helldiver** (`hd2.helldiver()`, `:zone(id)`): the rows are built from `domains/helldiver_writes.fields(path, zone)`.
  The enum fields (`zone.damage_multiplier`, `zone.damage_multiplier_dps`) are choices of the enum's names, listed by
  native value. Every row carries `allow_shared` and `allow_unverified_effect`.
- **Armor** (`hd2.armor_stats`):
  - one object per kit from `domains/armor_stats.kits`, keyed by id (several kits share a name; those show their id);
    its piece weights are choices (`light`, `medium`, `heavy`) from `armor_stats_writes.kit_fields(kit)`;
  - the class tables (`class_fields(0..2)`, target `hd2.armor_stats.class(name)`) and the damage curve
    (`curve_fields()`, target `hd2.armor_stats.damage_curve()`).
  These are not component records: their location key is `armor_kit/<id>/<slot>` or `image/<table>@<rva>`.
- **Armor perks** (`hd2.player_passives.set`): not an ensure. The two perk rows (`controller = 'passives'`) are applied
  together by the layer's perk controller. A change stops the previous handle and calls `set` again; resetting both
  stops it. The handle's status is followed, so a refused, lost or replaced override shows on the rows. The exporter
  skips them with that reason.
- **Attachments:** a weapon's magazines (`attachment_authoring.weapons[name]`) and its muzzles, optics and
  underbarrels (`slots[name][slot]`), each slot a closed group. The `attachment.modifier.*` fields are multipliers and
  `attachment.ergonomics_modifier` an addition; target `hd2.weapon_attachment(id)`.

## Exporting (editor/export.lua)

- **Target code:** the catalogue's `hd2` is a proxy. While the exporter traces a row (`export.tracing`), every `hd2` call returns a recorder whose method calls build Lua text. A row's own `target` and `expect` functions therefore yield the exact code that builds them, for every row type, with no per-type code generator.
- **Values:** plain values are written as literals. Reference handles are written from their stored form (`catalog.encode`): `hd2.attack_output(id)`, `hd2.pickup(id)`, a terminal explosion chain, or `:no_explosion()`.
- **Containers, in Lua:**
  - MurmurHash64A (LuaJIT 64-bit cdata);
  - the patch archive (`hd2_archive.make_archive`'s layout, compared byte for byte in the tests);
  - a stored ZIP with CRC-32;
  - SHA-256, for ModBuilder's GUID;
  - a small JSON writer;
  - the SDK's addon wrapper.
- **Files:** written with `io.open` in binary mode; folders are created through `CreateDirectoryW` (`editor/win.lua`).
- **Tests:** they build a mod with a number, a calldown code, a projectile swap and a rate list with its selector binding. They then run the generated operations against the real Runtime ensure (all four apply) and check the ZIP and archive with Python's `zipfile` and the SDK's own `hd2_archive`.

## The Logs tab (editor/logfile.lua)

The log is read with `io.open`:
- the last 256 KB on first look, then only the appended bytes, at most twice a second;
- a file that shrank (a new session) is read again from its end.

Each line is classified by keywords (error, warning, ok, editor, perf, info) for its colour and the filters. **OPEN LOG FILE** and **SHOW IN FOLDER** use `ShellExecuteW`.

## Mount swaps

A vehicle's mount row (kind `reference`, field `mount.weapon`, target `hd2.vehicle(name):mount(slot)`) offers the
slot's vanilla weapon and the catalogue's `allowedValues`. Its `expect` is always the vanilla weapon, and a swap
needs `allow_unverified_reference`.

- **Which weapon is it?** A mounted weapon id maps to the catalogued vehicle weapon whose `attackResource` equals the
  mounted weapon's `resource` (`catalog.mounted_weapon_entry`). 21 of the 79 mounted weapons have one.
- **What the list shows.** While a mount holds another weapon, the Runtime refuses writes to the slot's original
  weapon records. So the field list replaces that slot's weapon group with the held weapon's rows, from the vehicle
  that carries it (`App:effective_sections`, `Catalog:weapon_rows`).
- **Shared records.** Those rows are the held weapon's own records, so an edit also changes it on its home vehicle.
  The sections say so (`· shared with <vehicle>`).

## The mouse wheel (r51)

`ui/input.lua` reads `hd2.input.wheel()` once per frame when the Runtime has it (r51), and the engine's wheel axis
otherwise. The Runtime samples the engine axis and a read-only message hook on the game window's thread (see its
docs/ui-overlay.md "The mouse wheel").

## The other tabs

- **Changes:** the layer's held user values and the pending ones; Del stages the base value (or drops a pending one).
- **Mods:** the mod manager's deployed mods, merged with the HD2Runtime mods the ledger knows: a manager entry is an
  HD2Runtime mod when one of the Lua addons Echelon scanned in it registered with the Runtime. In-game options come
  from `hd2.diagnostics.options()` (HD2Runtime r52), grouped by the declaring mod; the status bar names the options
  page whose operation set a field.
- **Custom:** `hd2.custom_stratagem.status()` and `describe(id)`; cooldown and uses are tuned with
  `hd2.custom_stratagem.tune` (r52), which logs each change and affects this player's next call.
- **Settings:** stored with the presets (`hd2.store`): restore session, cursor capture, menu sounds, keeping input from
  the game, language.

## Keeping input from the game (r53)

While the window is shown, `main.lua` renews `hd2.input.block({keyboard = true, mouse = true})` every frame and
releases it on hide. The Runtime's native message hook turns key presses, characters, button presses and the wheel into
`WM_NULL` before the game's window sees them; the editor itself reads keys with `GetAsyncKeyState` and the cursor with
`GetCursorPos`, which are not affected.

## Applying a value

The Runtime's guard (`core/ownership.expected`) accepts a write only when the bytes hold the operation's `expect` (vanilla), its own desired value, or a value that same ensure owns. A second writer is refused with CONFLICT. The editor works within that rule.

1. **Adopt.** For a field the editor does not hold yet, it creates a script value (`hd2.mod(editor):value{min,max,step,default}`) whose default is the value now in the game: the newest claim by another mod, or vanilla. It then registers `hd2.ensure{patch={target, field, expect=vanilla, value=handle, acks}, startup_delay=0, recover=true}`.
   - The ensure's bind-time proof validates the handle's min, max, default and first step.
   - Its first resolution finds current = desired, so it reports ALREADY_DESIRED and records the bytes as owned.
2. **Hand-over.** If the claim on those bytes belongs to a mod's `ensure` that is still running, every change of that operation is adopted the same way. The ledger keeps each operation's changes and its object, and the catalogue gives the row. When all of them hold, the mod's handle is cancelled; cancel stops future cycles and leaves the bytes as they are.
   - If some change cannot be held (non-numeric, more than 3 decimals), the mod's ensure is left running. It then stops itself with a CONFLICT on its next byte check, once the editor changes the bytes.
3. **Steer.** `handle:set(value)`. The ensure debounces for 0.5 s and re-applies the value as an owned transition. A value outside the handle's range is reached by adopting again with a wider handle, with the editor's previous ensure handed over the same way.
4. **Reset.** `handle:set(base)`, where `base` is the mod's claim value or vanilla. Once the reset is verified:
   - a field whose base is vanilla or a one-time mod write is released (its ensure is cancelled and the bytes stay at the base);
   - a field taken from a mod's ensure stays held at the mod's value.

Values are held with three decimals (the script values' precision) or as integers. A float32 value counts as representable when its three-decimal form has the same float32 bytes.

## HD2Runtime internals this relies on

These are not public API. A Runtime change here needs an editor update. The tests read them from the Runtime checkout, so a change shows up as a failing test.

- `hd2runtime/domains/{player_weapon,support_weapon,stratagem,vehicle_weapon,throwable,booster,enemy,attachment}_authoring` and `entity_authoring`: catalogue shapes.
- `hd2runtime/core/shared_records`: `claim(spec, kind, mod)` (observed), `entry(descriptor)`, `key(backing)` and `describe(descriptor)`.
- The upvalue `registry` of `hd2.diagnostics.operations`: `{kind, id, origin = {mod}, handle}`.
- Validated spec keys: `kind`, `weapon`, `stratagem`, `entity`, `family`, `throwable`, `booster`, `enemy`, `attachment`, `changes[].descriptor`, `changes[].value`, `changes[].expect`, `allow_*`.
- `hd2runtime/domains/patches.validate`: tests only.

## Text placement

The Runtime's FS Sinclair glyphs land 0.41 × size below the baseline `Gui.text` is given (measured from a 3838 × 2158 screenshot, sizes 12–22). r50's overlay lifts its text by that much, so the editor's cap-height centring is exact. Runtime GUIs that pass baselines directly are not corrected yet.

## Runtime additions that would make this first-class

1. **A public override layer** (for example `hd2.overrides`): a priority above mod operations, with exact restore. The editor would then need neither claim observation nor the registry.
2. **`hd2.diagnostics.operations({changes = true})`**: each operation's target, field and value.
3. **Script choices and an exact restore** for non-numeric fields (references, statuses, lists, booleans). An ensure can restore its `expect` today only through a menu toggle.
4. **A public catalogue API** (for example `hd2.catalog.categories()`, `:fields(target)`), so editors stop reading the generated tables directly.
5. **Overlay input capture**: keep keys, clicks and the wheel away from the game while a mod window is open (r50 frees the cursor; r51 reads the wheel).

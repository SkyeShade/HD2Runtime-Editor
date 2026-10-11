# How HD2R Editor works

## Modules (`src/`)

| File | Role |
| --- | --- |
| `addon.lua` | Entry point; the SDK wraps it with the dependency check and runs it as the mod (`hd2.events.run_as`). |
| `editor/main.lua` | Wiring: checks for the Runtime services, binds the open key (F8, or the one chosen in Settings), ticks the layer every frame, restores and saves the session. Every module is required at load, because the engine resolves a mod's archived Lua only while its startup package is loaded. |
| `editor/catalog.lua` | Categories → objects → sections → rows, read from the installed Runtime's generated catalogues. One adapter per family; a family whose table changed shape is reported unavailable. |
| `editor/ledger.lua` | Which mod applied which value: an observer on `core/shared_records.claim`, plus the operation registry behind `hd2.diagnostics.operations`. |
| `editor/layer.lua` | The override layer: adopt, hand-over, steer, reset (below). |
| `editor/presets.lua` | Presets (with their icons), the saved session and settings in `hd2.store`. A preset that would take the store past HD2Runtime's 1 MiB per mod (with room for the session) is refused with its size. |
| `editor/preset_files.lua` | Shared preset files (`.hd2rpreset.json`, with an optional `icon`): encode, decode, list, and the reading job that reads, decodes and checks a file a few milliseconds a frame. |
| `editor/ui/presets_view.lua` | The Presets tab: the import page and its job (also stepped while the window is closed, `background_tick`), the collapsible sections, the icon picker. Every import outcome is a toast, the import page's last result and a log line. |
| `editor/session.lua` | The saved session: restored once at startup, saved whenever the values change. A saved value that does not come back at a start (no row now, refused by the Runtime this time, a custom stratagem not registered) stays saved until that field is changed or reset, so one bad start never erases it. |
| `editor/ui/sections.lua` | An object page's categories: a small table from each section label's head (the catalogue's domain labels) and its rest (feed, explosion phase, Status) to a category (Projectile, Damage, Handling / Fire, Ammunition, Heat / Charge, Beam / Arc, Armory, Hellpod / Call-in, else the head itself) and a subsection, ordered per round (swap, flight, direct hit, missile, impact, expiry) and feed. A direct hit is its round's (Projectile; an attack's or mount's damage too when its round is on the page); Damage keeps damage no round carries. A part of one row is folded into its category (`fold`, `prefix`), a category of one row is that row (`plain`). Presentation only: row keys and sections are unchanged. |
| `editor/ui/*.lua` | The window: theme, canvas (scaled 1080p units, cached text metrics, hit regions), input (key repeat, typing, mouse, wheel), the app (Browse, staging, dialogs), pickers (the value picker, the code, fire mode, rate and traits editors) and views (Changes, Mods, Custom, Settings). |
| `editor/installed.lua`, `editor/json.lua` | Every deployed mod from the mod manager's own state (Echelon `state.json`, HD2 Arsenal `hd2a_data.json`), read with `io.open` and a JSON reader that yields, so the 1 MB file is parsed over a few frames. |
| `editor/i18n.lua`, `editor/strings.lua` | Localisation: `L(text)` looks every interface text up in the chosen language file; `strings.lua` lists the texts for the template. |
| `editor/sounds.lua` | The game's menu sounds on the buttons (`hd2.sounds.play('ui/generic_select')` and others), at most one per 40 ms. |
| `editor/generated/game_icons.lua` | Optional, written by `tools/game_icons.py`: stratagem and booster name → the image of its own HUD sprite (HD2Runtime SDK `tools/hd2_hud_icons.py`), its accent and, for boosters, the glyph colour. |
| `editor/generated/mod_icons.lua` | Optional, written by `tools/mod_icons.py`: a deployed mod's icon as up to three mask layers, each with its own three colours. |
| `editor/generated/preset_icons.lua` | Optional, written by `tools/preset_icons.py`: your own pictures for preset icons, as mask layers like the mod icons. |

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
- **Fire modes (HD2Runtime 0.31.0):** two or three fire modes on a weapon without a fire-mode selector
  (`fire_mode.modes` descriptor `fireModeState == 'addable'`) bind `weapon_function.<first bindable input>` =
  `fire_mode` the same way.

## Fields that depend on another field (0.31.0)

Every field keeps its own ensure, so two fields the Runtime checks against each other are ordered by the layer
(`Layer:tick`, before a dirty slot adopts or steers):

- **The Eagle Rearm pool.** A stratagem in the pool keeps a finite use count; the Runtime checks the row's bytes when it
  applies (`REARM_POOL_UNLIMITED`). Joining the pool waits while the stratagem's Mission uses are being applied, and
  unlimited uses wait while the pool is being left; the combination itself is refused at once with that code.
  Resetting the uses takes the stratagem out of a pool the editor put it in.
- **Beam conversions** (feature-detected: `hd2.beam_conversion`). A converted weapon's own rate, pulse, damage and
  range are accepted only on a converted weapon (`NOT_CONVERTED`), and a conversion is never part of a plan. A setting
  is refused while its conversion is off, waits while the conversion is being applied, and is reset when the
  conversion is turned off. Every request carries `allow_component_swap` and `allow_unverified_effect`. The exporter
  writes one weapon's conversion changes as one transaction ensure (`recover = true`; the conversion first), so a
  mod never depends on the order its ensures resolve in. The conversion rows are not inspected (`hd2.inspect`): their
  state is the conversion's own live status.

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

HD2Runtime runs one guarded operation at a time (`runtime/exclusive.lua`); the others report `queued`, and each
operation takes a few updates (a fresh discovery, capture and re-read). So a preset of 300 fields takes about 20 to 30
seconds to be written, whatever the editor does: it registers one ensure per field so that each refusal stays on its
own field (a transaction or plan of many fields is all or nothing, and one CONFLICT would block and stop maintaining
every field in it). The time a steer's operation spends `queued` behind others does not count towards the 4 s and 20 s
above (a 300-field preset re-applied over held fields queued steers past 20 s, and they were shown failed although
they applied afterwards). At most 16 fields start their ensure in one update (registering 300 at once, each with its
bind-time proof, cost one frame of about 60 ms); the rest start on the next updates, shown applying meanwhile.

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

The Arsenal image is chosen in the Windows open-file dialog (`editor/win.lua` `pick_file`):
- `GetOpenFileNameW` takes one pointer and returns a BOOL, the shape of a thread procedure. So `CreateThread` starts it
  directly on its own thread, and the game's frame loop never waits for the dialog.
- The export view polls the thread every frame (`WaitForSingleObject(thread, 0)`), then reads the chosen path from its
  buffer. Every buffer stays referenced until the thread ends.
- The game window owns the dialog, so it stays above the game. The owner is the foreground window, used only when it
  belongs to this process (a window of another process would make the dialog fail).
- Without the FFI, or if the thread cannot start, the in-game folder browser is used instead.

The log is read with `io.open`:
- the last 256 KB on first look, then only the appended bytes, at most twice a second;
- a file that shrank (a new session) is read again from its end.

Each line is classified by keywords (error, warning, ok, editor, perf, info) for its colour and the filters. **OPEN LOG FILE** and **SHOW IN FOLDER** use `ShellExecuteW`.

## Projectile swaps: what the weapon fires

HD2Runtime resolves a weapon's own projectile, direct-hit damage, impact / expiry explosion and status rows through
the projectile the weapon fires. After a swap it refuses them (`COMPOSITION_TARGET_CHANGED`), its reset included.

- **Scopes.** The catalogue tags those rows with `fires_scope` (`attack:<role>`; `function:programmable` for the
  AC-8 / GR-8 / RL-77 feed; a mount's own `<weapon>|attack:primary`) and the swap row with `swap_scope`. Player
  weapons tag the rows targeted through `weapon:attack(role):projectile()`; support and mounted weapons go by the
  field's linkage (`projectile`, `projectile_damage`, `projectile_explosion*`, a status of those). `Catalog:open`
  links them (`row.fires_from`, `swap.fires_rows`, `object.swap_rows`). Sentries' stratagem attack rows are not
  tagged.
- **The page.** `App:fires_sections` hides a swap's rows while it names a donor (`catalog.donor_of`: an output handle
  that is not the weapon's own), except those holding a pending, applied or failed value of yours, shown locked
  (`App:fires_block`: only their reset is accepted). `Catalog:donor_sections` adds "Fires" next to the swap and, with
  `hd2.attack_output(id):stats()` (0.31.2), the donor's vanilla flight, direct hit and explosions as info rows, and a
  link row when `:owner_projectile()` returns a handle (`App:open_link` opens the owner's page).
- **Order.** Staging a swap to a donor drops the pending values of its rows. In the layer, `release_dependents` resets
  the applied ones and `swap_wait` holds the swap until they are back; a value of yours on such a row waits while the
  swap goes back to the own projectile, and is refused at once while it names a donor. Presets stage swaps first and
  leave such values out (counted in the load message); the saved session keeps them saved but does not apply them;
  exports skip them with the reason.

## Payload slots: what an impact or expiry payload sets off

An impact or expiry payload slot (`terminal.explosion`, kind `reference`) names an explosion: the weapon's own, none,
another weapon's terminal explosion (`weapon:attack(a):projectile():terminal_action(p):explosion()`, what the editor
offers) or a catalogued one (`hd2.explosion(name)`, a mod's value).

- **Links.** `Catalog:open` gives each slot `payload_rows`: the rows of its own explosion (its section and that
  section's Status, same weapon and part), each with `row.payload_from`; the page's slots are `object.payload_slots`.
- **What it names.** `catalog.payload_identity(value)` keys a value (`w|...` a weapon's terminal explosion, `x|<id>` a
  catalogued one). `Catalog:payload_explosion` finds that explosion's rows where they are edited: the owner weapon's
  own rows of that attack and phase; for a catalogued explosion, the row on the same native bytes on an owner's page
  (owners' pages opened first, what spawns a chained explosion counted as its owner), else a row of the explosion's
  own (`ex|<id>|<field>`, through `hd2.explosion(id)`, found again by `Catalog:row`). An unknown explosion, one without
  a known package (`payload = false`) or one without editable fields gets a note (an info row) instead.
- **Views.** `Catalog:payload_view(slot, value)` (cached per slot and explosion) returns views of those rows: tables
  with the slot's object, section and group, `canonical` (the owner's row, read through `__index`) and `shown_by`.
  `App:stage` stages a view's value on its canonical row, so the key, pending value, layer slot, Changes entry, preset
  key and error are the owner's; markers and values are by key and native bytes, so both pages show the same state.
  `view.other` is true when the slot names another explosion than the weapon's own.
- **The page.** `App:payload_sections` adds a slot's views right after it (ui/sections.lua keeps them under the slot,
  in its subsection), leaving out rows already shown on the page (by native bytes; an explosion named by both slots
  shows once) and status durations that do not apply. While `view.other`, the slot's own explosion rows are set aside
  like a swap's (`App:payload_block`, through `App:fires_block`: locked while they hold a value of yours; staging the
  slot drops their pending values).
- **Order.** In the layer, `release_dependents` resets the applied own explosion values when the slot is set to another
  explosion, and `swap_wait` holds the slot until they are back; an own value waits while the slot goes back to the
  weapon's own explosion and is refused at once while it names another one. Presets and the saved session stage the
  slots after the projectile swaps and before every other value, leaving such values out (the session keeps them
  saved); exports skip them with the reason (`catalog.payload_other`).
- **Labels.** "<explosion> · <field>": the owner weapon's name (or the catalogue's label), cut first to the same width
  on every row of the slot so the field stays readable (`App:fitted_label`). The status line's SHARED chip and
  "also changes ..." name the owner page and every other object on the same bytes.
- **Support weapons (HD2Runtime 0.31.2).** `support_payload_rows` makes a slot of every `explosion_reference` field
  whose target path is `terminal_action` (`hd2.support_weapon(w):attack(role):projectile():terminal_action(phase)`,
  expect `:current()`), in `Explosion · <Role> <phase>` ("Primary impact", "Full charge impact") or, for the
  ProgrammableAmmo feed, `Explosion · <feed> · <Phase>` ("Flak · Impact"). The rows of the explosion it sets off
  natively (by its `referenceSettings` record) move into that section, impact slots first, each section once (the GL-21's
  expiry, which sets off its impact explosion, keeps a section of its own). Rows edited through `hd2.explosion(name)`
  (the flak's burst) are linked as `slot.payload_soft`: set aside from view while the slot names another explosion,
  never locked (HD2Runtime keeps taking them). `fieldRefusals` of a `terminal.*` id (the missiles' expiry) are locked
  rows with the Runtime's reason. A support weapon's own explosion handle is stored as `{ref='terminal',
  resource='support_weapon', ...}`; a catalogued one as `{ref='explosion', id}` (presets, session, exports, ModBuilder
  custom Lua).
- **Picker.** `explosion_options` uses `terminal:payload_options()` when the Runtime has it (`catalog.payload_options`):
  own and none first, then every option with `group` (a short header, `PAYLOAD_GROUPS`), `warnings`, `acks` and
  `checked` (not probed when the list opens; the chosen one is validated when staged, the highlighted one for its
  acknowledgements, `App:picker_details`); `excluded` options become the picker's note. The picker draws a header
  before each group and searches `item.search` (owner, catalogue name, group) too. Without it, the earlier list.
- **Packages.** `Layer:loading(row)`: the ensure of a field being applied reports `waiting_for_assets` (its package
  loads first); the row and Changes show LOADING, and that time does not count toward the steer's give-up. A gate that
  fails (ASSET_UNAVAILABLE) is an error with its reason; the field keeps its value.

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
   - a field reset while its value is still on its way never gets that value first: an ensure that has not run yet is
     stopped (an ensure counts its run in the update that writes, so nothing was written), and a steer still queued is
     turned to the base. Until the base is back the field is *removing*: it stays in Changes with a `REMOVING` chip
     and the counter "Removing n of m". A reset that fails keeps its `ERROR` and reason, and the value it could not
     take away is not saved to the session. A field whose ensure stopped (rejected, blocked) remembers the value it left
     in the game, so a later reset adopts that value again and takes it back instead of assuming the base.
   - RESET TO DEFAULTS / REVERT ALL takes every field with a value of yours or a failed one, whether applied or still
     being applied (before 0.9.3 it said "nothing to reset" when the only fields left were failed or applying ones).

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

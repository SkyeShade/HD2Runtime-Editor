# How HD2Runtime Editor works

## Modules (`src/`)

| File | Role |
| --- | --- |
| `addon.lua` | Entry point; the SDK wraps it with the dependency check and runs it as the mod (`hd2.events.run_as`). |
| `editor/main.lua` | Wiring: checks for the Runtime services, binds F8, ticks the layer every frame, restores and saves the session. Every module is required at load, because the engine resolves a mod's archived Lua only while its startup package is loaded. |
| `editor/catalog.lua` | Categories → objects → sections → rows, read from the installed Runtime's generated catalogues. One adapter per family; a family whose table changed shape is reported unavailable. |
| `editor/ledger.lua` | Which mod applied which value: an observer on `core/shared_records.claim`, plus the operation registry behind `hd2.diagnostics.operations`. |
| `editor/layer.lua` | The override layer: adopt, hand-over, steer, reset (below). |
| `editor/presets.lua` | Presets, the saved session and settings in `hd2.store`. |
| `editor/ui/*.lua` | The window: theme, canvas (scaled 1080p units, cached text metrics, hit regions), input (key repeat, typing, mouse, wheel), the app (views, staging, dialogs) and pickers (the value picker and the calldown code editor). |
| `editor/generated/game_icons.lua` | Optional, written by `tools/game_icons.py`: stratagem and booster name → icon image and accent colour. |

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
5. **Overlay input capture**: show and free the cursor, and keep keys and clicks away from the game while a mod window is open.

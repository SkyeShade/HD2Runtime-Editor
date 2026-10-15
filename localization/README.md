# Bundled translations

`builtin.json` is the existing 135-text supplement shared by 13 languages. `zh-cn.json`
extends Chinese with 2,234 entries: all 862 interface texts in the generated
`src/editor/strings.lua`, plus 1,372 reviewed catalogue display texts and unit labels.
The shared supplement and the other 12 languages are unchanged.

This coverage is against Editor 1.0.0 and Runtime 0.40.0. It is not a claim that every
Runtime-generated catalogue string is translated: that Runtime adds 10,414 catalogue
texts beyond the interface, including generated names, technical identifiers and
new domain descriptions. Unrecognized text stays English; composite labels still
use the existing part-by-part lookup. Add reviewed translations as the Runtime evolves.

The translations adapt the editor's and Runtime's public English display text.
Uses code / research from [HD2Runtime by SkyeShade](https://github.com/SkyeShade/HD2Runtime).
The original author notices and licenses remain in place. No Runtime source,
catalogue dump, game text dump, game binary, font, user configuration or log is bundled
with this translation contribution. Official weapon and stratagem names are read
from the installed game's text API by `game_names.lua`, with its existing precedence
and English fallback; the translation pack does not embed an extracted name table.

## Loading and overrides

The generated `src/editor/locale.lua` is an ordinary source resource. The SDK packs
it into the mod archive with every other `src/**/*.lua` file, so Chinese is available
without copying anything into AppData. The game/Runtime code `cn` selects **简体中文**
automatically when no preference was saved. Explicit English and other saved choices
are not changed. **简体中文** is also selectable in Settings, and remains usable when
a previously selected external file is missing.

External UTF-8 language files take precedence and inherit missing bundled entries.
A Chinese override can use `@code cn` with its own language name; a file named
**简体中文** is listed once and takes priority over the built-in entry of that name.
Removing that file restores the bundled fallback. Reload's count includes files only.

Windows directory discovery uses the native code page for `os.getenv`/`io.open`
paths, including Chinese CP936 profiles; file contents remain UTF-8. The WinAPI
calls use explicit function pointer types so another addon's `FIND_DATA` declaration
does not break enumeration. The existing `index.txt` fallback still works without
FFI. External filenames remain subject to native `io.open` code-page limits;
the built-in pack requires neither a directory scan nor an index.

## Updating and checking

Keep the original English keys, numeric values, printf specifiers and technical IDs.
Translate display text only. Do not change stored keys, resource identities, callbacks,
gameplay values, log contents, error codes or engineering unit symbols.

After editing a pack or a displayed string:

```console
python tools/locale_builtin.py
python tools/locale_strings.py
python -m unittest discover -s tests -p test_localization.py -v
```

The static checks need only Python. They check interface coverage, duplicate keys,
placeholders, numbers, identifiers and generated resource freshness, and run in the
Localization GitHub Actions workflow. Native tests are explicitly skipped there.

With the game's LuaJIT and a Runtime checkout configured as described in the main
README, the same command also exercises automatic/manual language selection,
external overrides, missing files, unavailable FFI, other languages, English fallback,
every format string, official-name precedence, font glyph availability and all nine
window tabs. `test_win_interop.py` additionally checks a private Chinese profile and
filename without an index after `win.lua` has declared its WinAPI structs. The
Chinese-path case skips on Windows code pages that cannot represent those names.
Use private temporary/configuration directories for the complete offline suite.

```console
python -m unittest discover -s tests -v
python build.py
```

These are static and offline checks, not an in-game rendering, stability or multiplayer
claim. The earlier 0.9.4 translation was accepted by its user after adding the external
index; that acceptance is not an in-game test of this 1.0.0 integration.

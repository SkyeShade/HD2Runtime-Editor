# Third-party material and upstream contracts

- **HD2Runtime** (https://github.com/SkyeShade/HD2Runtime) is a separate, required dependency. It is not bundled or redistributed.
  - The editor calls its public API: `hd2.ensure`, `hd2.mod():value`, `hd2.ui.overlay`, `hd2.store`, `hd2.on_frame`, `hd2.input`, `hd2.diagnostics.operations` and the target builders.
  - At run time it also reads these internal modules of the installed Runtime: the generated authoring catalogues (`hd2runtime/domains/*_authoring`) and `hd2runtime/core/shared_records`, whose claim records it observes, and read-only access to the operation registry behind `hd2.diagnostics.operations`.
  - No HD2Runtime source code is copied into this repository.
- **HD2Runtime SDK.** `build.py` runs the SDK's `hd2.py build`. The SDK is not included.
- **Bingus Shared Loader** loads the mod. It is a separate dependency and not included.
- **Fonts.** The in-game window uses the FS Sinclair fonts that HD2Runtime builds from the installed game. No font is shipped here. `tests/render_frames.py` uses Windows' Bahnschrift as a stand-in for offline previews only.
- **Lua VM for tests.** The tests load `bin/lua51.dll` from the local Helldivers 2 installation. It is not redistributed.
- **Icon.** `assets/HD2Editor · icon@1x.png` is this project's own artwork.

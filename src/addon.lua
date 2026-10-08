-- HD2Runtime Editor (c) 2026 SkyeShade. All rights reserved except as granted in LICENSE
-- (https://github.com/SkyeShade/HD2Runtime-Editor). Do not redistribute or reuse without the credit it requires.
-- HD2Runtime Editor: an in-game editor for the values HD2Runtime exposes, over the installed Runtime mods.
local hd2=require('mods/skyeshade/hd2runtime')
local editor=require('mods/skyeshade/hd2runtime_editor/editor/main')
return editor.start(hd2,'mods/skyeshade/hd2runtime_editor')

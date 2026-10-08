-- HD2R Editor (c) 2026 SkyeShade. All rights reserved except as granted in LICENSE
-- (https://github.com/SkyeShade/HD2Runtime-Editor). Do not redistribute or reuse without the credit it requires.
-- The game's own menu sounds on the editor's buttons (hd2.sounds.play, HD2Runtime 0.30.0-dev): the keys the
-- Runtime's stratagem selector uses (domains/stratagem_selector.lua uiSound). Silent when the Runtime has no sound
-- API, when the setting is off, or when the game's UI bank is not loaded (play returns NO_EVENT; that event is tried again after 30 s).
local M={}

local EVENTS={click='ui/generic_select',open='ui/slot_select',back='ui/picker_close',apply='ui/stratagem_pick',
    hover='ui/item_hover_select',error='ui/picker_close'}
local GAP=0.04   -- at most one sound per 40 ms (the Runtime allows 32 calls per second per mod)

function M.new(hd2,enabled)
    local self={hd2=hd2,enabled=enabled,last=-1,clock=0,failed={}}
    function self.tick(dt)self.clock=self.clock+(dt or 0)end
    function self.play(kind)
        if not self.enabled()then return end
        local sounds=type(self.hd2.sounds)=='table'and self.hd2.sounds
        if not sounds or type(sounds.play)~='function'then return end
        local event=EVENTS[kind]
        if not event or(self.failed[event]and self.clock-self.failed[event]<30)then return end
        if self.clock-self.last<GAP then return end
        self.last=self.clock
        local ok,handle,code=pcall(sounds.play,event)
        if not ok or handle==nil then self.failed[event]=self.clock else self.failed[event]=nil end
    end
    return self
end
M.EVENTS=EVENTS
return M

-- HD2R Editor (c) 2026 SkyeShade. All rights reserved except as granted in LICENSE
-- (https://github.com/SkyeShade/HD2Runtime-Editor). Do not redistribute or reuse without the credit it requires.
-- The saved session: the values applied last, restored once when the game starts and saved again whenever they change.
--
-- A saved value that does not come back at a start stays saved: its row may be missing from this catalogue, the Runtime
-- may refuse it this time (another mod's value, data not as reviewed), or its custom stratagem may not be registered.
-- Such values are carried into every later save until the player changes or resets that field (or resets everything),
-- so one start that cannot restore a value never erases it for the next. A field still being applied never holds the
-- save back either: the values asked for are saved at once, and a refused one leaves the session only through the
-- carried value it came from.
local M={}
local Session={};Session.__index=Session

function M.new(opts)
    return setmetatable({app=opts.app,layer=opts.layer,presets=opts.presets,log=opts.log or function()end,
        carried={},saved_version=-1,restored=false},Session)
end

-- Restores the saved values once. Returns applied, carried (the values that did not come back now).
function Session:restore()
    local app,layer=self.app,self.layer
    local values=self.presets:session()
    local applied,carried,reasons=0,0,{}
    -- projectile swaps first: a value of a weapon's own projectile row waits for (or is refused by) what it fires; then
    -- payload slots: a value of a weapon's own explosion row the same way by what its slot sets off
    local keys,first,slots={},{},{}
    for key in pairs(values)do
        local row=not app.is_custom_key(key)and app.catalog and app.catalog:row(key)
        if row and row.swap_scope then first[#first+1]=key
        elseif row and row.payload_rows then slots[#slots+1]=key
        else keys[#keys+1]=key end
    end
    table.sort(first)
    table.sort(slots)
    table.sort(keys)
    for _,key in ipairs(slots)do first[#first+1]=key end
    for _,key in ipairs(keys)do first[#first+1]=key end
    for _,key in ipairs(first)do
        local stored=values[key]
        local ok,why
        if app.is_custom_key(key)then
            -- a custom stratagem tune, applied through the Runtime again
            ok,why=app:apply_custom_value(key,stored)
        else
            local row,value=app:decode_value(key,stored)
            if not row then why='no editable row now'
            elseif value==nil then why='the saved value cannot be read now'
            elseif row.fires_from and app:fires(row.fires_from)then
                -- (kept saved: it comes back at a start whose weapon fires its own projectile again)
                why='the weapon fires another projectile (its own projectile rows are refused while it does)'
            elseif row.payload_from and app.payload_block and app:payload_block(row)then
                -- (kept saved the same way, until its payload slot sets off its own explosion again)
                why='its payload slot sets off another explosion (its own explosion rows are refused while it does)'
            else ok,why=layer:set(row,value,{kind='session'})end
        end
        -- every saved value is carried: a restored one that the Runtime refuses later stays saved as well
        self.carried[key]=stored
        if ok then applied=applied+1
        else
            carried=carried+1
            if#reasons<8 then reasons[#reasons+1]=key..' ('..tostring(why or'refused')..')'end
        end
    end
    -- the restore's own changes are not the player's
    layer.touched={}
    self.restored=true
    self.saved_version=layer.version
    if applied+carried>0 then
        self.log('restored '..applied..' saved values'..(carried>0 and('; '..carried..' did not come back now and stay '
            ..'saved for the next start: '..table.concat(reasons,', ')..(carried>#reasons and', ...'or''))or''))
    end
    return applied,carried
end

-- Forgets every carried value (Reset to defaults).
function Session:forget_all()self.carried={}end

-- The values to save: the applied ones, then each carried value the player has not changed or reset since.
function Session:values()
    local app,layer=self.app,self.layer
    local values=layer:overrides()
    for key,value in pairs(app:custom_values())do values[key]=value end
    local stored=app:encode_values(values)
    for key,value in pairs(self.carried)do
        if layer.touched[key]then self.carried[key]=nil
        elseif stored[key]==nil then stored[key]=value end
    end
    return stored
end

-- Saves the session when the values changed (once restored: before that the saved values are not in the game yet).
function Session:tick()
    local app,layer=self.app,self.layer
    if not self.restored or not(app.save_session or layer.version~=self.saved_version)then return false end
    app.save_session=false
    self.saved_version=layer.version
    self.presets:set_session(self:values())
    return true
end

return M

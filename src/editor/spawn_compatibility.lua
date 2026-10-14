-- Ask the API for ownership: the editor never maintains a second list of native addresses.
local M={}
function M.status(hd2)
    local api=hd2 and hd2.enemies
    return api and api.spawn_compatibility and api.spawn_compatibility()or{blocked=false}
end
function M.reason(hd2,row)
    row=row.canonical or row
    local api=hd2 and hd2.enemies
    local descriptor=row.descriptor
    if api and api.spawn_control_reason and descriptor then
        return api.spawn_control_reason(descriptor.target,row.field)
    end
end
return M

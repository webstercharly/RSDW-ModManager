-- Shared mutation lock: equipment changes must never overlap.

local M = {}
local owner = nil

function M.acquire(requested)
    requested = tostring(requested or "transaction")
    if owner then return false, owner .. " is already changing equipment" end
    owner = requested
    return true
end

function M.release(requested)
    if requested == nil or owner == tostring(requested) then owner = nil; return true end
    return false
end

function M.current() return owner end

return M

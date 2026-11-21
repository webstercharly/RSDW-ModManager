local M = {}

local prefix = "[ModManager] "
local detailed = false

function M.configure(options)
    options = type(options) == "table" and options or {}
    detailed = options.detailed == true
end

function M.info(message)
    print(prefix .. tostring(message) .. "\n")
end

function M.warn(message)
    print(prefix .. "WARNING: " .. tostring(message) .. "\n")
end

function M.error(message)
    print(prefix .. "ERROR: " .. tostring(message) .. "\n")
end

function M.debug(message)
    if detailed then M.info("debug: " .. tostring(message)) end
end

return M


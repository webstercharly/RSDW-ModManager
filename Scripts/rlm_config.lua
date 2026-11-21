local M = {}

local DEFAULTS = {
    ShowInPauseMenu = true,
    MenuKey = "F7",
    Notifications = true,
    DetailedLog = false,
    DispatchIntervalMs = 70,
    VerifyTimeoutSeconds = 5,
}

local function clone_defaults()
    local result = {}
    for key, value in pairs(DEFAULTS) do result[key] = value end
    return result
end

local function trim(value)
    return tostring(value or ""):gsub("^%s+", ""):gsub("%s+$", "")
end

local function parse_value(raw, current)
    raw = trim(raw):gsub("%s*[#;].*$", "")
    if type(current) == "boolean" then
        local lower = raw:lower()
        if lower == "true" or lower == "1" or lower == "yes" or lower == "on" then return true end
        if lower == "false" or lower == "0" or lower == "no" or lower == "off" then return false end
        return current
    end
    if type(current) == "number" then return tonumber(raw) or current end
    return raw
end

function M.load(path)
    local config = clone_defaults()
    local warnings = {}
    local file = io.open(path, "r")
    if not file then return config, { "config.txt was not readable; defaults are active" } end

    for line in file:lines() do
        line = trim(line)
        if line ~= "" and line:sub(1, 1) ~= "#" then
            local key, raw = line:match("^([%w_]+)%s*=%s*(.+)$")
            if key and config[key] ~= nil then
                config[key] = parse_value(raw, config[key])
            elseif key then
                warnings[#warnings + 1] = "unknown config key ignored: " .. key
            end
        end
    end
    file:close()

    config.DispatchIntervalMs = math.max(50, math.min(300, tonumber(config.DispatchIntervalMs) or 70))
    config.VerifyTimeoutSeconds = math.max(2, math.min(15, tonumber(config.VerifyTimeoutSeconds) or 5))
    config.MenuKey = trim(config.MenuKey)
    if config.MenuKey == "" then config.MenuKey = "none" end
    return config, warnings
end

function M.defaults()
    return clone_defaults()
end

return M


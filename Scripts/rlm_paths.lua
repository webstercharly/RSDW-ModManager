local M = {}

local resolved = nil

local function parent(path)
    return tostring(path or ""):match("^(.*)[/\\][^/\\]+$")
end

local function join(left, right)
    left, right = tostring(left or ""), tostring(right or "")
    if left:sub(-1) == "\\" or left:sub(-1) == "/" then return left .. right end
    return left .. "\\" .. right
end

local function ensure_directory(path)
    if not path or path == "" then return false end
    -- Paths come only from this mod's location or LOCALAPPDATA. Quotes are
    -- doubled defensively before the fixed mkdir command is constructed.
    local safe = tostring(path):gsub('"', '""')
    local ok = pcall(os.execute, ('if not exist "%s" mkdir "%s"'):format(safe, safe))
    return ok
end

function M.initialize()
    if resolved then return resolved end
    local source = (debug.getinfo(1, "S").source or ""):gsub("^@", "")
    local scripts = parent(source)
    local mod_root = parent(scripts)
    if not scripts or not mod_root then return nil, "could not resolve installed mod path" end

    local local_app_data = os.getenv("LOCALAPPDATA")
    local user_root
    if local_app_data and local_app_data ~= "" then
        user_root = join(local_app_data, "RSDWLoadoutManager")
    else
        user_root = join(mod_root, "UserData")
    end

    local backups = join(user_root, "backups")
    local logs = join(user_root, "logs")
    ensure_directory(user_root)
    ensure_directory(backups)
    ensure_directory(logs)

    resolved = {
        scripts = scripts,
        mod_root = mod_root,
        config = join(mod_root, "config.txt"),
        installed_data = join(mod_root, "Data"),
        modules = join(mod_root, "Modules"),
        user_root = user_root,
        backups = backups,
        logs = logs,
        settings = join(user_root, "settings.json"),
        migration = join(user_root, "migration.json"),
    }
    return resolved
end

function M.get()
    return M.initialize()
end

function M.join(left, right)
    return join(left, right)
end

return M


-- Mod Manager - standalone UE4SS entry point.

local function script_directory()
    local source = (debug.getinfo(1, "S").source or ""):gsub("^@", "")
    return source:match("^(.*)[/\\][^/\\]+$")
end

local scripts = script_directory()
if scripts and not package.path:find(scripts, 1, true) then
    package.path = scripts .. "\\?.lua;" .. package.path
end

local ok_module, bootstrap = pcall(require, "rlm_bootstrap")
if not ok_module then
    print("[ModManager] bootstrap module failed to load: " .. tostring(bootstrap) .. "\n")
    return
end

local ok_start, started, detail = pcall(bootstrap.start, {
    id = "RSDWModManager",
    name = "Mod Manager",
    version = "0.1.2-dev",
})

if not ok_start then
    print("[ModManager] startup crashed: " .. tostring(started) .. "\n")
elseif not started then
    print("[ModManager] startup stopped: " .. tostring(detail) .. "\n")
end

if ModRef then
    ModRef.OnUnload = function()
        pcall(bootstrap.stop)
    end
end


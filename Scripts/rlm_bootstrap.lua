local paths = require("rlm_paths")
local config_reader = require("rlm_config")
local log = require("rlm_log")
local store = require("rlm_store")
local modules = require("rlm_modules")
local ui = require("rlm_ui")
local inventory = require("rlm_inventory")
local async = require("rlm_async")

local M = {}
local state = { started = false, phase = "new" }

function M.start(identity)
    if state.started then return true, "already started" end
    identity = type(identity) == "table" and identity or {}

    state.phase = "paths"
    local locations, path_error = paths.initialize()
    if not locations then return false, path_error end

    state.phase = "config"
    local config, warnings = config_reader.load(locations.config)
    log.configure({ detailed = config.DetailedLog })
    for _, warning in ipairs(warnings or {}) do log.warn(warning) end

    state.phase = "storage"
    local storage_ready, storage_or_error = store.initialize(locations, identity)
    if not storage_ready then return false, "storage initialization failed: " .. tostring(storage_or_error) end

    state.identity = identity
    state.paths = locations
    state.config = config
    state.started = true
    state.documents = storage_or_error

    state.phase = "modules"
    local module_list, module_error = modules.initialize(locations)
    if not module_list then
        return false, "module initialization failed: " .. tostring(module_error or "unknown error")
    end
    state.modules = module_list
    log.info(("discovered %d module(s) from manifests"):format(#module_list))
    if #module_list == 0 then
        log.warn("no modules installed; add a module folder under Modules/ and use Reload Mods")
    end

    state.phase = "foundation-ready"
    state.compatibility = inventory.probe()

    local async_ready, async_error = async.start()
    if not async_ready then log.warn("transaction scheduler unavailable: " .. tostring(async_error)) end

    local ui_ready, ui_error = ui.start(state)
    if not ui_ready then log.warn("UI unavailable: " .. tostring(ui_error)) end

    -- Modules start their own background work once the shell is ready.
    modules.start_all(state)

    log.info(("loaded %s; standalone foundation ready"):format(tostring(identity.version or "dev")))
    log.info("user data: " .. tostring(locations.user_root))
    log.debug(("dispatch=%dms verify=%ds pauseMenu=%s"):format(
        config.DispatchIntervalMs,
        config.VerifyTimeoutSeconds,
        tostring(config.ShowInPauseMenu)))
    return true, state.phase
end

function M.status()
    return state
end

function M.stop()
    if not state.started then return true end
    pcall(modules.stop_all, state)
    pcall(async.stop)
    pcall(ui.stop)
    state.started = false
    state.phase = "stopped"
    return true
end

return M

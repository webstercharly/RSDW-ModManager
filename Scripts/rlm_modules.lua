-- Manifest-driven module discovery and isolated runtime loading.
--
-- A module is any folder under Modules/ that holds a valid manifest.json and
-- the runtime file it names. Dropping a folder in (or removing one) is enough;
-- no central index has to be edited. An optional Modules/index.json is read
-- only as a fallback when directories cannot be listed.
--
-- Runtime contract (module.lua returns a table):
--   activate(state)               required: returns the view for the module screen
--   run_action / select_row / rename_selection   optional UI callbacks
--   start(state)                  optional: begin background work; called after the
--                                 shell is ready and again after every Reload Mods,
--                                 so it must be idempotent
--   stop()                        optional: called when the module is replaced by a
--                                 reload and when the manager unloads
--   shutdown()                    optional: called only when the manager unloads
--                                 (use it for services that must survive a reload)

local json = require("rlm_json")
local log = require("rlm_log")

local M = {}
local loaded = nil

local function join(left, right)
    if tostring(left):sub(-1) == "\\" then return tostring(left) .. tostring(right) end
    return tostring(left) .. "\\" .. tostring(right)
end

local function read_json(path)
    local file = io.open(path, "rb")
    if not file then return nil, "file not found" end
    local body = file:read("*a")
    file:close()
    local ok, value = pcall(json.decode, body)
    if not ok then return nil, tostring(value) end
    return value
end

local function safe_leaf(value)
    local text = tostring(value or "")
    return text ~= "" and text:match("^[%w_.-]+$") ~= nil
end

local function validate_manifest(manifest)
    if type(manifest) ~= "table" then return false, "manifest root is not an object" end
    if tonumber(manifest.schemaVersion) ~= 1 then return false, "unsupported manifest schema" end
    if not safe_leaf(manifest.id) then return false, "invalid module id" end
    if type(manifest.name) ~= "string" or manifest.name == "" then return false, "module name is missing" end
    if not safe_leaf(manifest.entry) then return false, "invalid runtime entry" end
    if type(manifest.ui) ~= "table" or type(manifest.ui.menuLabel) ~= "string"
        or manifest.ui.menuLabel == "" then return false, "module menu label is missing" end
    if manifest.ui.actions ~= nil then
        if type(manifest.ui.actions) ~= "table" then return false, "module actions must be an array" end
        for _, action in ipairs(manifest.ui.actions) do
            if type(action) ~= "table" or not safe_leaf(action.id)
                or type(action.label) ~= "string" or action.label == "" then
                return false, "module action is invalid"
            end
        end
    end
    return true
end

local function load_runtime(path)
    if type(loadfile) ~= "function" then return nil, "loadfile is unavailable" end
    local chunk, load_error = loadfile(path)
    if not chunk then return nil, load_error end
    local ok, runtime = pcall(chunk)
    if not ok then return nil, runtime end
    if type(runtime) ~= "table" or type(runtime.activate) ~= "function" then
        return nil, "runtime must return a table with activate()"
    end
    return runtime
end

-- Module directory names, from the file system when possible.
local function module_directories(modules_path)
    local names = {}
    if io.popen then
        local safe = tostring(modules_path):gsub('"', '""')
        local ok_open, pipe = pcall(io.popen, ('dir /b /ad "%s" 2>nul'):format(safe))
        if ok_open and pipe then
            for line in pipe:lines() do
                local name = line:gsub("%s+$", "")
                if name ~= "" then names[#names + 1] = name end
            end
            pcall(function() pipe:close() end)
        end
    end
    if #names == 0 then
        local index = read_json(join(modules_path, "index.json"))
        if type(index) == "table" and tonumber(index.schemaVersion) == 1 and type(index.modules) == "table" then
            for _, name in ipairs(index.modules) do names[#names + 1] = name end
        end
    end
    table.sort(names)
    return names
end

function M.initialize(paths)
    if loaded then return loaded end
    if type(paths) ~= "table" or not paths.modules then return nil, "module path is unavailable" end

    local result, ids = {}, {}
    for _, directory in ipairs(module_directories(paths.modules)) do
        if safe_leaf(directory) then
            local root = join(paths.modules, directory)
            local manifest, manifest_error = read_json(join(root, "manifest.json"))
            if manifest == nil and manifest_error == "file not found" then
                -- A folder without a manifest is not a module; ignore it quietly.
            else
                local valid, validation_error = validate_manifest(manifest)
                if not valid then
                    log.warn(("module %s skipped: %s"):format(tostring(directory),
                        tostring(manifest_error or validation_error)))
                elseif ids[manifest.id] then
                    log.warn("duplicate module id skipped: " .. manifest.id)
                else
                    local runtime, runtime_error = load_runtime(join(root, manifest.entry))
                    if runtime then
                        ids[manifest.id] = true
                        result[#result + 1] = {
                            id = manifest.id,
                            manifest = manifest,
                            runtime = runtime,
                            root = root,
                        }
                    else
                        log.warn(("module %s runtime skipped: %s"):format(manifest.id, tostring(runtime_error)))
                    end
                end
            end
        else
            log.warn("unsafe module directory skipped: " .. tostring(directory))
        end
    end
    table.sort(result, function(left, right)
        local left_order = tonumber(left.manifest.order) or 999
        local right_order = tonumber(right.manifest.order) or 999
        if left_order == right_order then return left.id < right.id end
        return left_order < right_order
    end)
    loaded = result
    return loaded
end

function M.reload(paths)
    local previous = loaded
    loaded = nil
    local result, reload_error = M.initialize(paths)
    if not result then
        loaded = previous
        return nil, reload_error or "module refresh failed"
    end
    for _, module in ipairs(previous or {}) do
        if type(module.runtime) == "table" and type(module.runtime.stop) == "function" then
            pcall(module.runtime.stop)
        end
    end
    return result
end

-- Begin background work for every module that has any. Idempotent by contract.
function M.start_all(state)
    for _, module in ipairs(loaded or {}) do
        local runtime = module.runtime
        if type(runtime) == "table" and type(runtime.start) == "function" then
            local ok, started, detail = pcall(runtime.start, state)
            if not ok then
                log.warn(("module %s failed to start: %s"):format(module.id, tostring(started)))
            elseif started == false then
                log.warn(("module %s did not start: %s"):format(module.id, tostring(detail)))
            end
        end
    end
end

-- Manager unload: modules get shutdown() (if any) and then stop().
function M.stop_all(state)
    for _, module in ipairs(loaded or {}) do
        local runtime = module.runtime
        if type(runtime) == "table" then
            if type(runtime.shutdown) == "function" then pcall(runtime.shutdown, state) end
            if type(runtime.stop) == "function" then pcall(runtime.stop, state) end
        end
    end
end

return M

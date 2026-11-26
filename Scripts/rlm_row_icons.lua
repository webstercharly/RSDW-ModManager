-- Look up shipped texture paths first and use the live registry for misses.
-- The widget brush holds the texture. The index keeps plain strings only.
local engine = require("rlm_engine")
local log = require("rlm_log")
local M = {}

local records, cursor, paths, complete
local baked_paths
local SLICE = 500

local function unwrap(value)
    for _ = 1, 2 do
        if type(value) ~= "userdata" then break end
        local ok, inner = pcall(function()
            if type(value.get) == "function" then return value:get() end
        end)
        if not ok or inner == nil then break end
        value = inner
    end
    return value
end

local function text(value)
    value = unwrap(value)
    if type(value) == "string" then return value end
    return value:ToString()
end

function M.cancel_scan()
    records, cursor = nil, nil
    if not complete then paths = nil end
end

function M.index_step()
    if complete then return true end
    if not records then
        local ok, output = pcall(function()
            local helpers = StaticFindObject("/Script/AssetRegistry.Default__AssetRegistryHelpers")
            local registry = engine.object_call(helpers, "GetAssetRegistry")
            if not registry then return nil end
            local results = {}
            registry:GetAssetsByClass({
                PackageName = FName("/Script/Engine"),
                AssetName = FName("Texture2D"),
            }, results, false)
            return results
        end)
        if not ok or not output or #output == 0 or #output > 100000 then
            log.warn("recipe icons: Texture2D registry unavailable")
            complete, paths = true, {}
            return true
        end
        records, cursor, paths = output, 1, {}
        return false
    end
    local last = math.min(cursor + SLICE - 1, #records)
    local started = os.clock()
    for index = cursor, last do
        local record = unwrap(records[index])
        local ok, name, package = pcall(function()
            local asset_name = text(record.AssetName)
            if asset_name:match("^T_") then return asset_name, text(record.PackageName) end
        end)
        if ok and type(package) == "string" and package:sub(1, 1) == "/" then
            local key = name:lower()
            local path = package .. "." .. name
            if paths[key] == nil then
                paths[key] = path
            elseif paths[key] ~= path then
                paths[key] = false
            end
        end
        cursor = index + 1
        if index % 32 == 0 and os.clock() - started >= 0.004 then break end
    end
    if cursor <= #records then return false end
    complete = true
    M.cancel_scan()
    return true
end

function M.path(name)
    if not baked_paths then
        local ok, bundled = pcall(require, "rlm_item_icon_paths")
        baked_paths = ok and type(bundled) == "table" and bundled or {}
    end
    local key = name:lower()
    return baked_paths[key] or (complete and paths[key]) or nil
end

function M.index_ready()
    return complete == true
end

local function texture2d(object)
    if not engine.is_valid(object) then return false end
    local ok, class = pcall(function() return object:GetClass():GetFName():ToString() end)
    return ok and class == "Texture2D"
end

function M.load(path, attempt_load)
    local ok, texture = pcall(StaticFindObject, path)
    if ok and texture2d(texture) then return texture end
    if attempt_load then
        local loaded, object = pcall(LoadAsset, path)
        if loaded and texture2d(object) then return object end
    end
end

return M

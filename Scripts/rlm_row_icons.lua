-- Look up shipped texture paths first and use the live registry for misses.
-- The widget brush holds the texture. The index keeps plain strings only.
local engine = require("rlm_engine")
local log = require("rlm_log")
local M = {}

local records, cursor, paths, complete
local baked_paths, baked_norm, paths_norm, item_catalog, progression_icons
local resolved_cache = {}
local SLICE = 2500
local SRC_ROOT = (debug.getinfo(1, "S").source or ""):match("^@?(.*)[/\\]Scripts[/\\][^/\\]+$")

local function normalize_icon_key(s)
    if type(s) ~= "string" or s == "" then return "" end
    local k = s:lower()
    k = k:gsub("_%x%x%x%x%x%x%x%x$", "")
    k = k:gsub("^t_icon_resources?_", "")
    k = k:gsub("^t_icon_", "")
    k = k:gsub("^t_food_", "")
    k = k:gsub("^t_arrows?_", "")
    k = k:gsub("^t_dagger_", "")
    k = k:gsub("^t_", "")
    k = k:gsub("_%d+$", "")
    k = k:gsub("[^%w]+", "")
    return k
end

local function ensure_item_sources(root_dir)
    local root = root_dir or SRC_ROOT
    if item_catalog == nil and root and root ~= "" then
        local file = io.open(root .. "\\Modules\\Items\\recipes.json", "rb")
        if file then
            local raw = file:read("*a")
            file:close()
            local ok_j, json = pcall(require, "rlm_json")
            if ok_j and type(json) == "table" and type(json.decode) == "function" then
                local ok_d, decoded = pcall(json.decode, raw or "")
                if ok_d and type(decoded) == "table" and type(decoded.items) == "table" then
                    item_catalog = decoded.items
                end
            end
        end
        if item_catalog == nil then item_catalog = false end
    end
    if progression_icons == nil then
        local ok_p, p = pcall(require, "rlm_progression_icons")
        progression_icons = (ok_p and type(p) == "table") and p or false
    end
end

local function lookup_path_exact_or_norm(candidate)
    if type(candidate) ~= "string" or candidate == "" then return nil end
    local exact = M.path(candidate)
    if exact then return exact end
    local stripped = candidate:gsub("_%x%x%x%x%x%x%x%x$", "")
    if stripped ~= candidate then
        local p = M.path(stripped)
        if p then return p end
    end
    local nk = normalize_icon_key(candidate)
    if nk ~= "" then
        if baked_norm and baked_norm[nk] then return baked_norm[nk] end
        if complete and paths_norm and paths_norm[nk] then return paths_norm[nk] end
    end
    return nil
end

local function fuzzy_norm_scan(slug_or_name)
    if type(slug_or_name) ~= "string" or slug_or_name == "" then return nil end
    local clean = slug_or_name:lower():gsub("^mount:", ""):gsub("^da_consumab[le]+_", ""):gsub("^da_", "")
    local nk = clean:gsub("[^%w]+", "")
    if #nk < 4 then return nil end
    local function scan_tbl(tbl)
        if type(tbl) ~= "table" then return nil end
        if tbl[nk] then return tbl[nk] end
        local best_len, best_v = 0, nil
        for k, v in pairs(tbl) do
            if type(v) == "string" and #k >= 4 then
                if nk:find(k, 1, true) or k:find(nk, 1, true) then
                    if #k > best_len then best_len, best_v = #k, v end
                end
            end
        end
        return best_v
    end
    return scan_tbl(baked_norm) or (complete and scan_tbl(paths_norm)) or nil
end

function M.resolve_item_icon(asset_id, display_name, root_dir)
    ensure_item_sources(root_dir)
    M.path("__warm__")
    local cache_key = tostring(asset_id or "") .. "|" .. tostring(display_name or "") .. "|" .. tostring(complete == true)
    local hit_cached = resolved_cache[cache_key]
    if hit_cached ~= nil then return hit_cached ~= false and hit_cached or nil end

    local function finish(res)
        resolved_cache[cache_key] = res or false
        return res
    end

    local key = type(asset_id) == "string" and asset_id ~= "" and asset_id ~= "?" and asset_id or nil
    if key then
        if type(progression_icons) == "table" and type(progression_icons.texture) == "function" then
            local direct = progression_icons.texture(key)
            if direct and direct ~= "" then return finish(direct) end
        end
        if type(item_catalog) == "table" then
            local row = item_catalog[key]
            if type(row) == "table" and type(row[2]) == "string" and row[2] ~= "" and row[2] ~= "T_Icon_Placeholder" then
                local p = lookup_path_exact_or_norm(row[2])
                if p then return finish(p) end
            end
        end
        local short = key
            :gsub("^ITEM_Resources_", "")
            :gsub("^ITEM_Consumable_Potion_[Tt]%d+_", "")
            :gsub("^ITEM_Consumable_Potion_", "")
            :gsub("^ITEM_Consumable_Food_", "")
            :gsub("^ITEM_Consumable_Fish_", "")
            :gsub("^ITEM_Consumable_Meat_", "")
            :gsub("^ITEM_Consumable_", "")
            :gsub("^ITEM_Equipment_", "")
            :gsub("^ITEM_Weapon_", "")
            :gsub("^ITEM_Armour_[Tt]%d+_", "")
            :gsub("^ITEM_Armour_Head_", "")
            :gsub("^ITEM_Armour_", "")
            :gsub("^ITEM_Ammo_Arrows_", "arrows_")
            :gsub("^ITEM_Ammo_Bolts_", "bolts_")
            :gsub("^ITEM_Ammo_", "")
            :gsub("^ITEM_Trinket_Iconic_", "")
            :gsub("^ITEM_Trinket_Inspiring_", "")
            :gsub("^ITEM_Trinket_", "")
            :gsub("^ITEM_Tools?_", "")
            :gsub("^ITEM_Cape_", "")
            :gsub("^ITEM_", "")
            :gsub("^DA_Consumab[le]+_", "")
            :gsub("^DA_", "")
        local slug = short:lower():gsub("[^%w]+", "_"):gsub("^_+", ""):gsub("_+$", "")
        local alt_slug = slug:gsub("terrorbird", "terrobird")
        if slug ~= "" then
            local p = M.path("t_icon_" .. slug) or M.path("t_icon_resource_" .. slug)
                or M.path("t_food_" .. slug) or M.path("t_" .. slug)
                or M.path("t_" .. alt_slug) or M.path("t_icon_" .. alt_slug)
                or lookup_path_exact_or_norm(alt_slug)
            if p then return finish(p) end
        end
    end
    if type(display_name) == "string" and display_name ~= "" then
        local clean_name = display_name:gsub("^MOUNT:%s*", "")
        local name_slug = clean_name:lower():gsub("[^%w]+", "_"):gsub("^_+", ""):gsub("_+$", "")
        if name_slug ~= "" then
            local p = M.path("t_icon_" .. name_slug) or M.path("t_food_" .. name_slug)
                or M.path("t_" .. name_slug) or lookup_path_exact_or_norm(name_slug)
            if p then return finish(p) end
        end
    end
    local fuzzy = (key and fuzzy_norm_scan(key)) or (display_name and fuzzy_norm_scan(display_name)) or nil
    if fuzzy then return finish(fuzzy) end
    if key and type(item_catalog) == "table" then
        local row = item_catalog[key]
        if type(row) == "table" and row[2] == "T_Icon_Placeholder" then
            return finish(M.path("T_Icon_Placeholder"))
        end
    end
    return finish(nil)
end

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
            if asset_name:match("^T_") then
                local pkg = text(record.PackageName)
                local low_n = asset_name:lower()
                local is_pbr = low_n:match("_[dn]$") or low_n:match("_orm$") or low_n:match("_tm$")
                if not is_pbr or pkg:find("/UI/", 1, true) then
                    return asset_name, pkg
                end
            end
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
    paths_norm = {}
    for k, v in pairs(paths or {}) do
        if type(v) == "string" then
            local nk = normalize_icon_key(k)
            if nk ~= "" and paths_norm[nk] == nil then paths_norm[nk] = v end
        end
    end
    complete = true
    M.cancel_scan()
    return true
end

function M.path(name)
    if type(name) ~= "string" or name == "" then return nil end
    if name:match("^/[%w_/]+%.[%w_]+$") then return name end
    if not baked_paths then
        local ok, bundled = pcall(require, "rlm_item_icon_paths")
        baked_paths = ok and type(bundled) == "table" and bundled or {}
        baked_norm = {}
        for k, v in pairs(baked_paths) do
            if type(v) == "string" then
                local nk = normalize_icon_key(k)
                if nk ~= "" and baked_norm[nk] == nil then baked_norm[nk] = v end
            end
        end
    end
    local key = name:lower()
    return baked_paths[key] or (complete and paths and paths[key]) or nil
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

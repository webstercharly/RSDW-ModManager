-- Guarded access to the small part of the Dragonwilds runtime used by the
-- Mod Manager. Game-specific reflection names belong here so a game
-- update does not spread compatibility changes through every service.

local M = {}

local cached_controller = nil
local next_controller_scan = 0
local kismet_system_library = nil

function M.is_valid(object)
    if object == nil then return false end
    local ok_method, method = pcall(function() return object.IsValid end)
    if not ok_method or not method then return false end
    local ok, value = pcall(function() return object:IsValid() end)
    return ok and value == true
end

function M.call(object, method, ...)
    if not M.is_valid(object) then return nil end
    local ok_method, fn = pcall(function() return object[method] end)
    if not ok_method or not fn then return nil end
    local arguments = { ... }
    local ok, value = pcall(function() return fn(object, table.unpack(arguments)) end)
    if ok then return value end
    return nil
end

function M.object_call(object, method, ...)
    local value = M.call(object, method, ...)
    return M.is_valid(value) and value or nil
end

function M.field_object(object, names)
    if not M.is_valid(object) then return nil end
    for _, name in ipairs(names or {}) do
        local ok, value = pcall(function() return object[name] end)
        if ok and M.is_valid(value) then return value end
    end
    return nil
end

function M.number_field(object, names, fallback)
    if M.is_valid(object) then
        for _, name in ipairs(names or {}) do
            local ok, value = pcall(function() return object[name] end)
            if ok and tonumber(value) then return math.floor(tonumber(value)) end
        end
    end
    return fallback
end

function M.full_name(object)
    if not M.is_valid(object) then return "" end
    local ok, value = pcall(function() return object:GetFullName() end)
    return ok and type(value) == "string" and value or ""
end

function M.real_time_seconds()
    if not M.is_valid(kismet_system_library) and type(StaticFindObject) == "function" then
        local ok, value = pcall(StaticFindObject, "/Script/Engine.Default__KismetSystemLibrary")
        if ok and M.is_valid(value) then kismet_system_library = value end
    end
    local context = M.local_controller()
    if M.is_valid(kismet_system_library) and M.is_valid(context) then
        local ok, value = pcall(function()
            return kismet_system_library:GetRealTimeSeconds(context)
        end)
        if ok and tonumber(value) then return tonumber(value) end
    end
    return os.clock()
end

local function enum_number(value)
    if tonumber(value) then return math.floor(tonumber(value)) end
    if type(value) == "userdata" then
        local ok, inner = pcall(function() return value:get() end)
        if ok and inner ~= value then
            local parsed = enum_number(inner)
            if parsed ~= nil then return parsed end
        end
        local ok_value, field = pcall(function() return value.Value end)
        if ok_value and tonumber(field) then return math.floor(tonumber(field)) end
        for _, method in ipairs({ "ToString", "GetName", "GetPlainNameString" }) do
            local ok_text, text = pcall(function() return value[method](value) end)
            if ok_text and type(text) == "string" then value = text; break end
        end
    end
    if type(value) == "string" then
        local normalized = value:lower():gsub("[%s_]", "")
        if normalized:find("standalone", 1, true) then return 0 end
        if normalized:find("dedicatedserver", 1, true) then return 1 end
        if normalized:find("listenserver", 1, true) then return 2 end
        if normalized == "client" or normalized:find("nmclient", 1, true) then return 3 end
    end
    return nil
end

function M.net_mode_int()
    local controller = M.local_controller()
    local mode = controller and enum_number(M.call(controller, "GetNetMode")) or nil
    if mode ~= nil then return mode end
    local pawn = M.local_pawn()
    mode = pawn and enum_number(M.call(pawn, "GetNetMode")) or nil
    if mode ~= nil then return mode end
    local ok_helpers, helpers = pcall(require, "UEHelpers")
    if ok_helpers and type(helpers) == "table" and helpers.GetWorld then
        local ok_world, world = pcall(helpers.GetWorld)
        mode = ok_world and M.is_valid(world) and enum_number(M.call(world, "GetNetMode")) or nil
        if mode ~= nil then return mode end
    end
    return -1
end

function M.net_mode()
    return ({ [0] = "Standalone", [1] = "DedicatedServer", [2] = "ListenServer", [3] = "Client" })
        [M.net_mode_int()] or "Unknown"
end

function M.local_generation_allowed()
    local mode = M.net_mode_int()
    if mode == 0 or mode == 2 then return true, M.net_mode() end
    if mode == 1 or mode == 3 then return false, M.net_mode() end

    -- Some cooked builds do not expose GetNetMode's enum cleanly to UE4SS.
    -- Authority is a safe fallback: a remote client's local controller/pawn
    -- reports false, while standalone and the listen host report true.
    for _, object in ipairs({ M.local_controller(), M.local_pawn() }) do
        if M.is_valid(object) then
            local ok_method, method = pcall(function() return object.HasAuthority end)
            if ok_method and method then
                local ok, authority = pcall(function() return object:HasAuthority() end)
                if ok and authority == true then return true, "AuthorityHost" end
                if ok and authority == false then return false, "RemoteClient" end
            end
        end
    end
    return false, "Unknown"
end

local function is_local_controller(controller)
    if not M.is_valid(controller) then return false end
    local ok, value = pcall(function() return controller:IsLocalController() end)
    return ok and value == true
end

local function controller_from_helpers()
    local ok_module, helpers = pcall(require, "UEHelpers")
    if not ok_module or type(helpers) ~= "table" or not helpers.GetPlayerController then return nil end
    local ok, controller = pcall(function() return helpers.GetPlayerController() end)
    if ok and M.is_valid(controller) then return controller end
    return nil
end

function M.local_controller(force)
    if is_local_controller(cached_controller) then return cached_controller end
    cached_controller = nil

    local now = os.clock()
    if not force and now < next_controller_scan then return nil end
    next_controller_scan = now + 1

    if type(FindAllOf) == "function" then
        local ok, controllers = pcall(FindAllOf, "PlayerController")
        if ok and type(controllers) == "table" then
            for _, controller in pairs(controllers) do
                if is_local_controller(controller) then
                    local name = M.full_name(controller)
                    if not name:find("MainMenu", 1, true) then
                        cached_controller = controller
                        return controller
                    end
                end
            end
        end
    end

    local helper_controller = controller_from_helpers()
    if is_local_controller(helper_controller) then cached_controller = helper_controller end
    return cached_controller
end

function M.local_pawn()
    local controller = M.local_controller()
    if not controller then return nil end
    return M.object_call(controller, "GetPawn") or M.field_object(controller, { "Pawn", "AcknowledgedPawn" })
end

function M.invalidate()
    cached_controller = nil
    next_controller_scan = 0
end

function M.component(controller, getter, fields)
    return M.object_call(controller, getter) or M.field_object(controller, fields)
end

function M.open_container(player_inventory)
    if type(FindAllOf) ~= "function" then return nil end
    local ok, panels = pcall(FindAllOf, "WorldActorInventoryMainPanel")
    if not ok or type(panels) ~= "table" then return nil end
    for _, panel in pairs(panels) do
        if M.is_valid(panel) then
            local active = M.call(panel, "IsActivated")
            if active == nil then
                local field_ok, value = pcall(function() return panel.bIsActive end)
                if field_ok then active = value end
            end
            if active == true then
                local api = M.field_object(panel, { "WorldInventoryManagerAPI" })
                if api and M.call(api, "IsInitialized") == true then
                    local component = M.object_call(api, "GetInventoryComponent")
                        or M.field_object(api, { "InventoryComponent" })
                    if component and component ~= player_inventory then
                        local label = "open container"
                        local owner = M.object_call(component, "GetOwner")
                        local name = owner and M.full_name(owner) or ""
                        if name ~= "" then label = name end
                        return component, label
                    end
                end
            end
        end
    end
    return nil
end

function M.player_runtime()
    local controller = M.local_controller()
    if not controller then return nil, "local player controller is not ready" end

    local inventory = M.component(controller, "GetInventory", {
        "InventoryComponent", "BP_Components_PersonalInventory",
    })
    local loadout = M.component(controller, "GetLoadout", {
        "LoadoutComponent", "BP_Components_Loadout",
    })
    local inventory_controller = M.component(controller, "GetInventoryController", {
        "InventoryController", "BP_Components_InventoryController",
    })

    if not inventory then return nil, "player inventory is not ready" end
    if not loadout then return nil, "player loadout is not ready" end

    return {
        controller = controller,
        pawn = M.local_pawn(),
        inventory = inventory,
        loadout = loadout,
        inventory_controller = inventory_controller,
    }
end

function M.probe()
    local runtime, reason = M.player_runtime()
    if not runtime then return { status = "waiting", reason = reason } end
    if not runtime.inventory_controller then
        return {
            status = "degraded",
            reason = "inventory transfer controller is unavailable; snapshots are read-only",
        }
    end
    return { status = "ready", reason = "player inventory and loadout paths resolved" }
end

return M

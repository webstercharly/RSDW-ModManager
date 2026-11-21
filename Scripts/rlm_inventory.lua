-- Read-only inventory adapter. Mutation and server dispatch deliberately live
-- outside this module so capture/preview cannot accidentally equip anything.

local engine = require("rlm_engine")

local M = {}

local LOADOUT_LAST_SLOT = 11
local QUICK_SLOT_FALLBACK = 10
local INVENTORY_SCAN_FALLBACK = 120

local LOADOUT_SLOT_NAMES = {
    [0] = "Head",
    [1] = "Body",
    [2] = "Legs",
    [3] = "Cape",
    [4] = "Jewellery 1",
    [5] = "Ranged ammo 1",
    [6] = "Magic ammo 1",
    [7] = "Right hand",
    [8] = "Left hand",
    [9] = "Ranged ammo 2",
    [10] = "Magic ammo 2",
    [11] = "Jewellery 2",
}

local function item_at(component, slot)
    local item = engine.call(component, "GetItemFromSlot", slot)
    return engine.is_valid(item) and item or nil
end

local function item_data(item)
    local data = engine.object_call(item, "BP_GetItemData")
    return data or engine.field_object(item, { "ItemData" })
end

local function short_asset_name(identity)
    local text = tostring(identity or "")
    return text:match("%.([^%.%s]+)$")
        or text:match("/([^/%s]+)$")
        or text:match("([^%s]+)$")
        or text
end

local function facing_name(item)
    local value = engine.call(item, "GetPlayerFacingName")
    if type(value) == "string" then return value end
    if value ~= nil then
        local ok, text = pcall(function() return value:ToString() end)
        if ok and type(text) == "string" then return text end
    end
    return ""
end

local function item_count(item)
    local count = engine.number_field(item, { "Count", "StackCount", "Quantity" }, 1)
    return math.max(1, count or 1)
end

local function item_record(item, slot, slot_name)
    local data = item_data(item)
    if not data then return nil end
    local identity = engine.full_name(data)
    if identity == "" then return nil end

    local record = {
        slot = slot,
        slotName = slot_name,
        asset = short_asset_name(identity),
        identity = identity,
        count = item_count(item),
    }
    local label = facing_name(item)
    if label ~= "" then record.label = label end
    local durability = engine.call(item, "GetDurability")
    if tonumber(durability) then record.durability = tonumber(durability) end
    return record
end

local function same_identity(left, right)
    if type(left) ~= "table" or type(right) ~= "table" then return false end
    local left_identity, right_identity = tostring(left.identity or ""), tostring(right.identity or "")
    if left_identity ~= "" and right_identity ~= "" and left_identity == right_identity then return true end
    return tostring(left.asset or ""):lower() == tostring(right.asset or ""):lower()
        and tostring(left.asset or "") ~= ""
end

function M.same_item(left, right)
    return same_identity(left, right)
end

function M.probe()
    return engine.probe()
end

local function matching_record(item, wanted)
    local record = item_record(item, -1, "")
    return record and same_identity(record, wanted) or false
end

local function find_item(runtime, wanted, inventory_slots)
    for slot = 0, inventory_slots - 1 do
        local item = item_at(runtime.inventory, slot)
        if item and matching_record(item, wanted) then return "inventory", slot end
    end
    for slot = 0, LOADOUT_LAST_SLOT do
        local item = item_at(runtime.loadout, slot)
        if item and matching_record(item, wanted) then return "loadout", slot end
    end
    return nil
end

local function component_has(component, wanted)
    if not engine.is_valid(component) then return false end
    local slots = engine.number_field(component,
        { "MaxSlotCount", "MaxSlots", "SlotCount" }, INVENTORY_SCAN_FALLBACK)
    if slots < 1 or slots > 500 then slots = INVENTORY_SCAN_FALLBACK end
    for slot = 0, slots - 1 do
        local item = item_at(component, slot)
        if item and matching_record(item, wanted) then return true, slot end
    end
    return false
end

function M.preflight_equipment(entries, options)
    if type(entries) ~= "table" or #entries == 0 then
        return nil, "swap has no captured equipment"
    end
    local runtime, runtime_error = engine.player_runtime()
    if not runtime then return nil, runtime_error end
    local inventory_slots = engine.number_field(runtime.inventory,
        { "MaxSlotCount", "MaxSlots", "SlotCount" }, INVENTORY_SCAN_FALLBACK)
    if inventory_slots < 1 or inventory_slots > 500 then inventory_slots = INVENTORY_SCAN_FALLBACK end

    local open_inventory, open_label = nil, nil
    if type(options) == "table" and options.includeOpenContainer == true then
        open_inventory, open_label = engine.open_container(runtime.inventory)
    end
    local report = { total = 0, correct = 0, available = 0, fromOpenContainer = 0,
        openContainer = open_label, missing = {}, invalid = {} }
    local seen_held = {}
    for _, wanted in ipairs(entries) do
        local slot = type(wanted) == "table" and tonumber(wanted.slot) or nil
        local asset = type(wanted) == "table" and tostring(wanted.asset or "") or ""
        if not slot or asset == "" or slot < 0 or slot > LOADOUT_LAST_SLOT then
            report.invalid[#report.invalid + 1] = asset ~= "" and asset or "invalid entry"
        else
            local held = slot == 7 or slot == 8
            local held_key = held and asset:lower() or nil
            if not (held and seen_held[held_key]) then
                if held then seen_held[held_key] = true end
                report.total = report.total + 1
                local current = item_at(runtime.loadout, slot)
                if current and matching_record(current, wanted) then
                    report.correct = report.correct + 1
                else
                    local source = find_item(runtime, wanted, inventory_slots)
                    if source then
                        report.available = report.available + 1
                    elseif open_inventory and component_has(open_inventory, wanted) then
                        report.fromOpenContainer = report.fromOpenContainer + 1
                    else
                        report.missing[#report.missing + 1] = tostring(wanted.label or wanted.asset)
                    end
                end
            end
        end
    end
    for _, value in ipairs(report.invalid) do report.missing[#report.missing + 1] = value end
    return report
end

function M.preflight_quick_slots(entries, options)
    if type(entries) ~= "table" then return nil, "quick-slot setup is invalid" end
    local runtime, runtime_error = engine.player_runtime()
    if not runtime then return nil, runtime_error end
    local inventory_slots = engine.number_field(runtime.inventory,
        { "MaxSlotCount", "MaxSlots", "SlotCount" }, INVENTORY_SCAN_FALLBACK)
    if inventory_slots < 1 or inventory_slots > 500 then inventory_slots = INVENTORY_SCAN_FALLBACK end

    local open_inventory, open_label = nil, nil
    if type(options) == "table" and options.includeOpenContainer == true then
        open_inventory, open_label = engine.open_container(runtime.inventory)
    end
    local report = { total = 0, correct = 0, available = 0, fromOpenContainer = 0,
        openContainer = open_label, missing = {}, lowStacks = {} }
    for _, wanted in ipairs(entries) do
        local slot = type(wanted) == "table" and tonumber(wanted.slot) or nil
        local asset = type(wanted) == "table" and tostring(wanted.asset or "") or ""
        if not slot or slot < 0 or asset == "" then
            report.missing[#report.missing + 1] = asset ~= "" and asset or "invalid quick-slot entry"
        else
            report.total = report.total + 1
            local current = item_at(runtime.inventory, slot)
            local wanted_count = math.max(1, tonumber(wanted.count) or 1)
            if current and matching_record(current, wanted) then
                report.correct = report.correct + 1
                local count = item_count(current)
                if count < wanted_count then
                    report.lowStacks[#report.lowStacks + 1] = ("%s %d/%d")
                        :format(tostring(wanted.label or wanted.asset), count, wanted_count)
                end
            else
                local source = find_item(runtime, wanted, inventory_slots)
                if source then report.available = report.available + 1
                elseif open_inventory and component_has(open_inventory, wanted) then
                    report.fromOpenContainer = report.fromOpenContainer + 1
                else report.missing[#report.missing + 1] = tostring(wanted.label or wanted.asset) end
            end
        end
    end
    return report
end

function M.owned_count(wanted, include_open_container)
    local runtime, runtime_error = engine.player_runtime()
    if not runtime then return nil, runtime_error end
    local slots = engine.number_field(runtime.inventory,
        { "MaxSlotCount", "MaxSlots", "SlotCount" }, INVENTORY_SCAN_FALLBACK)
    if slots < 1 or slots > 500 then slots = INVENTORY_SCAN_FALLBACK end
    local total = 0
    for slot = 0, slots - 1 do
        local item = item_at(runtime.inventory, slot)
        if item and matching_record(item, wanted) then total = total + item_count(item) end
    end
    if total == 0 then
        for slot = 0, LOADOUT_LAST_SLOT do
            local item = item_at(runtime.loadout, slot)
            if item and matching_record(item, wanted) then total = item_count(item); break end
        end
    end
    if include_open_container == true then
        local open = engine.open_container(runtime.inventory)
        if open then
            local open_slots = engine.number_field(open,
                { "MaxSlotCount", "MaxSlots", "SlotCount" }, INVENTORY_SCAN_FALLBACK)
            if open_slots < 1 or open_slots > 500 then open_slots = INVENTORY_SCAN_FALLBACK end
            for slot = 0, open_slots - 1 do
                local item = item_at(open, slot)
                if item and matching_record(item, wanted) then total = total + item_count(item) end
            end
        end
    end
    return total
end

function M.snapshot()
    local runtime, reason = engine.player_runtime()
    if not runtime then
        return nil, reason
    end

    local snapshot = {
        schemaVersion = 1,
        capturedUtc = os.date("!%Y-%m-%dT%H:%M:%SZ"),
        equipment = {},
        quickSlots = {},
        warnings = {},
    }

    -- A two-handed item can be exposed in both hand slots as the same UItem.
    -- Record it once so later plans never attempt to equip one object twice.
    local seen_objects, seen_held_assets = {}, {}
    for slot = 0, LOADOUT_LAST_SLOT do
        local item = item_at(runtime.loadout, slot)
        if item and not seen_objects[item] then
            seen_objects[item] = true
            local record = item_record(item, slot, LOADOUT_SLOT_NAMES[slot] or ("Loadout " .. slot))
            if record then
                local held = slot == 7 or slot == 8
                local held_key = held and tostring(record.asset):lower() or nil
                if not (held and seen_held_assets[held_key]) then
                    if held then seen_held_assets[held_key] = true end
                    snapshot.equipment[#snapshot.equipment + 1] = record
                end
            end
        end
    end

    local quick_count = engine.number_field(runtime.inventory,
        { "NumberOfQuickActionSlots", "NumQuickActionSlots" }, QUICK_SLOT_FALLBACK)
    if quick_count < 0 or quick_count > 30 then
        quick_count = QUICK_SLOT_FALLBACK
        snapshot.warnings[#snapshot.warnings + 1] = "quick-slot count was outside the expected range"
    end
    snapshot.quickSlotCapacity = quick_count

    for slot = 0, quick_count - 1 do
        local item = item_at(runtime.inventory, slot)
        if item then
            local record = item_record(item, slot, "Quick " .. tostring(slot + 1))
            if record then snapshot.quickSlots[#snapshot.quickSlots + 1] = record end
        end
    end

    snapshot.equipmentCount = #snapshot.equipment
    snapshot.quickItemCount = #snapshot.quickSlots
    snapshot.compatibility = runtime.inventory_controller and "ready" or "degraded"
    if not runtime.inventory_controller then
        snapshot.warnings[#snapshot.warnings + 1] = "inventory transfer controller is unavailable"
    end
    return snapshot
end

return M

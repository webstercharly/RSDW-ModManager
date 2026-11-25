local json = require("rlm_json")
local log = require("rlm_log")

local M = {}

local SCHEMA_VERSION = 1
local documents = {}
local locations = nil
local mod_version = "dev"
local BACKUP_LIMIT = 12
local next_backup_slots = {}

local function mark_save(timing, phase)
    if not timing then return end
    local now = os.clock()
    timing.phases[#timing.phases + 1] = ("%s %.0f ms"):format(phase, (now - timing.last) * 1000)
    timing.last = now
end

local function utc_now()
    return os.date("!%Y-%m-%dT%H:%M:%SZ")
end

local function read_file(path)
    local file = io.open(path, "rb")
    if not file then return nil end
    local body = file:read("*a")
    file:close()
    return body
end

local function file_exists(path)
    local file = io.open(path, "rb")
    if not file then return false end
    file:close()
    return true
end

local function join(left, right)
    if tostring(left):sub(-1) == "\\" then return tostring(left) .. tostring(right) end
    return tostring(left) .. "\\" .. tostring(right)
end

local function write_atomic(path, body, timing)
    local temporary = path .. ".tmp"
    local previous = path .. ".previous"
    local file, open_error = io.open(temporary, "wb")
    mark_save(timing, "open temporary file")
    if not file then return false, "could not open temporary file: " .. tostring(open_error) end
    local ok_write, write_error = pcall(function()
        assert(file:write(body))
        assert(file:flush())
    end)
    local closed, close_error = file:close()
    mark_save(timing, "write and close temporary file")
    if not ok_write or not closed then
        os.remove(temporary)
        return false, "temporary write failed: " .. tostring(write_error or close_error)
    end

    if file_exists(path) then
        os.remove(previous)
        local moved, move_error = os.rename(path, previous)
        if not moved then
            os.remove(temporary)
            return false, "could not preserve previous document: " .. tostring(move_error)
        end
    end
    mark_save(timing, "rotate previous document")

    local installed, install_error = os.rename(temporary, path)
    mark_save(timing, "install document")
    if not installed then
        if file_exists(previous) then os.rename(previous, path) end
        os.remove(temporary)
        return false, "could not install new document: " .. tostring(install_error)
    end
    return true
end

local function read_backup_slot(path)
    local file = io.open(path, "rb")
    if not file then return nil end
    local index = tonumber(file:read(4))
    file:close()
    if index and index % 1 == 0 and index >= 1 and index <= BACKUP_LIMIT then return index end
end

local function backup_existing(kind, path, timing)
    if not locations.backups then return true end
    local body = read_file(path)
    mark_save(timing, "read previous document")
    if not body then return true end

    -- Fixed slots avoid launching a shell on the game thread. Dated backups from
    -- earlier releases stay available for manual recovery.
    local cursor = join(locations.backups, kind .. "-rolling.next")
    local index = next_backup_slots[kind] or read_backup_slot(cursor)
        or read_backup_slot(cursor .. ".previous") or 1
    local target = join(locations.backups, ("%s-rolling-%02d.json"):format(kind, index))
    local ok, backup_error = write_atomic(target, body)
    mark_save(timing, "write rolling backup")
    if not ok then return false, backup_error end
    os.remove(target .. ".previous")

    local next_index = index % BACKUP_LIMIT + 1
    next_backup_slots[kind] = next_index
    local cursor_saved, cursor_error = write_atomic(cursor, tostring(next_index) .. "\n")
    mark_save(timing, "advance backup slot")
    if not cursor_saved then
        log.warn("could not record next " .. kind .. " backup slot: " .. tostring(cursor_error))
    end
    return true
end

-- Every document is described by a spec: { path, base(document), validate(value) }.
-- "settings" is owned by the shell. Modules register their own documents with
-- M.register so the shell never needs to know their schemas.
local specs = {}

local function base_document(kind)
    local document = {
        schemaVersion = SCHEMA_VERSION,
        modVersion = mod_version,
        updatedUtc = utc_now(),
    }
    local spec = specs[kind]
    if spec and type(spec.base) == "function" then spec.base(document) end
    return document
end

local function validate(kind, value)
    if type(value) ~= "table" then return false, kind .. " root is not an object" end
    local schema = tonumber(value.schemaVersion)
    if not schema then return false, kind .. " has no schemaVersion" end
    if schema > SCHEMA_VERSION then
        return false, kind .. " uses newer schema " .. tostring(schema)
    end
    local spec = specs[kind]
    if spec and type(spec.validate) == "function" then
        local ok, reason = spec.validate(value)
        if not ok then return false, reason or (kind .. " is invalid") end
    end
    return true
end

local function load_document(kind, path)
    local body = read_file(path)
    if not body then
        local created = base_document(kind)
        local saved, save_error = write_atomic(path, json.encode(created, true) .. "\n")
        if not saved then return nil, save_error end
        log.info("created " .. kind .. " document")
        return created
    end

    local decoded_ok, decoded = pcall(json.decode, body)
    if not decoded_ok then return nil, kind .. " JSON is invalid: " .. tostring(decoded) end
    local valid, validation_error = validate(kind, decoded)
    if not valid then return nil, validation_error end
    return decoded
end

function M.initialize(paths, identity)
    if locations then return true, documents end
    if type(paths) ~= "table" then return false, "storage paths are missing" end
    locations = paths
    mod_version = tostring(type(identity) == "table" and identity.version or "dev")

    specs.settings = {
        path = paths.settings,
        base = function(document)
            document.ui = { lastTab = "", scale = 100 }
            document.hotkeys = {}
        end,
    }
    local document, load_error = load_document("settings", specs.settings.path)
    if not document then
        locations = nil
        return false, load_error
    end
    documents.settings = document
    return true, documents
end

-- Register a module-owned document stored beside the shell's settings.
-- spec = { file = "name.json", base = function(document) end,
--          validate = function(value) return ok, reason end }
-- Safe to call again after a module reload: the loaded document is kept.
function M.register(kind, spec)
    if documents[kind] then return true, documents[kind] end
    if not locations then return false, "storage is not initialized" end
    if type(kind) ~= "string" or not kind:match("^[%w_]+$") then return false, "invalid document kind" end
    if type(spec) ~= "table" or type(spec.file) ~= "string" or not spec.file:match("^[%w_.-]+%.json$") then
        return false, "invalid document file name"
    end
    specs[kind] = { path = join(locations.user_root, spec.file), base = spec.base, validate = spec.validate }
    local document, load_error = load_document(kind, specs[kind].path)
    if not document then
        specs[kind] = nil
        return false, load_error
    end
    documents[kind] = document
    return true, document
end

function M.get(kind)
    return documents[kind]
end

function M.save(kind)
    local document = documents[kind]
    if not document or not locations then return false, "document is not loaded: " .. tostring(kind) end
    local spec = specs[kind]
    local path = spec and spec.path
    if not path then return false, "document path is unavailable" end
    local started = os.clock()
    local timing = { last = started, phases = {} }
    document.schemaVersion = SCHEMA_VERSION
    document.modVersion = mod_version
    document.updatedUtc = utc_now()
    local backed_up, backup_error = backup_existing(kind, path, timing)
    if not backed_up then
        log.warn("could not create " .. kind .. " backup: " .. tostring(backup_error))
    end
    local encoded = json.encode(document, true) .. "\n"
    mark_save(timing, "encode JSON")
    local saved, save_error = write_atomic(path, encoded, timing)
    local elapsed = (os.clock() - started) * 1000
    if elapsed >= 50 then
        log.info(("Store save %s: %.0f ms (%d bytes, %s): %s")
            :format(kind, elapsed, #encoded, saved and "saved" or "failed", table.concat(timing.phases, ", ")))
    end
    return saved, save_error
end

function M.schema_version()
    return SCHEMA_VERSION
end

return M


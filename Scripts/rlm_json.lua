-- Small dependency-free JSON codec for Mod Manager documents.

local M = {}
M.null = {}

local function escape_string(value)
    local replacements = {
        ['"'] = '\\"', ['\\'] = '\\\\', ['\b'] = '\\b', ['\f'] = '\\f',
        ['\n'] = '\\n', ['\r'] = '\\r', ['\t'] = '\\t',
    }
    return '"' .. value:gsub('[%z\1-\31\\"]', function(char)
        return replacements[char] or string.format('\\u%04x', char:byte())
    end) .. '"'
end

local function is_array(value)
    local count, highest = 0, 0
    for key in pairs(value) do
        if type(key) ~= "number" or key < 1 or key % 1 ~= 0 then return false end
        count = count + 1
        if key > highest then highest = key end
    end
    return highest == count
end

local function encode_value(value, pretty, depth, seen)
    local kind = type(value)
    if value == M.null or kind == "nil" then return "null" end
    if kind == "boolean" then return value and "true" or "false" end
    if kind == "number" then
        if value ~= value or value == math.huge or value == -math.huge then
            error("cannot encode a non-finite number")
        end
        return tostring(value)
    end
    if kind == "string" then return escape_string(value) end
    if kind ~= "table" then error("cannot encode " .. kind) end
    if seen[value] then error("cannot encode a cyclic table") end
    seen[value] = true

    local array = is_array(value)
    local open_char, close_char = array and "[" or "{", array and "]" or "}"
    local entries = {}
    if array then
        for index = 1, #value do
            entries[#entries + 1] = encode_value(value[index], pretty, depth + 1, seen)
        end
    else
        local keys = {}
        for key in pairs(value) do
            if type(key) ~= "string" then error("object key must be a string") end
            keys[#keys + 1] = key
        end
        table.sort(keys)
        for _, key in ipairs(keys) do
            entries[#entries + 1] = escape_string(key) .. (pretty and ": " or ":")
                .. encode_value(value[key], pretty, depth + 1, seen)
        end
    end
    seen[value] = nil
    if #entries == 0 then return open_char .. close_char end
    if not pretty then return open_char .. table.concat(entries, ",") .. close_char end

    local indent = string.rep("  ", depth + 1)
    local closing_indent = string.rep("  ", depth)
    return open_char .. "\n" .. indent .. table.concat(entries, ",\n" .. indent)
        .. "\n" .. closing_indent .. close_char
end

function M.encode(value, pretty)
    return encode_value(value, pretty == true, 0, {})
end

local function decode_error(position, message)
    error(("JSON error at byte %d: %s"):format(position, message), 0)
end

function M.decode(source)
    if type(source) ~= "string" then error("JSON source must be a string", 0) end
    local position, length = 1, #source

    local function skip_space()
        local _, finish = source:find("^[ \t\r\n]*", position)
        position = (finish or position - 1) + 1
    end

    local parse_value

    local function parse_string()
        position = position + 1
        local parts, start = {}, position
        while position <= length do
            local byte = source:byte(position)
            if byte == 34 then
                parts[#parts + 1] = source:sub(start, position - 1)
                position = position + 1
                return table.concat(parts)
            end
            if byte == 92 then
                parts[#parts + 1] = source:sub(start, position - 1)
                position = position + 1
                local escaped = source:sub(position, position)
                local simple = {
                    ['"'] = '"', ['\\'] = '\\', ['/'] = '/', b = '\b', f = '\f',
                    n = '\n', r = '\r', t = '\t',
                }
                if simple[escaped] then
                    parts[#parts + 1] = simple[escaped]
                    position = position + 1
                elseif escaped == "u" then
                    local hex = source:sub(position + 1, position + 4)
                    if not hex:match("^%x%x%x%x$") then decode_error(position, "invalid unicode escape") end
                    local code = tonumber(hex, 16)
                    if code < 0x80 then
                        parts[#parts + 1] = string.char(code)
                    elseif code < 0x800 then
                        parts[#parts + 1] = string.char(0xC0 + math.floor(code / 64), 0x80 + code % 64)
                    else
                        parts[#parts + 1] = string.char(
                            0xE0 + math.floor(code / 4096),
                            0x80 + math.floor(code / 64) % 64,
                            0x80 + code % 64)
                    end
                    position = position + 5
                else
                    decode_error(position, "invalid escape")
                end
                start = position
            elseif byte < 32 then
                decode_error(position, "control character in string")
            else
                position = position + 1
            end
        end
        decode_error(position, "unterminated string")
    end

    local function parse_array()
        position = position + 1
        skip_space()
        local result = {}
        if source:sub(position, position) == "]" then position = position + 1; return result end
        while true do
            result[#result + 1] = parse_value()
            skip_space()
            local char = source:sub(position, position)
            if char == "]" then position = position + 1; return result end
            if char ~= "," then decode_error(position, "expected ',' or ']'") end
            position = position + 1
            skip_space()
        end
    end

    local function parse_object()
        position = position + 1
        skip_space()
        local result = {}
        if source:sub(position, position) == "}" then position = position + 1; return result end
        while true do
            if source:sub(position, position) ~= '"' then decode_error(position, "expected object key") end
            local key = parse_string()
            skip_space()
            if source:sub(position, position) ~= ":" then decode_error(position, "expected ':'") end
            position = position + 1
            skip_space()
            result[key] = parse_value()
            skip_space()
            local char = source:sub(position, position)
            if char == "}" then position = position + 1; return result end
            if char ~= "," then decode_error(position, "expected ',' or '}'") end
            position = position + 1
            skip_space()
        end
    end

    parse_value = function()
        skip_space()
        local char = source:sub(position, position)
        if char == '"' then return parse_string() end
        if char == "[" then return parse_array() end
        if char == "{" then return parse_object() end
        if source:sub(position, position + 3) == "true" then position = position + 4; return true end
        if source:sub(position, position + 4) == "false" then position = position + 5; return false end
        if source:sub(position, position + 3) == "null" then position = position + 4; return M.null end
        local number_text = source:sub(position):match("^-?%d+%.?%d*[eE]?[+-]?%d*")
        if number_text and number_text ~= "" then
            local number = tonumber(number_text)
            if number == nil then decode_error(position, "invalid number") end
            position = position + #number_text
            return number
        end
        decode_error(position, "unexpected token")
    end

    local result = parse_value()
    skip_space()
    if position <= length then decode_error(position, "trailing content") end
    return result
end

return M


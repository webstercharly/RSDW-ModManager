-- One persistent game-thread scheduler shared by equipment transactions.

local log = require("rlm_log")
local engine = require("rlm_engine")

local M = {}
local active = false
local generation = 0
local queue = {}
local driver = rawget(_G, "__RLM_ASYNC_DRIVER")
if type(driver) ~= "table" then
    driver = { started = false, tick = nil }
    rawset(_G, "__RLM_ASYNC_DRIVER", driver)
end

local function tick(my_generation)
    if not active or my_generation ~= generation then return end
    local current, due = engine.real_time_seconds(), {}
    for index = #queue, 1, -1 do
        local task = queue[index]
        if task.generation ~= generation then
            table.remove(queue, index)
        elseif current >= task.due then
            table.remove(queue, index)
            due[#due + 1] = task
        end
    end
    for index = #due, 1, -1 do
        local ok, task_error = pcall(due[index].callback)
        if not ok then log.warn("scheduled task failed: " .. tostring(task_error)) end
    end
end

function M.start()
    if active then return true end
    if type(LoopInGameThreadWithDelay) ~= "function" then
        return false, "game-thread scheduler is unavailable"
    end
    generation = generation + 1
    active, queue = true, {}
    local my_generation = generation
    driver.tick = function() tick(my_generation) end
    if not driver.started then
        local ok, loop_error = pcall(LoopInGameThreadWithDelay, 16, function()
            local callback = driver.tick
            if type(callback) == "function" then callback() end
        end)
        if not ok then active = false; driver.tick = nil; return false, tostring(loop_error) end
        driver.started = true
    end
    return true
end

function M.after(seconds, callback)
    if not active then return false, "scheduler is not running" end
    if type(callback) ~= "function" then return false, "scheduled callback is invalid" end
    queue[#queue + 1] = {
        due = engine.real_time_seconds() + math.max(0, tonumber(seconds) or 0),
        callback = callback,
        generation = generation,
    }
    return true
end

function M.stop()
    active = false
    generation = generation + 1
    queue = {}
    driver.tick = nil
    return true
end

return M

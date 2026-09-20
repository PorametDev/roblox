-- Every auto_* module used to run its own RunService.Heartbeat connection,
-- so enabling several at once made them all fire every frame at the same
-- time - Auto Sell teleporting to the SellStand while Auto Mine/Auto Chest
-- were still acting on the plot, fighting over the character. This gives
-- them one shared Heartbeat instead: only one registered task's Step() runs
-- at a time, in round-robin order, each getting a few seconds before the
-- scheduler moves on to the next enabled one.
return function(import)

local RunService = game:GetService("RunService")
local log = import("core/logger")

local SLICE_SECONDS = 3

local scheduler = {}
local tasks = {}
local connection = nil
local rrIndex = 0
local currentTask = nil
local sliceEnd = 0

function scheduler.Register(name, step, isEnabled)
    table.insert(tasks, { name = name, step = step, isEnabled = isEnabled })
end

local function pickNextEnabled()
    if #tasks == 0 then
        return nil
    end
    for _ = 1, #tasks do
        rrIndex = (rrIndex % #tasks) + 1
        local candidate = tasks[rrIndex]
        if candidate.isEnabled() then
            return candidate
        end
    end
    return nil
end

function scheduler.Start()
    if connection then
        return
    end

    connection = RunService.Heartbeat:Connect(function()
        local now = tick()

        if not currentTask or not currentTask.isEnabled() or now > sliceEnd then
            local next_ = pickNextEnabled()
            if next_ ~= currentTask then
                currentTask = next_
                log("[Scheduler] turn: " .. (currentTask and currentTask.name or "(none enabled)"))
            end
            sliceEnd = now + SLICE_SECONDS
        end

        if currentTask then
            local ok, err = pcall(currentTask.step)
            if not ok then
                log("[Scheduler] " .. currentTask.name .. " error: " .. tostring(err))
            end
        end
    end)
end

function scheduler.Stop()
    if connection then
        connection:Disconnect()
        connection = nil
    end
    currentTask = nil
end

return scheduler

end

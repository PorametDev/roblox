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

function scheduler.Register(name, step, isEnabled, isBusy)
    table.insert(tasks, { name = name, step = step, isEnabled = isEnabled, isBusy = isBusy })
end

-- A task whose job spans several seconds (teleport, open, click, teleport
-- back) must finish before anyone else runs - otherwise one task's
-- teleport-back yanks the character away mid-click of another's. Auto Sell
-- returning home exactly as Auto Chest clicked Take All is why nothing was
-- ever collected.
local function anyBusy()
    for _, task_ in ipairs(tasks) do
        if task_.isBusy and task_.isBusy() then
            return true
        end
    end
    return false
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
        if anyBusy() then
            return
        end

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

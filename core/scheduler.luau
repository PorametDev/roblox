-- One Heartbeat for every automation, with two registration modes:
--
--   RegisterStandalone - the task touches nothing shared (firing a
--     ClickDetector ignores distance, so it works wherever the character
--     happens to be). Runs every frame while enabled, alongside everything
--     else, and is never blocked.
--
--   RegisterExclusive - the task takes over the character or the screen
--     (teleporting, opening a menu, clicking through it). These take turns,
--     one at a time, and while any of them is mid-job nothing else
--     exclusive runs. Auto Sell teleporting home in the same frame Auto
--     Chest clicked Take All is what this prevents.
--
-- New automations pick a mode by asking one question: does it need the
-- character to be somewhere specific, or a menu to be open? If no, it's
-- standalone.
return function(import)

local RunService = game:GetService("RunService")
local log = import("core/logger")

local SLICE_SECONDS = 3

local scheduler = {}
local standaloneTasks = {}
local exclusiveTasks = {}
local connection = nil
local rrIndex = 0
local currentTask = nil
local sliceEnd = 0

function scheduler.RegisterStandalone(name, step, isEnabled)
    table.insert(standaloneTasks, { name = name, step = step, isEnabled = isEnabled })
end

function scheduler.RegisterExclusive(name, step, isEnabled, isBusy)
    table.insert(exclusiveTasks, { name = name, step = step, isEnabled = isEnabled, isBusy = isBusy })
end

local function run(task_)
    local ok, err = pcall(task_.step)
    if not ok then
        log("[Scheduler] " .. task_.name .. " error: " .. tostring(err))
    end
end

local function anyExclusiveBusy()
    for _, task_ in ipairs(exclusiveTasks) do
        if task_.isBusy and task_.isBusy() then
            return true
        end
    end
    return false
end

local function pickNextEnabled()
    if #exclusiveTasks == 0 then
        return nil
    end
    for _ = 1, #exclusiveTasks do
        rrIndex = (rrIndex % #exclusiveTasks) + 1
        local candidate = exclusiveTasks[rrIndex]
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
        for _, task_ in ipairs(standaloneTasks) do
            if task_.isEnabled() then
                run(task_)
            end
        end

        if anyExclusiveBusy() then
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
            run(currentTask)
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

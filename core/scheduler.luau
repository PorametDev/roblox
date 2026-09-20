-- One Heartbeat for every automation, with two registration modes:
--
--   RegisterStandalone - the task touches nothing shared (firing a
--     ClickDetector ignores distance, so it works wherever the character
--     happens to be). Runs every frame while enabled, alongside everything
--     else, and is never blocked.
--
--   RegisterExclusive - the task takes over the character or the screen
--     (teleporting, opening a menu, clicking through it). Only one runs at
--     a time, and while any of them is mid-job nothing else exclusive
--     runs. Auto Sell teleporting home in the same frame Auto Chest
--     clicked Take All is what this prevents.
--
--     These run in REGISTRATION ORDER, not round-robin: the first enabled
--     one that still has work to do wins. That's what makes the intended
--     sequence hold - collect the chest, then fill every holder, and only
--     sell once there's nothing left to place. A task says whether it has
--     work through the optional hasWork predicate; without one it's always
--     considered ready, so anything open-ended registers last.
--
--     Strict priority has a failure mode, and it bit: a task near the top
--     that ALWAYS reports work starves everything below it forever. In one
--     session Auto Chest and Auto Upgrade traded turns for four solid
--     minutes and Auto Sell never ran once - so nothing was ever sold, so
--     there was never any money, so Auto Upgrade kept logging "not enough
--     cash". Priority was eating the thing that funded it.
--
--     maxWait is the floor under that: once a lower-priority task has been
--     sitting on work for that long, it gets the next turn regardless of
--     who outranks it. Order still decides the normal case; the timer only
--     decides the starved one.
--
-- New automations pick a mode by asking one question: does it need the
-- character to be somewhere specific, or a menu to be open? If no, it's
-- standalone.
return function(import)

local RunService = game:GetService("RunService")
local log = import("core/logger")

local scheduler = {}
local standaloneTasks = {}
local exclusiveTasks = {}
local connection = nil
local currentTask = nil
-- The task currently allowed to ignore priority because it was starving,
-- and whether it has since managed to start a job (at which point it has
-- had its turn and goes back to the end of the queue).
local starvedOverride = nil
local overrideRan = false

function scheduler.RegisterStandalone(name, step, isEnabled)
    table.insert(standaloneTasks, { name = name, step = step, isEnabled = isEnabled })
end

-- maxWait: seconds this task will tolerate being outranked while it has
-- work waiting. nil means "no floor" - fine for anything that can't be
-- starved into uselessness.
function scheduler.RegisterExclusive(name, step, isEnabled, isBusy, hasWork, maxWait)
    table.insert(exclusiveTasks, {
        name = name,
        step = step,
        isEnabled = isEnabled,
        isBusy = isBusy,
        hasWork = hasWork,
        maxWait = maxWait,
        waitingSince = nil,
    })
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

local function isReady(candidate)
    return candidate.isEnabled() and (not candidate.hasWork or candidate.hasWork())
end

local function pickExclusive()
    local now = tick()
    local ready = {}
    local starved = nil

    for _, candidate in ipairs(exclusiveTasks) do
        if isReady(candidate) then
            candidate.waitingSince = candidate.waitingSince or now
            table.insert(ready, candidate)

            -- First (so still highest-priority) task past its patience.
            if not starved and candidate.maxWait
                and now - candidate.waitingSince >= candidate.maxWait
            then
                starved = candidate
            end
        else
            -- Nothing to do means nothing to wait for; the clock restarts
            -- next time work actually appears.
            candidate.waitingSince = nil
        end
    end

    -- The override is sticky. A single frame of priority is worthless here:
    -- every task rate-limits itself inside Step, so being picked once
    -- almost always means being picked during a tick it intends to skip.
    -- Hold the turn until it has actually started a job (at which point
    -- anyExclusiveBusy blocks everyone) or has nothing left to do.
    -- Released once it has had a real turn, or once it runs out of work.
    if starvedOverride and (overrideRan or not isReady(starvedOverride)) then
        starvedOverride = nil
        overrideRan = false
    end

    if not starvedOverride and starved then
        starvedOverride = starved
        log("[Scheduler] " .. starved.name .. " waited "
            .. string.format("%.0f", now - starved.waitingSince)
            .. "s - jumping the queue")
    end

    local chosen = starvedOverride or ready[1]
    if chosen then
        chosen.waitingSince = nil
    end
    return chosen
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
            -- A job is running; if the queue-jumper is the one that
            -- started it, its turn has been served.
            if starvedOverride then
                overrideRan = true
            end
            return
        end

        local next_ = pickExclusive()
        if next_ ~= currentTask then
            currentTask = next_
            log("[Scheduler] turn: " .. (currentTask and currentTask.name or "(nothing to do)"))
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
    starvedOverride = nil
    overrideRan = false
    for _, task_ in ipairs(exclusiveTasks) do
        task_.waitingSince = nil
    end
end

return scheduler

end

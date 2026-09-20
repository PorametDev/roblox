-- Registered with core/scheduler as STANDALONE: firing a ClickDetector
-- ignores distance, so this keeps mining no matter where Auto Sell or Auto
-- Chest have taken the character, and never waits for a turn.
return function(import)

local getCurrentPlot = import("games/my_anime_mine/get_current_plot")
local getPlotParts = import("games/my_anime_mine/get_plot_parts")
local log = import("core/logger")

-- NodeClick's MaxActivationDistance is 34 studs; firing on an interval
-- instead of every frame avoids hammering the server for no benefit.
--
-- Two dials, both adjustable from the menu and remembered in config:
--   cyclesPerSecond - how often every node gets clicked (was a fixed 5,
--     i.e. one cycle per 0.2s)
--   clicksPerCycle  - how many times each node is clicked per cycle (was
--     a fixed 1)
-- Total traffic is nodes x clicksPerCycle x cyclesPerSecond per second, so
-- both maxed out is a lot of remote calls - worth being deliberate about.
local DEFAULT_CYCLES_PER_SECOND = 5
local DEFAULT_CLICKS_PER_CYCLE = 1

local function findClickDetector(instance)
    return instance:FindFirstChildWhichIsA("ClickDetector", true)
end

local autoMine = {}
local enabled = false
local lastFire = 0
local cyclesPerSecond = DEFAULT_CYCLES_PER_SECOND
local clicksPerCycle = DEFAULT_CLICKS_PER_CYCLE

function autoMine.SetCyclesPerSecond(value)
    cyclesPerSecond = math.clamp(value, 1, 30)
end

function autoMine.SetClicksPerCycle(value)
    clicksPerCycle = math.clamp(value, 1, 10)
end

function autoMine.SetEnabled(state)
    if state == enabled then
        return
    end
    enabled = state
    log("[AutoMine] " .. (enabled and "enabled" or "disabled"))
end

function autoMine.IsEnabled()
    return enabled
end

function autoMine.Step()
    if not enabled then
        return
    end

    local now = tick()
    if now - lastFire < 1 / cyclesPerSecond then
        return
    end
    lastFire = now

    local plot = getCurrentPlot()
    if not plot then
        return
    end

    local parts = getPlotParts(plot)
    if not parts.Nodes then
        return
    end

    for _, node in ipairs(parts.Nodes:GetChildren()) do
        local detector = findClickDetector(node)
        if detector then
            for _ = 1, clicksPerCycle do
                fireclickdetector(detector)
            end
        end
    end
end

return autoMine

end

-- Registered with core/scheduler as STANDALONE: firing a ClickDetector
-- ignores distance, so this keeps mining no matter where Auto Sell or Auto
-- Chest have taken the character, and never waits for a turn.
return function(import)

local getCurrentPlot = import("games/my_anime_mine/get_current_plot")
local getPlotParts = import("games/my_anime_mine/get_plot_parts")
local log = import("core/logger")

-- NodeClick's MaxActivationDistance is 34 studs; firing on an interval
-- instead of every frame avoids hammering the server for no benefit.
local FIRE_INTERVAL = 0.2

local function findClickDetector(instance)
    return instance:FindFirstChildWhichIsA("ClickDetector", true)
end

local autoMine = {}
local enabled = false
local lastFire = 0

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
    if now - lastFire < FIRE_INTERVAL then
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
            fireclickdetector(detector)
        end
    end
end

return autoMine

end

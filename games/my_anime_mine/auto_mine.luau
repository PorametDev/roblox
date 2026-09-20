return function(import)

local RunService = game:GetService("RunService")
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
local connection = nil

function autoMine.SetEnabled(enabled)
    if enabled == autoMine.IsEnabled() then
        return
    end

    if not enabled then
        connection:Disconnect()
        connection = nil
        log("[AutoMine] disabled")
        return
    end

    log("[AutoMine] enabled")
    local lastFire = 0

    connection = RunService.Heartbeat:Connect(function()
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
    end)
end

function autoMine.IsEnabled()
    return connection ~= nil
end

return autoMine

end

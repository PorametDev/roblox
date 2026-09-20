return function(import)

local RunService = game:GetService("RunService")
local getCurrentPlot = import("games/my_anime_mine/get_current_plot")
local getPlotParts = import("games/my_anime_mine/get_plot_parts")
local log = import("core/logger")

local FIRE_INTERVAL = 1

local autoOpenChest = {}
local connection = nil

function autoOpenChest.SetEnabled(enabled)
    if enabled == autoOpenChest.IsEnabled() then
        return
    end

    if not enabled then
        connection:Disconnect()
        connection = nil
        log("[AutoOpenChest] disabled")
        return
    end

    log("[AutoOpenChest] enabled")
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
        if not parts.Chest then
            return
        end

        local prompt = parts.Chest:FindFirstChildWhichIsA("ProximityPrompt", true)
        if prompt then
            fireproximityprompt(prompt)
        end
    end)
end

function autoOpenChest.IsEnabled()
    return connection ~= nil
end

return autoOpenChest

end

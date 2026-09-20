-- UpgradeClick fired fine manually despite MaxActivationDistance=0
-- (confirmed via Interaction Logger), same as NodeClick for mining.
return function(import)

local RunService = game:GetService("RunService")
local getCurrentPlot = import("games/my_anime_mine/get_current_plot")
local getPlotParts = import("games/my_anime_mine/get_plot_parts")
local log = import("core/logger")

local FIRE_INTERVAL = 1

local function findUpgradeClickDetector(holder)
    local upgradePart = holder:FindFirstChild("UpgradePart")
    return upgradePart and upgradePart:FindFirstChildWhichIsA("ClickDetector")
end

local autoUpgrade = {}
local connection = nil

function autoUpgrade.SetEnabled(enabled)
    if enabled == autoUpgrade.IsEnabled() then
        return
    end

    if not enabled then
        connection:Disconnect()
        connection = nil
        log("[AutoUpgrade] disabled")
        return
    end

    log("[AutoUpgrade] enabled")
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
        if not parts.Holders then
            return
        end

        for _, holder in ipairs(parts.Holders:GetChildren()) do
            local detector = findUpgradeClickDetector(holder)
            if detector then
                fireclickdetector(detector)
            end
        end
    end)
end

function autoUpgrade.IsEnabled()
    return connection ~= nil
end

return autoUpgrade

end

-- UpgradeClick fired fine manually despite MaxActivationDistance=0
-- (confirmed via Interaction Logger), same as NodeClick for mining.
-- Registered with core/scheduler as STANDALONE: same as Auto Mine, firing a
-- ClickDetector ignores distance, so it never needs a turn.
return function(import)

local getCurrentPlot = import("games/my_anime_mine/get_current_plot")
local getPlotParts = import("games/my_anime_mine/get_plot_parts")
local log = import("core/logger")

local fireInterval = 1

local function findUpgradeClickDetector(holder)
    local upgradePart = holder:FindFirstChild("UpgradePart")
    return upgradePart and upgradePart:FindFirstChildWhichIsA("ClickDetector")
end

local autoUpgrade = {}
local enabled = false
local lastFire = 0

function autoUpgrade.SetEnabled(state)
    if state == enabled then
        return
    end
    enabled = state
    log("[AutoUpgrade] " .. (enabled and "enabled" or "disabled"))
end

function autoUpgrade.IsEnabled()
    return enabled
end

function autoUpgrade.SetInterval(seconds)
    fireInterval = math.max(seconds, 1)
end

function autoUpgrade.Step()
    if not enabled then
        return
    end

    local now = tick()
    if now - lastFire < fireInterval then
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
end

return autoUpgrade

end

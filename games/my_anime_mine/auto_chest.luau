-- Combines opening the chest and claiming its contents into one loop, so
-- there's only one toggle instead of needing "open" and "take" enabled
-- together to actually get anything.
return function(import)

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local getCurrentPlot = import("games/my_anime_mine/get_current_plot")
local getPlotParts = import("games/my_anime_mine/get_plot_parts")
local log = import("core/logger")

local FIRE_INTERVAL = 1

local function getRemote(name)
    local remotes = ReplicatedStorage:FindFirstChild("Remotes")
    return remotes and remotes:FindFirstChild(name)
end

local autoChest = {}
local connection = nil

function autoChest.SetEnabled(enabled)
    if enabled == autoChest.IsEnabled() then
        return
    end

    if not enabled then
        connection:Disconnect()
        connection = nil
        log("[AutoChest] disabled")
        return
    end

    local claimOre = getRemote("ClaimOre")
    local collectAll = getRemote("CollectAll")
    log(string.format(
        "[AutoChest] enabled (ClaimOre=%s, CollectAll=%s)",
        tostring(claimOre ~= nil), tostring(collectAll ~= nil)
    ))

    local lastFire = 0

    connection = RunService.Heartbeat:Connect(function()
        local now = tick()
        if now - lastFire < FIRE_INTERVAL then
            return
        end
        lastFire = now

        local plot = getCurrentPlot()
        local parts = plot and getPlotParts(plot)
        local prompt = parts and parts.Chest and parts.Chest:FindFirstChildWhichIsA("ProximityPrompt", true)
        if prompt then
            fireproximityprompt(prompt)
        end

        if claimOre then
            local ok, err = pcall(function()
                claimOre:FireServer()
            end)
            if not ok then
                log("[AutoChest] ClaimOre:FireServer() error: " .. tostring(err))
            end
        end
        if collectAll then
            local ok, err = pcall(function()
                collectAll:FireServer()
            end)
            if not ok then
                log("[AutoChest] CollectAll:FireServer() error: " .. tostring(err))
            end
        end
    end)
end

function autoChest.IsEnabled()
    return connection ~= nil
end

return autoChest

end

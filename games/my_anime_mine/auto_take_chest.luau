-- Fires ClaimOre and CollectAll directly (found via Debug: Dump All
-- Remotes) instead of finding and simulating a click on the "Take All"
-- GUI button - no UI dependency at all now.
return function(import)

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local log = import("core/logger")

local FIRE_INTERVAL = 0.5

local function getRemote(name)
    local remotes = ReplicatedStorage:FindFirstChild("Remotes")
    return remotes and remotes:FindFirstChild(name)
end

local autoTakeChest = {}
local connection = nil

function autoTakeChest.SetEnabled(enabled)
    if enabled == autoTakeChest.IsEnabled() then
        return
    end

    if not enabled then
        connection:Disconnect()
        connection = nil
        log("[AutoTakeChest] disabled")
        return
    end

    local claimOre = getRemote("ClaimOre")
    local collectAll = getRemote("CollectAll")
    log(string.format(
        "[AutoTakeChest] enabled (ClaimOre=%s, CollectAll=%s)",
        tostring(claimOre ~= nil), tostring(collectAll ~= nil)
    ))

    local lastFire = 0

    connection = RunService.Heartbeat:Connect(function()
        local now = tick()
        if now - lastFire < FIRE_INTERVAL then
            return
        end
        lastFire = now

        if claimOre then
            pcall(function()
                claimOre:FireServer()
            end)
        end
        if collectAll then
            pcall(function()
                collectAll:FireServer()
            end)
        end
    end)
end

function autoTakeChest.IsEnabled()
    return connection ~= nil
end

return autoTakeChest

end

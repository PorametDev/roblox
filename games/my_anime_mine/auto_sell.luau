-- Fires SellItems directly (found via Debug: Dump All Remotes) instead of
-- clicking SelectAllButton. Still walks up to SellStand's ProximityPrompt
-- first since that's a real world object, not a UI simulation - matches
-- what a player actually does to open the sell flow. Argument signature
-- for SellItems is unconfirmed (fired with no args here); check MekPro.log
-- for errors and whether currency actually increases.
return function(import)

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Workspace = game:GetService("Workspace")
local RunService = game:GetService("RunService")
local log = import("core/logger")

local FIRE_INTERVAL = 2

local autoSell = {}
local connection = nil

function autoSell.SetEnabled(enabled)
    if enabled == autoSell.IsEnabled() then
        return
    end

    if not enabled then
        connection:Disconnect()
        connection = nil
        log("[AutoSell] disabled")
        return
    end

    local remotes = ReplicatedStorage:FindFirstChild("Remotes")
    local sellItems = remotes and remotes:FindFirstChild("SellItems")
    log("[AutoSell] enabled (SellItems=" .. tostring(sellItems ~= nil) .. ")")

    local lastFire = 0

    connection = RunService.Heartbeat:Connect(function()
        local now = tick()
        if now - lastFire < FIRE_INTERVAL then
            return
        end
        lastFire = now

        local sellStand = Workspace:FindFirstChild("SellStand")
        local prompt = sellStand and sellStand:FindFirstChildWhichIsA("ProximityPrompt", true)
        if prompt then
            fireproximityprompt(prompt)
        end

        if sellItems then
            local ok, err = pcall(function()
                sellItems:FireServer()
            end)
            if not ok then
                log("[AutoSell] SellItems:FireServer() error: " .. tostring(err))
            end
        end
    end)
end

function autoSell.IsEnabled()
    return connection ~= nil
end

return autoSell

end

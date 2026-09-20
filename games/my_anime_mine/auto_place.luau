return function(import)

local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local getCurrentPlot = import("games/my_anime_mine/get_current_plot")
local getPlotParts = import("games/my_anime_mine/get_plot_parts")
local log = import("core/logger")

-- HolderPrompt's HoldDuration is 0 (fires instantly), but placing is still
-- paced on an interval so an equipped tool has time to actually leave the
-- Backpack before the next holder is checked.
local FIRE_INTERVAL = 1

local function findHolderPrompt(holder)
    local pad = holder:FindFirstChild("Pad")
    return pad and pad:FindFirstChildWhichIsA("ProximityPrompt", true)
end

local function isHolderEmpty(prompt)
    return prompt ~= nil and prompt.ObjectText == "Empty miner slot"
end

local autoPlace = {}
local connection = nil

function autoPlace.SetEnabled(enabled)
    if enabled == autoPlace.IsEnabled() then
        return
    end

    if not enabled then
        connection:Disconnect()
        connection = nil
        log("[AutoPlace] disabled")
        return
    end

    log("[AutoPlace] enabled")
    local lastFire = 0

    connection = RunService.Heartbeat:Connect(function()
        local now = tick()
        if now - lastFire < FIRE_INTERVAL then
            return
        end
        lastFire = now

        local player = Players.LocalPlayer
        local character = player.Character
        local backpack = player:FindFirstChild("Backpack")
        if not character or not backpack then
            return
        end

        local humanoid = character:FindFirstChildOfClass("Humanoid")
        local tool = backpack:FindFirstChildWhichIsA("Tool")
        if not humanoid or not tool then
            return
        end

        local plot = getCurrentPlot()
        if not plot then
            return
        end

        local parts = getPlotParts(plot)
        if not parts.Holders then
            return
        end

        for _, holder in ipairs(parts.Holders:GetChildren()) do
            local prompt = findHolderPrompt(holder)
            if isHolderEmpty(prompt) then
                humanoid:EquipTool(tool)
                fireproximityprompt(prompt)
                log("[AutoPlace] placed " .. tool.Name .. " on " .. holder.Name)
                break
            end
        end
    end)
end

function autoPlace.IsEnabled()
    return connection ~= nil
end

return autoPlace

end

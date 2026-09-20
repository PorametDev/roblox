-- Registered with core/scheduler as EXCLUSIVE: equipping a tool and firing
-- a holder's prompt both act on the character, and the server checks real
-- position for placement, so this must not run while Auto Sell/Auto Chest
-- have the character teleported elsewhere.
return function(import)

local Players = game:GetService("Players")
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
local enabled = false
local lastFire = 0
local lastReason = nil

local function reason(text)
    if text ~= lastReason then
        log("[AutoPlace] " .. text)
        lastReason = text
    end
end

function autoPlace.SetEnabled(state)
    if state == enabled then
        return
    end
    enabled = state
    lastReason = nil
    log("[AutoPlace] " .. (enabled and "enabled" or "disabled"))
end

function autoPlace.IsEnabled()
    return enabled
end

function autoPlace.Step()
    if not enabled then
        return
    end

    local now = tick()
    if now - lastFire < FIRE_INTERVAL then
        return
    end
    lastFire = now

    local player = Players.LocalPlayer
    local character = player.Character
    local backpack = player:FindFirstChild("Backpack")
    if not character or not backpack then
        reason("no character/backpack")
        return
    end

    local humanoid = character:FindFirstChildOfClass("Humanoid")
    local tool = backpack:FindFirstChildWhichIsA("Tool")
    if not humanoid then
        reason("no humanoid")
        return
    end
    if not tool then
        reason("no tool in Backpack (all miners already placed?)")
        return
    end

    local plot = getCurrentPlot()
    if not plot then
        reason("not standing in any plot")
        return
    end

    local parts = getPlotParts(plot)
    if not parts.Holders then
        reason("plot has no Holders folder")
        return
    end

    local placed = false
    for _, holder in ipairs(parts.Holders:GetChildren()) do
        local prompt = findHolderPrompt(holder)
        if isHolderEmpty(prompt) then
            humanoid:EquipTool(tool)
            local ok, err = pcall(function()
                fireproximityprompt(prompt, Enum.ProximityPromptInputType.Keyboard, prompt.HoldDuration)
            end)
            if ok then
                log("[AutoPlace] placed " .. tool.Name .. " on " .. holder.Name)
            else
                log("[AutoPlace] fireproximityprompt error: " .. tostring(err))
            end
            placed = true
            break
        end
    end

    if not placed then
        reason("no empty holder found (" .. #parts.Holders:GetChildren() .. " holders checked)")
    else
        lastReason = nil
    end
end

return autoPlace

end

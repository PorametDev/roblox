return function(import)

local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local log = import("core/logger")

local FIRE_INTERVAL = 0.5

-- Searches by text instead of a fixed path, since the chest popup's GUI
-- tree isn't something we control and could be nested differently than
-- what we saw once in Explorer.
local function findButtonByText(instance, text)
    for _, descendant in ipairs(instance:GetDescendants()) do
        if descendant:IsA("TextButton") and descendant.Visible then
            if descendant.Text:lower():find(text, 1, true) then
                return descendant
            end
        end
    end
    return nil
end

local function clickButton(button)
    if not firesignal then
        return false, "firesignal is not available on this executor"
    end
    pcall(firesignal, button.MouseButton1Click)
    pcall(firesignal, button.Activated)
    return true
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

    log("[AutoTakeChest] enabled")
    local lastFire = 0

    connection = RunService.Heartbeat:Connect(function()
        local now = tick()
        if now - lastFire < FIRE_INTERVAL then
            return
        end
        lastFire = now

        local playerGui = Players.LocalPlayer:FindFirstChild("PlayerGui")
        if not playerGui then
            return
        end

        local button = findButtonByText(playerGui, "take all")
        if not button then
            return
        end

        local ok, err = clickButton(button)
        if ok then
            log("[AutoTakeChest] clicked Take All")
        else
            log("[AutoTakeChest] " .. tostring(err))
        end
    end)
end

function autoTakeChest.IsEnabled()
    return connection ~= nil
end

return autoTakeChest

end

-- Sell flow observed via Interaction Logger: walk up to the SellStand NPC's
-- SellPrompt (ProximityPrompt, ActionText="Sell items") to open SellFrame,
-- then SelectAllButton picks everything. Whether SelectAllButton alone
-- completes the sale, or a separate confirm button exists that we haven't
-- seen fire yet, is still unconfirmed - watch MekPro.log/your currency to
-- check this is actually selling, not just selecting.
return function(import)

local Players = game:GetService("Players")
local Workspace = game:GetService("Workspace")
local RunService = game:GetService("RunService")
local log = import("core/logger")

local FIRE_INTERVAL = 2

local function clickButton(button)
    if not firesignal then
        return false, "firesignal is not available on this executor"
    end
    pcall(firesignal, button.Activated)
    return true
end

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

    log("[AutoSell] enabled")
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

        local playerGui = Players.LocalPlayer:FindFirstChild("PlayerGui")
        local mineGui = playerGui and playerGui:FindFirstChild("MineGui")
        local content = mineGui and mineGui:FindFirstChild("SellFrame") and mineGui.SellFrame:FindFirstChild("Content")
        local selectAllButton = content and content:FindFirstChild("SelectAllButton")

        if selectAllButton then
            local ok, err = clickButton(selectAllButton)
            if ok then
                log("[AutoSell] clicked SelectAllButton")
            else
                log("[AutoSell] " .. tostring(err))
            end
        end
    end)
end

function autoSell.IsEnabled()
    return connection ~= nil
end

return autoSell

end

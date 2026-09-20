-- The interaction logger showed prompt.Triggered firing locally every tick,
-- but the ChestFrame never actually opened in-game (the native "E" prompt
-- bubble stayed up) - fireproximityprompt() alone isn't replicating a real
-- trigger to the server for this game. Passing holdDuration/inputType is a
-- known fix for some executors. We also now check Visible before clicking
-- TakeButton and log every state, so we can tell "prompt didn't open the
-- frame" apart from "frame opened but click did nothing".
return function(import)

local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local getCurrentPlot = import("games/my_anime_mine/get_current_plot")
local getPlotParts = import("games/my_anime_mine/get_plot_parts")
local log = import("core/logger")

local FIRE_INTERVAL = 1

local function getChestFrame()
    local playerGui = Players.LocalPlayer:FindFirstChild("PlayerGui")
    local mineGui = playerGui and playerGui:FindFirstChild("MineGui")
    return mineGui and mineGui:FindFirstChild("ChestFrame")
end

local function getTakeButton(chestFrame)
    local content = chestFrame and chestFrame:FindFirstChild("Content")
    local actions = content and content:FindFirstChild("Actions")
    return actions and actions:FindFirstChild("TakeButton")
end

local function clickButton(button)
    local ok, err = pcall(function()
        firesignal(button.MouseButton1Click)
    end)
    return ok, err
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

    log("[AutoChest] enabled")
    local lastFire = 0
    local lastVisibleState = nil

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
            local ok, err = pcall(function()
                fireproximityprompt(prompt, Enum.ProximityPromptInputType.Keyboard, prompt.HoldDuration)
            end)
            if not ok then
                log("[AutoChest] fireproximityprompt error: " .. tostring(err))
            end
        end

        local chestFrame = getChestFrame()
        local visible = chestFrame ~= nil and chestFrame.Visible

        if visible ~= lastVisibleState then
            log("[AutoChest] ChestFrame.Visible = " .. tostring(visible))
            lastVisibleState = visible
        end

        if visible then
            local takeButton = getTakeButton(chestFrame)
            if takeButton then
                local ok, err = clickButton(takeButton)
                if ok then
                    log("[AutoChest] clicked TakeButton")
                else
                    log("[AutoChest] TakeButton click error: " .. tostring(err))
                end
            end
        end
    end)
end

function autoChest.IsEnabled()
    return connection ~= nil
end

return autoChest

end

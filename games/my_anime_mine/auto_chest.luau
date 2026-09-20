-- ClaimOre/CollectAll fired with no args did nothing. The GUI dump captured
-- while a chest was open showed the real action is a plain button click:
-- ChestFrame.Content.Actions.TakeButton. We don't know what remote/args that
-- button's own script fires internally (no namecall spying allowed - see
-- interaction logger notes), so instead of guessing we click that exact
-- confirmed button, same approach that worked for Auto Sell.
return function(import)

local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local getCurrentPlot = import("games/my_anime_mine/get_current_plot")
local getPlotParts = import("games/my_anime_mine/get_plot_parts")
local log = import("core/logger")

local FIRE_INTERVAL = 1

local function getTakeButton()
    local playerGui = Players.LocalPlayer:FindFirstChild("PlayerGui")
    local mineGui = playerGui and playerGui:FindFirstChild("MineGui")
    local chestFrame = mineGui and mineGui:FindFirstChild("ChestFrame")
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

        local takeButton = getTakeButton()
        if takeButton then
            local ok, err = clickButton(takeButton)
            if ok then
                log("[AutoChest] clicked TakeButton")
            else
                log("[AutoChest] TakeButton click error: " .. tostring(err))
            end
        end
    end)
end

function autoChest.IsEnabled()
    return connection ~= nil
end

return autoChest

end

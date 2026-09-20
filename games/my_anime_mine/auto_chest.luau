-- Two bugs found from the Visible-transition log: (1) we kept firing the
-- ProximityPrompt every tick even while ChestFrame was already open, which
-- toggled it closed again before TakeButton could do anything (open/close
-- looped forever). (2) TakeButton's own label never confirmed anything
-- happened. Fix: only fire the prompt when the frame is currently closed;
-- click TakeButton on every tick it's open using multiple signals
-- (MouseButton1Click, Activated, MouseButton1Down/Up) since we don't know
-- which one the game's script actually listens to.
return function(import)

local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local getCurrentPlot = import("games/my_anime_mine/get_current_plot")
local getPlotParts = import("games/my_anime_mine/get_plot_parts")
local log = import("core/logger")

local FIRE_INTERVAL = 0.5

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
    for _, signalName in ipairs({ "MouseButton1Click", "Activated", "MouseButton1Down", "MouseButton1Up" }) do
        local signal = button[signalName]
        if signal then
            pcall(function()
                firesignal(signal)
            end)
        end
    end
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

        local chestFrame = getChestFrame()
        local visible = chestFrame ~= nil and chestFrame.Visible

        if visible ~= lastVisibleState then
            log("[AutoChest] ChestFrame.Visible = " .. tostring(visible))
            lastVisibleState = visible
        end

        if visible then
            local takeButton = getTakeButton(chestFrame)
            if takeButton then
                clickButton(takeButton)
                log("[AutoChest] clicked TakeButton")
            end
        else
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
        end
    end)
end

function autoChest.IsEnabled()
    return connection ~= nil
end

return autoChest

end

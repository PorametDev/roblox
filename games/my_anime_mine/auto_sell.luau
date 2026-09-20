-- Two bugs found from the log: (1) we kept firing the ProximityPrompt every
-- tick even while SellFrame was already open, which could re-toggle it
-- closed. (2) "clicked SelectAllButton" showed every single cycle with the
-- label never flipping to "Deselect All" - firesignal(MouseButton1Click)
-- had no listener to catch it. Fix: only fire the prompt when the frame is
-- closed; click using multiple signals (MouseButton1Click, Activated,
-- MouseButton1Down/Up) since we don't know which one the game listens to.
return function(import)

local Players = game:GetService("Players")
local Workspace = game:GetService("Workspace")
local RunService = game:GetService("RunService")
local log = import("core/logger")

local FIRE_INTERVAL = 0.5

local function getSellFrame()
    local playerGui = Players.LocalPlayer:FindFirstChild("PlayerGui")
    local mineGui = playerGui and playerGui:FindFirstChild("MineGui")
    return mineGui and mineGui:FindFirstChild("SellFrame")
end

local function labelText(button)
    local content = button:FindFirstChild("Content")
    local label = content and content:FindFirstChild("Label")
    return label and label.Text or ""
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
    local lastVisibleState = nil

    connection = RunService.Heartbeat:Connect(function()
        local now = tick()
        if now - lastFire < FIRE_INTERVAL then
            return
        end
        lastFire = now

        local sellFrame = getSellFrame()
        local visible = sellFrame ~= nil and sellFrame.Visible

        if visible ~= lastVisibleState then
            log("[AutoSell] SellFrame.Visible = " .. tostring(visible))
            lastVisibleState = visible
        end

        if visible then
            local content = sellFrame:FindFirstChild("Content")
            local selectAllButton = content and content:FindFirstChild("SelectAllButton")
            local sellButton = content and content:FindFirstChild("SellButton")

            if selectAllButton and labelText(selectAllButton) == "Select All" then
                clickButton(selectAllButton)
                log("[AutoSell] clicked SelectAllButton")
            elseif sellButton and labelText(sellButton):find("Sell for", 1, true) then
                clickButton(sellButton)
                log("[AutoSell] clicked SellButton")
            end
        else
            local sellStand = Workspace:FindFirstChild("SellStand")
            local prompt = sellStand and sellStand:FindFirstChildWhichIsA("ProximityPrompt", true)
            if prompt then
                local ok, err = pcall(function()
                    fireproximityprompt(prompt, Enum.ProximityPromptInputType.Keyboard, prompt.HoldDuration)
                end)
                if not ok then
                    log("[AutoSell] fireproximityprompt error: " .. tostring(err))
                end
            end
        end
    end)
end

function autoSell.IsEnabled()
    return connection ~= nil
end

return autoSell

end

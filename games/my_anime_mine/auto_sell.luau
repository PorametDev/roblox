-- The interaction logger showed prompt.Triggered firing locally every tick,
-- but SellFrame never actually opened in-game - fireproximityprompt() alone
-- isn't replicating a real trigger to the server for this game. Passing
-- holdDuration/inputType is a known fix for some executors. We also now
-- check Visible before clicking, and log every state, so we can tell
-- "prompt didn't open the frame" apart from "frame opened but click did
-- nothing".
return function(import)

local Players = game:GetService("Players")
local Workspace = game:GetService("Workspace")
local RunService = game:GetService("RunService")
local log = import("core/logger")

local FIRE_INTERVAL = 3

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
    local ok, err = pcall(function()
        firesignal(button.MouseButton1Click)
    end)
    return ok, err
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
    local busy = false
    local lastVisibleState = nil

    connection = RunService.Heartbeat:Connect(function()
        local now = tick()
        if now - lastFire < FIRE_INTERVAL or busy then
            return
        end
        lastFire = now

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

        busy = true
        task.spawn(function()
            task.wait(0.3)

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
                    local ok, err = clickButton(selectAllButton)
                    if ok then
                        log("[AutoSell] clicked SelectAllButton")
                    else
                        log("[AutoSell] SelectAllButton click error: " .. tostring(err))
                    end
                    task.wait(0.3)
                end

                if sellButton and labelText(sellButton):find("Sell for", 1, true) then
                    local ok, err = clickButton(sellButton)
                    if ok then
                        log("[AutoSell] clicked SellButton")
                    else
                        log("[AutoSell] SellButton click error: " .. tostring(err))
                    end
                end
            end

            busy = false
        end)
    end)
end

function autoSell.IsEnabled()
    return connection ~= nil
end

return autoSell

end

-- SellItems fired with no args did nothing. The GUI dump captured during a
-- real manual sell showed the actual working flow is two button clicks:
-- SellFrame.Content.SelectAllButton (labels flip to "Deselect All", every
-- sellable card gets a check overlay) then SellFrame.Content.SellButton
-- (label becomes "Sell for $X"), which produced a real "Sold for $X!" toast.
-- We don't know SellItems' real argument, so we click those two confirmed
-- buttons directly instead of guessing.
return function(import)

local Players = game:GetService("Players")
local Workspace = game:GetService("Workspace")
local RunService = game:GetService("RunService")
local log = import("core/logger")

local FIRE_INTERVAL = 3

local function getSellFrame()
    local playerGui = Players.LocalPlayer:FindFirstChild("PlayerGui")
    local mineGui = playerGui and playerGui:FindFirstChild("MineGui")
    local sellFrame = mineGui and mineGui:FindFirstChild("SellFrame")
    return sellFrame and sellFrame:FindFirstChild("Content")
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

    connection = RunService.Heartbeat:Connect(function()
        local now = tick()
        if now - lastFire < FIRE_INTERVAL or busy then
            return
        end
        lastFire = now

        local sellStand = Workspace:FindFirstChild("SellStand")
        local prompt = sellStand and sellStand:FindFirstChildWhichIsA("ProximityPrompt", true)
        if prompt then
            fireproximityprompt(prompt)
        end

        busy = true
        task.spawn(function()
            task.wait(0.3)

            local content = getSellFrame()
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

            busy = false
        end)
    end)
end

function autoSell.IsEnabled()
    return connection ~= nil
end

return autoSell

end

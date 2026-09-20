-- SellButton was clicking successfully (per interaction log) but the sale
-- still failed - the server checks the player's REAL position before
-- allowing a sell, and fireproximityprompt bypasses distance but doesn't
-- move the character. So we now teleport the HumanoidRootPart next to the
-- SellStand before opening it, and teleport back to where we started once
-- the sale completes. We also move SellFrame off-screen while it's open
-- (instead of touching .Visible, which the game's own scripts key off of)
-- so the popup doesn't flash on screen during automation.
return function(import)

local Players = game:GetService("Players")
local Workspace = game:GetService("Workspace")
local RunService = game:GetService("RunService")
local log = import("core/logger")

local FIRE_INTERVAL = 0.5
local HIDDEN_POSITION = UDim2.new(3, 0, 3, 0)

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

local function getSellStandPromptPart()
    local sellStand = Workspace:FindFirstChild("SellStand")
    local prompt = sellStand and sellStand:FindFirstChildWhichIsA("ProximityPrompt", true)
    return prompt, prompt and prompt.Parent
end

local function teleportTo(part)
    local character = Players.LocalPlayer.Character
    local hrp = character and character:FindFirstChild("HumanoidRootPart")
    if not (hrp and part) then
        return false
    end
    hrp.CFrame = CFrame.new(part.Position + Vector3.new(0, 3, 5))
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
        local sellFrame = getSellFrame()
        if sellFrame then
            sellFrame.Position = sellFrame:GetAttribute("MekProOriginalPosition") or sellFrame.Position
        end
        log("[AutoSell] disabled")
        return
    end

    log("[AutoSell] enabled")
    local lastFire = 0
    local lastVisibleState = nil
    local returnCFrame = nil

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

            if visible and sellFrame:GetAttribute("MekProOriginalPosition") == nil then
                sellFrame:SetAttribute("MekProOriginalPosition", sellFrame.Position)
            end

            if not visible and returnCFrame then
                local character = Players.LocalPlayer.Character
                local hrp = character and character:FindFirstChild("HumanoidRootPart")
                if hrp then
                    hrp.CFrame = returnCFrame
                end
                returnCFrame = nil
            end
        end

        if visible then
            sellFrame.Position = HIDDEN_POSITION

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
            local prompt, promptPart = getSellStandPromptPart()
            if prompt and promptPart then
                if not returnCFrame then
                    local character = Players.LocalPlayer.Character
                    local hrp = character and character:FindFirstChild("HumanoidRootPart")
                    if hrp then
                        returnCFrame = hrp.CFrame
                    end
                end

                teleportTo(promptPart)

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

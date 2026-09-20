-- SellButton was clicking successfully (per interaction log) but the sale
-- still failed - the server checks the player's REAL position before
-- allowing a sell, and fireproximityprompt bypasses distance but doesn't
-- move the character. Teleport next to the SellStand via core/teleport
-- before opening, and always teleport back once the frame closes again
-- (previously only happened on the "nothing to sell" path - a successful
-- sell closing the frame on its own never triggered the return, stranding
-- the character at the SellStand).
--
-- SellFrame also kept flashing on screen. Moving the whole frame's Position
-- off-screen was the wrong fix - its Backdrop (the full-screen dim behind
-- the popup) blocked the player from clicking anything else in the game
-- while "hidden" this way. Instead we hide only the visible pieces
-- (Content, Backdrop, Close) via .Visible, leaving SellFrame itself
-- untouched so the game's own open/close state and our own Visible check
-- both keep working normally, and the player's other UI stays clickable.
--
-- Step() itself no longer owns a Heartbeat connection - core/turn_scheduler
-- calls it only when it's this task's turn, so multiple autos never fire in
-- the same frame and fight over the character.
return function(import)

local Players = game:GetService("Players")
local Workspace = game:GetService("Workspace")
local RunService = game:GetService("RunService")
local teleport = import("core/teleport")(import)
local log = import("core/logger")

local FIRE_INTERVAL = 0.5
local RECHECK_COOLDOWN = 5
local HIDDEN_PIECE_NAMES = { "Content", "Backdrop", "Close" }

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

local function countCards(sellFrame)
    local content = sellFrame:FindFirstChild("Content")
    local scroll = content and content:FindFirstChild("Scroll")
    if not scroll then
        return 0
    end
    local count = 0
    for _, child in ipairs(scroll:GetChildren()) do
        if child.Name == "Card" then
            count = count + 1
        end
    end
    return count
end

-- Firing MouseButton1Click AND Activated together double-toggled
-- SelectAllButton (a toggle, not a one-shot action) back to its starting
-- state within the same "click" - it never advanced past "Select All".
-- Activated alone is the one Interaction Logger confirms actually reaches
-- the game's handler.
local function clickButton(button)
    pcall(function()
        firesignal(button.Activated)
    end)
end

local function getSellStandPromptPart()
    local sellStand = Workspace:FindFirstChild("SellStand")
    local prompt = sellStand and sellStand:FindFirstChildWhichIsA("ProximityPrompt", true)
    return prompt, prompt and prompt.Parent
end

local autoSell = {}
local enabled = false
local lastFire = 0
local lastVisibleState = nil
local nextOpenCheck = 0
local hideConnection = nil

local function setPiecesVisible(sellFrame, isVisible)
    for _, name in ipairs(HIDDEN_PIECE_NAMES) do
        local piece = sellFrame:FindFirstChild(name)
        if piece then
            piece.Visible = isVisible
        end
    end
end

function autoSell.SetEnabled(state)
    if state == enabled then
        return
    end
    enabled = state

    if not enabled then
        if hideConnection then
            hideConnection:Disconnect()
            hideConnection = nil
        end
        local sellFrame = getSellFrame()
        if sellFrame then
            setPiecesVisible(sellFrame, true)
        end
        teleport.Return()
        log("[AutoSell] disabled")
    else
        nextOpenCheck = 0
        hideConnection = RunService.Heartbeat:Connect(function()
            local sellFrame = getSellFrame()
            if sellFrame and sellFrame.Visible then
                setPiecesVisible(sellFrame, false)
            end
        end)
        log("[AutoSell] enabled (only sells when there's something in the scroll)")
    end
end

function autoSell.IsEnabled()
    return enabled
end

function autoSell.Step()
    if not enabled then
        return
    end

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

        if not visible then
            -- Covers every way the frame can close: selling successfully,
            -- closing an empty cart, or the player closing it themselves.
            teleport.Return()
        end
    end

    if visible then
        local cardCount = countCards(sellFrame)
        if cardCount == 0 then
            log("[AutoSell] nothing to sell, closing")
            local closeButton = sellFrame:FindFirstChild("Close")
            if closeButton then
                clickButton(closeButton)
            end
            nextOpenCheck = now + RECHECK_COOLDOWN
            return
        end

        local content = sellFrame:FindFirstChild("Content")
        local selectAllButton = content and content:FindFirstChild("SelectAllButton")
        local sellButton = content and content:FindFirstChild("SellButton")

        -- Ore keeps flowing in passively (placed miners, chest collecting),
        -- which can refresh the card list and reset the selection between
        -- our 0.5s ticks - "Select All" never got a chance to be observed
        -- as "Deselect All" before the next tick reset it. Click Select All
        -- and re-check/click Sell in the SAME tick instead of waiting for
        -- the next one, since the label updates synchronously.
        if selectAllButton and labelText(selectAllButton) == "Select All" then
            clickButton(selectAllButton)
            log("[AutoSell] clicked SelectAllButton (" .. cardCount .. " cards)")
        end

        if sellButton and labelText(sellButton):find("Sell for", 1, true) then
            clickButton(sellButton)
            log("[AutoSell] clicked SellButton")
        end
    elseif now >= nextOpenCheck then
        local prompt, promptPart = getSellStandPromptPart()
        if prompt and promptPart then
            teleport.To(promptPart)

            local ok, err = pcall(function()
                fireproximityprompt(prompt, Enum.ProximityPromptInputType.Keyboard, prompt.HoldDuration)
            end)
            if not ok then
                log("[AutoSell] fireproximityprompt error: " .. tostring(err))
            end
        end
    end
end

return autoSell

end

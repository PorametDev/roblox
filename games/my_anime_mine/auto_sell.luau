-- Restructured into a single one-shot job instead of a per-tick state
-- machine: teleport, open the sell menu, check the condition (at least one
-- card), and only then select+sell - the whole thing runs to completion as
-- one job instead of repeatedly re-clicking every tick while the frame
-- stays open (that's what caused the SelectAllButton loop before).
-- Registered with core/scheduler as EXCLUSIVE: a new job only starts every
-- checkInterval, and while `busy` is true no other exclusive task runs -
-- this one's teleport home used to land right on Auto Chest's Take All.
--
-- Note: whether there's anything to sell can only be read from the cards
-- inside the sell menu itself (nothing exposes it before opening), so
-- "check the condition first" here means "open, read, then decide" as one
-- atomic job - not zero UI interaction when there's nothing to sell.
--
-- Selling previously failed even though SellButton clicked successfully:
-- the server checks the player's REAL position, and fireproximityprompt
-- bypasses distance but doesn't move the character - hence the teleport via
-- core/teleport before opening, and always back once the job finishes.
return function(import)

local Players = game:GetService("Players")
local Workspace = game:GetService("Workspace")
local teleport = import("core/teleport")
local click = import("core/click")
local log = import("core/logger")

-- Unlike the chest there's no world-side indicator of what's sellable, so
-- this one does have to open the menu to find out. Keep that rare: ore
-- piles up slowly and a sale every 45s is plenty, whereas every 3s meant
-- teleporting the player off their plot constantly.
local checkInterval = 45
-- Once everything sellable is gone, the leftovers (equipped units and the
-- like) can't be selected at all, so Select All does nothing and the Sell
-- label never shows a price. That's a normal state, not a failure - back
-- off properly instead of retrying every few seconds.
local nothingSellableCooldown = 60

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

-- Real mouse click, not firesignal: the log proved firesignal(Activated)
-- never reached the game's own handler for these buttons (labels never
-- changed), even though our Interaction Logger saw the signal fire.
local function clickButton(button)
    local ok, err = click.Real(button)
    if not ok then
        log("[AutoSell] click failed on " .. button.Name .. ": " .. tostring(err))
    end
    return ok
end

-- A ticked card gains a SelectOverlay; unticked ones don't have one.
local function isCardSelected(card)
    local content = card:FindFirstChild("Content")
    local overlay = content and content:FindFirstChild("SelectOverlay")
    return overlay ~= nil and overlay.Visible
end

-- Only clicks cards actually rendered inside the scroll's bounds - a real
-- mouse click at the position of a card scrolled out of view would land on
-- whatever happens to be there instead.
local function isOnScreen(card, scroll)
    local top = scroll.AbsolutePosition.Y
    local bottom = top + scroll.AbsoluteSize.Y
    local cardTop = card.AbsolutePosition.Y
    local cardBottom = cardTop + card.AbsoluteSize.Y
    return cardTop >= top and cardBottom <= bottom
end

local function selectUnselectedCards(sellFrame)
    local content = sellFrame:FindFirstChild("Content")
    local scroll = content and content:FindFirstChild("Scroll")
    if not scroll then
        return 0
    end

    local selected = 0
    for _, card in ipairs(scroll:GetChildren()) do
        if card.Name == "Card" and not isCardSelected(card) and isOnScreen(card, scroll) then
            clickButton(card)
            selected = selected + 1
            task.wait(0.1)
        end
    end

    return selected
end

local function getSellStandPromptPart()
    local sellStand = Workspace:FindFirstChild("SellStand")
    local prompt = sellStand and sellStand:FindFirstChildWhichIsA("ProximityPrompt", true)
    return prompt, prompt and prompt.Parent
end

local autoSell = {}
local enabled = false
local busy = false
local lastAttempt = 0

function autoSell.SetEnabled(state)
    if state == enabled then
        return
    end
    enabled = state

    if not enabled then
        if not busy then
            teleport.Return()
        end
        log("[AutoSell] disabled")
    else
        lastAttempt = 0
        log("[AutoSell] enabled (only sells when there's something in the scroll)")
    end
end

function autoSell.IsEnabled()
    return enabled
end

function autoSell.SetCheckInterval(seconds)
    checkInterval = math.max(seconds, 5)
end

-- The scheduler holds everyone else off while a job is mid-flight - Auto
-- Sell's teleport home used to land right on top of Auto Chest's Take All.
function autoSell.IsBusy()
    return busy
end

local function runJob()
    busy = true

    local prompt, promptPart = getSellStandPromptPart()
    if not (prompt and promptPart) then
        busy = false
        return
    end

    teleport.To(promptPart)

    local ok, err = pcall(function()
        fireproximityprompt(prompt, Enum.ProximityPromptInputType.Keyboard, prompt.HoldDuration)
    end)
    if not ok then
        log("[AutoSell] fireproximityprompt error: " .. tostring(err))
        teleport.Return()
        busy = false
        return
    end

    -- Long enough for the open animation to finish - a real mouse click
    -- needs the button sitting at its final on-screen position, not
    -- mid-tween.
    task.wait(0.8)

    if not enabled then
        teleport.Return()
        busy = false
        return
    end

    local sellFrame = getSellFrame()
    if not (sellFrame and sellFrame.Visible) then
        log("[AutoSell] sell menu didn't open, aborting")
        teleport.Return()
        busy = false
        return
    end

    local cardCount = countCards(sellFrame)
    if cardCount == 0 then
        log("[AutoSell] nothing to sell, closing")
        local closeButton = sellFrame:FindFirstChild("Close")
        if closeButton then
            clickButton(closeButton)
        end
        teleport.Return()
        busy = false
        return
    end

    local content = sellFrame:FindFirstChild("Content")
    local selectAllButton = content and content:FindFirstChild("SelectAllButton")
    local sellButton = content and content:FindFirstChild("SellButton")

    if selectAllButton and labelText(selectAllButton) == "Select All" then
        clickButton(selectAllButton)
        log("[AutoSell] clicked SelectAllButton (" .. cardCount .. " cards)")
        task.wait(0.2)
    end

    -- "Select All" only ticks the ores - every unit card stays unchecked and
    -- has to be clicked individually. Safe to sweep them all up because
    -- Auto Place runs to completion first, so whatever's still here is
    -- surplus.
    local selected = selectUnselectedCards(sellFrame)
    if selected > 0 then
        log("[AutoSell] also selected " .. selected .. " unit card(s) Select All skipped")
    end

    -- The Sell label may animate a price count-up before it reads
    -- "Sell for $X" - poll for up to ~1.5s instead of checking once, and
    -- log what we actually see either way so a real stuck state is
    -- distinguishable from "just needed a bit more time".
    local sawLabel = nil
    for _ = 1, 5 do
        task.wait(0.3)
        sawLabel = sellButton and labelText(sellButton) or nil
        if sawLabel and sawLabel:find("Sell for", 1, true) then
            break
        end
    end

    if sawLabel and sawLabel:find("Sell for", 1, true) then
        clickButton(sellButton)
        log("[AutoSell] clicked SellButton")
    else
        lastAttempt = tick() + nothingSellableCooldown - checkInterval
        local closeButton = sellFrame:FindFirstChild("Close")
        if closeButton then
            clickButton(closeButton)
        end
        log("[AutoSell] nothing selectable (" .. cardCount .. " cards left, label = '"
            .. tostring(sawLabel) .. "'), backing off " .. nothingSellableCooldown .. "s")
    end

    task.wait(0.5)
    teleport.Return()
    busy = false
end

function autoSell.Step()
    if not enabled or busy then
        return
    end

    local now = tick()
    if now - lastAttempt < checkInterval then
        return
    end
    lastAttempt = now

    task.spawn(runJob)
end

return autoSell

end

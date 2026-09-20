-- Hiding ChestFrame's Content/Backdrop/Close caused the game's whole UI to
-- disappear for the user - pulled out entirely for now so the game stays
-- usable. Once Take All is confirmed actually collecting (teleporting to
-- the chest first, below), popup-hiding can be revisited more carefully.
--
-- Two bugs found earlier from the Visible-transition log: (1) we kept
-- firing the ProximityPrompt every tick even while ChestFrame was already
-- open, which toggled it closed again before TakeButton could do anything
-- (open/close looped forever). (2) TakeButton's own label never confirmed
-- anything happened. Fix: only fire the prompt when the frame is currently
-- closed; click TakeButton on every tick it's open.
--
-- Only actually collects once the chest's own progress label
-- ("141/3,600 Items") shows at least MIN_ITEMS_TO_COLLECT, so we're not
-- taking a nearly-empty chest every second - per user request.
--
-- The item count never actually went down after clicking TakeButton, same
-- symptom Auto Sell had: the server likely checks the player's REAL
-- position for the actual collect action too, same as selling did.
-- Teleport to the chest via core/teleport before opening it, and back once
-- it closes.
--
-- Step() itself no longer owns a Heartbeat connection - core/turn_scheduler
-- calls it only when it's this task's turn, so multiple autos never fire in
-- the same frame and fight over the character.
return function(import)

local Players = game:GetService("Players")
local getCurrentPlot = import("games/my_anime_mine/get_current_plot")
local getPlotParts = import("games/my_anime_mine/get_plot_parts")
local teleport = import("core/teleport")(import)
local log = import("core/logger")

local FIRE_INTERVAL = 0.5
local RECHECK_COOLDOWN = 5
local MIN_ITEMS_TO_COLLECT = 100

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

local function getItemCount(chestFrame)
    local content = chestFrame:FindFirstChild("Content")
    local progress = content and content:FindFirstChild("Progress")
    local label = progress and progress:FindFirstChild("Label")
    local text = label and label.Text or ""
    local digits = text:gsub(",", ""):match("^(%d+)")
    return tonumber(digits)
end

local function clickButton(button)
    pcall(function()
        firesignal(button.Activated)
    end)
end

local autoChest = {}
local enabled = false
local lastFire = 0
local lastVisibleState = nil
local nextOpenCheck = 0

function autoChest.SetEnabled(state)
    if state == enabled then
        return
    end
    enabled = state

    if not enabled then
        teleport.Return()
        log("[AutoChest] disabled")
    else
        nextOpenCheck = 0
        log("[AutoChest] enabled (collects once >= " .. MIN_ITEMS_TO_COLLECT .. " items)")
    end
end

function autoChest.IsEnabled()
    return enabled
end

function autoChest.Step()
    if not enabled then
        return
    end

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

        if not visible then
            -- Covers every way the frame can close: taking successfully,
            -- closing a too-small chest, or the player closing it themselves.
            teleport.Return()
        end
    end

    if visible then
        local count = getItemCount(chestFrame)
        if count and count < MIN_ITEMS_TO_COLLECT then
            log("[AutoChest] only " .. count .. " items, waiting for " .. MIN_ITEMS_TO_COLLECT)
            local closeButton = chestFrame:FindFirstChild("Close")
            if closeButton then
                clickButton(closeButton)
            end
            nextOpenCheck = now + RECHECK_COOLDOWN
            return
        end

        local takeButton = getTakeButton(chestFrame)
        if takeButton then
            clickButton(takeButton)
            log("[AutoChest] clicked TakeButton (" .. tostring(count) .. " items)")
        end
    elseif now >= nextOpenCheck then
        local plot = getCurrentPlot()
        local parts = plot and getPlotParts(plot)
        local prompt = parts and parts.Chest and parts.Chest:FindFirstChildWhichIsA("ProximityPrompt", true)
        if prompt then
            teleport.To(prompt.Parent)

            local ok, err = pcall(function()
                fireproximityprompt(prompt, Enum.ProximityPromptInputType.Keyboard, prompt.HoldDuration)
            end)
            if not ok then
                log("[AutoChest] fireproximityprompt error: " .. tostring(err))
            end
        end
    end
end

return autoChest

end

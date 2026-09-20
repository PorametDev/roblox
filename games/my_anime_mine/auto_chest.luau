-- Restructured into a single one-shot job instead of a per-tick state
-- machine: check the condition (>= MIN_ITEMS_TO_COLLECT) FIRST, before
-- teleporting or opening anything. Only if it's met do we teleport, open
-- the chest, click Take All once, and teleport back - the whole thing runs
-- to completion as one job instead of repeatedly re-clicking every tick
-- while the frame stays open. core/turn_scheduler calls Step() often, but
-- a new job only starts every CHECK_INTERVAL and while `busy` is true every
-- call until the current job finishes is a no-op.
--
-- The item count previously never actually went down after clicking
-- TakeButton: the server checks the player's REAL position for the collect
-- action, same as selling does, hence the teleport via core/teleport.
return function(import)

local Players = game:GetService("Players")
local getCurrentPlot = import("games/my_anime_mine/get_current_plot")
local getPlotParts = import("games/my_anime_mine/get_plot_parts")
local teleport = import("core/teleport")(import)
local log = import("core/logger")

local CHECK_INTERVAL = 3
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

local function getChestPrompt()
    local plot = getCurrentPlot()
    local parts = plot and getPlotParts(plot)
    return parts and parts.Chest and parts.Chest:FindFirstChildWhichIsA("ProximityPrompt", true)
end

local autoChest = {}
local enabled = false
local busy = false
local lastAttempt = 0

function autoChest.SetEnabled(state)
    if state == enabled then
        return
    end
    enabled = state

    if not enabled then
        if not busy then
            teleport.Return()
        end
        log("[AutoChest] disabled")
    else
        lastAttempt = 0
        log("[AutoChest] enabled (collects once >= " .. MIN_ITEMS_TO_COLLECT .. " items)")
    end
end

function autoChest.IsEnabled()
    return enabled
end

local function runJob()
    busy = true

    local prompt = getChestPrompt()
    if not prompt then
        busy = false
        return
    end

    teleport.To(prompt.Parent)

    local ok, err = pcall(function()
        fireproximityprompt(prompt, Enum.ProximityPromptInputType.Keyboard, prompt.HoldDuration)
    end)
    if not ok then
        log("[AutoChest] fireproximityprompt error: " .. tostring(err))
        teleport.Return()
        busy = false
        return
    end

    task.wait(0.3)

    if not enabled then
        teleport.Return()
        busy = false
        return
    end

    local chestFrame = getChestFrame()
    if not (chestFrame and chestFrame.Visible) then
        log("[AutoChest] chest didn't open, aborting")
        teleport.Return()
        busy = false
        return
    end

    local count = getItemCount(chestFrame)
    if count and count < MIN_ITEMS_TO_COLLECT then
        log("[AutoChest] only " .. count .. " items, closing")
        local closeButton = chestFrame:FindFirstChild("Close")
        if closeButton then
            clickButton(closeButton)
        end
        teleport.Return()
        busy = false
        return
    end

    local takeButton = getTakeButton(chestFrame)
    if takeButton then
        clickButton(takeButton)
        log("[AutoChest] clicked TakeButton (" .. tostring(count) .. " items)")
    end

    task.wait(0.5)
    teleport.Return()
    busy = false
end

function autoChest.Step()
    if not enabled or busy then
        return
    end

    local now = tick()
    if now - lastAttempt < CHECK_INTERVAL then
        return
    end
    lastAttempt = now

    task.spawn(runJob)
end

return autoChest

end

-- Two bugs found from the Visible-transition log: (1) we kept firing the
-- ProximityPrompt every tick even while ChestFrame was already open, which
-- toggled it closed again before TakeButton could do anything (open/close
-- looped forever). (2) TakeButton's own label never confirmed anything
-- happened. Fix: only fire the prompt when the frame is currently closed;
-- click TakeButton on every tick it's open using multiple signals
-- (MouseButton1Click, Activated, MouseButton1Down/Up) since we don't know
-- which one the game's script actually listens to.
--
-- ChestFrame also kept flashing on screen: the game tweens its Position in
-- every frame while opening, which overrides a Position we only set once
-- every 0.5s in Step(). A separate per-frame connection keeps re-hiding it
-- every single frame so our override always wins.
--
-- Only actually collects once the chest's own progress label
-- ("141/3,600 Items") shows at least MIN_ITEMS_TO_COLLECT, so we're not
-- taking a nearly-empty chest every second - per user request.
--
-- Step() itself no longer owns a Heartbeat connection - core/turn_scheduler
-- calls it only when it's this task's turn, so multiple autos never fire in
-- the same frame and fight over the character.
return function(import)

local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local getCurrentPlot = import("games/my_anime_mine/get_current_plot")
local getPlotParts = import("games/my_anime_mine/get_plot_parts")
local log = import("core/logger")

local FIRE_INTERVAL = 0.5
local RECHECK_COOLDOWN = 5
local MIN_ITEMS_TO_COLLECT = 100
local HIDDEN_POSITION = UDim2.new(3, 0, 3, 0)

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

-- Firing multiple signals at once double-toggled Auto Sell's SelectAllButton
-- (it never advanced past "Select All"). Activated alone is the one
-- Interaction Logger confirms actually reaches the game's handler, and
-- TakeButton/Close here are one-shot actions so this is just as reliable
-- for them.
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
local hideConnection = nil

local function restoreFramePosition()
    local chestFrame = getChestFrame()
    if chestFrame then
        chestFrame.Position = chestFrame:GetAttribute("MekProOriginalPosition") or chestFrame.Position
    end
end

function autoChest.SetEnabled(state)
    if state == enabled then
        return
    end
    enabled = state

    if not enabled then
        if hideConnection then
            hideConnection:Disconnect()
            hideConnection = nil
        end
        restoreFramePosition()
        log("[AutoChest] disabled")
    else
        nextOpenCheck = 0
        hideConnection = RunService.Heartbeat:Connect(function()
            local chestFrame = getChestFrame()
            if chestFrame and chestFrame.Visible then
                if chestFrame:GetAttribute("MekProOriginalPosition") == nil then
                    chestFrame:SetAttribute("MekProOriginalPosition", chestFrame.Position)
                end
                chestFrame.Position = HIDDEN_POSITION
            end
        end)
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

-- The chest's own billboard in the world (Chest.ChestBase.ChestLabel.BG.
-- Amount, reading e.g. "16/3,600") carries the live count the server
-- replicates, so the condition is checked silently from the client - no
-- teleport, no popup - and we only disturb the player at all once it's
-- actually worth collecting.
--
-- Once the threshold is met the whole collect runs as a single one-shot
-- job: teleport, open, click Take All, verify the count dropped, teleport
-- back. Registered with core/scheduler as EXCLUSIVE: a new job only starts
-- every CHECK_INTERVAL, and while `busy` is true no other exclusive task
-- runs, so nothing teleports the character mid-job.
--
-- The item count previously never actually went down after clicking
-- TakeButton: the server checks the player's REAL position for the collect
-- action, same as selling does, hence the teleport via core/teleport.
return function(import)

local Players = game:GetService("Players")
local getCurrentPlot = import("games/my_anime_mine/get_current_plot")
local getPlotParts = import("games/my_anime_mine/get_plot_parts")
local teleport = import("core/teleport")
local click = import("core/click")
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

local function parseCount(text)
    local digits = tostring(text):gsub(",", ""):match("^(%d+)")
    return tonumber(digits)
end

-- Reads the count off the chest's world billboard ("16/3,600"). Available
-- at any time, so the threshold can be checked without opening anything.
local function getChestCount()
    local plot = getCurrentPlot()
    local parts = plot and getPlotParts(plot)
    local chest = parts and parts.Chest
    local amount = chest and chest:FindFirstChild("Amount", true)
    return amount and parseCount(amount.Text)
end

local function getItemCount(chestFrame)
    local content = chestFrame:FindFirstChild("Content")
    local progress = content and content:FindFirstChild("Progress")
    local label = progress and progress:FindFirstChild("Label")
    return parseCount(label and label.Text or "")
end

-- Real mouse click rather than firesignal: firesignal reached our own
-- Interaction Logger but not always the game's handler (Auto Sell's
-- buttons never responded to it at all), and 74 TakeButton "clicks" in a
-- row left the chest count climbing untouched.
local function clickButton(button)
    local ok, err = click.Real(button)
    if not ok then
        log("[AutoChest] click failed on " .. button.Name .. ": " .. tostring(err))
    end
    return ok
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
-- Only log a state change, not the same "still waiting" line every few
-- seconds forever.
local lastReportedCount = nil

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
        lastReportedCount = nil
        log("[AutoChest] enabled (collects once >= " .. MIN_ITEMS_TO_COLLECT .. " items)")
    end
end

function autoChest.IsEnabled()
    return enabled
end

-- The scheduler asks this every frame to decide whose turn it is, so cache
-- the billboard read rather than walking the chest's descendants 60x a
-- second.
local cachedCount, cachedAt = nil, 0

function autoChest.HasWork()
    local now = tick()
    if now - cachedAt > 1 then
        cachedCount = getChestCount()
        cachedAt = now
    end
    return cachedCount ~= nil and cachedCount >= MIN_ITEMS_TO_COLLECT
end

-- The scheduler holds everyone else off while a job is mid-flight.
function autoChest.IsBusy()
    return busy
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

    -- Long enough for the open animation to finish - a real mouse click
    -- needs the button sitting at its final on-screen position.
    task.wait(0.8)

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
    local takeButton = getTakeButton(chestFrame)
    if takeButton then
        clickButton(takeButton)

        -- Verify rather than assume: the count climbing untouched across 74
        -- "successful" clicks is how we found out the old click never
        -- reached the game at all.
        task.wait(0.6)
        local after = getItemCount(chestFrame)
        if after and count and after < count then
            log("[AutoChest] Take All worked: " .. count .. " -> " .. after .. " items")
        else
            log("[AutoChest] Take All had NO effect (" .. tostring(count)
                .. " -> " .. tostring(after) .. " items)")
        end
    end

    teleport.Return()
    cachedAt = 0
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

    -- Silent check off the world billboard. Below the threshold nothing
    -- happens at all: no teleport, no popup, no interruption.
    local count = getChestCount()
    if not count then
        if lastReportedCount ~= "unreadable" then
            log("[AutoChest] can't read the chest billboard, is the plot loaded?")
            lastReportedCount = "unreadable"
        end
        return
    end

    if count < MIN_ITEMS_TO_COLLECT then
        if lastReportedCount ~= "waiting" then
            log("[AutoChest] waiting: " .. count .. "/" .. MIN_ITEMS_TO_COLLECT .. " items")
            lastReportedCount = "waiting"
        end
        return
    end

    lastReportedCount = nil
    log("[AutoChest] " .. count .. " items, going to collect")
    task.spawn(runJob)
end

return autoChest

end

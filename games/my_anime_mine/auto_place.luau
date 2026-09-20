-- The real flow, straight from the game's own hint: "Hold a miner first -
-- tap it in your hotbar (or press 1-9), then press E here." Miners aren't
-- Roblox Tools (the Backpack is empty - that's why this kept reporting "no
-- miner to place"), so holding one means pressing its hotbar number key.
--
-- The holder's prompt confirms each state: ActionText reads "Hold a miner
-- to place" until one is held, then becomes "Place <miner name>". We wait
-- for that second state before pressing E, so we never fire into a prompt
-- the game hasn't accepted yet.
--
-- Registered with core/scheduler as EXCLUSIVE: it teleports to the holder
-- and presses the hotbar key, so it must not run while Auto Sell/Auto Chest
-- have the character somewhere else.
return function(import)

local Players = game:GetService("Players")
local getCurrentPlot = import("games/my_anime_mine/get_current_plot")
local getPlotParts = import("games/my_anime_mine/get_plot_parts")
local getMinerSlots = import("games/my_anime_mine/get_best_miner")(import)
local teleport = import("core/teleport")
local click = import("core/click")
local log = import("core/logger")

local CHECK_INTERVAL = 3
local EMPTY_SLOT_TEXT = "Empty miner slot"
local SLOT_KEYS = {
    Enum.KeyCode.One, Enum.KeyCode.Two, Enum.KeyCode.Three,
    Enum.KeyCode.Four, Enum.KeyCode.Five, Enum.KeyCode.Six,
    Enum.KeyCode.Seven, Enum.KeyCode.Eight, Enum.KeyCode.Nine,
}

local function findHolderPrompt(holder)
    local pad = holder:FindFirstChild("Pad")
    return pad and pad:FindFirstChildWhichIsA("ProximityPrompt", true)
end

-- A locked holder still reads "Empty miner slot" but has its prompt
-- disabled - H3 is one, and without this check Auto Place hammered it
-- forever while the usable holders sat untouched.
local function isHolderUsable(prompt)
    return prompt ~= nil and prompt.Enabled and prompt.ObjectText == EMPTY_SLOT_TEXT
end

local function isHolderEmpty(prompt)
    return prompt ~= nil and prompt.ObjectText == EMPTY_SLOT_TEXT
end

local function distanceTo(part)
    local character = Players.LocalPlayer.Character
    local hrp = character and character:FindFirstChild("HumanoidRootPart")
    if not (hrp and part) then
        return nil
    end
    return (hrp.Position - part.Position).Magnitude
end

local function findEmptyHolder()
    local plot = getCurrentPlot()
    local parts = plot and getPlotParts(plot)
    if not (parts and parts.Holders) then
        return nil
    end

    for _, holder in ipairs(parts.Holders:GetChildren()) do
        local prompt = findHolderPrompt(holder)
        if isHolderUsable(prompt) then
            return holder, prompt
        end
    end

    return nil
end

local autoPlace = {}
local enabled = false
local busy = false
local lastAttempt = 0
local lastReason = nil

local function reason(text)
    if text ~= lastReason then
        log("[AutoPlace] " .. text)
        lastReason = text
    end
end

function autoPlace.SetEnabled(state)
    if state == enabled then
        return
    end
    enabled = state
    lastReason = nil

    if not enabled then
        if not busy then
            teleport.Return()
        end
        log("[AutoPlace] disabled")
    else
        lastAttempt = 0
        log("[AutoPlace] enabled (places the strongest miner it can find)")
    end
end

function autoPlace.IsEnabled()
    return enabled
end

function autoPlace.IsBusy()
    return busy
end

-- "Place <name>" is the game telling us it sees the held miner. Until then
-- pressing E does nothing.
local function isPromptReady(prompt)
    return prompt.ActionText ~= nil and prompt.ActionText:find("Place", 1, true) ~= nil
end

local function holdMiner(prompt, miner)
    local key = SLOT_KEYS[miner.slot]
    if not key then
        return false
    end

    click.Key(key)

    for _ = 1, 8 do
        task.wait(0.1)
        if isPromptReady(prompt) then
            return true
        end
    end

    return false
end

local function runJob(holder, prompt, candidates)
    busy = true

    -- Stand right on the pad. Offsetting 5 studs away worked for the two
    -- holders that happened to be near where we already were and failed for
    -- every other one - the prompt only reports "Place <name>" while we're
    -- inside its activation distance.
    teleport.To(prompt.Parent, Vector3.new(0, 3, 0))
    task.wait(0.3)

    -- Cycling all nine slots took ~5 seconds, long enough for the character
    -- to end up 128 studs from the pad while we were still pressing keys.
    -- Confirm we actually landed before spending any time here.
    local arrived = distanceTo(prompt.Parent)
    if arrived and arrived > prompt.MaxActivationDistance then
        log(string.format("[AutoPlace] teleport didn't land: %.1f studs from %s (max %s), skipping",
            arrived, holder.Name, tostring(prompt.MaxActivationDistance)))
        teleport.Return()
        busy = false
        return
    end

    -- Walk down from the strongest, but give up as soon as we've drifted
    -- out of range rather than pressing keys into nothing.
    local miner = nil
    for _, candidate in ipairs(candidates) do
        if holdMiner(prompt, candidate) then
            miner = candidate
            break
        end

        local distance = distanceTo(prompt.Parent)
        if distance and distance > prompt.MaxActivationDistance then
            log(string.format("[AutoPlace] drifted %.1f studs from %s while selecting, aborting",
                distance, holder.Name))
            teleport.Return()
            busy = false
            return
        end

        log("[AutoPlace] slot " .. candidate.slot .. " (" .. candidate.name
            .. ") didn't take, trying the next one")
    end

    -- ActionText is only a hint that the game noticed us; the slot filling
    -- is the real proof. Press E regardless and judge by the result, but
    -- record why the hint never arrived so a repeat failure is diagnosable.
    if not miner then
        miner = candidates[1]
        log(string.format(
            "[AutoPlace] no slot reported ready (prompt '%s', enabled=%s, %s studs away) - trying %s anyway",
            tostring(prompt.ActionText), tostring(prompt.Enabled),
            distanceTo(prompt.Parent) and string.format("%.1f", distanceTo(prompt.Parent)) or "?",
            miner.name
        ))
    end

    local ok, err = pcall(function()
        fireproximityprompt(prompt, Enum.ProximityPromptInputType.Keyboard, prompt.HoldDuration)
    end)
    if not ok then
        log("[AutoPlace] fireproximityprompt error: " .. tostring(err))
        teleport.Return()
        busy = false
        return
    end

    task.wait(0.5)

    if isHolderEmpty(prompt) then
        log("[AutoPlace] " .. holder.Name .. " is still empty after placing " .. miner.name)
    else
        log("[AutoPlace] placed " .. miner.name .. " (power " .. miner.power
            .. ") on " .. holder.Name)
    end

    teleport.Return()
    busy = false
end

function autoPlace.Step()
    if not enabled or busy then
        return
    end

    local now = tick()
    if now - lastAttempt < CHECK_INTERVAL then
        return
    end
    lastAttempt = now

    -- Everything below is a read: nothing moves the character until there's
    -- both an empty holder and a miner to put in it.
    local holder, prompt = findEmptyHolder()
    if not holder then
        reason("no empty holder right now")
        return
    end

    local candidates = getMinerSlots()
    if #candidates == 0 then
        reason("hotbar has no miner to place")
        return
    end

    lastReason = nil
    task.spawn(function()
        runJob(holder, prompt, candidates)
    end)
end

return autoPlace

end

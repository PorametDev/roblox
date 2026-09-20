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

local getCurrentPlot = import("games/my_anime_mine/get_current_plot")
local getPlotParts = import("games/my_anime_mine/get_plot_parts")
local getBestMiner = import("games/my_anime_mine/get_best_miner")(import)
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

local function isHolderEmpty(prompt)
    return prompt ~= nil and prompt.ObjectText == EMPTY_SLOT_TEXT
end

local function findEmptyHolder()
    local plot = getCurrentPlot()
    local parts = plot and getPlotParts(plot)
    if not (parts and parts.Holders) then
        return nil
    end

    for _, holder in ipairs(parts.Holders:GetChildren()) do
        local prompt = findHolderPrompt(holder)
        if isHolderEmpty(prompt) then
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

local function runJob(holder, prompt, miner)
    busy = true

    teleport.To(prompt.Parent)
    task.wait(0.2)

    local key = SLOT_KEYS[miner.slot]
    if not key then
        log("[AutoPlace] slot " .. tostring(miner.slot) .. " has no key binding")
        teleport.Return()
        busy = false
        return
    end

    click.Key(key)

    -- "Place <name>" is the game telling us it sees the held miner. Until
    -- then pressing E does nothing.
    local ready = false
    for _ = 1, 10 do
        task.wait(0.1)
        if prompt.ActionText and prompt.ActionText:find("Place", 1, true) then
            ready = true
            break
        end
    end

    if not ready then
        log("[AutoPlace] prompt still says '" .. tostring(prompt.ActionText)
            .. "' after selecting slot " .. miner.slot .. " (" .. miner.name .. "), skipping")
        teleport.Return()
        busy = false
        return
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

    local miner = getBestMiner()
    if not miner then
        reason("hotbar has no miner to place")
        return
    end

    lastReason = nil
    task.spawn(function()
        runJob(holder, prompt, miner)
    end)
end

return autoPlace

end

-- The real flow, straight from the game's own hint: "Hold a miner first -
-- tap it in your hotbar (or press 1-9), then press E here." Miners aren't
-- Roblox Tools (the Backpack is empty), so holding one means pressing its
-- hotbar number key.
--
-- Each holder's prompt spells out its state:
--   Enabled = false            -> locked slot, unusable (H3 is one)
--   "Empty miner slot" +
--     "Hold a miner to place"  -> empty, nothing held yet
--     "Place <name>"           -> empty, holding a miner, ready to press E
--   "<name>" + "Pick up"       -> occupied by that miner
--
-- So filling the plot isn't just "put miners in empty slots": a holder
-- sitting on a power-31 Namek Prince while power-195 Warped Ninjas wait in
-- the hotbar should be swapped. Pick up the weak one, then place the strong
-- one in the slot it freed.
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

local function isEmpty(prompt)
    return prompt.ObjectText == EMPTY_SLOT_TEXT
end

-- The billboard over a placed miner reads name / "Level 1" / rarity /
-- power. Only the power is a bare number, so that's what to match.
local function readPlacedPower(holder)
    for _, descendant in ipairs(holder:GetDescendants()) do
        if descendant:IsA("TextLabel") then
            local digits = descendant.Text:match("^([%d,]+)$")
            if digits then
                return tonumber((digits:gsub(",", "")))
            end
        end
    end
    return nil
end

local function distanceTo(part)
    local character = Players.LocalPlayer.Character
    local hrp = character and character:FindFirstChild("HumanoidRootPart")
    if not (hrp and part) then
        return nil
    end
    return (hrp.Position - part.Position).Magnitude
end

local function inRange(prompt)
    local distance = distanceTo(prompt.Parent)
    return distance == nil or distance <= prompt.MaxActivationDistance
end

local function firePrompt(prompt)
    local ok, err = pcall(function()
        fireproximityprompt(prompt, Enum.ProximityPromptInputType.Keyboard, prompt.HoldDuration)
    end)
    if not ok then
        log("[AutoPlace] fireproximityprompt error: " .. tostring(err))
    end
    return ok
end

-- Surveys every holder once: which are free to fill, and which are holding
-- something weak enough to be worth swapping out.
local function surveyHolders()
    local plot = getCurrentPlot()
    local parts = plot and getPlotParts(plot)
    if not (parts and parts.Holders) then
        return nil
    end

    local empty, occupied = {}, {}

    for _, holder in ipairs(parts.Holders:GetChildren()) do
        local prompt = findHolderPrompt(holder)
        -- A locked slot still reads "Empty miner slot" but has its prompt
        -- disabled, and Auto Place used to hammer it forever.
        if prompt and prompt.Enabled then
            if isEmpty(prompt) then
                table.insert(empty, { holder = holder, prompt = prompt })
            else
                table.insert(occupied, {
                    holder = holder,
                    prompt = prompt,
                    name = prompt.ObjectText,
                    power = readPlacedPower(holder) or 0,
                })
            end
        end
    end

    table.sort(occupied, function(a, b)
        return a.power < b.power
    end)

    return empty, occupied
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
        log("[AutoPlace] enabled (fills empty holders, then upgrades weak ones)")
    end
end

function autoPlace.IsEnabled()
    return enabled
end

function autoPlace.IsBusy()
    return busy
end

-- Stand on the pad. Offsetting away put us outside the prompt's activation
-- distance for every holder that wasn't already nearby.
local function goTo(prompt)
    teleport.To(prompt.Parent, Vector3.new(0, 3, 0))
    task.wait(0.3)

    if inRange(prompt) then
        return true
    end

    local distance = distanceTo(prompt.Parent)
    log(string.format("[AutoPlace] teleport didn't land: %.1f studs away (max %s)",
        distance or -1, tostring(prompt.MaxActivationDistance)))
    return false
end

-- "Place <name>" is the game confirming it sees the held miner. Pressing E
-- before that does nothing.
local function holdMiner(prompt, miner)
    local key = SLOT_KEYS[miner.slot]
    if not key then
        return false
    end

    click.Key(key)

    for _ = 1, 8 do
        task.wait(0.1)
        if prompt.ActionText and prompt.ActionText:find("Place", 1, true) then
            return true
        end
    end

    return false
end

local function placeBest(holder, prompt)
    local candidates = getMinerSlots()
    if #candidates == 0 then
        log("[AutoPlace] nothing in the hotbar to place")
        return false
    end

    local miner = nil
    for _, candidate in ipairs(candidates) do
        if holdMiner(prompt, candidate) then
            miner = candidate
            break
        end

        if not inRange(prompt) then
            log("[AutoPlace] drifted out of range of " .. holder.Name .. " while selecting")
            return false
        end

        log("[AutoPlace] slot " .. candidate.slot .. " (" .. candidate.name
            .. ") didn't take, trying the next one")
    end

    -- ActionText is only a hint; the slot filling is the real proof.
    miner = miner or candidates[1]
    firePrompt(prompt)
    task.wait(0.5)

    if isEmpty(prompt) then
        log("[AutoPlace] " .. holder.Name .. " still empty after placing " .. miner.name)
        return false
    end

    log("[AutoPlace] placed " .. miner.name .. " (power " .. miner.power
        .. ") on " .. holder.Name)
    return true
end

local function pickUp(entry)
    firePrompt(entry.prompt)
    task.wait(0.5)

    if not isEmpty(entry.prompt) then
        log("[AutoPlace] couldn't pick up " .. entry.name .. " from " .. entry.holder.Name
            .. " (prompt says '" .. tostring(entry.prompt.ActionText) .. "')")
        return false
    end

    log("[AutoPlace] picked up " .. entry.name .. " (power " .. entry.power
        .. ") from " .. entry.holder.Name)
    return true
end

local function runFillJob(target)
    busy = true

    if goTo(target.prompt) then
        placeBest(target.holder, target.prompt)
    end

    teleport.Return()
    busy = false
end

local function runUpgradeJob(target)
    busy = true

    if goTo(target.prompt) and pickUp(target) then
        -- The picked-up miner lands back in the hotbar, so re-read it
        -- before choosing what goes in - placeBest does that itself.
        placeBest(target.holder, target.prompt)
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

    -- Everything here is a read: nothing moves the character until there's
    -- actually something worth doing.
    local empty, occupied = surveyHolders()
    if not empty then
        reason("not standing in any plot")
        return
    end

    local candidates = getMinerSlots()
    if #candidates == 0 then
        reason("hotbar has no miner to place")
        return
    end

    if #empty > 0 then
        lastReason = nil
        task.spawn(function()
            runFillJob(empty[1])
        end)
        return
    end

    -- Every slot is taken, so the only gain left is swapping out the
    -- weakest one - and only when it's strictly weaker, otherwise an equal
    -- pair would swap back and forth forever.
    local weakest = occupied[1]
    local best = candidates[1]

    if weakest and best.power > weakest.power then
        lastReason = nil
        log("[AutoPlace] upgrading " .. weakest.holder.Name .. ": " .. weakest.name
            .. " (" .. weakest.power .. ") -> " .. best.name .. " (" .. best.power .. ")")
        task.spawn(function()
            runUpgradeJob(weakest)
        end)
        return
    end

    reason("every holder already has something at least as strong as the hotbar's best")
end

return autoPlace

end

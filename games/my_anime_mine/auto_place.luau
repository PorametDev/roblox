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
local LOCKED_SLOT_TEXT = "Locked miner slot"
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

-- Walking up to an unbought slot shows "Locked miner slot / Unlock", so the
-- prompt states it outright - no need to infer anything. The price tag and
-- ActionText checks below are only fallbacks for slots we haven't seen up
-- close, since Enabled stays true on these (pressing E there just gets
-- "Not enough cash - the next miner slot costs $14.4B").
local function findPriceTag(holder)
    for _, descendant in ipairs(holder:GetDescendants()) do
        if descendant:IsA("TextLabel") and descendant.Text:match("^%$") then
            return descendant.Text
        end
    end
    return nil
end

local function isLocked(prompt, holder)
    if prompt.ObjectText == LOCKED_SLOT_TEXT then
        return true, "locked slot"
    end

    if not prompt.Enabled then
        return true, "prompt disabled"
    end

    local price = findPriceTag(holder)
    if price then
        return true, "costs " .. price
    end

    local action = prompt.ActionText or ""
    if action:match("[Uu]nlock") or action:match("[Bb]uy") or action:match("%$") then
        return true, "action '" .. action .. "'"
    end

    return false
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

local lastSurvey = nil

-- Surveys every holder once: which are free to fill, and which are holding
-- something weak enough to be worth swapping out.
local function surveyHolders()
    local plot = getCurrentPlot()
    local parts = plot and getPlotParts(plot)
    if not (parts and parts.Holders) then
        return nil
    end

    local empty, occupied = {}, {}
    local summary = {}

    for _, holder in ipairs(parts.Holders:GetChildren()) do
        local prompt = findHolderPrompt(holder)
        if prompt then
            local locked, why = isLocked(prompt, holder)
            if locked then
                table.insert(summary, holder.Name .. "=locked(" .. why .. ")")
            elseif isEmpty(prompt) then
                table.insert(summary, holder.Name .. "=empty")
                table.insert(empty, { holder = holder, prompt = prompt })
            else
                local power = readPlacedPower(holder) or 0
                table.insert(summary, holder.Name .. "=" .. prompt.ObjectText .. "(" .. power .. ")")
                table.insert(occupied, {
                    holder = holder,
                    prompt = prompt,
                    name = prompt.ObjectText,
                    power = power,
                })
            end
        end
    end

    -- One line describing the whole plot, only when it changes, so the log
    -- shows what Auto Place believes about every slot without spamming.
    local line = table.concat(summary, " | ")
    if line ~= lastSurvey then
        log("[AutoPlace] holders: " .. line)
        lastSurvey = line
    end

    table.sort(occupied, function(a, b)
        return a.power < b.power
    end)

    return { empty = empty, occupied = occupied }
end

-- The scheduler asks HasWork every frame, and a survey walks every holder's
-- descendants, so share one cached snapshot between it and Step.
local cachedSurvey, cachedCandidates, cachedAt = nil, nil, 0

local function look()
    local now = tick()
    if now - cachedAt > 1 then
        cachedSurvey = surveyHolders()
        cachedCandidates = getMinerSlots()
        cachedAt = now
    end
    return cachedSurvey, cachedCandidates
end

-- "Still has work" means a free slot to fill, or a placed miner weaker than
-- the best one waiting in the hotbar. Strictly weaker, so two equal miners
-- can't swap back and forth forever.
local function findNextAction()
    local survey, candidates = look()
    if not survey or not candidates or #candidates == 0 then
        return nil
    end

    if #survey.empty > 0 then
        return "fill", survey.empty[1], candidates[1]
    end

    local weakest = survey.occupied[1]
    if weakest and candidates[1].power > weakest.power then
        return "upgrade", weakest, candidates[1]
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
        log("[AutoPlace] enabled (fills empty holders, then upgrades weak ones)")
    end
end

function autoPlace.IsEnabled()
    return enabled
end

function autoPlace.IsBusy()
    return busy
end

-- Tells the scheduler whether the plot still needs attention, so Auto Sell
-- doesn't get a turn until every holder is filled and upgraded.
function autoPlace.HasWork()
    return (findNextAction()) ~= nil
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
    cachedAt = 0
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
    cachedAt = 0
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

    -- Every check above is a read: nothing moves the character until
    -- there's actually something worth doing.
    local action, target, best = findNextAction()
    if not action then
        reason("nothing to place or upgrade")
        return
    end

    lastReason = nil
    cachedAt = 0

    if action == "fill" then
        task.spawn(function()
            runFillJob(target)
        end)
        return
    end

    log("[AutoPlace] upgrading " .. target.holder.Name .. ": " .. target.name
        .. " (" .. target.power .. ") -> " .. best.name .. " (" .. best.power .. ")")
    task.spawn(function()
        runUpgradeJob(target)
    end)
end

return autoPlace

end

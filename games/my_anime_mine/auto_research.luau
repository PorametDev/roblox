-- Drives the game's own client API rather than its UI. From
-- MineSkillTreeClient the buy button sends:
--
--   GameState.SendEvent("MineBuySkill", <zoneKey>, <family>)
--
-- and the state dump showed both sides of that already sitting in the
-- client's data:
--
--   UnlockedZones = { Z1 = true }
--   Skills.Z1     = { NodeCount = 3, Luck = 1, NodeHealth = 1 }
--
-- Note what's being bought is a FAMILY, not a specific node - the server
-- works out which node in that family comes next. The tree's node ids
-- (Deposits1, Fracture2, ...) never need to enter into it, which is why
-- this needs no menu at all.
--
-- Families the player hasn't started yet don't appear in Skills, so
-- KNOWN_FAMILIES seeds the ones seen so far; anything new the player
-- unlocks shows up in Skills on its own and gets picked up from there.
--
-- Prices aren't in the state table, so as with unit upgrades this stops
-- when a level fails to rise, which covers both maxed and unaffordable.
return function(import)

local gameApi = import("games/my_anime_mine/game_api")(import)
local log = import("core/logger")

local KNOWN_FAMILIES = { "NodeCount", "Luck", "NodeHealth" }

local checkInterval = 30
local maxPerPass = 5

local autoResearch = {}
local enabled = false
local busy = false
local lastAttempt = 0

function autoResearch.SetEnabled(state)
    if state == enabled then
        return
    end
    enabled = state
    log("[AutoResearch] " .. (enabled and "enabled" or "disabled"))
end

function autoResearch.IsEnabled()
    return enabled
end

function autoResearch.IsBusy()
    return busy
end

function autoResearch.SetCheckInterval(seconds)
    checkInterval = math.max(seconds, 5)
end

function autoResearch.SetMaxPerPass(count)
    maxPerPass = math.max(count, 1)
end

local function unlockedZones()
    local mine = gameApi.GetMineData()
    local zones = mine and mine.UnlockedZones or {}

    local list = {}
    for zoneKey, unlocked in pairs(zones) do
        if unlocked then
            table.insert(list, zoneKey)
        end
    end
    table.sort(list)
    return list
end

local function skillLevel(zoneKey, family)
    local mine = gameApi.GetMineData()
    local skills = mine and mine.Skills and mine.Skills[zoneKey]
    return skills and skills[family] or 0
end

local function familiesFor(zoneKey)
    local seen = {}
    local list = {}

    for _, family in ipairs(KNOWN_FAMILIES) do
        seen[family] = true
        table.insert(list, family)
    end

    local mine = gameApi.GetMineData()
    local skills = mine and mine.Skills and mine.Skills[zoneKey]
    if skills then
        for family in pairs(skills) do
            if not seen[family] then
                table.insert(list, family)
            end
        end
    end

    return list
end

local function runJob()
    busy = true
    local bought = 0

    for _, zoneKey in ipairs(unlockedZones()) do
        for _, family in ipairs(familiesFor(zoneKey)) do
            if not enabled or bought >= maxPerPass then
                break
            end

            local before = skillLevel(zoneKey, family)
            gameApi.BuySkill(zoneKey, family)
            task.wait(0.4)

            local after = skillLevel(zoneKey, family)
            if after > before then
                log("[AutoResearch] " .. zoneKey .. " " .. family .. " "
                    .. before .. " -> " .. after)
                bought = bought + 1
            end
        end
    end

    if bought == 0 then
        log("[AutoResearch] nothing bought (maxed out or not enough cash)")
    end

    busy = false
end

function autoResearch.Step()
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

return autoResearch

end

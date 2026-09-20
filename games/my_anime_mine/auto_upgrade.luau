-- Drives the game's own client API rather than its UI. From
-- MineSlotFocusClient the upgrade button sends:
--
--   GameState.SendEvent("MineUpgradeCharacter", <holder key>, <stat>)
--
-- and the state dump showed the holder key is simply the holder's name,
-- with each one's levels sitting right there:
--
--   Holders.M1 = { CharName, CharLevel, CharSpeedLevel, CharMineSpeedLevel }
--
-- So no teleporting to a holder, no opening the unit screen, no clicking
-- through three tabs - read the levels, send the event, confirm the level
-- moved.
--
-- Prices aren't in the state table, so instead of a money cap this stops
-- as soon as a level fails to rise: that covers both "maxed out" and
-- "can't afford it" without having to know the cost. maxPerPass keeps one
-- pass from spending everything the moment a sale lands.
return function(import)

local gameApi = import("games/my_anime_mine/game_api")(import)
local log = import("core/logger")

-- The screen labels these Damage / Speed / Mining; the server wants
-- Damage / Speed / MineSpeed, and the state stores them as CharLevel /
-- CharSpeedLevel / CharMineSpeedLevel.
local STATS = {
    { event = "Damage", field = "CharLevel" },
    { event = "Speed", field = "CharSpeedLevel" },
    { event = "MineSpeed", field = "CharMineSpeedLevel" },
}

local checkInterval = 20
local maxPerPass = 5
-- "lowest" keeps a miner's three stats level with each other; the others
-- pour everything into one, which is what you want when a specific stat is
-- the bottleneck.
local priority = "lowest"
local buyPickaxe = true

local autoUpgrade = {}
local enabled = false
local busy = false
local lastAttempt = 0

function autoUpgrade.SetEnabled(state)
    if state == enabled then
        return
    end
    enabled = state
    log("[AutoUpgrade] " .. (enabled and "enabled" or "disabled"))
end

function autoUpgrade.IsEnabled()
    return enabled
end

function autoUpgrade.IsBusy()
    return busy
end

function autoUpgrade.SetInterval(seconds)
    checkInterval = math.max(seconds, 1)
end

function autoUpgrade.SetMaxPerPass(count)
    maxPerPass = math.max(count, 1)
end

-- "lowest" | "Damage" | "Speed" | "MineSpeed"
function autoUpgrade.SetPriority(value)
    priority = value
end

function autoUpgrade.SetBuyPickaxe(state)
    buyPickaxe = state
end

local function holders()
    local mine = gameApi.GetMineData()
    return mine and mine.Holders or {}
end

local function levelOf(holderKey, field)
    local entry = holders()[holderKey]
    return entry and entry[field] or nil
end

local function chooseStat(entry)
    if priority ~= "lowest" then
        for _, stat in ipairs(STATS) do
            if stat.event == priority and entry[stat.field] then
                return { event = stat.event, field = stat.field, level = entry[stat.field] }
            end
        end
    end

    -- Lowest first, so a miner's three stats climb together rather than one
    -- racing ahead.
    local lowest = nil
    for _, stat in ipairs(STATS) do
        local level = entry[stat.field]
        if level and (not lowest or level < lowest.level) then
            lowest = { event = stat.event, field = stat.field, level = level }
        end
    end
    return lowest
end

-- The pickaxe is bought by tier index, and PickaxeTier in the state says
-- which one we're on, so the next one is simply the one after it.
local function tryPickaxe()
    local mine = gameApi.GetMineData()
    local tier = mine and mine.PickaxeTier
    if not tier then
        return false
    end

    gameApi.BuyPickaxe(tier + 1)
    task.wait(0.4)

    local after = gameApi.GetMineData()
    if after and (after.PickaxeTier or tier) > tier then
        log("[AutoUpgrade] pickaxe tier " .. tier .. " -> " .. after.PickaxeTier)
        return true
    end

    return false
end

local function runJob()
    busy = true
    local bought = 0

    for holderKey, entry in pairs(holders()) do
        if not enabled or bought >= maxPerPass then
            break
        end

        local stat = chooseStat(entry)
        if stat then
            gameApi.UpgradeCharacter(holderKey, stat.event)
            task.wait(0.4)

            local after = levelOf(holderKey, stat.field)
            if after and after > stat.level then
                log("[AutoUpgrade] " .. holderKey .. " " .. stat.event .. " "
                    .. stat.level .. " -> " .. after)
                bought = bought + 1
            end
        end
    end

    if buyPickaxe and enabled and bought < maxPerPass and tryPickaxe() then
        bought = bought + 1
    end

    if bought == 0 then
        log("[AutoUpgrade] nothing upgraded (maxed out or not enough cash)")
    end

    busy = false
end

function autoUpgrade.Step()
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

return autoUpgrade

end

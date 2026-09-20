-- Buys the next zone and keeps you mining in the deepest one you own.
--
-- The board on the plot - "The Underground / $100,000 / Locked / Locked" -
-- looks like two different things, a zone picker and a shop. It isn't.
-- MineZoneBoardClient binds every row, owned or priced or locked, to one
-- event:
--
--   GameState.SendEvent("MineSelectZone", zoneKey)
--
-- The server works out whether that was a switch or a purchase. So both
-- halves of this module are the same call, and the difference is only in
-- what we check afterwards: did CurrentZone move, or did UnlockedZones
-- gain a key.
--
-- The price is the one thing the client doesn't know. It isn't in
-- MineConfig anywhere - the board is a physical SurfaceGui with the number
-- baked in - so the sign is read for a sanity check and, when it can't be
-- read, the purchase is simply attempted and verified. A refused remote
-- costs nothing.
return function(import)

local gameApi = import("games/my_anime_mine/game_api")(import)
local parseMoney = import("core/parse_money")
local log = import("core/logger")
local runGuarded = import("core/run_job")(import)

local checkInterval = 30
local buyNextZone = true
local useLatestZone = true
-- Zones cost far more than research nodes, so this one has a reserve of
-- its own rather than sharing the general pot.
local keepMoney = 0

local autoPlot = {}
local enabled = false
local busy = false
local lastAttempt = 0
local reportedLocked = nil

function autoPlot.SetEnabled(state)
    if state == enabled then
        return
    end
    enabled = state
    reportedLocked = nil
    log("[AutoPlot] " .. (enabled and "enabled" or "disabled"))
end

function autoPlot.IsEnabled()
    return enabled
end

function autoPlot.IsBusy()
    return busy
end

function autoPlot.SetCheckInterval(seconds)
    checkInterval = math.max(seconds, 5)
end

function autoPlot.SetBuyNextZone(state)
    buyNextZone = state
end

function autoPlot.SetUseLatestZone(state)
    useLatestZone = state
end

function autoPlot.SetKeepMoney(amount)
    keepMoney = math.max(amount, 0)
end

-- Highest-numbered zone we own, by position in MineConfig.ZoneKeys - that
-- ordering IS the progression, so "latest" is "last unlocked index".
local function deepestUnlocked()
    local mine = gameApi.GetMineData()
    local unlocked = mine and mine.UnlockedZones or {}

    local bestIndex, bestKey = nil, nil
    for index, zoneKey in ipairs(gameApi.ZoneKeys()) do
        if unlocked[zoneKey] then
            bestIndex, bestKey = index, zoneKey
        end
    end
    return bestIndex, bestKey
end

-- The first zone we don't own. Zones unlock in order, so this is the only
-- one worth trying.
local function nextLockedZone()
    local mine = gameApi.GetMineData()
    local unlocked = mine and mine.UnlockedZones or {}

    for index, zoneKey in ipairs(gameApi.ZoneKeys()) do
        if not unlocked[zoneKey] then
            return index, zoneKey
        end
    end
    return nil
end

-- nil means "the sign didn't say", which is treated as "worth a try"
-- rather than as a refusal.
local function priceOf(zoneIndex)
    local text = gameApi.ZoneBoardPriceText(zoneIndex)
    if not text or not text:find("%$") then
        return nil
    end
    local amount = parseMoney(text)
    if amount == math.huge then
        return nil
    end
    return amount
end

local function switchToDeepest()
    if not useLatestZone then
        return false
    end

    local deepestIndex, deepestKey = deepestUnlocked()
    if not deepestIndex or gameApi.CurrentZoneIndex() == deepestIndex then
        return false
    end

    gameApi.SelectZone(deepestKey)
    task.wait(0.5)

    if gameApi.CurrentZoneIndex() == deepestIndex then
        log("[AutoPlot] now mining " .. gameApi.ZoneDisplayName(deepestKey)
            .. " (" .. deepestKey .. ")")
        return true
    end

    log("[AutoPlot] couldn't switch to " .. deepestKey)
    return false
end

local function tryBuyNextZone()
    if not buyNextZone then
        return false
    end

    local index, zoneKey = nextLockedZone()
    if not index then
        return false
    end

    local price = priceOf(index)
    if price and price > (gameApi.GetMoney() - keepMoney) then
        -- Said once per price, not once per pass.
        if reportedLocked ~= price then
            reportedLocked = price
            log("[AutoPlot] " .. gameApi.ZoneDisplayName(zoneKey) .. " costs "
                .. math.floor(price) .. ", you have " .. math.floor(gameApi.GetMoney()))
        end
        return false
    end

    gameApi.SelectZone(zoneKey)
    task.wait(0.6)

    local mine = gameApi.GetMineData()
    if mine and (mine.UnlockedZones or {})[zoneKey] then
        log("[AutoPlot] unlocked " .. gameApi.ZoneDisplayName(zoneKey)
            .. " (" .. zoneKey .. ")")
        reportedLocked = nil
        return true
    end

    -- Zones gate on research as well as cash, so a refusal here usually
    -- means the current zone's tree isn't finished.
    local _, currentKey = deepestUnlocked()
    if currentKey then
        local done, total = gameApi.ZoneResearchProgress(currentKey)
        if reportedLocked ~= "research" then
            reportedLocked = "research"
            log("[AutoPlot] " .. zoneKey .. " refused - "
                .. gameApi.ZoneDisplayName(currentKey) .. " research is "
                .. done .. "/" .. total)
        end
    end
    return false
end

local function runJob()
    busy = true

    -- Buy first, then switch: unlocking a zone and immediately moving into
    -- it is one action from the player's point of view.
    local bought = tryBuyNextZone()
    if bought then
        task.wait(0.4)
    end
    switchToDeepest()

    busy = false
end

function autoPlot.HasWork()
    if useLatestZone then
        local deepestIndex = deepestUnlocked()
        if deepestIndex and gameApi.CurrentZoneIndex() ~= deepestIndex then
            return true
        end
    end

    if buyNextZone then
        local index = nextLockedZone()
        if index then
            local price = priceOf(index)
            if not price or price <= (gameApi.GetMoney() - keepMoney) then
                return true
            end
        end
    end

    return false
end

function autoPlot.Step()
    if not enabled or busy then
        return
    end

    local now = tick()
    if now - lastAttempt < checkInterval then
        return
    end
    lastAttempt = now

    -- Guarded: a job that throws would otherwise leave busy set
    -- forever, and one stuck flag blocks every exclusive task.
    runGuarded("AutoPlot", runJob, function()
        busy = false
    end)
end

return autoPlot

end

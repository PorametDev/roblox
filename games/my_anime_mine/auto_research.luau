-- Drives the game's own client API rather than its UI.
--
-- The first version of this sent GameState.SendEvent("MineBuySkill", zone,
-- family) for a hand-written list of family names and hoped. It bought
-- nothing, and the decompiled MineSkillTreeClient says why - its buy button
-- refuses unless ALL of this holds:
--
--   zone unlocked  ·  the NODE exists  ·  node not maxed  ·  node OPEN
--
-- A family spans several nodes going down the tree, and a node only opens
-- once its parents are finished. So "buy family Luck" is meaningless until
-- some Luck node is actually open. Now the node list comes from
-- MineConfig.GetSkillNodes and every node is filtered through the game's own
-- IsSkillNodeOpen / IsSkillNodeMaxed before a single remote goes out.
--
-- The Core tab is a different tree entirely: no MineBuySkill, each upgrade
-- has its own argument-less event at MineConfig.CoreUpgradeById[family].Event.
-- That whole half of the screen was simply missing before.
--
-- Costs are real now (GetSkillCost / CoreUpgradeById.Cost), so an unaffordable
-- node is skipped rather than fired at and silently dropped.
--
-- Team power is a SOFT gate, and getting that wrong stopped research
-- dead. MineSkillTreeClient greys the button out with "Needs X team power
-- (you have Y)" when GetSkillPowerReq(zone, family, nextLevel) exceeds the
-- player's MinePower - but that check lives only in the rendering code.
-- buySelected(), the thing the button actually calls, checks nothing but
-- maxed and open. Treating the grey-out as a hard block made this filter
-- stricter than the game's own and left affordable nodes unbought.
--
-- So power-blocked nodes are now sorted to the BACK rather than dropped:
-- everything else gets bought first, and if nothing else is available they
-- still get tried, because one refused remote costs far less than never
-- buying. The requirement is reported either way.
return function(import)

local gameApi = import("games/my_anime_mine/game_api")(import)
local log = import("core/logger")
local runGuarded = import("core/run_job")(import)
local spendPolicy = import("core/spend_policy")(import)

local checkInterval = 30
local maxPerPass = 5
local buyZones = true
local buyCore = true
-- The Core tree is optional; the zone tree is what gates the next zone.
-- Core nodes cost millions where zone nodes cost thousands, so letting
-- them share a wallet means one Core purchase can swallow the balance a
-- hundred zone nodes were waiting on. Holding Core back until the zone
-- tree has nothing buyable keeps the required track moving first.
local coreLastResort = true
-- Cheapest open node first, so a pass spreads across the tree instead of
-- saving up for one expensive node while ten $22 ones sit unbought.
local cheapestFirst = true
-- Never spend below this, so research can't eat the money the unit
-- upgrades and pickaxes want.
local keepMoney = 0

local autoResearch = {}
local enabled = false
local busy = false
local lastAttempt = 0
-- Cleared whenever something is bought, so the next idle line describes
-- the new situation rather than being suppressed as a repeat.
local lastIdleSummary = nil

-- Forward-declared: reportIdle needs the settings and helpers defined
-- below it, but SetEnabled above wants to call it.
local reportIdle

function autoResearch.SetEnabled(state)
    if state == enabled then
        return
    end
    enabled = state
    log("[AutoResearch] " .. (enabled and "enabled" or "disabled"))

    -- Report straight away on switch-on rather than waiting for the
    -- scheduler. Last round the idle report lived somewhere that only ran
    -- once the scheduler had granted a turn, which is exactly what wasn't
    -- happening, so the log came back empty again. Flipping the toggle now
    -- always produces output, whatever the scheduler decides.
    if enabled then
        task.spawn(function()
            -- The game's modules may not have answered yet on a fresh
            -- join; a moment's grace beats reporting zeroes.
            task.wait(1)
            if enabled then
                reportIdle()
            end
        end)
    end
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

function autoResearch.SetBuyZones(state)
    buyZones = state
end

function autoResearch.SetBuyCore(state)
    buyCore = state
end

function autoResearch.SetCoreLastResort(state)
    coreLastResort = state
end

function autoResearch.SetCheapestFirst(state)
    cheapestFirst = state
end

function autoResearch.SetKeepMoney(amount)
    keepMoney = math.max(amount, 0)
end

local function spendable()
    return gameApi.GetMoney() - keepMoney
end

-- Everything that would actually go through if we pressed Buy on it.
-- Exactly the conditions buySelected() enforces, and nothing more.
local function buyableZoneNodes()
    local budget = spendable()
    local list = {}
    local powerBlocked = nil

    for _, zoneKey in ipairs(gameApi.UnlockedZones()) do
        for _, node in ipairs(gameApi.SkillNodes(zoneKey)) do
            if node.open and not node.maxed and node.cost and node.cost <= budget then
                table.insert(list, node)

                if not node.powerOk then
                    -- Cheapest requirement we're short of, so the log can
                    -- say how far off we are.
                    if not powerBlocked or node.powerReq < powerBlocked.powerReq then
                        powerBlocked = node
                    end
                end
            end
        end
    end

    return list, powerBlocked
end

local function buyableCoreNodes()
    local budget = spendable()
    local list = {}

    for _, node in ipairs(gameApi.CoreNodes()) do
        if node.open and not node.maxed and node.event
            and node.cost and node.cost <= budget
        then
            table.insert(list, node)
        end
    end

    return list
end

-- Deterministic either way: without a tiebreak two equally priced nodes
-- could swap places between passes and the "did the level move?" check
-- would compare the wrong pair.
local function sortNodes(list)
    table.sort(list, function(a, b)
        -- Anything the tree would grey out for team power goes last, but
        -- still gets its turn if nothing else is left.
        local aPower = a.powerOk ~= false
        local bPower = b.powerOk ~= false
        if aPower ~= bPower then
            return aPower
        end

        if a.cost ~= b.cost then
            if cheapestFirst then
                return a.cost < b.cost
            end
            return a.cost > b.cost
        end
        return tostring(a.id) < tostring(b.id)
    end)
end

local function levelOfZoneNode(node)
    for _, current in ipairs(gameApi.SkillNodes(node.zoneKey)) do
        if current.id == node.id then
            return current.level
        end
    end
    return node.level
end

local function levelOfCoreNode(node)
    for _, current in ipairs(gameApi.CoreNodes()) do
        if current.id == node.id then
            return current.level
        end
    end
    return node.level
end

local function runJob()
    busy = true
    local bought = 0
    local blocked = 0

    local powerBlocked = nil

    if buyZones then
        local nodes
        nodes, powerBlocked = buyableZoneNodes()
        sortNodes(nodes)

        for _, node in ipairs(nodes) do
            if not enabled or bought >= maxPerPass then
                break
            end

            gameApi.BuySkill(node.zoneKey, node.family)
            task.wait(0.4)

            local after = levelOfZoneNode(node)
            if after > node.level then
                log("[AutoResearch] " .. node.zoneKey .. " " .. node.id
                    .. " (" .. node.family .. ") " .. node.level .. " -> " .. after)
                bought = bought + 1
                lastIdleSummary = nil
            else
                blocked = blocked + 1
            end
        end
    end

    -- Zone nodes still pending means Core waits, even if this pass hit
    -- maxPerPass before reaching them.
    local zonesStillWant = coreLastResort and #(buyableZoneNodes()) > 0

    if buyCore and not zonesStillWant then
        local nodes = buyableCoreNodes()
        sortNodes(nodes)

        for _, node in ipairs(nodes) do
            if not enabled or bought >= maxPerPass then
                break
            end

            gameApi.BuyCore(node.event)
            task.wait(0.4)

            local after = levelOfCoreNode(node)
            if after > node.level then
                log("[AutoResearch] Core " .. node.id
                    .. " (" .. node.family .. ") " .. node.level .. " -> " .. after)
                bought = bought + 1
                lastIdleSummary = nil
            else
                blocked = blocked + 1
            end
        end
    end

    if bought == 0 then
        -- Telling these two apart matters: "nothing open" means wait for
        -- more money or a prerequisite, "the server said no" means the
        -- filter above still disagrees with the server.
        if blocked > 0 then
            log("[AutoResearch] " .. blocked
                .. " node(s) looked buyable but the server refused")
        elseif powerBlocked then
            log("[AutoResearch] " .. powerBlocked.zoneKey .. " " .. powerBlocked.id
                .. " (" .. powerBlocked.family .. ") needs "
                .. math.floor(powerBlocked.powerReq) .. " team power, you have "
                .. math.floor(powerBlocked.power)
                .. " - upgrade the miners first")
        else
            log("[AutoResearch] nothing open and affordable right now"
                .. " (money " .. math.floor(gameApi.GetMoney()) .. ")")
            -- Name the cheapest thing that is open but out of reach, so
            -- "it just sits there" is never a mystery again.
            local nearest = nil
            for _, zoneKey in ipairs(gameApi.UnlockedZones()) do
                for _, node in ipairs(gameApi.SkillNodes(zoneKey)) do
                    if node.open and not node.maxed and node.cost
                        and (not nearest or node.cost < nearest.cost)
                    then
                        nearest = node
                    end
                end
            end
            if nearest then
                log("[AutoResearch] cheapest open node: " .. nearest.zoneKey
                    .. " " .. nearest.id .. " (" .. nearest.family .. ") "
                    .. nearest.level .. "/" .. nearest.max
                    .. " costs " .. math.floor(nearest.cost))
            end
        end
    end

    busy = false
end

-- Cheap enough to run before committing a turn: it's all table reads off
-- state the client already holds.
-- Why a pass isn't happening.
--
-- This started as temporary debugging and then ran overnight: 1,694 idle
-- reports, 12,396 lines, four per cent of a 341,000-line log, burying
-- everything worth reading. So it now prints only when the ANSWER
-- changes. Sitting in the same state for six hours is one line, and the
-- moment something moves it says so again.
-- One line: the cheapest thing standing between us and a purchase, and
-- what's stopping it. Everything else was noise.
local function idleSummary()
    -- A switched-off half of the feature is the likeliest explanation and
    -- the easiest to miss in a menu, so it leads.
    if not buyZones and not buyCore then
        return "both Zone and Core buying are switched off"
    end

    local money = gameApi.GetMoney()
    local budget = spendable()
    local nearest = nil

    if buyZones then
        for _, zoneKey in ipairs(gameApi.UnlockedZones()) do
            for _, node in ipairs(gameApi.SkillNodes(zoneKey)) do
                if node.open and not node.maxed and node.cost
                    and (not nearest or node.cost < nearest.cost)
                then
                    nearest = node
                end
            end
        end
    end

    if buyCore then
        for _, node in ipairs(gameApi.CoreNodes()) do
            if node.open and not node.maxed and node.cost
                and (not nearest or node.cost < nearest.cost)
            then
                nearest = {
                    zoneKey = "Core",
                    id = node.id,
                    family = node.family,
                    level = node.level,
                    max = node.level + 1,
                    cost = node.cost,
                    powerOk = true,
                }
            end
        end
    end

    if not nearest then
        local parts = {}
        if not buyZones then
            table.insert(parts, "Zone buying is off")
        end
        if not buyCore then
            table.insert(parts, "Core buying is off")
        end
        if #parts == 0 then
            return "every open node is maxed"
        end
        return "nothing left to buy (" .. table.concat(parts, ", ") .. ")"
    end

    local why
    if nearest.cost > budget then
        why = "needs " .. string.format("%.3g", nearest.cost)
            .. ", have " .. string.format("%.3g", money)
    elseif nearest.powerOk == false then
        why = "needs " .. string.format("%.3g", nearest.powerReq) .. " team power"
    else
        why = "affordable - waiting for a turn"
    end

    return "cheapest open node " .. nearest.zoneKey .. " " .. tostring(nearest.id)
        .. " (" .. tostring(nearest.family) .. ") " .. why
end

function reportIdle()
    local summary = idleSummary()
    if summary == lastIdleSummary then
        return
    end
    lastIdleSummary = summary
    log("[AutoResearch] idle: " .. summary)
end

local lastIdleReport = 0

-- Reporting lives here rather than in Step because Step is only reached
-- once the scheduler grants a turn, and the scheduler only grants one when
-- this returns true. HasWork is the one thing that still runs while the
-- task is idle, so it is the only place the idle case can be observed.
-- What this would spend next, for core/spend_policy to compare against
-- the other buyers. Cheapest or dearest of everything currently buyable.
function autoResearch.NextPrice(mode)
    local candidates = {}

    if buyZones then
        for _, node in ipairs((buyableZoneNodes())) do
            table.insert(candidates, node.cost)
        end
    end
    if buyCore then
        for _, node in ipairs(buyableCoreNodes()) do
            table.insert(candidates, node.cost)
        end
    end

    local best = nil
    for _, cost in ipairs(candidates) do
        if not best
            or (mode == "dearest" and cost > best)
            or (mode ~= "dearest" and cost < best)
        then
            best = cost
        end
    end
    return best
end

function autoResearch.HasWork()
    local zoneNodes = buyZones and buyableZoneNodes() or {}
    local has

    if #zoneNodes > 0 then
        has = true
    elseif not buyCore then
        has = false
    else
        has = #buyableCoreNodes() > 0
    end

    -- Everything this task does is a purchase, so the policy gates the
    -- whole thing rather than any one branch of it.
    if has and not spendPolicy.MaySpend("AutoResearch") then
        return false
    end

    if not has and enabled then
        local now = tick()
        if now - lastIdleReport >= math.max(checkInterval, 15) then
            lastIdleReport = now
            reportIdle()
        end
    end

    return has
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

    -- Guarded: a job that throws would otherwise leave busy set
    -- forever, and one stuck flag blocks every exclusive task.
    runGuarded("AutoResearch", runJob, function()
        busy = false
    end)
end

return autoResearch

end

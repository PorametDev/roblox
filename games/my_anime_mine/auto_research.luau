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
return function(import)

local gameApi = import("games/my_anime_mine/game_api")(import)
local log = import("core/logger")

local checkInterval = 30
local maxPerPass = 5
local buyZones = true
local buyCore = true
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

function autoResearch.SetBuyZones(state)
    buyZones = state
end

function autoResearch.SetBuyCore(state)
    buyCore = state
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
local function buyableZoneNodes()
    local budget = spendable()
    local list = {}

    for _, zoneKey in ipairs(gameApi.UnlockedZones()) do
        for _, node in ipairs(gameApi.SkillNodes(zoneKey)) do
            if node.open and not node.maxed and node.cost and node.cost <= budget then
                table.insert(list, node)
            end
        end
    end

    return list
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

    if buyZones then
        local nodes = buyableZoneNodes()
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
            else
                blocked = blocked + 1
            end
        end
    end

    if buyCore then
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
        else
            log("[AutoResearch] nothing open and affordable right now")
        end
    end

    busy = false
end

-- Cheap enough to run before committing a turn: it's all table reads off
-- state the client already holds.
function autoResearch.HasWork()
    if buyZones and #buyableZoneNodes() > 0 then
        return true
    end
    return buyCore and #buyableCoreNodes() > 0
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

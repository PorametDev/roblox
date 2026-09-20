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
-- 0 means "work it out": buy the most expensive one we don't own yet and
-- can actually afford, which is the best available upgrade.
local pickaxeTarget = 0
local equipPickaxes = true
-- Off by default: rolling costs something, and nothing in the state says
-- what, so this shouldn't start spending on its own.
local rollMutations = false

-- Holder entries don't record which pickaxe they're carrying, so remember
-- what we handed out rather than re-sending the same one every pass.
local equippedByHolder = {}

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

function autoUpgrade.SetPickaxeTarget(index)
    pickaxeTarget = index
end

function autoUpgrade.SetEquipPickaxes(state)
    equipPickaxes = state
    if not state then
        table.clear(equippedByHolder)
    end
end

function autoUpgrade.SetRollMutations(state)
    rollMutations = state
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

local function findPickaxe()
    local pickaxes = gameApi.GetPickaxes()

    if pickaxeTarget > 0 then
        for _, pickaxe in ipairs(pickaxes) do
            if pickaxe.index == pickaxeTarget and not pickaxe.owned then
                return pickaxe
            end
        end
        return nil
    end

    -- Most expensive affordable one we don't own: cost tracks quality, so
    -- that's the best upgrade available right now.
    local money = gameApi.GetMoney()
    local best = nil
    for _, pickaxe in ipairs(pickaxes) do
        if not pickaxe.owned and pickaxe.cost <= money then
            if not best or pickaxe.cost > best.cost then
                best = pickaxe
            end
        end
    end
    return best
end

local function tryPickaxe()
    local pickaxe = findPickaxe()
    if not pickaxe then
        return false
    end

    gameApi.BuyPickaxe(pickaxe.index)
    task.wait(0.4)

    for _, current in ipairs(gameApi.GetPickaxes()) do
        if current.index == pickaxe.index and current.owned then
            log("[AutoUpgrade] bought pickaxe #" .. pickaxe.index .. " " .. pickaxe.name)
            return true
        end
    end

    return false
end

-- Hands the best pickaxe we own to every placed miner.
local function equipBestPickaxe()
    local best = gameApi.BestOwnedPickaxe()
    if not best then
        return
    end

    for holderKey in pairs(holders()) do
        if equippedByHolder[holderKey] ~= best.name then
            gameApi.EquipPickaxe(holderKey, best.name)
            equippedByHolder[holderKey] = best.name
            log("[AutoUpgrade] gave " .. best.name .. " to " .. holderKey)
            task.wait(0.3)
        end
    end
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

    if equipPickaxes and enabled then
        equipBestPickaxe()
    end

    if rollMutations and enabled then
        for holderKey in pairs(holders()) do
            if bought >= maxPerPass then
                break
            end
            gameApi.RollMutation(holderKey)
            log("[AutoUpgrade] rolled a mutation on " .. holderKey)
            bought = bought + 1
            task.wait(0.4)
        end
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

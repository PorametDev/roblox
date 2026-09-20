-- Drives the game's own client API rather than its UI. From
-- MineSlotFocusClient the upgrade button sends:
--
--   GameState.SendEvent("MineUpgradeCharacter", <holder key>, <stat>)
--
-- and the state dump showed the holder key is simply the holder's name,
-- with each one's levels sitting right there:
--
--   Holders.M1 = { CharName, CharLevel, CharSpeedLevel, CharMineSpeedLevel, Pickaxe }
--
-- So no teleporting to a holder, no opening the unit screen, no clicking
-- through three tabs.
--
-- This used to fire at a stat and see whether the level moved, which meant
-- it couldn't tell "maxed out" from "can't afford it" and kept poking both
-- forever. MineConfig hands over both numbers the button itself uses -
-- CharMaxLevel / CharSpeedMaxLevel / CharMineSpeedMaxLevel for the cap, and
-- GetCharacter*UpgradeCost for the price - so a stat is now skipped before
-- any remote goes out, and the log says which reason applied.
--
-- The pickaxe half follows MineHUDClient's own pickaxeAlertWanted rule (see
-- game_api.WantedPickaxe): quality is Multiplier, the shop is stocked and
-- restocks, and MineGame.Pickaxes holds counts because six miners need six
-- pickaxes.
return function(import)

local Workspace = game:GetService("Workspace")
local gameApi = import("games/my_anime_mine/game_api")(import)
local teleport = import("core/teleport")
local log = import("core/logger")
local runGuarded = import("core/run_job")(import)

-- The screen labels these Damage / Speed / Mining; the server wants
-- Damage / Speed / MineSpeed.
local STATS = { "Damage", "Speed", "MineSpeed" }

local checkInterval = 20
local maxPerPass = 5
-- "lowest" keeps a miner's three stats level with each other; the others
-- pour everything into one, which is what you want when a specific stat is
-- the bottleneck.
local priority = "lowest"
local keepMoney = 0
local buyPickaxe = true
-- 0 means "work it out": follow the game's own wanted-pickaxe rule.
local pickaxeTarget = 0
local equipPickaxes = true
-- Don't own more pickaxes than there are holders to hold them.
local limitToHolders = true
-- Now that GetMutationRollCost is known this can be switched on safely, but
-- it still spends money on a gamble, so it stays off until asked for.
local rollMutations = false
local mutationTarget = 2
local mutationBudget = 0

local autoUpgrade = {}
local enabled = false
local busy = false
local lastAttempt = 0
-- Says "we're at the cap" once rather than every pass forever.
local reportedCap = false

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

function autoUpgrade.SetKeepMoney(amount)
    keepMoney = math.max(amount, 0)
end

function autoUpgrade.SetBuyPickaxe(state)
    buyPickaxe = state
end

function autoUpgrade.SetPickaxeTarget(index)
    pickaxeTarget = index
end

function autoUpgrade.SetEquipPickaxes(state)
    equipPickaxes = state
end

function autoUpgrade.SetLimitPickaxesToHolders(state)
    limitToHolders = state
end

function autoUpgrade.SetRollMutations(state)
    rollMutations = state
end

-- Stop rolling a holder once its variant is at least this good, so a lucky
-- roll isn't immediately thrown away by the next pass.
function autoUpgrade.SetMutationTarget(multiplier)
    mutationTarget = math.max(multiplier, 1)
end

-- Hard ceiling on a single roll, since the price climbs with the unit.
function autoUpgrade.SetMutationBudget(amount)
    mutationBudget = math.max(amount, 0)
end

local function holders()
    local mine = gameApi.GetMineData()
    return mine and mine.Holders or {}
end

-- Sorted, so passes are reproducible and the log reads the same way twice.
local function holderKeys()
    local keys = {}
    for holderKey, entry in pairs(holders()) do
        if type(entry) == "table" and entry.CharName then
            table.insert(keys, holderKey)
        end
    end
    table.sort(keys)
    return keys
end

local function spendable()
    return gameApi.GetMoney() - keepMoney
end

-- Returns the stat to buy next for this holder, or nil plus the reason.
local function chooseStat(holderKey)
    local budget = spendable()
    local anyLeft = false
    local best = nil

    for _, stat in ipairs(STATS) do
        local info = gameApi.StatInfo(holderKey, stat)
        if info and not info.maxed and info.cost then
            anyLeft = true
            if info.cost <= budget then
                if priority ~= "lowest" then
                    if stat == priority then
                        return { stat = stat, info = info }
                    end
                elseif not best or info.level < best.info.level then
                    best = { stat = stat, info = info }
                end
            end
        end
    end

    if best then
        return best
    end
    return nil, anyLeft and "cost" or "maxed"
end

local function upgradeStats()
    local bought = 0
    local tooExpensive = 0
    local maxed = 0

    -- One stat per holder per lap, so every miner gets a turn before any
    -- miner gets a second one.
    while enabled and bought < maxPerPass do
        local boughtThisLap = 0

        for _, holderKey in ipairs(holderKeys()) do
            if not enabled or bought >= maxPerPass then
                break
            end

            local choice, reason = chooseStat(holderKey)
            if choice then
                gameApi.UpgradeCharacter(holderKey, choice.stat)
                task.wait(0.35)

                local after = gameApi.StatInfo(holderKey, choice.stat)
                if after and after.level > choice.info.level then
                    log("[AutoUpgrade] " .. holderKey .. " " .. choice.stat .. " "
                        .. choice.info.level .. " -> " .. after.level
                        .. "/" .. after.max)
                    bought = bought + 1
                    boughtThisLap = boughtThisLap + 1
                end
            elseif reason == "cost" then
                tooExpensive = tooExpensive + 1
            else
                maxed = maxed + 1
            end
        end

        if boughtThisLap == 0 then
            break
        end
    end

    return bought, tooExpensive, maxed
end

-- A pickaxe is only worth anything while someone is holding it, so there's
-- no point owning more of them than there are holders to put them in.
--
-- Worth being clear about what this costs, because the game's own rule
-- would keep buying past this point: once you own one per holder,
-- WantedPickaxe only ever picks something that BEATS the weakest one
-- currently in use, so each further purchase is a real upgrade to the
-- lineup - it just costs a full price to raise one miner by one step. The
-- cap trades those marginal upgrades for not bleeding money, which is the
-- right trade while research and unit levels are the bottleneck.
--
-- "Holders you can place into" is the unlocked slot count rather than the
-- number currently filled, so buying ahead of Auto Place is still allowed.
local function pickaxeCapReached()
    if not limitToHolders then
        return false
    end

    local cap = gameApi.MinerSlots()
    if cap <= 0 then
        return false
    end

    return gameApi.OwnedPickaxeCount() >= cap
end

local function findPickaxe()
    if pickaxeCapReached() then
        return nil
    end

    if pickaxeTarget > 0 then
        for _, pickaxe in ipairs(gameApi.GetPickaxes()) do
            if pickaxe.index == pickaxeTarget then
                if pickaxe.zoneUnlocked and pickaxe.inStock
                    and pickaxe.cost <= spendable()
                then
                    return pickaxe
                end
                return nil
            end
        end
        return nil
    end

    local wanted = gameApi.WantedPickaxe()
    if wanted and wanted.cost <= spendable() then
        return wanted
    end
    return nil
end

local function ownedCountOf(name)
    for _, pickaxe in ipairs(gameApi.GetPickaxes()) do
        if pickaxe.name == name then
            return pickaxe.ownedCount
        end
    end
    return 0
end

-- MineHUDClient finds the shop at workspace.PickaxesStand["Shop Stand"],
-- which is where its alert billboard hangs.
local function getPickaxeStandPart()
    local stand = Workspace:FindFirstChild("PickaxesStand")
    local shop = stand and stand:FindFirstChild("Shop Stand")
    if not shop then
        return nil
    end
    if shop:IsA("BasePart") then
        return shop
    end
    return shop:FindFirstChildWhichIsA("BasePart", true)
end

-- Same shape as Auto Sell's answer to the same question, for the same
-- reason: MineSellItems turned out to be position-checked server-side and
-- MineBuyPickaxe may well be too. Rather than assume either way, try it
-- from where we stand once, and if the purchase silently fails, teleport
-- and retry - then remember which it was for the rest of the session.
--
-- nil = not yet known, true = must stand at the stand, false = works from
-- anywhere.
local needsProximity = nil

local function sendBuy(pickaxe)
    local before = ownedCountOf(pickaxe.name)
    gameApi.BuyPickaxe(pickaxe.index)
    task.wait(0.4)
    return ownedCountOf(pickaxe.name) > before
end

local function tryPickaxe()
    local pickaxe = findPickaxe()
    if not pickaxe then
        return false
    end

    local bought = false

    if needsProximity ~= true then
        bought = sendBuy(pickaxe)

        if needsProximity == nil then
            needsProximity = not bought
            log("[AutoUpgrade] MineBuyPickaxe "
                .. (bought and "works from anywhere - no teleport needed"
                           or "may need us at the stand - trying that"))
        end
    end

    if not bought then
        local part = getPickaxeStandPart()
        if part then
            teleport.To(part)
            task.wait(0.4)
            bought = sendBuy(pickaxe)
            teleport.Return()

            -- If it only worked after teleporting, proximity really is the
            -- requirement; if it failed both ways it was stock or money,
            -- so don't lock in a teleport we may not need.
            if not bought then
                needsProximity = nil
            end
        else
            log("[AutoUpgrade] can't find workspace.PickaxesStand['Shop Stand']")
        end
    end

    if bought then
        log("[AutoUpgrade] bought pickaxe #" .. pickaxe.index .. " " .. pickaxe.name
            .. " (x" .. pickaxe.multiplier .. ")")
        return true
    end

    log("[AutoUpgrade] pickaxe #" .. pickaxe.index .. " " .. pickaxe.name
        .. " didn't go through (out of stock or too expensive)")
    return false
end

-- Hand out the strongest pickaxes first, one copy per holder. Copies
-- matter: MineGame.Pickaxes stores a count, so owning two of the same
-- pickaxe really does let two miners hold it, and the unit screen's
-- wornBy() exists precisely to show that.
local function equipPickaxesBestFirst()
    local pool = {}
    for _, pickaxe in ipairs(gameApi.GetPickaxes()) do
        for _ = 1, pickaxe.ownedCount do
            table.insert(pool, pickaxe)
        end
    end

    if #pool == 0 then
        return
    end

    -- By Multiplier, not Cost: a later zone's cheap pickaxe can beat an
    -- earlier zone's expensive one.
    table.sort(pool, function(a, b)
        if a.multiplier ~= b.multiplier then
            return a.multiplier > b.multiplier
        end
        return a.name < b.name
    end)

    local keys = holderKeys()

    -- Anything already correctly placed is left alone and its copy taken
    -- out of the pool, so a full pass with nothing to change sends nothing.
    local remaining = {}
    local settled = {}
    local current = holders()

    for _, pickaxe in ipairs(pool) do
        local claimed = false
        for _, holderKey in ipairs(keys) do
            local entry = current[holderKey]
            if not settled[holderKey] and entry and entry.Pickaxe == pickaxe.name then
                settled[holderKey] = true
                claimed = true
                break
            end
        end
        if not claimed then
            table.insert(remaining, pickaxe)
        end
    end

    local nextSpare = 1
    for _, holderKey in ipairs(keys) do
        if not settled[holderKey] then
            local wanted = remaining[nextSpare]
            if not wanted then
                break
            end
            nextSpare = nextSpare + 1

            local entry = current[holderKey]
            gameApi.EquipPickaxe(holderKey, wanted.name)
            log("[AutoUpgrade] " .. holderKey .. " pickaxe "
                .. tostring(entry and entry.Pickaxe or "none") .. " -> " .. wanted.name)
            task.wait(0.3)
        end
    end
end

local function rollMutationsPass(remaining)
    local rolled = 0

    for _, holderKey in ipairs(holderKeys()) do
        if not enabled or rolled >= remaining then
            break
        end

        local variant = gameApi.HolderVariantMult(holderKey)
        local cost = gameApi.MutationRollCost(holderKey)

        if variant < mutationTarget and cost
            and cost <= spendable()
            and (mutationBudget == 0 or cost <= mutationBudget)
        then
            gameApi.RollMutation(holderKey)
            task.wait(0.5)

            local after = gameApi.HolderVariantMult(holderKey)
            log("[AutoUpgrade] " .. holderKey .. " mutation x" .. variant
                .. " -> x" .. after .. " (cost " .. cost .. ")")
            rolled = rolled + 1
        end
    end

    return rolled
end

local function runJob()
    busy = true

    local bought, tooExpensive, maxed = upgradeStats()

    if buyPickaxe and enabled and bought < maxPerPass then
        if pickaxeCapReached() then
            if not reportedCap then
                log("[AutoUpgrade] " .. gameApi.OwnedPickaxeCount()
                    .. " pickaxe(s) for " .. gameApi.MinerSlots()
                    .. " holder(s) - not buying more")
                reportedCap = true
            end
        elseif tryPickaxe() then
            bought = bought + 1
            reportedCap = false
        end
    end

    if equipPickaxes and enabled then
        equipPickaxesBestFirst()
    end

    if rollMutations and enabled and bought < maxPerPass then
        bought = bought + rollMutationsPass(maxPerPass - bought)
    end

    if bought == 0 then
        if tooExpensive > 0 then
            log("[AutoUpgrade] nothing bought - can't afford the next upgrade yet")
        elseif maxed > 0 then
            log("[AutoUpgrade] every stat on every miner is maxed")
        else
            log("[AutoUpgrade] nothing to upgrade (no miners placed?)")
        end
    end

    busy = false
end

-- Skip the turn entirely unless something is genuinely affordable and not
-- already maxed, so a maxed-out or broke account stops taking turns from
-- the others - and stops the game printing "already max mining speed" at
-- the player five times a pass.
function autoUpgrade.HasWork()
    for _, holderKey in ipairs(holderKeys()) do
        if chooseStat(holderKey) then
            return true
        end
    end

    if buyPickaxe and findPickaxe() then
        return true
    end

    -- "Would equipping change anything?" rather than "is equipping on?" -
    -- the latter meant every interval claimed a turn forever.
    if equipPickaxes then
        local owned = 0
        for _, pickaxe in ipairs(gameApi.GetPickaxes()) do
            owned = owned + pickaxe.ownedCount
        end
        if owned > 0 then
            local wearing = 0
            for _, entry in pairs(holders()) do
                if type(entry) == "table" and entry.Pickaxe and entry.Pickaxe ~= "" then
                    wearing = wearing + 1
                end
            end
            if wearing < math.min(owned, #holderKeys()) then
                return true
            end
        end
    end

    if rollMutations then
        for _, holderKey in ipairs(holderKeys()) do
            local cost = gameApi.MutationRollCost(holderKey)
            if gameApi.HolderVariantMult(holderKey) < mutationTarget
                and cost and cost <= spendable()
                and (mutationBudget == 0 or cost <= mutationBudget)
            then
                return true
            end
        end
    end

    return false
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

    -- Guarded: a job that throws would otherwise leave busy set
    -- forever, and one stuck flag blocks every exclusive task.
    runGuarded("AutoUpgrade", runJob, function()
        busy = false
    end)
end

return autoUpgrade

end

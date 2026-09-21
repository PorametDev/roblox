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
-- The ceiling is MaxMinerSlots, not the slots unlocked right now.
--
-- Overnight this sat at "7 pickaxe(s) for 7 holder(s) - not buying more"
-- for six hours while the balance climbed into the quadrillions and two
-- more slots were still there to be bought. Pegging the cap to the
-- CURRENT count makes it self-fulfilling: it stops buying pickaxes for
-- slots that are about to exist, and it never notices when they do.
-- MaxMinerSlots is the real ceiling and never moves.
local function pickaxeCapReached()
    if not limitToHolders then
        return false
    end

    local cap = gameApi.MaxMinerSlots()
    if cap <= 0 then
        cap = gameApi.MinerSlots()
    end
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
-- Holders paired with the pickaxe each should be wearing, strongest with
-- strongest. Shared so HasWork and the job can never disagree about what
-- "already correct" means - they did, and the job simply never ran.
local function plannedPickaxes()
    local pool = gameApi.OwnedPickaxePool()
    local keys = holderKeys()
    if #pool == 0 or #keys == 0 then
        return {}
    end

    table.sort(keys, function(a, b)
        local da = gameApi.HolderBaseDamage(a) or 0
        local db = gameApi.HolderBaseDamage(b) or 0
        if da ~= db then
            return da > db
        end
        return a < b
    end)

    local plan = {}
    for position, holderKey in ipairs(keys) do
        local wanted = pool[position]
        if not wanted then
            break
        end
        table.insert(plan, { holderKey = holderKey, pickaxe = wanted })
    end
    return plan
end

local function pickaxeAssignmentPending()
    local current = holders()
    for _, step in ipairs(plannedPickaxes()) do
        local entry = current[step.holderKey]
        if (entry and entry.Pickaxe or nil) ~= step.pickaxe.name then
            return true
        end
    end
    return false
end

-- Give the strongest pickaxe to the strongest miner, one copy each.
--
-- The previous version marked a holder "settled" if it wore ANY pickaxe we
-- owned, took that copy out of the pool, and never looked at it again. So
-- a miner wearing an Iron stayed on Iron indefinitely while eighty-five
-- Sapphires sat unused - which is exactly what the unit screen showed.
-- "Already wearing something we own" is not the same question as "already
-- wearing the best one available", and only the second one matters.
--
-- Pairing best-with-best rather than handing them out in holder order:
-- the pickaxe is a multiplier on the character's damage, so the same
-- pickaxe is worth more on a stronger miner.
local function equipPickaxesBestFirst()
    local current = holders()

    for _, step in ipairs(plannedPickaxes()) do
        local holderKey, wanted = step.holderKey, step.pickaxe
        local entry = current[holderKey]
        local worn = entry and entry.Pickaxe or nil

        if worn ~= wanted.name then
            gameApi.EquipPickaxe(holderKey, wanted.name)
            task.wait(0.3)

            -- Confirm rather than assume: the server can refuse, and a
            -- silent refusal here is how this went unnoticed all night.
            local after = holders()[holderKey]
            local nowWorn = after and after.Pickaxe or nil
            if nowWorn == wanted.name then
                log("[AutoUpgrade] " .. holderKey .. " pickaxe "
                    .. tostring(worn or "none") .. " -> " .. wanted.name)
            else
                log("[AutoUpgrade] " .. holderKey .. " wouldn't take "
                    .. wanted.name .. " (still " .. tostring(nowWorn or "none") .. ")")
            end
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
                    .. " pickaxe(s) for " .. gameApi.MaxMinerSlots()
                    .. " possible holder(s) - not buying more")
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

    -- "Would equipping change anything?" - and that has to mean the same
    -- pairing the job itself would make. Counting how many miners wear
    -- SOMETHING said no while a miner on an Iron had eighty-five Sapphires
    -- going spare, so the job was never given a turn to fix it.
    if equipPickaxes and pickaxeAssignmentPending() then
        return true
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

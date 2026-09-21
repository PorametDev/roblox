-- Talks to the game's own client modules instead of driving its UI.
--
-- Decompiling PlayerScripts.UI.MineGame showed every action goes through
-- one wrapper - GameState.SendEvent(name, ...) - and that the client
-- already holds the full game state in GameState.GetData2().MineGame. So
-- there's no need to open a menu to read anything, or to click a button to
-- do anything:
--
--   Take All        SendEvent("MineTakeChest")            -- no arguments
--   Sell            SendEvent("MineSellItems", {keys})
--   Hold a miner    SendEvent("MineEquipSlot", key)
--   Buy research    SendEvent("MineBuySkill", nodeId, family)
--   Upgrade a unit  SendEvent("MineUpgradeCharacter", key, stat)
--   Buy a pickaxe   SendEvent("MineBuyPickaxe", tierIndex)
--   Give one out    SendEvent("MineEquipPickaxe", holderKey, pickaxeName)
--   Roll a mutation SendEvent("MineRollMutation", holderKey)
--
-- The unit screen's fourth tab, Enchants, has no event of its own in any
-- of the decompiled clients - only panel-visibility code - so there's
-- nothing to automate there yet.
--
-- The same dump also explained a long-standing mystery: the game binds its
-- buttons to MouseButton1Down, not Activated, which is why
-- firesignal(Activated) never once reached a handler.
--
-- Note these still go through the game's own remotes, so any server-side
-- position checks apply exactly as before - this removes the UI, not the
-- rules.
-- Deliberately a singleton, for two reasons. `import` caches the factory
-- below rather than its result, so each caller would otherwise get a table
-- of its own: the settings on it (SetProtectUsefulUnits) would apply only
-- to whichever copy the menu happened to hold, and the game's modules
-- would be required once per caller instead of once.
local instance

return function(import)

if instance then
    return instance
end


local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Workspace = game:GetService("Workspace")
local log = import("core/logger")

local api = {}
-- Never sell a character good enough to be worth placing. Off would mean
-- reverting to the behaviour that sold the best unit in the inventory.
local protectUsefulUnits = true
-- One line, once a session.
local reportedHolderShape = false
local gameState, mineInventory, mineConfig, mineStock, items, indexRewards
local loadFailed = false

local function modules()
    if gameState or loadFailed then
        return gameState ~= nil
    end

    local ok, err = pcall(function()
        local moduleFolder = ReplicatedStorage:WaitForChild("Modules", 5)
        gameState = require(moduleFolder.GameState)
        mineInventory = require(moduleFolder.MineInventory)
        mineConfig = require(moduleFolder.MineConfig)
        -- The pickaxe shop is a rotating stock list, not a fixed catalogue,
        -- so buying needs MineStock as much as it needs MineConfig.
        mineStock = require(moduleFolder.MineStock)
        items = require(moduleFolder.Items)
        indexRewards = require(moduleFolder.MineIndexRewardsConfig)
    end)

    if not ok then
        loadFailed = true
        log("[GameAPI] couldn't load the game's modules: " .. tostring(err))
        return false
    end

    return true
end

function api.SetProtectUsefulUnits(state)
    protectUsefulUnits = state
end

function api.IsReady()
    return modules()
end

-- The whole player record. MineStock and the index rewards want this rather
-- than the MineGame sub-table, so both are exposed.
function api.GetData()
    if not modules() then
        return nil
    end

    local ok, data = pcall(gameState.GetData2)
    if not ok then
        return nil
    end
    return data
end

-- Everything the client knows about the mine: Chest contents, inventory,
-- plot state. Reading this replaces opening menus to look at things.
function api.GetMineData()
    local data = api.GetData()
    return data and data.MineGame or nil
end

-- Money sits on Data2 itself rather than under MineGame.
function api.GetMoney()
    local data = api.GetData()
    return data and tonumber(data.Money) or 0
end

-- MineConfig.Pickaxes is a plain array and MineBuyPickaxe takes the array
-- index, so position in this list IS the argument. The shop hides free,
-- robux-only and unstocked entries, so do the same - they can't be bought
-- with cash.
--
-- Three things the first version of this got wrong, all of them read back
-- out of MineHUDClient's shop renderer:
--
--   * quality is Multiplier, not Cost - a later zone's cheap pickaxe can
--     beat an earlier zone's expensive one
--   * the shop is stocked, not a permanent catalogue: MineStock.GetRemaining
--     decides whether the Buy button does anything at all
--   * a pickaxe needs its ZoneReq unlocked, and MineGame.Pickaxes holds a
--     COUNT, not a flag - you can own several of the same one
function api.GetPickaxes()
    if not modules() then
        return {}
    end

    local data = api.GetData()
    local mine = data and data.MineGame
    local owned = (mine and mine.Pickaxes) or {}
    local unlocked = (mine and mine.UnlockedZones) or {}
    local list = {}

    local ok = pcall(function()
        for index, def in ipairs(mineConfig.Pickaxes) do
            local buyableWithCash = not (mineConfig.IsPickaxeFree(def)
                or def.RobuxOnly or type(def.Stock) ~= "table")

            if buyableWithCash then
                local remaining = nil
                if data then
                    local gotStock, value = pcall(mineStock.GetRemaining, data, def.Name)
                    remaining = gotStock and value or nil
                end

                local zoneOpen = unlocked[def.ZoneReq] and true or false
                table.insert(list, {
                    index = index,
                    name = def.Name,
                    cost = tonumber(def.Cost) or math.huge,
                    multiplier = tonumber(def.Multiplier) or 1,
                    zoneReq = def.ZoneReq,
                    zoneUnlocked = zoneOpen,
                    ownedCount = math.floor(tonumber(owned[def.Name]) or 0),
                    -- nil means unlimited; the shop only blocks on <= 0.
                    stock = remaining,
                    inStock = (remaining == nil) or (remaining > 0),
                })
            end
        end
    end)

    if not ok then
        return {}
    end

    return list
end

-- A straight port of MineHUDClient's pickaxeAlertWanted: the game itself
-- decides "is a better pickaxe worth buying right now", and copying that
-- beats inventing a rule.
--
-- It works out the WORST multiplier that would still be in use once every
-- non-Hauler miner is holding something, then looks for a shop entry that
-- beats it. That's why owning one great pickaxe doesn't stop it buying
-- more: six miners need six pickaxes.
function api.WantedPickaxe()
    if not modules() then
        return nil
    end

    local data = api.GetData()
    local mine = data and data.MineGame
    if not mine then
        return nil
    end

    local wanted = nil
    pcall(function()
        local minerCount = 0
        for _, holder in pairs(mine.Holders or {}) do
            if type(holder) == "table" and holder.CharName then
                local itemData = items.GetItemData(holder.CharName)
                if itemData and itemData.MineRole ~= "Hauler" then
                    minerCount = minerCount + 1
                end
            end
        end

        if minerCount <= 0 then
            return
        end

        -- One entry per owned copy, capped at the number of miners - copies
        -- beyond that can't be worn by anyone.
        local inUse = {}
        for _, def in ipairs(mineConfig.Pickaxes) do
            if not mineConfig.IsPickaxeFree(def) then
                local count = math.floor(tonumber((mine.Pickaxes or {})[def.Name]) or 0)
                for _ = 1, math.min(count, minerCount) do
                    table.insert(inUse, tonumber(def.Multiplier) or 1)
                end
            end
        end
        table.sort(inUse, function(a, b) return a > b end)

        -- What the last miner ends up holding: either the weakest owned
        -- pickaxe that still gets worn, or the free starter one.
        local weakestInUse = minerCount <= #inUse
            and inUse[minerCount]
            or (tonumber(mineConfig.Pickaxes[1].Multiplier) or 1)

        local money = tonumber(data.Money) or 0
        for _, pickaxe in ipairs(api.GetPickaxes()) do
            if pickaxe.zoneUnlocked and pickaxe.inStock
                and pickaxe.multiplier > weakestInUse
                and pickaxe.cost <= money
            then
                if not wanted or pickaxe.multiplier > wanted.multiplier then
                    wanted = pickaxe
                end
            end
        end
    end)

    return wanted
end

-- MineInventory.ChestEntries is what the chest screen itself counts, so
-- this matches the "397/126.3K Items" readout exactly rather than guessing
-- at the shape of MineGame.Chest.
function api.ChestCount()
    if not modules() then
        return nil
    end

    local mine = api.GetMineData()
    if not mine then
        return nil
    end

    local ok, entries = pcall(mineInventory.ChestEntries, mine)
    if not ok or type(entries) ~= "table" then
        return nil
    end

    local total = 0
    for _, entry in ipairs(entries) do
        total = total + (tonumber(entry.Count) or 0)
    end
    return total
end

-- The chest has a ceiling, and once it's hit everything the miners dig is
-- thrown away - so this is a limit worth knowing about, not just a number
-- on a bar.
function api.ChestCapacity()
    if not modules() then
        return nil
    end

    local mine = api.GetMineData()
    if not mine then
        return nil
    end

    local ok, capacity = pcall(mineConfig.GetChestCapacityFor, mine, 0)
    return ok and tonumber(capacity) or nil
end

-- Take All is a no-op on an empty chest - the game's own button checks
-- this before sending.
function api.ChestHasItems()
    local mine = api.GetMineData()
    return mine ~= nil and next(mine.Chest or {}) ~= nil
end

-- Miner slot M<i> exists only while i <= MinerSlots; past that the holder
-- is bought-but-not-yet-owned and every interaction with it is refused.
-- Reading this beats walking over to a holder to see which ProximityPrompt
-- text it shows.
function api.MinerSlots()
    if not modules() then
        return 0
    end

    local data = api.GetData()
    local mine = data and data.MineGame
    if not mine then
        return 0
    end

    local ok, count = pcall(function()
        return tonumber(mine.MinerSlots or data.MinerSlots or mineConfig.BaseMinerSlots) or 0
    end)
    return (ok and count) or 0
end

-- Miners actually standing on a holder, Haulers excluded - the same count
-- MineHUDClient uses to decide how many pickaxes can be in use at once,
-- since a Hauler doesn't swing one.
function api.PlacedMinerCount()
    if not modules() then
        return 0
    end

    local mine = api.GetMineData()
    if not mine then
        return 0
    end

    local count = 0
    pcall(function()
        for _, holder in pairs(mine.Holders or {}) do
            if type(holder) == "table" and holder.CharName then
                local itemData = items.GetItemData(holder.CharName)
                if itemData and itemData.MineRole ~= "Hauler" then
                    count = count + 1
                end
            end
        end
    end)
    return count
end

-- Total pickaxes owned across every type, counting duplicates. The free
-- starter is excluded because it isn't something we bought.
function api.OwnedPickaxeCount()
    local total = 0
    for _, pickaxe in ipairs(api.GetPickaxes()) do
        total = total + pickaxe.ownedCount
    end
    return total
end

function api.MaxMinerSlots()
    if not modules() then
        return 0
    end
    local ok, count = pcall(function() return tonumber(mineConfig.MaxMinerSlots) or 0 end)
    return (ok and count) or 0
end

-- true / false for a miner slot; nil for anything else (hauler slots
-- aren't described in MineConfig, so those still have to be judged from
-- the prompt on the holder itself).
function api.IsSlotUnlocked(holderKey)
    local index = tostring(holderKey):match("^M(%d+)$")
    if not index then
        return nil
    end
    return tonumber(index) <= api.MinerSlots()
end

local function send(...)
    if not modules() then
        return false
    end

    local ok, err = pcall(gameState.SendEvent, ...)
    if not ok then
        log("[GameAPI] SendEvent failed: " .. tostring(err))
    end
    return ok
end

function api.TakeChest()
    return send("MineTakeChest")
end

-- The sell menu builds its list from MineInventory.Collect and sends the
-- keys of everything ticked; an entry counts as sellable when it has both
-- a count and a worth, which is the same test the menu applies.
function api.SellableKeys()
    if not modules() then
        return {}
    end

    local mine = api.GetMineData()
    if not mine then
        return {}
    end

    local ok, entries = pcall(mineInventory.Collect, mine, "All", mineInventory.KindOrder.OreFirst)
    if not ok or type(entries) ~= "table" then
        return {}
    end

    -- Anything at least as good as the weakest character currently on a
    -- holder is upgrade material, not surplus. Without this a 305.2K Gear
    -- 5 Lufy went to the buyer while level-38 Warped Ninjas kept mining,
    -- because it hadn't been placed yet and so counted as stock.
    --
    -- Ores are never affected; this only ever spares Character entries.
    local floorDamage = nil
    if protectUsefulUnits then
        for holderKey, holder in pairs(mine.Holders or {}) do
            if type(holder) == "table" and holder.CharName then
                local base = api.HolderBaseDamage(holderKey)
                if base and (not floorDamage or base < floorDamage) then
                    floorDamage = base
                end
            end
        end
    end

    local keys = {}
    for _, entry in pairs(entries) do
        local count = entry.SellCount or entry.Count or 0
        if count > 0 and (entry.Worth or 0) > 0 and entry.Key then
            local spare = false
            if floorDamage and entry.Kind == "Character" then
                local base = api.CharacterBaseDamage(entry.Name)
                spare = base ~= nil and base >= floorDamage
            end

            if not spare then
                table.insert(keys, entry.Key)
            end
        end
    end
    return keys
end

function api.SellItems(keys)
    if #keys == 0 then
        return false
    end
    return send("MineSellItems", keys)
end

-- MineHotbarClient's number-key handler calls equipSlot(tostring(slot)),
-- and MineGame.Hotbar is keyed by those strings - so the slot is "3", not
-- 3. Sending the number meant the hold silently never happened, and Auto
-- Place would pick a miner up, fail to hold anything, and leave the
-- holder empty.
--
-- Passing "" unequips, which is the same call the game makes when you tap
-- the slot you're already holding.
function api.EquipSlot(slot)
    return send("MineEquipSlot", slot == "" and "" or tostring(slot))
end

-- Which hotbar slot is in hand, straight from the game rather than
-- inferred from a ProximityPrompt's label. The prompt only updates when
-- you're standing next to a holder; this is true anywhere.
function api.EquippedSlot()
    if not modules() then
        return nil
    end

    local mine = api.GetMineData()
    if not mine then
        return nil
    end

    local ok, slot = pcall(mineInventory.EquippedSlot, mine)
    return ok and slot or nil
end

-- equipSlot refuses on both of these before it sends anything, so they're
-- worth checking rather than firing and wondering.
function api.HotbarHasSlot(slot)
    local mine = api.GetMineData()
    return mine ~= nil and (mine.Hotbar or {})[tostring(slot)] ~= nil
end

-- The usable part of the hotbar can be smaller than what's rendered.
function api.IsSlotWithinCap(slot)
    if not modules() then
        return true
    end
    local ok, within = pcall(mineInventory.SlotWithinCap, tostring(slot))
    if not ok then
        return true
    end
    return within and true or false
end

function api.BuyPickaxe(tierIndex)
    return send("MineBuyPickaxe", tierIndex)
end

function api.EquipPickaxe(holderKey, pickaxeName)
    return send("MineEquipPickaxe", holderKey, pickaxeName)
end

function api.RollMutation(holderKey)
    return send("MineRollMutation", holderKey)
end

-- Every pickaxe we can actually put on a miner, strongest first, one entry
-- per copy owned.
--
-- GetPickaxes deliberately lists only what the SHOP will sell for cash, so
-- it hides the free starter pickaxes and the Robux ones. That's right for
-- buying and wrong for equipping: a pickaxe you were given still works.
function api.OwnedPickaxePool()
    if not modules() then
        return {}
    end

    local mine = api.GetMineData()
    local owned = (mine and mine.Pickaxes) or {}
    local pool = {}

    pcall(function()
        for index, def in ipairs(mineConfig.Pickaxes) do
            local count = math.floor(tonumber(owned[def.Name]) or 0)

            -- Free ones are always available and never appear in the owned
            -- table, but they're the weakest, so they can only ever end up
            -- as filler once the real ones run out.
            local free = mineConfig.IsPickaxeFree(def) and true or false
            if free and count <= 0 then
                count = api.MaxMinerSlots()
            end

            for _ = 1, count do
                table.insert(pool, {
                    index = index,
                    name = def.Name,
                    multiplier = tonumber(def.Multiplier) or 1,
                    free = free,
                })
            end
        end
    end)

    table.sort(pool, function(a, b)
        if a.multiplier ~= b.multiplier then
            return a.multiplier > b.multiplier
        end
        return a.name < b.name
    end)

    return pool
end

-- Highest cost among the ones we own: cost tracks quality here too.
function api.BestOwnedPickaxe()
    local best = nil
    for _, pickaxe in ipairs(api.GetPickaxes()) do
        if pickaxe.owned and (not best or pickaxe.cost > best.cost) then
            best = pickaxe
        end
    end
    return best
end

-- The Inventory screen's "Equip Best" button, which fills the hotbar with
-- the strongest miners you own:
--
--   SendEvent("MineEquipBest")     -- no arguments at all
--
-- This is the answer to "why won't it place the better unit": Auto Place
-- can only place what's ON the hotbar, and the strongest miners often
-- aren't there. Rather than reimplement the ranking and the
-- MineAssignHotbar juggling, ask the game to do it - its own button is
-- one argument-less remote.
function api.EquipBest()
    return send("MineEquipBest")
end

function api.BuySkill(zoneKey, family)
    return send("MineBuySkill", zoneKey, family)
end

-- The research tree is not "a zone has families you can pour money into".
-- MineSkillTreeClient's buy button refuses unless the specific NODE is both
-- open (its parents are done) and not maxed - and a family spans several
-- nodes down the tree. Sending a family name with no open node just gets
-- dropped, which is why blind buying looked like it did nothing.
function api.ZoneKeys()
    if not modules() then
        return {}
    end
    local ok, keys = pcall(function() return mineConfig.ZoneKeys end)
    return (ok and type(keys) == "table") and keys or {}
end

function api.UnlockedZones()
    local mine = api.GetMineData()
    local unlocked = mine and mine.UnlockedZones or {}

    local list = {}
    for _, zoneKey in ipairs(api.ZoneKeys()) do
        if unlocked[zoneKey] then
            table.insert(list, zoneKey)
        end
    end
    return list
end

-- Team power: the tree's third gate, and the one nothing else hints at.
-- Past the parents-are-done check and the price, MineSkillTreeClient also
-- greys the Buy button out with "Needs X team power (you have Y)" when
--
--   MineConfig.GetSkillPowerReq(zone, family, nextLevel) > MinePower
--
-- MinePower is an attribute on the local player, kept up to date by the
-- server. The plot's own level - the NodeLevel family, which is what makes
-- rocks tougher and ore worth more - is gated this way, so a research pass
-- that ignored it would keep firing at a node the server always refuses.
function api.MinePower()
    local player = game:GetService("Players").LocalPlayer
    return tonumber(player and player:GetAttribute("MinePower")) or 0
end

local function skillPowerReq(zoneKey, family, nextLevel)
    if type(mineConfig.GetSkillPowerReq) ~= "function" then
        return nil
    end
    local ok, req = pcall(mineConfig.GetSkillPowerReq, zoneKey, family, nextLevel)
    return ok and tonumber(req) or nil
end

-- Every node the tree can show for a zone, annotated with everything that
-- decides whether buying it will work.
function api.SkillNodes(zoneKey)
    if not modules() then
        return {}
    end

    local mine = api.GetMineData()
    local skills = (mine and mine.Skills and mine.Skills[zoneKey]) or {}
    local power = api.MinePower()
    local list = {}

    local ok, nodes = pcall(mineConfig.GetSkillNodes, zoneKey)
    if not ok or type(nodes) ~= "table" then
        return list
    end

    for _, node in ipairs(nodes) do
        -- One pcall PER NODE. Wrapping the whole loop in a single pcall
        -- meant one awkward family could throw and hand back an empty
        -- list, which reads identically to "there is nothing to buy" -
        -- and Auto Research would then quietly never take a turn again.
        local built
        local gotNode = pcall(function()
            local level = tonumber(skills[node.Family]) or 0
            local max = tonumber(mineConfig.GetSkillMax(zoneKey, node.Family)) or 0
            local cost = nil
            if level < max then
                cost = tonumber(mineConfig.GetSkillCost(zoneKey, level, node.Family))
            end

            local powerReq = skillPowerReq(zoneKey, node.Family, level + 1)

            built = {
                zoneKey = zoneKey,
                id = node.Id,
                family = node.Family,
                row = node.Row or 0,
                col = node.Col or 0,
                level = level,
                max = max,
                cost = cost,
                powerReq = powerReq,
                power = power,
                powerOk = (powerReq == nil) or (power >= powerReq),
                maxed = mineConfig.IsSkillNodeMaxed(skills, node) and true or false,
                open = mineConfig.IsSkillNodeOpen(skills, node) and true or false,
            }
        end)

        if gotNode and built then
            table.insert(list, built)
        end
    end

    return list
end

-- Zones. MineZoneBoardClient binds every row on the plot's board - owned
-- or not, priced or "Locked" - to the same single event:
--
--   GameState.SendEvent("MineSelectZone", zoneKey)
--
-- So switching to a zone you own and buying the next one are the same
-- call, and the server decides which one it was. MineGame.CurrentZone is
-- an INDEX into MineConfig.ZoneKeys, not a key.
function api.CurrentZoneIndex()
    local mine = api.GetMineData()
    return mine and tonumber(mine.CurrentZone) or 1
end

function api.CurrentZoneKey()
    local keys = api.ZoneKeys()
    return keys[api.CurrentZoneIndex()] or keys[1]
end

function api.SelectZone(zoneKey)
    return send("MineSelectZone", zoneKey)
end

function api.ZoneDisplayName(zoneKey)
    if not modules() then
        return zoneKey
    end
    local ok, zone = pcall(function() return mineConfig.Zones[zoneKey] end)
    return (ok and zone and zone.DisplayName) or zoneKey
end

-- How far the zone's research tree has been taken, which is what gates
-- the next zone.
function api.ZoneResearchProgress(zoneKey)
    if not modules() then
        return 0, 0
    end

    local mine = api.GetMineData()
    if not mine then
        return 0, 0
    end

    local ok, done, total = pcall(mineConfig.GetZoneResearchProgress, mine.Skills, zoneKey)
    if not ok then
        return 0, 0
    end
    return tonumber(done) or 0, tonumber(total) or 0
end

-- The unlock price isn't in any client config - the board is a physical
-- SurfaceGui on the plot with the number already rendered into it, so the
-- only way to read it is to read the sign. Rows are ZoneRow<i>, matching
-- MineConfig.ZoneKeys by position.
function api.ZoneBoardPriceText(zoneIndex)
    local plots = Workspace:FindFirstChild("MineWorld")
    plots = plots and plots:FindFirstChild("Plots")
    if not plots then
        return nil
    end

    local userId = game:GetService("Players").LocalPlayer.UserId
    local myPlot = nil
    for _, plot in ipairs(plots:GetChildren()) do
        if plot:GetAttribute("OwnerUserId") == userId then
            myPlot = plot
            break
        end
    end
    if not myPlot then
        return nil
    end

    local board = myPlot:FindFirstChild("ZoneBoard")
    local gui = board and board:FindFirstChild("ZoneBoardGui")
    local root = gui and gui:FindFirstChild("Root")
    local list = root and root:FindFirstChild("List")
    local row = list and list:FindFirstChild("ZoneRow" .. zoneIndex)
    if not row then
        return nil
    end

    for _, descendant in ipairs(row:GetDescendants()) do
        if descendant:IsA("TextLabel") and descendant.Text ~= "" then
            return descendant.Text
        end
    end
    return nil
end

-- The plot's own level for a zone, straight from the same helper the tree
-- uses to describe it.
function api.NodeLevel(zoneKey)
    if not modules() then
        return nil
    end

    local mine = api.GetMineData()
    if not mine then
        return nil
    end

    local ok, level = pcall(mineConfig.GetNodeLevel, mine.Skills, zoneKey)
    return ok and tonumber(level) or nil
end

-- The Core tab is a separate tree with a separate remote per upgrade -
-- MineConfig.CoreUpgradeById[family].Event, sent with no arguments at all.
function api.CoreNodes()
    if not modules() then
        return {}
    end

    local mine = api.GetMineData()
    if not mine then
        return {}
    end

    local list = {}
    pcall(function()
        for _, node in ipairs(mineConfig.CoreNodes or {}) do
            local upgrade = mineConfig.CoreUpgradeById[node.Family]
            local level = tonumber(mineConfig.GetCoreLevel(mine, node.Family)) or 0
            local cost = nil
            if upgrade and type(upgrade.Cost) == "function" then
                local ok, value = pcall(upgrade.Cost, level)
                cost = ok and tonumber(value) or nil
            end

            table.insert(list, {
                id = node.Id,
                family = node.Family,
                row = node.Row or 0,
                level = level,
                cost = cost,
                event = upgrade and upgrade.Event or nil,
                maxed = mineConfig.IsCoreNodeMaxed(mine, node) and true or false,
                open = mineConfig.IsCoreNodeOpen(mine, node) and true or false,
            })
        end
    end)

    return list
end

function api.BuyCore(eventName)
    return send(eventName)
end

-- The unit screen labels the stat "Mining" but sends "MineSpeed".
function api.UpgradeCharacter(characterKey, stat)
    return send("MineUpgradeCharacter", characterKey, stat == "Mining" and "MineSpeed" or stat)
end

-- What the unit screen prints on each upgrade button: the current level,
-- the cap, and the price of the next one. Having the real price means
-- "nothing happened" can be reported as "too expensive" or "maxed out"
-- instead of guessing, and stops money being thrown at a maxed stat.
local STAT_FIELDS = {
    Damage = { level = "GetHolderLevel", max = "CharMaxLevel", cost = "GetCharacterUpgradeCost" },
    Speed = { level = "GetHolderSpeedLevel", max = "CharSpeedMaxLevel", cost = "GetCharacterSpeedUpgradeCost" },
    MineSpeed = { level = "GetHolderMineSpeedLevel", max = "CharMineSpeedMaxLevel", cost = "GetCharacterMineSpeedUpgradeCost" },
}

function api.StatInfo(holderKey, stat)
    if not modules() then
        return nil
    end

    local field = STAT_FIELDS[stat]
    local mine = api.GetMineData()
    local holder = mine and (mine.Holders or {})[holderKey]
    if not (field and holder and holder.CharName) then
        return nil
    end

    local info = nil
    pcall(function()
        local itemData = items.GetItemData(holder.CharName)
        if not itemData then
            return
        end

        local level = tonumber(mineConfig[field.level](holder)) or 0
        local max = tonumber(mineConfig[field.max]) or 0
        info = {
            level = level,
            max = max,
            maxed = level >= max,
            cost = level < max
                and tonumber(mineConfig[field.cost](level, itemData))
                or nil,
        }
    end)

    return info
end

-- A character's damage BEFORE any level, pickaxe, mutation or enchant
-- multiplier - the number printed on its hotbar card.
--
-- This is the right basis for "is that unit better than this one", because
-- levels are bought and mutations are rolled, but a character's base
-- damage is fixed. A level-56 Warped Ninja out-hits a level-1 Gear 5 Lufy
-- today and loses to it badly once both are levelled, so comparing what
-- they currently hit for picks the wrong one permanently.
function api.CharacterBaseDamage(charName)
    if not modules() or type(charName) ~= "string" or charName == "" then
        return nil
    end

    local ok, damage = pcall(function()
        local itemData = items.GetItemData(charName)
        if not itemData then
            return nil
        end
        return tonumber(mineConfig.GetCharacterDamage(itemData))
    end)

    return ok and damage or nil
end

-- The same figure for whoever is standing on a holder, INCLUDING its
-- mutation - which is what makes it comparable with a hotbar card.
--
-- A card's number already has the stack's mutation baked in, which is how
-- four "Whale Island Kid" entries can read 72.5B, 45.8B, 42B and 7.6B.
-- Comparing that against a name-only lookup for the placed miner was
-- comparing two different things again. Level and pickaxe are still left
-- out on purpose: levels are bought and pickaxes move, so neither says
-- anything about which unit is better to own.
function api.HolderBaseDamage(holderKey)
    local mine = api.GetMineData()
    local holder = mine and (mine.Holders or {})[holderKey]
    if not (holder and holder.CharName) then
        return nil
    end

    -- Derived by dividing the level and pickaxe back out of the holder's
    -- real damage, rather than rebuilt from the character name.
    --
    -- MineSlotFocusClient computes a holder's damage as
    --     base x pickaxe x level x variant x enchant
    -- so dividing by the two transferable factors leaves base x variant x
    -- enchant, which is what a hotbar card shows.
    --
    -- Multiplying base by GetVariantMult(GetHolderVariant(...)) was meant
    -- to do the same and didn't: it came back 1 for every holder, so a
    -- Whale Island Kid worth 74.4B read as its bare 7.6B base. Auto Place
    -- then swapped the 74.4B stack in, measured 7.6B, decided it still
    -- needed upgrading, and did it again - the swap loop in the log.
    local derived = nil
    pcall(function()
        local shown = tonumber(mineConfig.GetHolderDamage(holder))
        if not shown or shown <= 0 then
            return
        end

        local levelMult = tonumber(mineConfig.GetCharacterLevelMultiplier(
            mineConfig.GetHolderLevel(holder))) or 1
        local pickaxe = mineConfig.GetHolderPickaxe(holder)
        local pickMult = tonumber(pickaxe and pickaxe.Multiplier) or 1

        if levelMult > 0 and pickMult > 0 then
            derived = shown / (levelMult * pickMult)
        end
    end)

    if derived and derived > 0 then
        return derived
    end

    -- Both routes to a holder's mutation have now failed - GetVariantMult
    -- returns 1 and dividing GetHolderDamage gives the bare base - so say
    -- once what a holder record actually contains. Auto Place works around
    -- this by remembering what it placed; this is so the underlying field
    -- can be found and used properly.
    if not reportedHolderShape then
        reportedHolderShape = true
        local fields = {}
        for key, value in pairs(holder) do
            table.insert(fields, tostring(key) .. "=" .. tostring(value))
        end
        table.sort(fields)
        log("[GameAPI] holder " .. holderKey .. " fields: " .. table.concat(fields, " "))
    end

    -- Fallback for when GetHolderDamage isn't available.
    local base = api.CharacterBaseDamage(holder.CharName)
    if not base then
        return nil
    end
    return base * (api.HolderVariantMult(holderKey) or 1)
end

-- MineConfig.GetMutationRollCost(item, mineGame) - the number the Roll
-- button shows. This was the missing piece that kept mutation rolling
-- switched off by default.
function api.MutationRollCost(holderKey)
    if not modules() then
        return nil
    end

    local mine = api.GetMineData()
    local holder = mine and (mine.Holders or {})[holderKey]
    if not (holder and holder.CharName) then
        return nil
    end

    local ok, cost = pcall(function()
        return tonumber(mineConfig.GetMutationRollCost(items.GetItemData(holder.CharName), mine))
    end)
    return ok and cost or nil
end

-- How good a holder's current mutation is, so a reroll can be aimed at
-- improving it rather than fired blindly.
function api.HolderVariantMult(holderKey)
    if not modules() then
        return 1
    end

    local mine = api.GetMineData()
    local holder = mine and (mine.Holders or {})[holderKey]
    if not holder then
        return 1
    end

    local ok, mult = pcall(function()
        return tonumber(mineConfig.GetVariantMult(mineConfig.GetHolderVariant(holder)))
    end)
    return (ok and mult) or 1
end

-- MineIndexRewardsConfig.ClaimableTiers is what drives the red badge on the
-- Index button; .Total is the number waiting to be collected.
function api.ClaimableIndexTiers()
    if not modules() then
        return 0
    end

    local mine = api.GetMineData()
    if not mine then
        return 0
    end

    local ok, result = pcall(indexRewards.ClaimableTiers, mine)
    if not ok or type(result) ~= "table" then
        return 0
    end
    return tonumber(result.Total) or 0
end

-- Index rewards. MineIndexClient hides the claim behind a config lookup
-- rather than a literal, which is why grepping the first six decompiled
-- scripts for an event name turned up nothing:
--
--   GameState.SendEvent(MineIndexRewardsConfig.Events.Claim,
--                       category, tierKey, rewardIndex)
--
-- A tier is claimable when it's Reached, not already Claimed, and that
-- particular reward slot isn't in ClaimedRewards. The client also spaces
-- its own claims 0.6s apart, so this does too.
--
-- "Held" names feed into State because owning a character counts towards
-- the index whether it's in storage or standing on a holder.
local function heldCharacterNames(mine)
    local held = {}

    for stackKey, count in pairs(mine.Characters or {}) do
        if type(count) == "number" and count > 0 then
            local ok, name = pcall(mineConfig.ParseCharStack, stackKey)
            if ok and type(name) == "string" then
                held[name] = true
            end
        end
    end

    for _, holder in pairs(mine.Holders or {}) do
        if type(holder) == "table" and type(holder.CharName) == "string" then
            held[holder.CharName] = true
        end
    end

    return held
end

-- The Index tabs are every zone key plus two fixed extras. The claim
-- event wants a CATEGORY key, which Category(tab) resolves from a tab -
-- but when that lookup gives nothing the tab key itself is the sensible
-- fallback rather than skipping the tab silently, which is what the first
-- version did.
local EXTRA_INDEX_TABS = { "Limited", "Exclusive" }

local function indexTabKeys()
    local tabs = {}
    for _, zoneKey in ipairs(api.ZoneKeys()) do
        table.insert(tabs, zoneKey)
    end
    for _, extra in ipairs(EXTRA_INDEX_TABS) do
        table.insert(tabs, extra)
    end
    return tabs
end

local function indexCategoryKey(tabKey)
    local ok, category = pcall(indexRewards.Category, tabKey)
    if ok and type(category) == "table" and category.Key then
        return category.Key
    end
    return tabKey
end

-- Every reward sitting there waiting, as { category, tierKey, index }.
--
-- ClaimableTiers().ByKey is keyed by tab - the same table that drives the
-- red badge on each tab - so it says outright which tabs have anything,
-- and nothing has to be enumerated speculatively.
function api.ClaimableIndexRewards()
    if not modules() then
        return {}, "modules not loaded"
    end

    local mine = api.GetMineData()
    if not mine then
        return {}, "no mine data"
    end

    if indexRewards.Enabled ~= true then
        return {}, "index rewards are disabled in this game build"
    end

    local ok, tiers = pcall(indexRewards.ClaimableTiers, mine)
    if not ok or type(tiers) ~= "table" then
        return {}, "ClaimableTiers failed"
    end

    local total = tonumber(tiers.Total) or 0
    if total <= 0 then
        return {}, "nothing claimable"
    end

    local byKey = tiers.ByKey or {}
    local list = {}
    local notes = {}

    local held = heldCharacterNames(mine)

    for _, tabKey in ipairs(indexTabKeys()) do
        local waiting = tonumber(byKey[tabKey]) or 0
        if waiting > 0 then
            local category = indexCategoryKey(tabKey)
            local gotState, state = pcall(indexRewards.State, mine, category, held)

            if not gotState or type(state) ~= "table" or type(state.Track) ~= "table" then
                table.insert(notes, tabKey .. ": State(" .. tostring(category) .. ") gave nothing")
            else
                local before = #list
                for _, tier in ipairs(state.Track) do
                    if tier.Reached and not tier.Claimed then
                        local claimed = tier.ClaimedRewards or {}
                        for index in ipairs(tier.Rewards or {}) do
                            if not claimed[index] then
                                table.insert(list, {
                                    category = category,
                                    tierKey = tier.Key,
                                    index = index,
                                })
                            end
                        end
                    end
                end
                if #list == before then
                    table.insert(notes, tabKey .. ": badge says " .. waiting
                        .. " but no unclaimed reward in its Track")
                end
            end
        end
    end

    if #list == 0 then
        return {}, "badge says " .. total .. " claimable but none could be resolved"
            .. (#notes > 0 and (" - " .. table.concat(notes, "; ")) or "")
    end

    return list
end

function api.ClaimIndexReward(reward)
    if not modules() then
        return false
    end

    local ok, eventName = pcall(function()
        return indexRewards.Events.Claim
    end)
    if not ok or type(eventName) ~= "string" then
        return false
    end

    return send(eventName, reward.category, reward.tierKey, reward.index)
end

instance = api
return instance

end

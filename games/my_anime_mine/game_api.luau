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
return function(import)

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local log = import("core/logger")

local api = {}
local gameState, mineInventory, mineConfig
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
    end)

    if not ok then
        loadFailed = true
        log("[GameAPI] couldn't load the game's modules: " .. tostring(err))
        return false
    end

    return true
end

function api.IsReady()
    return modules()
end

-- Everything the client knows about the mine: Chest contents, inventory,
-- plot state. Reading this replaces opening menus to look at things.
function api.GetMineData()
    if not modules() then
        return nil
    end

    local ok, data = pcall(gameState.GetData2)
    if not ok or not data then
        return nil
    end

    return data.MineGame
end

-- Money sits on Data2 itself rather than under MineGame.
function api.GetMoney()
    if not modules() then
        return 0
    end

    local ok, data = pcall(gameState.GetData2)
    if not ok or not data then
        return 0
    end

    return tonumber(data.Money) or 0
end

-- MineConfig.Pickaxes is a plain array and MineBuyPickaxe takes the array
-- index, so position in this list IS the argument. The shop hides free,
-- robux-only and unstocked entries, so do the same - they can't be bought
-- with cash.
function api.GetPickaxes()
    if not modules() then
        return {}
    end

    local mine = api.GetMineData()
    local owned = (mine and mine.Pickaxes) or {}
    local list = {}

    local ok = pcall(function()
        for index, def in ipairs(mineConfig.Pickaxes) do
            local buyableWithCash = not (mineConfig.IsPickaxeFree(def)
                or def.RobuxOnly or type(def.Stock) ~= "table")

            if buyableWithCash then
                table.insert(list, {
                    index = index,
                    name = def.Name,
                    cost = tonumber(def.Cost) or math.huge,
                    owned = owned[def.Name] ~= nil,
                })
            end
        end
    end)

    if not ok then
        return {}
    end

    return list
end

function api.ChestCount()
    local mine = api.GetMineData()
    local chest = mine and mine.Chest
    if not chest then
        return nil
    end

    local total = 0
    for _, entry in pairs(chest) do
        total = total + (tonumber(entry) or entry.Count or entry.SellCount or 0)
    end
    return total
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

    local keys = {}
    for _, entry in pairs(entries) do
        local count = entry.SellCount or entry.Count or 0
        if count > 0 and (entry.Worth or 0) > 0 and entry.Key then
            table.insert(keys, entry.Key)
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

function api.EquipSlot(key)
    return send("MineEquipSlot", key)
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

function api.BuySkill(nodeId, family)
    return send("MineBuySkill", nodeId, family)
end

-- The unit screen labels the stat "Mining" but sends "MineSpeed".
function api.UpgradeCharacter(characterKey, stat)
    return send("MineUpgradeCharacter", characterKey, stat == "Mining" and "MineSpeed" or stat)
end

return api

end

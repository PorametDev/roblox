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
local gameState, mineInventory
local loadFailed = false

local function modules()
    if gameState or loadFailed then
        return gameState ~= nil
    end

    local ok, err = pcall(function()
        local moduleFolder = ReplicatedStorage:WaitForChild("Modules", 5)
        gameState = require(moduleFolder.GameState)
        mineInventory = require(moduleFolder.MineInventory)
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

function api.BuySkill(nodeId, family)
    return send("MineBuySkill", nodeId, family)
end

-- The unit screen labels the stat "Mining" but sends "MineSpeed".
function api.UpgradeCharacter(characterKey, stat)
    return send("MineUpgradeCharacter", characterKey, stat == "Mining" and "MineSpeed" or stat)
end

return api

end

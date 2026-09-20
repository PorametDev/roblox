-- Drives the game's own client API rather than its UI. From
-- MineSellClient, the Sell button does exactly one thing:
--
--   GameState.SendEvent("MineSellItems", { key, key, ... })
--
-- where the keys come from MineInventory.Collect and a card counts as
-- sellable when it has both a count and a worth - which is also why
-- "Select All" only ticked ores: that's a UI concern that no longer
-- applies when we build the key list ourselves. Units get sold too, which
-- is safe because Auto Place fills every holder before Auto Sell gets a
-- turn.
--
-- Selling used to fail from a distance, so this still teleports to the
-- SellStand - but only after trying without. If a sale goes through while
-- standing on the plot, the server doesn't position-check this remote and
-- the teleport is dropped for good.
return function(import)

local Workspace = game:GetService("Workspace")
local gameApi = import("games/my_anime_mine/game_api")(import)
local teleport = import("core/teleport")
local log = import("core/logger")

local checkInterval = 45

local autoSell = {}
local enabled = false
local busy = false
local lastAttempt = 0
-- Set by main: "don't sell while this is true". Auto Place fills holders
-- from the same inventory this sells out of, so selling mid-placement
-- would sell the units meant for the empty slots.
local holdWhile = nil
-- Starts unknown; the first sale from where we stand answers it, and the
-- answer holds for the session.
local needsProximity = nil

function autoSell.SetEnabled(state)
    if state == enabled then
        return
    end
    enabled = state

    if not enabled then
        if not busy then
            teleport.Return()
        end
        log("[AutoSell] disabled")
    else
        lastAttempt = 0
        log("[AutoSell] enabled")
    end
end

function autoSell.IsEnabled()
    return enabled
end

function autoSell.IsBusy()
    return busy
end

function autoSell.SetCheckInterval(seconds)
    checkInterval = math.max(seconds, 5)
end

-- Expressing "place before sell" as a direct dependency rather than as a
-- position in the priority list. Ordering alone couldn't do the job: with
-- strict priority Auto Sell sat behind Chest, Place, Upgrade and Research,
-- all of which always had something to do, so it ran once every ninety
-- seconds while the chest refilled every fifteen. Nothing was being sold,
-- so there was no money, so every upgrade pass could afford exactly one
-- thing - which is what "กว่ามันจะซื้อก็นานมาก" actually was.
--
-- With the dependency stated outright, Auto Sell can be allowed to run
-- often without ever selling a unit that Auto Place still wants.
function autoSell.SetHoldWhile(predicate)
    holdWhile = predicate
end

function autoSell.HasWork()
    if holdWhile and holdWhile() then
        return false
    end
    return #gameApi.SellableKeys() > 0
end

local function getSellStandPart()
    local sellStand = Workspace:FindFirstChild("SellStand")
    local prompt = sellStand and sellStand:FindFirstChildWhichIsA("ProximityPrompt", true)
    return prompt and prompt.Parent
end

local function sell(keys)
    gameApi.SellItems(keys)
    task.wait(0.6)
    return #gameApi.SellableKeys() < #keys
end

local function runJob()
    busy = true

    local keys = gameApi.SellableKeys()
    if #keys == 0 then
        busy = false
        return
    end

    local sold = false

    if needsProximity ~= true then
        sold = sell(keys)

        if needsProximity == nil then
            needsProximity = not sold
            log("[AutoSell] MineSellItems "
                .. (sold and "works from anywhere - dropping the teleport"
                         or "needs us at the stand - keeping the teleport"))
        end
    end

    if not sold then
        local part = getSellStandPart()
        if part then
            teleport.To(part)
            task.wait(0.4)
            sold = sell(gameApi.SellableKeys())
            teleport.Return()
        end
    end

    log("[AutoSell] " .. (sold and ("sold " .. #keys .. " stack(s)") or "sale didn't go through"))
    busy = false
end

function autoSell.Step()
    if not enabled or busy then
        return
    end

    local now = tick()
    if now - lastAttempt < checkInterval then
        return
    end
    lastAttempt = now

    if #gameApi.SellableKeys() == 0 then
        return
    end

    task.spawn(runJob)
end

return autoSell

end

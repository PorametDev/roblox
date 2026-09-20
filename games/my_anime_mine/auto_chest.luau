-- Drives the game's own client API rather than its UI. Decompiling
-- MineChestClient showed the Take All button does exactly one thing:
--
--   GameState.SendEvent("MineTakeChest")     -- no arguments at all
--
-- and that the chest's contents sit in GameState.GetData2().MineGame.Chest,
-- readable any time. So this no longer teleports to the chest, fires a
-- prompt, waits for a popup, or clicks anything - it reads the count and
-- sends one event.
--
-- Registered with core/scheduler as EXCLUSIVE purely out of caution while
-- this approach is new; it no longer moves the character, so it could
-- become standalone once it's proven.
return function(import)

local gameApi = import("games/my_anime_mine/game_api")(import)
local log = import("core/logger")

local checkInterval = 3
local minItemsToCollect = 100

local autoChest = {}
local enabled = false
local busy = false
local lastAttempt = 0
local lastReported = nil

function autoChest.SetEnabled(state)
    if state == enabled then
        return
    end
    enabled = state
    lastReported = nil

    if enabled then
        lastAttempt = 0
        log("[AutoChest] enabled (collects once >= " .. minItemsToCollect .. " items)")
    else
        log("[AutoChest] disabled")
    end
end

function autoChest.IsEnabled()
    return enabled
end

function autoChest.IsBusy()
    return busy
end

function autoChest.SetMinItems(value)
    minItemsToCollect = math.max(value, 1)
end

function autoChest.SetCheckInterval(seconds)
    checkInterval = math.max(seconds, 1)
end

-- Reading the count is now a plain table lookup, so the scheduler can ask
-- as often as it likes.
function autoChest.HasWork()
    local count = gameApi.ChestCount()
    return count ~= nil and count >= minItemsToCollect
end

function autoChest.Step()
    if not enabled or busy then
        return
    end

    local now = tick()
    if now - lastAttempt < checkInterval then
        return
    end
    lastAttempt = now

    local count = gameApi.ChestCount()
    if not count then
        if lastReported ~= "unreadable" then
            log("[AutoChest] can't read the chest yet")
            lastReported = "unreadable"
        end
        return
    end

    if count < minItemsToCollect then
        if lastReported ~= "waiting" then
            log("[AutoChest] waiting: " .. count .. "/" .. minItemsToCollect .. " items")
            lastReported = "waiting"
        end
        return
    end

    lastReported = nil
    busy = true

    task.spawn(function()
        gameApi.TakeChest()
        task.wait(0.5)

        local after = gameApi.ChestCount()
        if after and after < count then
            log("[AutoChest] collected " .. count .. " items (now " .. after .. ")")
        else
            log("[AutoChest] MineTakeChest had no effect (" .. count
                .. " -> " .. tostring(after) .. ")")
        end

        busy = false
    end)
end

return autoChest

end

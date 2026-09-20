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
-- Two limits of the game's own apply here. Take All is a no-op on an empty
-- chest - the real button checks that before sending - and the chest has a
-- CAPACITY (MineConfig.GetChestCapacityFor), past which everything the
-- miners dig is simply discarded. So the threshold is clamped to the
-- capacity: setting "collect at 3000" on a chest that only holds 126 would
-- otherwise mean never collecting while the overflow is thrown away.
--
-- Registered with core/scheduler as EXCLUSIVE purely out of caution while
-- this approach is new; it no longer moves the character, so it could
-- become standalone once it's proven.
return function(import)

local gameApi = import("games/my_anime_mine/game_api")(import)
local log = import("core/logger")
local runGuarded = import("core/run_job")(import)

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

-- Never ask for more than the chest can physically hold, and never for
-- more than it currently has - a full chest is wasting every swing.
local function threshold()
    local capacity = gameApi.ChestCapacity()
    if capacity and capacity > 0 then
        return math.min(minItemsToCollect, capacity)
    end
    return minItemsToCollect
end

-- Reading the count is now a plain table lookup, so the scheduler can ask
-- as often as it likes.
function autoChest.HasWork()
    if not gameApi.ChestHasItems() then
        return false
    end
    local count = gameApi.ChestCount()
    return count ~= nil and count >= threshold()
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

    -- The game's own Take All does nothing on an empty chest, so don't
    -- spend a remote call finding that out.
    if not gameApi.ChestHasItems() then
        if lastReported ~= "empty" then
            log("[AutoChest] chest is empty")
            lastReported = "empty"
        end
        return
    end

    local want = threshold()
    if count < want then
        if lastReported ~= "waiting" then
            local capacity = gameApi.ChestCapacity()
            log("[AutoChest] waiting: " .. count .. "/" .. want .. " items"
                .. (capacity and (" (chest holds " .. capacity .. ")") or ""))
            lastReported = "waiting"
        end
        return
    end

    lastReported = nil
    busy = true

    -- Guarded: a job that throws would otherwise leave busy set forever,
    -- and one stuck flag blocks every exclusive task.
    runGuarded("AutoChest", function()
        gameApi.TakeChest()
        task.wait(0.5)

        local after = gameApi.ChestCount()
        if after and after < count then
            log("[AutoChest] collected " .. count .. " items (now " .. after .. ")")
        else
            log("[AutoChest] MineTakeChest had no effect (" .. count
                .. " -> " .. tostring(after) .. ")")
        end
    end, function()
        busy = false
    end)
end

return autoChest

end

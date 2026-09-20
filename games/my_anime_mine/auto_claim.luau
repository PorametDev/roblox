-- Collects the Index rewards - the red badge on the Index button, "13/13
-- Found" with the ! markers on the reward cards.
--
-- This was the last outstanding piece, and it stayed outstanding because
-- the event name isn't written anywhere in MineIndexClient. It sends
--
--   GameState.SendEvent(MineIndexRewardsConfig.Events.Claim,
--                       category, tierKey, rewardIndex)
--
-- so grepping the decompiled scripts for "Claim" as a string found the UI
-- and nothing else. Decompiling all 150 client scripts instead of a
-- hand-written list of six is what turned it up.
--
-- Preconditions, all the game's own: the rewards system has to be Enabled,
-- the category has to have a non-zero Total, the tier has to be Reached
-- and not Claimed, and that reward slot must not already be in
-- ClaimedRewards. Nothing is fired speculatively.
return function(import)

local gameApi = import("games/my_anime_mine/game_api")(import)
local log = import("core/logger")
local runGuarded = import("core/run_job")(import)

local checkInterval = 30
local maxPerPass = 10

local autoClaim = {}
local enabled = false
local busy = false
local lastAttempt = 0

function autoClaim.SetEnabled(state)
    if state == enabled then
        return
    end
    enabled = state
    log("[AutoClaim] " .. (enabled and "enabled" or "disabled"))
end

function autoClaim.IsEnabled()
    return enabled
end

function autoClaim.IsBusy()
    return busy
end

function autoClaim.SetCheckInterval(seconds)
    checkInterval = math.max(seconds, 5)
end

function autoClaim.SetMaxPerPass(count)
    maxPerPass = math.max(count, 1)
end

function autoClaim.HasWork()
    return #gameApi.ClaimableIndexRewards() > 0
end

local function stillClaimable(reward, list)
    for _, current in ipairs(list) do
        if current.category == reward.category
            and current.tierKey == reward.tierKey
            and current.index == reward.index
        then
            return true
        end
    end
    return false
end

local function runJob()
    busy = true

    local pending = gameApi.ClaimableIndexRewards()
    local claimed = 0

    for _, reward in ipairs(pending) do
        if not enabled or claimed >= maxPerPass then
            break
        end

        gameApi.ClaimIndexReward(reward)
        -- MineIndexClient spaces its own claims 0.6s apart; going faster
        -- than the real UI can is asking to be rate-limited.
        task.wait(0.7)

        if not stillClaimable(reward, gameApi.ClaimableIndexRewards()) then
            log("[AutoClaim] claimed " .. reward.category .. " "
                .. tostring(reward.tierKey) .. " #" .. reward.index)
            claimed = claimed + 1
        end
    end

    if claimed == 0 and #pending > 0 then
        log("[AutoClaim] " .. #pending .. " reward(s) looked claimable but none went through")
    end

    busy = false
end

function autoClaim.Step()
    if not enabled or busy then
        return
    end

    local now = tick()
    if now - lastAttempt < checkInterval then
        return
    end
    lastAttempt = now

    if not autoClaim.HasWork() then
        return
    end

    -- Guarded: a job that throws would otherwise leave busy set
    -- forever, and one stuck flag blocks every exclusive task.
    runGuarded("AutoClaim", runJob, function()
        busy = false
    end)
end

return autoClaim

end

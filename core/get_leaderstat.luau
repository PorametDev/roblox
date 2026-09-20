local function getLeaderstat(player, statName, timeout)
    local leaderstats = player:FindFirstChild("leaderstats")
    if not leaderstats then
        return nil
    end

    local stat = leaderstats:FindFirstChild(statName)
    if not stat and timeout then
        stat = leaderstats:WaitForChild(statName, timeout)
    end

    return stat
end

return getLeaderstat
-- Named children observed on a MinePlotN: Nodes (rocks, count varies - they
-- regenerate, so don't cache this table, call again whenever you need a
-- fresh read), Holders (bases you place a character on to auto-mine,
-- upgradable via each holder's UpgradePart), and Chest (where mined ore
-- and characters end up).
local function getPlotParts(plot)
    return {
        Holders = plot:FindFirstChild("Holders"),
        Nodes = plot:FindFirstChild("Nodes"),
        Chest = plot:FindFirstChild("Chest"),
        Zones = plot:FindFirstChild("Zones"),
        Crew = plot:FindFirstChild("Crew"),
        Loot = plot:FindFirstChild("Loot"),

        -- Attributes on the plot itself (PlotIndex, ChestCapacity,
        -- MineStartupNodeCount, ZoneKey, TrialUnlocked, ...).
        PlotIndex = plot:GetAttribute("PlotIndex"),
        ChestCapacity = plot:GetAttribute("ChestCapacity"),
    }
end

return getPlotParts

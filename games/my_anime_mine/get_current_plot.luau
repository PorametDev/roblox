local Players = game:GetService("Players")
local Workspace = game:GetService("Workspace")

-- Each MinePlotN carries an OwnerUserId attribute, so the player's plot is
-- found by matching UserId rather than guessing from position - works even
-- when the player isn't currently standing on it.
local function getCurrentPlot()
    local player = Players.LocalPlayer

    local mineWorld = Workspace:FindFirstChild("MineWorld")
    local plots = mineWorld and mineWorld:FindFirstChild("Plots")
    if not plots then
        return nil
    end

    for _, plot in ipairs(plots:GetChildren()) do
        if plot:GetAttribute("OwnerUserId") == player.UserId then
            return plot
        end
    end

    return nil
end

return getCurrentPlot

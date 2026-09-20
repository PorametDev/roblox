-- Opening the chest UI just to read "780/3,600 Items" is intrusive - the
-- character teleports and a popup covers the screen every few seconds. The
-- server has to replicate that count to the client for the UI to render it
-- at all, so it must be readable somewhere without opening anything. This
-- dumps everything under the plot's Chest (and the plot itself) that could
-- hold it: attributes, ValueBase objects, and any billboard/surface GUI
-- text.
return function(import)

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local getCurrentPlot = import("games/my_anime_mine/get_current_plot")
local getPlotParts = import("games/my_anime_mine/get_plot_parts")
local log = import("core/logger")

local function dumpAttributes(instance, indent)
    for name, value in pairs(instance:GetAttributes()) do
        log(indent .. "[attr] " .. name .. " = " .. tostring(value))
    end
end

-- PlayerGui alone is thousands of lines, and the character model adds
-- hundreds more - neither can hold the replicated count we're after.
local SKIP_NAMES = {
    PlayerGui = true,
    PlayerScripts = true,
    StarterGear = true,
}

local function dumpSubtree(root, indent)
    dumpAttributes(root, indent .. "  ")

    for _, child in ipairs(root:GetChildren()) do
        if not SKIP_NAMES[child.Name] then
            local line = indent .. child.ClassName .. " '" .. child.Name .. "'"

            if child:IsA("ValueBase") then
                line = line .. " = " .. tostring(child.Value)
            elseif child:IsA("TextLabel") or child:IsA("TextButton") then
                line = line .. " (Text=" .. tostring(child.Text) .. ")"
            end

            log(line)
            dumpSubtree(child, indent .. "  ")
        end
    end
end

local function dumpChest()
    local plot = getCurrentPlot()
    if not plot then
        log("[ChestDump] not standing in any plot")
        return 0
    end

    log("[ChestDump] === plot " .. plot.Name .. " attributes ===")
    dumpAttributes(plot, "  ")

    local parts = getPlotParts(plot)
    if not parts.Chest then
        log("[ChestDump] plot has no Chest")
        return 0
    end

    log("[ChestDump] === Chest subtree ===")
    dumpSubtree(parts.Chest, "")

    -- Per-player replicated state is the other place a live count could
    -- live, so check the Player object and any folder named after us.
    local player = Players.LocalPlayer
    log("[ChestDump] === Player subtree ===")
    dumpSubtree(player, "")

    local mine = ReplicatedStorage:FindFirstChild(player.Name)
    if mine then
        log("[ChestDump] === ReplicatedStorage." .. player.Name .. " ===")
        dumpSubtree(mine, "")
    end

    log("[ChestDump] === end ===")

    return #parts.Chest:GetDescendants()
end

return dumpChest

end

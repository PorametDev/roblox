-- Auto Place used to grab whatever Tool came first out of the Backpack,
-- which meant placing a power-6 Namek Hero while a power-195 Warped Ninja
-- sat unused. This ranks every miner the player holds and returns the
-- strongest.
--
-- The power number is the one the hotbar card shows in red. We don't know
-- which attribute the game stores it in, so try the likely attribute names
-- and Value children first, then fall back to reading the hotbar card's own
-- "Damage" label (confirmed to exist at
-- HotbarFrame > ... > ItemFrame > Content > Damage). Every tool's resolved
-- power is logged once so the real attribute name shows up in MekPro.log.
return function(import)

local Players = game:GetService("Players")
local log = import("core/logger")

local ATTRIBUTE_NAMES = { "Damage", "Power", "MineDamage", "MinePower", "DPS", "Strength" }

local reportedTools = {}

local function fromAttributes(tool)
    for _, name in ipairs(ATTRIBUTE_NAMES) do
        local value = tool:GetAttribute(name)
        if type(value) == "number" then
            return value, "attr:" .. name
        end
    end

    for _, name in ipairs(ATTRIBUTE_NAMES) do
        local child = tool:FindFirstChild(name)
        if child and child:IsA("ValueBase") and type(child.Value) == "number" then
            return child.Value, "value:" .. name
        end
    end

    return nil
end

-- The hotbar card for a held miner shows its power, so match by name.
local function fromHotbar(toolName)
    local playerGui = Players.LocalPlayer:FindFirstChild("PlayerGui")
    local mineGui = playerGui and playerGui:FindFirstChild("MineGui")
    local hotbar = mineGui and mineGui:FindFirstChild("HotbarFrame")
    if not hotbar then
        return nil
    end

    for _, descendant in ipairs(hotbar:GetDescendants()) do
        if descendant.Name == "ItemName" and descendant:IsA("TextLabel") and descendant.Text == toolName then
            local damage = descendant.Parent and descendant.Parent:FindFirstChild("Damage")
            if damage and damage:IsA("TextLabel") then
                local number = tonumber((damage.Text:gsub("[^%d%.]", "")))
                if number then
                    return number, "hotbar"
                end
            end
        end
    end

    return nil
end

local function getPower(tool)
    local power, source = fromAttributes(tool)
    if not power then
        power, source = fromHotbar(tool.Name)
    end

    if not reportedTools[tool.Name] then
        reportedTools[tool.Name] = true
        log("[BestMiner] " .. tool.Name .. " power = " .. tostring(power)
            .. " (" .. tostring(source) .. ")")
    end

    return power or 0
end

local function getBestMiner()
    local player = Players.LocalPlayer
    local backpack = player:FindFirstChild("Backpack")
    if not backpack then
        return nil
    end

    local best, bestPower = nil, -1

    for _, tool in ipairs(backpack:GetChildren()) do
        if tool:IsA("Tool") then
            local power = getPower(tool)
            if power > bestPower then
                best, bestPower = tool, power
            end
        end
    end

    return best, bestPower
end

return getBestMiner

end

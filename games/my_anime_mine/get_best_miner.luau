-- Miners are NOT Roblox Tools - the Backpack is empty and the game runs its
-- own inventory, which is why Auto Place kept reporting "no miner in the
-- Backpack". They live in the game's own hotbar UI, one slot frame per
-- number key:
--
--   MineGui > HotbarFrame > Content > Container > "1".."9"
--       > ItemFrame > Content > ItemName ("Namek Hero") / Damage ("6")
--
-- The red number on each card is its power, so this reads every filled slot
-- and returns the strongest one's slot number - pressing that number key is
-- how you "hold" it, exactly as the game's own hint says.
--
-- Only covers what's on the hotbar; anything still in the bag would need
-- the inventory screen opened first.
return function(import)

local Players = game:GetService("Players")
local log = import("core/logger")

local reported = {}

local function getContainer()
    local playerGui = Players.LocalPlayer:FindFirstChild("PlayerGui")
    local mineGui = playerGui and playerGui:FindFirstChild("MineGui")
    local hotbar = mineGui and mineGui:FindFirstChild("HotbarFrame")
    local content = hotbar and hotbar:FindFirstChild("Content")
    return content and content:FindFirstChild("Container")
end

local function readSlot(slotFrame)
    local itemFrame = slotFrame:FindFirstChild("ItemFrame")
    local content = itemFrame and itemFrame:FindFirstChild("Content")
    local nameLabel = content and content:FindFirstChild("ItemName")
    local damageLabel = content and content:FindFirstChild("Damage")

    if not (nameLabel and damageLabel) then
        return nil
    end

    local name = nameLabel.Text
    if name == "" then
        return nil
    end

    local power = tonumber((damageLabel.Text:gsub("[^%d%.]", "")))
    return name, power or 0
end

local function getBestMiner()
    local container = getContainer()
    if not container then
        return nil
    end

    local best = nil

    for _, slotFrame in ipairs(container:GetChildren()) do
        local slot = tonumber(slotFrame.Name)
        if slot and slot >= 1 and slot <= 9 then
            local name, power = readSlot(slotFrame)
            if name then
                if not reported[name] then
                    reported[name] = true
                    log("[BestMiner] slot " .. slot .. ": " .. name .. " power " .. power)
                end

                if not best or power > best.power then
                    best = { slot = slot, name = name, power = power }
                end
            end
        end
    end

    return best
end

return getBestMiner

end

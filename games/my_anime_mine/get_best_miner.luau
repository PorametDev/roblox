-- Miners are NOT Roblox Tools - the Backpack is empty and the game runs its
-- own inventory, which is why Auto Place once reported "no miner in the
-- Backpack". They live in the game's own hotbar UI, one slot frame per
-- number key:
--
--   MineGui > HotbarFrame > Content > Container > "1".."9"
--       > ItemFrame > Content > ItemName ("Namek Hero") / Damage ("6")
--
-- The red number on each card is its power. Returns every usable slot
-- sorted strongest first, rather than just the single best: a stack runs
-- out (placing the last Warped Ninja left slot 5 showing a card the game
-- would no longer let us hold) and Auto Place needs somewhere to fall back
-- to instead of pressing a dead key forever.
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

-- The stack size renders as "x46". Its label isn't consistently named
-- across this game's cards, so match on the text shape instead.
local function readCount(slotFrame)
    for _, descendant in ipairs(slotFrame:GetDescendants()) do
        if descendant:IsA("TextLabel") then
            local count = descendant.Text:match("^x(%d+)$")
            if count then
                return tonumber(count)
            end
        end
    end
    return nil
end

local function readSlot(slotFrame)
    local itemFrame = slotFrame:FindFirstChild("ItemFrame")
    if not (itemFrame and itemFrame.Visible) then
        return nil
    end

    local content = itemFrame:FindFirstChild("Content")
    local nameLabel = content and content:FindFirstChild("ItemName")
    local damageLabel = content and content:FindFirstChild("Damage")

    if not (nameLabel and damageLabel) or nameLabel.Text == "" then
        return nil
    end

    return {
        name = nameLabel.Text,
        power = tonumber((damageLabel.Text:gsub("[^%d%.]", ""))) or 0,
        count = readCount(slotFrame),
    }
end

-- Strongest first. A slot whose stack has visibly run out is dropped; a
-- slot with no count label at all is kept, since plenty of cards don't show
-- one when a single copy is left.
local function getMinerSlots()
    local container = getContainer()
    if not container then
        return {}
    end

    local slots = {}

    for _, slotFrame in ipairs(container:GetChildren()) do
        local slot = tonumber(slotFrame.Name)
        if slot and slot >= 1 and slot <= 9 then
            local info = readSlot(slotFrame)
            if info and (info.count == nil or info.count > 0) then
                info.slot = slot

                local key = info.name .. "/" .. slot
                if not reported[key] then
                    reported[key] = true
                    log("[BestMiner] slot " .. slot .. ": " .. info.name
                        .. " power " .. info.power .. " x" .. tostring(info.count))
                end

                table.insert(slots, info)
            end
        end
    end

    table.sort(slots, function(a, b)
        return a.power > b.power
    end)

    return slots
end

return getMinerSlots

end

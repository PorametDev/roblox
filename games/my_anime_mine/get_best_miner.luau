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
-- The power on the card is the character's BASE damage, and it's
-- abbreviated: "305.2K", "48.8K", "1.2K". Stripping non-digits out of that
-- gives 305.2 and 48.8 - three orders of magnitude too small - so every
-- hotbar unit looked feebler than anything already placed, Auto Place
-- decided nothing was worth swapping, and Auto Sell then sold a 305.2K
-- Gear 5 Lufy as surplus. The log said so plainly and I read past it:
--
--   [BestMiner] slot 4: One Arm Pirates power 48.8 x3
--
-- So the number comes from the game's data now - Items.GetItemData plus
-- MineConfig.GetCharacterDamage - with suffix-aware text parsing only as a
-- fallback for cards whose name doesn't resolve.
--
-- Only covers what's on the hotbar; anything still in the bag would need
-- the inventory screen opened first.
return function(import)

local Players = game:GetService("Players")
local gameApi = import("games/my_anime_mine/game_api")(import)
local log = import("core/logger")

local SUFFIXES = {
    K = 1e3, M = 1e6, B = 1e9, T = 1e12, Qa = 1e15, Qi = 1e18,
}

local function parsePower(text)
    local number, suffix = text:match("([%d,%.]+)%s*(%a*)")
    if not number then
        return 0
    end

    local value = tonumber((number:gsub(",", ""))) or 0
    if suffix ~= "" then
        local multiplier = SUFFIXES[suffix]
            or SUFFIXES[suffix:sub(1, 1):upper() .. suffix:sub(2)]
        -- An unknown suffix is a BIGGER unit than we know, so guessing
        -- small here would repeat the original mistake.
        value = value * (multiplier or 1)
    end
    return value
end

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

    local name = nameLabel.Text

    return {
        name = name,
        -- The game's own figure first; the card text is only a fallback.
        power = gameApi.CharacterBaseDamage(name) or parsePower(damageLabel.Text),
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

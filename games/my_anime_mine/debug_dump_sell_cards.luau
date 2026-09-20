-- Manual play showed selling isn't "select all then confirm" - each
-- individual Card under SellFrame.Content.Scroll gets clicked. Need to see
-- what identifies an item on its Card (Name, attributes, a child ObjectValue
-- pointing at the actual item, ...) before SellItems can be fired directly
-- with the right argument instead of clicking each Card.
return function(import)

local Players = game:GetService("Players")
local log = import("core/logger")

local function dumpSellCards()
    local playerGui = Players.LocalPlayer:FindFirstChild("PlayerGui")
    local mineGui = playerGui and playerGui:FindFirstChild("MineGui")
    local sellFrame = mineGui and mineGui:FindFirstChild("SellFrame")
    local scroll = sellFrame and sellFrame:FindFirstChild("Content") and sellFrame.Content:FindFirstChild("Scroll")

    if not scroll then
        log("[SellCards] SellFrame.Content.Scroll not found - open the sell menu first")
        return 0
    end

    local count = 0
    for _, card in ipairs(scroll:GetChildren()) do
        if card.Name == "Card" or card:IsA("GuiObject") then
            count = count + 1
            log("[SellCards] Card #" .. count .. ": " .. card.ClassName .. " '" .. card.Name .. "'")

            for attrName, attrValue in pairs(card:GetAttributes()) do
                log("  [attr] " .. attrName .. " = " .. tostring(attrValue))
            end

            for _, child in ipairs(card:GetDescendants()) do
                local line = "  " .. child.ClassName .. " '" .. child.Name .. "'"
                if child:IsA("ValueBase") then
                    line = line .. " = " .. tostring(child.Value)
                end
                log(line)
            end
        end
    end

    log("[SellCards] === total cards: " .. count .. " ===")
    return count
end

return dumpSellCards

end

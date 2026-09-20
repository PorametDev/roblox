local Players = game:GetService("Players")

local function getMe()
    local player = Players.LocalPlayer
    local character = player.Character or player.CharacterAdded:Wait()
    local humanoid = character:WaitForChild("Humanoid")
    local backpack = player:WaitForChild("Backpack")

    return player, humanoid, backpack
end

return getMe

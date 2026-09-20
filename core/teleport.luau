-- Shared teleport-and-return helper. Auto Sell was saving the character's
-- CFrame before warping to the SellStand, but the "return home" call only
-- ran on one of several exit paths (closing an empty sell menu) - it never
-- ran after a successful sell, since that path just let the frame close on
-- its own. Centralizing To/Return here means every caller gets the same
-- save-once/restore-once behavior instead of reimplementing it themselves.
return function(import)

local Players = game:GetService("Players")

local teleport = {}
local savedCFrame = nil

local function getHumanoidRootPart()
    local character = Players.LocalPlayer.Character
    return character and character:FindFirstChild("HumanoidRootPart")
end

-- Teleports next to `part` (with an optional offset), remembering where the
-- character was if it isn't already away from a previous To() call.
function teleport.To(part, offset)
    local hrp = getHumanoidRootPart()
    if not (hrp and part) then
        return false
    end

    if not savedCFrame then
        savedCFrame = hrp.CFrame
    end

    hrp.CFrame = CFrame.new(part.Position + (offset or Vector3.new(0, 3, 5)))
    return true
end

-- Restores the character to wherever it was before the last To() call.
-- Safe to call even if nothing is pending (no-op).
function teleport.Return()
    local hrp = getHumanoidRootPart()
    if hrp and savedCFrame then
        hrp.CFrame = savedCFrame
    end
    savedCFrame = nil
end

function teleport.IsAway()
    return savedCFrame ~= nil
end

return teleport

end

-- Lists every RemoteEvent/RemoteFunction under ReplicatedStorage by full
-- path. Purely reads the instance tree (GetDescendants) - no hooking, no
-- interception of anything - so this carries none of the risk a
-- __namecall spy does. Use it to find candidate remote names by pattern
-- (e.g. "Sell", "Chest", "Claim"), then call them directly with FireServer.
return function(import)

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local log = import("core/logger")

local function dumpRemotes()
    local count = 0
    for _, descendant in ipairs(ReplicatedStorage:GetDescendants()) do
        if descendant:IsA("RemoteEvent") or descendant:IsA("RemoteFunction") then
            count = count + 1
            log("[Remotes] " .. descendant.ClassName .. ": " .. descendant:GetFullName())
        end
    end
    log("[Remotes] === total: " .. count .. " ===")
    return count
end

return dumpRemotes

end

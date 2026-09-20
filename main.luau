local getPlaceId = loadstring(readfile("core/get_place_id.luau"))()
local registry = loadstring(readfile("games/registry.luau"))()

local scriptPath = registry[getPlaceId()]

if not scriptPath then
    print("This is not a supported place.")
    return
end

loadstring(readfile(scriptPath))()

return function(import)
    local getPlaceId = import("core/get_place_id")
    local registry = import("games/registry")

    local scriptPath = registry[getPlaceId()]

    if not scriptPath then
        print("This is not a supported place.")
        return
    end

    import(scriptPath)(import)
end

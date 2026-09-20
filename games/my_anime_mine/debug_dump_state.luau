-- Converting the rest to direct remote calls needs the keys the server
-- expects - the character key for MineUpgradeCharacter, the zone/family
-- pair for MineBuySkill. They all live in the client's own state table, so
-- print its shape rather than guessing again.
return function(import)

local gameApi = import("games/my_anime_mine/game_api")(import)
local log = import("core/logger")

local function describe(value)
    local valueType = typeof(value)
    if valueType == "table" then
        local count = 0
        for _ in pairs(value) do
            count = count + 1
        end
        return "table(" .. count .. ")"
    end
    return valueType .. " " .. tostring(value)
end

-- Two levels is enough to see the shape without printing every ore stack.
local function dumpTable(value, indent, depth)
    for key, entry in pairs(value) do
        log(indent .. tostring(key) .. " = " .. describe(entry))
        if type(entry) == "table" and depth > 0 then
            dumpTable(entry, indent .. "  ", depth - 1)
        end
    end
end

local function dumpState()
    local mine = gameApi.GetMineData()
    if not mine then
        log("[StateDump] no mine data (is the game API loaded?)")
        return 0
    end

    log("[StateDump] === MineGame ===")
    dumpTable(mine, "  ", 2)
    log("[StateDump] === end ===")

    return 1
end

return dumpState

end

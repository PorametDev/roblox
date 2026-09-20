-- Persists UI settings and toggle states to
-- workspace/MekPro/<placeId>/config.json so a reload comes back with
-- everything the way it was left. Scoped per place id because each game
-- has its own set of automations.
return function(import)

local HttpService = game:GetService("HttpService")
local getPlaceId = import("core/get_place_id")
local log = import("core/logger")

local ROOT_FOLDER = "MekPro"
local placeFolder = ROOT_FOLDER .. "/" .. tostring(getPlaceId())
local filePath = placeFolder .. "/config.json"

local values = {}
local loaded = false

local function ensureFolders()
    if not (isfolder and makefolder) then
        return
    end
    if not isfolder(ROOT_FOLDER) then
        makefolder(ROOT_FOLDER)
    end
    if not isfolder(placeFolder) then
        makefolder(placeFolder)
    end
end

local function load()
    if loaded then
        return
    end
    loaded = true

    local ok, err = pcall(function()
        if isfile and isfile(filePath) then
            local decoded = HttpService:JSONDecode(readfile(filePath))
            if type(decoded) == "table" then
                values = decoded
            end
        end
    end)

    if not ok then
        log("[Config] couldn't read " .. filePath .. ": " .. tostring(err))
    end
end

local function save()
    local ok, err = pcall(function()
        ensureFolders()
        writefile(filePath, HttpService:JSONEncode(values))
    end)

    if not ok then
        log("[Config] couldn't write " .. filePath .. ": " .. tostring(err))
    end

    return ok
end

local config = {}

function config.Get(key, default)
    load()
    local value = values[key]
    if value == nil then
        return default
    end
    return value
end

function config.Set(key, value)
    load()
    if values[key] == value then
        return
    end
    values[key] = value
    save()
end

function config.Path()
    return filePath
end

return config

end

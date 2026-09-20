-- Everything currently goes through the GUI because we never learned what
-- arguments the game's remotes expect - firing ClaimOre/SellItems bare did
-- nothing. The usual way to find out is a __namecall remote spy, and that
-- is exactly what got this account kicked (Hyperion, Error Code 267), so
-- it stays off the table permanently.
--
-- This reads instead of hooks. For a given button it walks the functions
-- already connected to its Activated signal and reports what they close
-- over: constants (remote names, string arguments) and upvalues (often the
-- RemoteEvent instance itself). Reading a closure's own data doesn't touch
-- engine metamethods.
--
-- Still worth being clear-eyed: getconnections and the debug library are
-- exploit APIs, lower risk than metamethod hooks but not zero. Run this
-- once, get what we need, then leave it off.
return function(import)

local Players = game:GetService("Players")
local log = import("core/logger")

local function describe(value)
    local valueType = typeof(value)

    if valueType == "Instance" then
        return value.ClassName .. " " .. value:GetFullName()
    end

    if valueType == "table" then
        return "table"
    end

    if valueType == "function" then
        return "function"
    end

    return valueType .. " " .. tostring(value)
end

-- Anything that names a remote or looks like an argument literal is worth
-- seeing; skipping the rest keeps the log readable.
local function isInteresting(value)
    local valueType = typeof(value)

    if valueType == "Instance" then
        return value:IsA("RemoteEvent") or value:IsA("RemoteFunction") or value:IsA("Folder")
    end

    return valueType == "string" or valueType == "number" or valueType == "boolean"
end

local function inspectFunction(fn, indent)
    local ok, source, line = pcall(function()
        return debug.info(fn, "sl")
    end)
    if ok and source then
        log(indent .. "defined at " .. tostring(source) .. ":" .. tostring(line))
    end

    local okConstants, constants = pcall(debug.getconstants, fn)
    if okConstants and type(constants) == "table" then
        for _, constant in pairs(constants) do
            if isInteresting(constant) then
                log(indent .. "  [const] " .. describe(constant))
            end
        end
    else
        log(indent .. "  (debug.getconstants unavailable)")
    end

    local okUpvalues, upvalues = pcall(debug.getupvalues, fn)
    if okUpvalues and type(upvalues) == "table" then
        for _, upvalue in pairs(upvalues) do
            if isInteresting(upvalue) then
                log(indent .. "  [upvalue] " .. describe(upvalue))
            end
        end
    else
        log(indent .. "  (debug.getupvalues unavailable)")
    end
end

local function inspectButton(label, button)
    if not button then
        log("[Handlers] " .. label .. ": not found")
        return
    end

    log("[Handlers] === " .. label .. " (" .. button:GetFullName() .. ") ===")

    if not getconnections then
        log("[Handlers] getconnections isn't available in this executor")
        return
    end

    for _, signalName in ipairs({ "Activated", "MouseButton1Click" }) do
        local okSignal, connections = pcall(getconnections, button[signalName])
        if okSignal and connections then
            log("[Handlers] " .. signalName .. ": " .. #connections .. " connection(s)")
            for index, connection in ipairs(connections) do
                local fn = connection.Function
                if fn then
                    log("[Handlers]   #" .. index)
                    inspectFunction(fn, "[Handlers]   ")
                end
            end
        end
    end
end

local function find(path)
    local playerGui = Players.LocalPlayer:FindFirstChild("PlayerGui")
    local current = playerGui and playerGui:FindFirstChild("MineGui")

    for _, name in ipairs(path) do
        if not current then
            return nil
        end
        current = current:FindFirstChild(name)
    end

    return current
end

-- Only the buttons whose remote we actually want: collecting, selling and
-- the two kinds of upgrade.
local function inspectHandlers()
    log("[Handlers] === start (open the relevant menus first) ===")

    inspectButton("Chest TakeButton", find({ "ChestFrame", "Content", "Actions", "TakeButton" }))
    inspectButton("Sell SelectAllButton", find({ "SellFrame", "Content", "SelectAllButton" }))
    inspectButton("Sell SellButton", find({ "SellFrame", "Content", "SellButton" }))
    inspectButton("Research BuyButton", find({ "SkillTreeFullFrame", "Detail", "BuyButton" }))

    local statsScroll = find({ "SlotFocusFrame", "BottomPanels", "StatsPanel", "Scroll" })
    local damageRow = statsScroll and statsScroll:FindFirstChild("Damage")
    inspectButton("Unit Damage UpgradeButton", damageRow and damageRow:FindFirstChild("UpgradeButton"))

    log("[Handlers] === end ===")
end

return inspectHandlers

end

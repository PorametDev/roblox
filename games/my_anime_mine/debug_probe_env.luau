-- Inspecting the buttons was a dead end: every one reported a single
-- Activated connection that turned out to be our own Interaction Logger.
-- The game binds no per-button handlers at all - it routes clicks through
-- some central input handler instead, which is exactly why
-- firesignal(Activated) never worked while a real mouse click does.
--
-- So the remote signatures have to come from the game's own code. This
-- reports which executor APIs Potassium actually exposes, lists the scripts
-- that could plausibly drive MineGui, and - if decompile exists - dumps one
-- so we can read which remote a purchase fires and with what arguments.
--
-- Read-only throughout. No metamethod hooks, ever.
return function(import)

local Players = game:GetService("Players")
local log = import("core/logger")

local CAPABILITIES = {
    "decompile", "getscriptbytecode", "getscripts", "getgc", "getloadedmodules",
    "getconnections", "getcallbackvalue", "getsenv", "getrenv", "debug.getconstants",
    "debug.getupvalues", "debug.getproto", "hookfunction", "getnilinstances",
}

local function resolve(path)
    local target = getfenv and getfenv(0) or _G
    for part in path:gmatch("[^%.]+") do
        if type(target) ~= "table" then
            return nil
        end
        target = rawget(target, part) or target[part]
    end
    return target
end

local function reportCapabilities()
    log("[Probe] === executor capabilities ===")
    for _, name in ipairs(CAPABILITIES) do
        local ok, value = pcall(resolve, name)
        log("[Probe] " .. name .. " = " .. ((ok and type(value) == "function") and "yes" or "no"))
    end
end

-- The UI scripts live in PlayerScripts.UI.MineGame, not under MineGui -
-- looking in the wrong place is why the first probe decompiled nothing.
-- These are the ones that fire the remotes we're after.
local WANTED_SCRIPTS = {
    "MineChestClient",
    "MineSellClient",
    "MineSkillTreeClient",
    "MineSlotFocusClient",
    "MineHotbarClient",
    "MineHUDClient",
}

-- Writes to files rather than the log: decompiled source runs to thousands
-- of lines and would bury everything else in MekPro.log.
local function tryDecompile()
    if not decompile then
        log("[Probe] decompile unavailable - can't read the game's source this way")
        return
    end

    local playerScripts = Players.LocalPlayer:FindFirstChild("PlayerScripts")
    local ui = playerScripts and playerScripts:FindFirstChild("UI")
    local mineGame = ui and ui:FindFirstChild("MineGame")
    if not mineGame then
        log("[Probe] PlayerScripts.UI.MineGame not found")
        return
    end

    for _, name in ipairs(WANTED_SCRIPTS) do
        local target = mineGame:FindFirstChild(name)
        if not target then
            log("[Probe] " .. name .. " not found")
        else
            local ok, source = pcall(decompile, target)
            if ok and type(source) == "string" and #source > 0 then
                local path = "MekPro/decompiled_" .. name .. ".lua"
                local written = pcall(writefile, path, source)
                log("[Probe] decompiled " .. name .. " (" .. #source .. " chars) -> "
                    .. (written and path or "write failed"))
            else
                log("[Probe] couldn't decompile " .. name .. ": " .. tostring(source))
            end
        end
    end
end

-- The capability and script listings already told us what we needed
-- (decompile works; the UI scripts are in PlayerScripts.UI.MineGame), and
-- the full listing is 636 entries, so only the decompile runs now.
local function probe()
    log("[Probe] === start ===")
    reportCapabilities()
    tryDecompile()
    log("[Probe] === end ===")
end

return probe

end

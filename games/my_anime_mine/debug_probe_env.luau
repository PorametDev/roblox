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
local ReplicatedStorage = game:GetService("ReplicatedStorage")
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

-- Only the containers whose scripts could own the mining UI; dumping every
-- script in the game would bury the useful ones.
local function reportScripts()
    log("[Probe] === client scripts ===")

    local player = Players.LocalPlayer
    local roots = {
        player:FindFirstChild("PlayerGui"),
        player:FindFirstChild("PlayerScripts"),
        ReplicatedStorage,
    }

    local count = 0
    for _, root in ipairs(roots) do
        if root then
            for _, descendant in ipairs(root:GetDescendants()) do
                if descendant:IsA("LocalScript") or descendant:IsA("ModuleScript") then
                    count = count + 1
                    if count <= 120 then
                        log("[Probe] " .. descendant.ClassName .. " " .. descendant:GetFullName())
                    end
                end
            end
        end
    end

    log("[Probe] total scripts: " .. count .. (count > 120 and " (listing capped at 120)" or ""))
end

-- Writes to its own file rather than the log: decompiled source runs to
-- thousands of lines and would bury everything else in MekPro.log.
local function tryDecompile()
    if not decompile then
        log("[Probe] decompile unavailable - can't read the game's source this way")
        return
    end

    local player = Players.LocalPlayer
    local playerGui = player:FindFirstChild("PlayerGui")
    local mineGui = playerGui and playerGui:FindFirstChild("MineGui")
    if not mineGui then
        log("[Probe] MineGui not found")
        return
    end

    for _, descendant in ipairs(mineGui:GetDescendants()) do
        if descendant:IsA("LocalScript") or descendant:IsA("ModuleScript") then
            local ok, source = pcall(decompile, descendant)
            if ok and type(source) == "string" and #source > 0 then
                local path = "MekPro/decompiled_" .. descendant.Name .. ".lua"
                local written = pcall(writefile, path, source)
                log("[Probe] decompiled " .. descendant:GetFullName()
                    .. " (" .. #source .. " chars) -> " .. (written and path or "write failed"))
            else
                log("[Probe] couldn't decompile " .. descendant:GetFullName())
            end
        end
    end
end

local function probe()
    log("[Probe] === start ===")
    reportCapabilities()
    reportScripts()
    tryDecompile()
    log("[Probe] === end ===")
end

return probe

end

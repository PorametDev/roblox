-- Reports which executor APIs are actually available, then decompiles the
-- game's own client scripts to files so their real remote calls can be read
-- instead of guessed at.
--
-- This is the tool that ended the guessing on My Anime Mine - every
-- "firesignal doesn't work", "the sell remote is position-checked", "a
-- research node has to be OPEN before you can buy it" answer came out of
-- reading the decompiled source. Nothing in it is specific to that game, so
-- it belongs here: it walks PlayerScripts for LocalScripts rather than
-- looking for a named folder.
--
-- Read-only throughout. No metamethod hooks, ever - a __namecall spy is
-- what got an account kicked, and this replaces the need for one.
return function(import)

local Players = game:GetService("Players")
local log = import("core/logger")

local CAPABILITIES = {
    "decompile", "getscriptbytecode", "getscripts", "getgc", "getloadedmodules",
    "getconnections", "getcallbackvalue", "getsenv", "getrenv", "debug.getconstants",
    "debug.getupvalues", "debug.getproto", "hookfunction", "getnilinstances",
}

-- Decompiled source runs to thousands of lines, so it goes to files; only
-- the summary reaches the log.
local OUT_FOLDER = "MekPro/decompiled"

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
    log("[Decompile] === executor capabilities ===")
    for _, name in ipairs(CAPABILITIES) do
        local ok, value = pcall(resolve, name)
        log("[Decompile] " .. name .. " = " .. ((ok and type(value) == "function") and "yes" or "no"))
    end
end

local function dumpAll()
    if not decompile then
        log("[Decompile] decompile unavailable in this executor")
        return 0
    end

    local playerScripts = Players.LocalPlayer:FindFirstChild("PlayerScripts")
    if not playerScripts then
        log("[Decompile] PlayerScripts not found")
        return 0
    end

    pcall(makefolder, "MekPro")
    pcall(makefolder, OUT_FOLDER)

    local written = 0
    local failed = 0

    for _, target in ipairs(playerScripts:GetDescendants()) do
        if target:IsA("LocalScript") or target:IsA("ModuleScript") then
            local ok, source = pcall(decompile, target)
            if ok and type(source) == "string" and #source > 0 then
                -- Full path in the filename, so two scripts with the same
                -- name in different folders don't overwrite each other.
                local name = target:GetFullName():gsub("[^%w]+", "_")
                if pcall(writefile, OUT_FOLDER .. "/" .. name .. ".lua", source) then
                    written = written + 1
                else
                    failed = failed + 1
                end
            else
                failed = failed + 1
            end
        end
    end

    log("[Decompile] wrote " .. written .. " script(s) to " .. OUT_FOLDER
        .. " (" .. failed .. " failed)")
    return written
end

local function run()
    log("[Decompile] === start ===")
    reportCapabilities()
    local count = dumpAll()
    log("[Decompile] === end ===")
    return count
end

return run

end

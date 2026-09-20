-- Dumps whatever GuiObjects are currently VISIBLE in PlayerGui (hidden
-- frames are skipped to cut noise). Open the screen you want to inspect
-- first, then run this.
--
-- Nothing here knows which game it's in: it walks every ScreenGui the
-- player has rather than a named one, so it's as useful on the next place
-- as it was on this one.
return function(import)

local Players = game:GetService("Players")
local log = import("core/logger")

local function dumpVisible(root, indent)
    indent = indent or ""

    for _, child in ipairs(root:GetChildren()) do
        if child:IsA("GuiObject") and child.Visible then
            local line = indent .. child.ClassName .. " '" .. child.Name .. "'"

            if child:IsA("TextLabel") or child:IsA("TextButton") then
                line = line .. " (Text=" .. tostring(child.Text) .. ")"
            end

            log(line)

            for attrName, attrValue in pairs(child:GetAttributes()) do
                log(indent .. "  [attr] " .. attrName .. " = " .. tostring(attrValue))
            end

            dumpVisible(child, indent .. "  ")
        end
    end
end

local function dumpGui()
    local playerGui = Players.LocalPlayer:FindFirstChild("PlayerGui")
    if not playerGui then
        log("[GuiDump] PlayerGui not found")
        return 0
    end

    local screens = 0
    log("[GuiDump] === visible PlayerGui tree ===")
    for _, screen in ipairs(playerGui:GetChildren()) do
        -- Our own menu would otherwise dominate the dump.
        if screen:IsA("LayerCollector") and screen.Enabled and screen.Name ~= "MekPro" then
            screens = screens + 1
            log("[GuiDump] " .. screen.ClassName .. " '" .. screen.Name .. "'")
            dumpVisible(screen, "  ")
        end
    end
    log("[GuiDump] === end (" .. screens .. " screen(s)) ===")
    return screens
end

return dumpGui

end

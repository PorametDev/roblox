-- Dumps whatever GuiObjects are currently VISIBLE under MineGui (hidden
-- frames are skipped to cut noise). Open the screen you want to inspect
-- (chest reward popup, sell menu, etc) first, then run this - works for
-- any screen since it doesn't assume a specific frame name.
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

local function dumpMineGui()
    local playerGui = Players.LocalPlayer:FindFirstChild("PlayerGui")
    local mineGui = playerGui and playerGui:FindFirstChild("MineGui")

    if not mineGui then
        log("[GuiDump] MineGui not found")
        return
    end

    log("[GuiDump] === visible MineGui tree ===")
    dumpVisible(mineGui)
    log("[GuiDump] === end ===")
end

return dumpMineGui

end

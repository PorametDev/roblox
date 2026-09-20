return function(import)

local log = import("core/logger")
local Players = game:GetService("Players")
local VirtualUser = game:GetService("VirtualUser")

local antiAfk = {}
local connection = nil

function antiAfk.SetEnabled(enabled)
    if enabled == antiAfk.IsEnabled() then
        return
    end

    if enabled then
        local player = Players.LocalPlayer
        log("[AntiAFK] enabled - watching Player.Idled")
        connection = player.Idled:Connect(function()
            log("[AntiAFK] idle detected, simulating input")
            VirtualUser:CaptureController()
            VirtualUser:ClickButton2(Vector2.new())
        end)
    else
        log("[AntiAFK] disabled")
        connection:Disconnect()
        connection = nil
    end
end

function antiAfk.IsEnabled()
    return connection ~= nil
end

return antiAfk

end

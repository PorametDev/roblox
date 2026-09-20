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
        print("[AntiAFK] enabled - watching Player.Idled")
        connection = player.Idled:Connect(function()
            print("[AntiAFK] idle detected, simulating input at", os.date("%X"))
            VirtualUser:CaptureController()
            VirtualUser:ClickButton2(Vector2.new())
        end)
    else
        print("[AntiAFK] disabled")
        connection:Disconnect()
        connection = nil
    end
end

function antiAfk.IsEnabled()
    return connection ~= nil
end

return antiAfk

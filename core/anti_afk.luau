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
        connection = player.Idled:Connect(function()
            VirtualUser:CaptureController()
            VirtualUser:ClickButton2(Vector2.new())
        end)
    else
        connection:Disconnect()
        connection = nil
    end
end

function antiAfk.IsEnabled()
    return connection ~= nil
end

return antiAfk

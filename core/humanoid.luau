-- Movement tweaks for the local character. Nothing here is specific to a
-- game, so it lives in core and every place script can use it.
--
-- All five re-apply themselves on respawn, since a new character resets
-- WalkSpeed/JumpPower and drops any BodyMover we added.
--
-- Worth being blunt about risk: speed, flight and noclip are the most
-- visible things on this list. The server sees the character's real
-- position, so flying across the map or walking through walls is plainly
-- anomalous movement in a way that firing a remote isn't. Small speed
-- bumps pass unnoticed far more easily than large ones.
local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local UserInputService = game:GetService("UserInputService")
local Workspace = game:GetService("Workspace")

local FLY_SPEED = 60

local humanoid = {}

local walkSpeed = nil
local jumpPower = nil
local flying = false
local noclip = false
local floating = false

local flyConnection, noclipConnection, floatConnection
local flyMover, floatMover
local respawnConnection

local function getCharacter()
    return Players.LocalPlayer.Character
end

local function getHumanoid()
    local character = getCharacter()
    return character and character:FindFirstChildOfClass("Humanoid")
end

local function getRoot()
    local character = getCharacter()
    return character and character:FindFirstChild("HumanoidRootPart")
end

function humanoid.SetWalkSpeed(value)
    walkSpeed = value
    local h = getHumanoid()
    if h then
        h.WalkSpeed = value
    end
end

function humanoid.SetJumpPower(value)
    jumpPower = value
    local h = getHumanoid()
    if h then
        -- JumpHeight replaced JumpPower on newer rigs; set whichever the
        -- character actually uses.
        h.UseJumpPower = true
        h.JumpPower = value
    end
end

local function stopFly()
    if flyConnection then
        flyConnection:Disconnect()
        flyConnection = nil
    end
    if flyMover then
        flyMover:Destroy()
        flyMover = nil
    end

    local h = getHumanoid()
    if h then
        h.PlatformStand = false
    end
end

local function startFly()
    stopFly()

    local root = getRoot()
    if not root then
        return
    end

    flyMover = Instance.new("BodyVelocity")
    flyMover.MaxForce = Vector3.new(1e5, 1e5, 1e5)
    flyMover.Velocity = Vector3.zero
    flyMover.Parent = root

    -- Steer with the usual movement keys, relative to where the camera is
    -- pointing, so flying feels like walking rather than a fixed heading.
    flyConnection = RunService.Heartbeat:Connect(function()
        local currentRoot = getRoot()
        if not (currentRoot and flyMover) then
            return
        end

        local camera = Workspace.CurrentCamera
        local direction = Vector3.zero

        if UserInputService:IsKeyDown(Enum.KeyCode.W) then
            direction = direction + camera.CFrame.LookVector
        end
        if UserInputService:IsKeyDown(Enum.KeyCode.S) then
            direction = direction - camera.CFrame.LookVector
        end
        if UserInputService:IsKeyDown(Enum.KeyCode.A) then
            direction = direction - camera.CFrame.RightVector
        end
        if UserInputService:IsKeyDown(Enum.KeyCode.D) then
            direction = direction + camera.CFrame.RightVector
        end
        if UserInputService:IsKeyDown(Enum.KeyCode.Space) then
            direction = direction + Vector3.yAxis
        end
        if UserInputService:IsKeyDown(Enum.KeyCode.LeftControl) then
            direction = direction - Vector3.yAxis
        end

        flyMover.Velocity = direction.Magnitude > 0
            and direction.Unit * FLY_SPEED
            or Vector3.zero
    end)
end

function humanoid.SetFlying(state)
    flying = state
    if state then
        startFly()
    else
        stopFly()
    end
end

local function stopNoclip()
    if noclipConnection then
        noclipConnection:Disconnect()
        noclipConnection = nil
    end

    local character = getCharacter()
    if character then
        for _, part in ipairs(character:GetDescendants()) do
            if part:IsA("BasePart") then
                part.CanCollide = true
            end
        end
    end
end

local function startNoclip()
    stopNoclip()

    -- Has to run every frame: the engine turns collision back on for
    -- character parts constantly.
    noclipConnection = RunService.Stepped:Connect(function()
        local character = getCharacter()
        if not character then
            return
        end
        for _, part in ipairs(character:GetDescendants()) do
            if part:IsA("BasePart") and part.CanCollide then
                part.CanCollide = false
            end
        end
    end)
end

function humanoid.SetNoclip(state)
    noclip = state
    if state then
        startNoclip()
    else
        stopNoclip()
    end
end

local function stopFloat()
    if floatConnection then
        floatConnection:Disconnect()
        floatConnection = nil
    end
    if floatMover then
        floatMover:Destroy()
        floatMover = nil
    end
end

-- Holds the character at the height it was at when switched on - handy for
-- standing still above the ground without the drifting that flight allows.
local function startFloat()
    stopFloat()

    local root = getRoot()
    if not root then
        return
    end

    local height = root.Position.Y

    floatMover = Instance.new("BodyPosition")
    floatMover.MaxForce = Vector3.new(0, 1e5, 0)
    floatMover.P = 10000
    floatMover.D = 500
    floatMover.Position = Vector3.new(0, height, 0)
    floatMover.Parent = root

    floatConnection = RunService.Heartbeat:Connect(function()
        local currentRoot = getRoot()
        if currentRoot and floatMover then
            floatMover.Position = Vector3.new(
                currentRoot.Position.X, height, currentRoot.Position.Z)
        end
    end)
end

function humanoid.SetFloating(state)
    floating = state
    if state then
        startFloat()
    else
        stopFloat()
    end
end

function humanoid.IsFlying()
    return flying
end

function humanoid.IsNoclip()
    return noclip
end

function humanoid.IsFloating()
    return floating
end

-- A fresh character resets everything, so put it all back.
local function reapply()
    task.wait(0.5)

    if walkSpeed then
        humanoid.SetWalkSpeed(walkSpeed)
    end
    if jumpPower then
        humanoid.SetJumpPower(jumpPower)
    end
    if flying then
        startFly()
    end
    if noclip then
        startNoclip()
    end
    if floating then
        startFloat()
    end
end

function humanoid.Start()
    if respawnConnection then
        return
    end
    respawnConnection = Players.LocalPlayer.CharacterAdded:Connect(reapply)
end

function humanoid.Stop()
    if respawnConnection then
        respawnConnection:Disconnect()
        respawnConnection = nil
    end
    stopFly()
    stopNoclip()
    stopFloat()
end

return humanoid

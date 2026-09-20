-- Logs every ProximityPrompt trigger, ClickDetector click, and UI button
-- press by connecting to their normal, public Roblox events - unlike a
-- metamethod hook (which Roblox's anti-cheat flags on sight), this only
-- listens to signals every script is meant to use.
return function(import)

local Players = game:GetService("Players")
local Workspace = game:GetService("Workspace")
local UserInputService = game:GetService("UserInputService")
local log = import("core/logger")

local interactionLogger = {}
local connections = nil

local function describe(instance)
    local ok, path = pcall(function()
        return instance:GetFullName()
    end)
    return ok and path or instance.Name
end

local function watchPrompt(prompt, list)
    table.insert(list, prompt.Triggered:Connect(function()
        log("[Interaction] ProximityPrompt triggered: " .. describe(prompt)
            .. " (ActionText=" .. prompt.ActionText .. ")")
    end))
end

local function watchClickDetector(detector, list)
    table.insert(list, detector.MouseClick:Connect(function()
        log("[Interaction] ClickDetector clicked: " .. describe(detector))
    end))
end

local function watchButton(button, list)
    table.insert(list, button.Activated:Connect(function()
        log("[Interaction] Button activated: " .. describe(button)
            .. " (Text=" .. tostring(button.Text) .. ")")
    end))
end

local function scan(root, list)
    for _, descendant in ipairs(root:GetDescendants()) do
        if descendant:IsA("ProximityPrompt") then
            watchPrompt(descendant, list)
        elseif descendant:IsA("ClickDetector") then
            watchClickDetector(descendant, list)
        elseif descendant:IsA("GuiButton") then
            watchButton(descendant, list)
        end
    end
end

function interactionLogger.SetEnabled(enabled)
    if enabled == interactionLogger.IsEnabled() then
        return
    end

    if not enabled then
        for _, connection in ipairs(connections) do
            connection:Disconnect()
        end
        connections = nil
        log("[Interaction] logger disabled")
        return
    end

    connections = {}
    log("[Interaction] logger enabled - go click/interact with things now")

    local playerGui = Players.LocalPlayer:WaitForChild("PlayerGui")

    scan(Workspace, connections)
    scan(playerGui, connections)

    -- Catches things that don't exist yet when enabled - e.g. the chest's
    -- "Take All" GUI, which is only created once the chest is opened.
    table.insert(connections, Workspace.DescendantAdded:Connect(function(descendant)
        if descendant:IsA("ProximityPrompt") then
            watchPrompt(descendant, connections)
        elseif descendant:IsA("ClickDetector") then
            watchClickDetector(descendant, connections)
        end
    end))

    table.insert(connections, playerGui.DescendantAdded:Connect(function(descendant)
        if descendant:IsA("GuiButton") then
            watchButton(descendant, connections)
        end
    end))

    table.insert(connections, UserInputService.InputBegan:Connect(function(input, gameProcessed)
        if input.UserInputType == Enum.UserInputType.Keyboard then
            log(string.format(
                "[Interaction] Key pressed: %s (gameProcessed=%s)",
                input.KeyCode.Name, tostring(gameProcessed)
            ))
        end
    end))
end

function interactionLogger.IsEnabled()
    return connections ~= nil
end

return interactionLogger

end

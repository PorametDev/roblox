-- firesignal(button.Activated) reaches our own Interaction Logger connection
-- (so the log says "Button activated") but NOT the game's real handler for
-- some buttons - Auto Sell's SelectAllButton never flipped to "Deselect All"
-- no matter how long we waited, while Chest's TakeButton worked fine the
-- same way. The likely difference is a handler that uses the inputObject
-- argument, which firesignal passes as nil.
--
-- Real() simulates an actual mouse click at the button's on-screen position
-- through the normal input pipeline, so every connection the game has gets
-- hit exactly like a player click. It requires the button to actually be
-- visible on screen (that's why popup-hiding had to go).
local VirtualInputManager = game:GetService("VirtualInputManager")
local GuiService = game:GetService("GuiService")

local click = {}

-- Fires the Activated signal directly. Works for buttons whose handler
-- ignores its arguments, and works even when the button is hidden.
function click.Signal(button)
    return pcall(function()
        firesignal(button.Activated)
    end)
end

-- Clicks the button for real, via the engine's input pipeline.
function click.Real(button)
    local position = button.AbsolutePosition
    local size = button.AbsoluteSize
    if size.X <= 0 or size.Y <= 0 then
        return false, "button has no size on screen"
    end

    -- AbsolutePosition is measured below the topbar for a ScreenGui with
    -- IgnoreGuiInset off, but SendMouseButtonEvent takes raw window coords.
    local inset = GuiService:GetGuiInset()
    local x = position.X + size.X / 2 + inset.X
    local y = position.Y + size.Y / 2 + inset.Y

    return pcall(function()
        VirtualInputManager:SendMouseMoveEvent(x, y, game)
        task.wait(0.05)
        VirtualInputManager:SendMouseButtonEvent(x, y, 0, true, game, 1)
        task.wait(0.05)
        VirtualInputManager:SendMouseButtonEvent(x, y, 0, false, game, 1)
    end)
end

return click

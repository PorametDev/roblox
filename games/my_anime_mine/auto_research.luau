-- Buys plot research from the skill tree, opened by the LeftBar's
-- UpgradesButton:
--
--   SkillTreeFullFrame
--     Sidebar > List > CoreTab / Tab1..TabN
--         Content > Label ("The Underground") / Research ("Research 4/35")
--                 / Lock (present only on zones not reached yet)
--     Tree > Canvas
--         Node_<Id> > Content > Pips ("3/3") / Cost ("$24")
--     Detail > BuyButton > Content > Label
--
-- A node only carries a Cost label when it can be bought right now -
-- maxed ones and ones still behind a prerequisite have none - so that
-- label alone decides what's worth clicking, no tree-walking needed.
--
-- Registered with core/scheduler as EXCLUSIVE: full-screen menu.
return function(import)

local Players = game:GetService("Players")
local parseMoney = import("core/parse_money")
local click = import("core/click")
local log = import("core/logger")

local checkInterval = 30
local maxSpend = 100000

local function getMineGui()
    local playerGui = Players.LocalPlayer:FindFirstChild("PlayerGui")
    return playerGui and playerGui:FindFirstChild("MineGui")
end

local function getTreeFrame()
    local mineGui = getMineGui()
    return mineGui and mineGui:FindFirstChild("SkillTreeFullFrame")
end

local function getUpgradesButton()
    local mineGui = getMineGui()
    local leftBar = mineGui and mineGui:FindFirstChild("LeftBar")
    local content = leftBar and leftBar:FindFirstChild("Content")
    local container = content and content:FindFirstChild("Container")
    return container and container:FindFirstChild("UpgradesButton")
end

-- Zones the player hasn't reached carry a Lock frame; skip those outright.
local function zoneTabs(frame)
    local sidebar = frame:FindFirstChild("Sidebar")
    local list = sidebar and sidebar:FindFirstChild("List")
    if not list then
        return {}
    end

    local tabs = {}
    for _, tab in ipairs(list:GetChildren()) do
        if tab:IsA("TextButton") then
            local content = tab:FindFirstChild("Content")
            local locked = content and content:FindFirstChild("Lock")
            if not locked then
                local label = content and content:FindFirstChild("Label")
                table.insert(tabs, {
                    button = tab,
                    name = (label and label.Text ~= "" and label.Text) or tab.Name,
                })
            end
        end
    end
    return tabs
end

local function affordableNodes(frame)
    local tree = frame:FindFirstChild("Tree")
    local canvas = tree and tree:FindFirstChild("Canvas")
    if not canvas then
        return {}
    end

    local nodes = {}
    for _, node in ipairs(canvas:GetChildren()) do
        if node:IsA("TextButton") and node.Name:match("^Node_") then
            local content = node:FindFirstChild("Content")
            local cost = content and content:FindFirstChild("Cost")
            local price = cost and parseMoney(cost.Text)
            if price and price <= maxSpend then
                local pips = content:FindFirstChild("Pips")
                table.insert(nodes, {
                    button = node,
                    name = node.Name:sub(6),
                    price = price,
                    priceText = cost.Text,
                    pips = pips and pips.Text or "?",
                })
            end
        end
    end

    -- Cheapest first: more upgrades per pass, and the expensive ones will
    -- still be there next time.
    table.sort(nodes, function(a, b)
        return a.price < b.price
    end)

    return nodes
end

local autoResearch = {}
local enabled = false
local busy = false
local lastAttempt = 0

function autoResearch.SetEnabled(state)
    if state == enabled then
        return
    end
    enabled = state
    log("[AutoResearch] " .. (enabled and "enabled" or "disabled"))
end

function autoResearch.IsEnabled()
    return enabled
end

function autoResearch.IsBusy()
    return busy
end

function autoResearch.SetCheckInterval(seconds)
    checkInterval = math.max(seconds, 5)
end

function autoResearch.SetMaxSpend(amount)
    maxSpend = math.max(amount, 0)
end

local function buyNode(frame, node)
    click.Real(node.button)
    task.wait(0.4)

    local detail = frame:FindFirstChild("Detail")
    local buyButton = detail and detail:FindFirstChild("BuyButton")
    if not buyButton then
        log("[AutoResearch] no BuyButton after selecting " .. node.name)
        return false
    end

    -- "Max" means the node is already fully bought, so there's nothing to
    -- press even though it still had a Cost label a moment ago.
    local content = buyButton:FindFirstChild("Content")
    local label = content and content:FindFirstChild("Label")
    if label and label.Text == "Max" then
        return false
    end

    click.Real(buyButton)
    task.wait(0.5)

    log("[AutoResearch] bought " .. node.name .. " (" .. node.pips .. ") for " .. node.priceText)
    return true
end

local function runJob()
    busy = true

    local button = getUpgradesButton()
    if not button then
        busy = false
        return
    end

    click.Real(button)
    task.wait(0.8)

    local frame = getTreeFrame()
    if not (frame and frame.Visible) then
        log("[AutoResearch] upgrades menu didn't open")
        busy = false
        return
    end

    local bought = 0
    for _, tab in ipairs(zoneTabs(frame)) do
        if not enabled then
            break
        end

        click.Real(tab.button)
        task.wait(0.5)

        for _, node in ipairs(affordableNodes(frame)) do
            if not enabled then
                break
            end
            if buyNode(frame, node) then
                bought = bought + 1
            end
        end
    end

    if bought == 0 then
        log("[AutoResearch] nothing affordable under the spend cap")
    end

    local close = frame:FindFirstChild("Close") or frame:FindFirstChild("ExitButton")
    if close then
        click.Real(close)
    end

    busy = false
end

function autoResearch.Step()
    if not enabled or busy then
        return
    end

    local now = tick()
    if now - lastAttempt < checkInterval then
        return
    end
    lastAttempt = now

    task.spawn(runJob)
end

return autoResearch

end

-- Upgrades the miners already standing on the plot. Firing a holder's
-- UpgradePart > UpgradeClick opens the unit screen:
--
--   SlotFocusFrame
--     Info > RowStack > CharName / Level ("Lv. 15 - Speed 30 - Mining x2.4")
--     BottomPanels > StatsPanel > Scroll
--       Damage / Speed / Mining
--         Content > LevelTitle ("Damage Level 15 / 100")
--         UpgradeButton > Content > Label ("$4,084")
--     ExitButton
--
-- The old version just fired UpgradeClick on every holder and stopped
-- there, which only ever opened that screen - it never bought anything.
--
-- Registered with core/scheduler as EXCLUSIVE: it opens a full-screen menu
-- and clicks through it.
return function(import)

local Players = game:GetService("Players")
local getCurrentPlot = import("games/my_anime_mine/get_current_plot")
local getPlotParts = import("games/my_anime_mine/get_plot_parts")
local parseMoney = import("core/parse_money")
local click = import("core/click")
local log = import("core/logger")

local STAT_NAMES = { "Damage", "Speed", "Mining" }

local checkInterval = 20
-- Nothing is bought above this, so a runaway loop can't drain the bank on
-- one absurdly priced stat.
local maxSpend = 100000

local function getFocusFrame()
    local playerGui = Players.LocalPlayer:FindFirstChild("PlayerGui")
    local mineGui = playerGui and playerGui:FindFirstChild("MineGui")
    return mineGui and mineGui:FindFirstChild("SlotFocusFrame")
end

local function findUpgradeClick(holder)
    local upgradePart = holder:FindFirstChild("UpgradePart")
    return upgradePart and upgradePart:FindFirstChildWhichIsA("ClickDetector")
end

local function occupiedHolders()
    local plot = getCurrentPlot()
    local parts = plot and getPlotParts(plot)
    if not (parts and parts.Holders) then
        return {}
    end

    local found = {}
    for _, holder in ipairs(parts.Holders:GetChildren()) do
        local detector = findUpgradeClick(holder)
        if detector then
            table.insert(found, { holder = holder, detector = detector })
        end
    end
    return found
end

-- Each stat row shows its next price on the button; a maxed stat shows
-- something that isn't a price at all, which parseMoney returns nil for.
local function readStat(scroll, statName)
    local row = scroll:FindFirstChild(statName)
    local button = row and row:FindFirstChild("UpgradeButton")
    local content = button and button:FindFirstChild("Content")
    local label = content and content:FindFirstChild("Label")
    if not label then
        return nil
    end

    return {
        name = statName,
        button = button,
        price = parseMoney(label.Text),
        text = label.Text,
    }
end

local autoUpgrade = {}
local enabled = false
local busy = false
local lastAttempt = 0

function autoUpgrade.SetEnabled(state)
    if state == enabled then
        return
    end
    enabled = state
    log("[AutoUpgrade] " .. (enabled and "enabled" or "disabled"))
end

function autoUpgrade.IsEnabled()
    return enabled
end

function autoUpgrade.IsBusy()
    return busy
end

function autoUpgrade.SetInterval(seconds)
    checkInterval = math.max(seconds, 1)
end

function autoUpgrade.SetMaxSpend(amount)
    maxSpend = math.max(amount, 0)
end

local function buyAffordableStats(entry)
    local frame = getFocusFrame()
    local panels = frame and frame:FindFirstChild("BottomPanels")
    local statsPanel = panels and panels:FindFirstChild("StatsPanel")
    local scroll = statsPanel and statsPanel:FindFirstChild("Scroll")
    if not scroll then
        log("[AutoUpgrade] upgrade screen didn't open for " .. entry.holder.Name)
        return 0
    end

    local bought = 0

    -- Cheapest first, and re-read after each purchase since buying one
    -- level raises that stat's next price.
    for _ = 1, #STAT_NAMES do
        local cheapest = nil
        for _, statName in ipairs(STAT_NAMES) do
            local stat = readStat(scroll, statName)
            if stat and stat.price and stat.price <= maxSpend then
                if not cheapest or stat.price < cheapest.price then
                    cheapest = stat
                end
            end
        end

        if not cheapest then
            break
        end

        click.Real(cheapest.button)
        log("[AutoUpgrade] bought " .. cheapest.name .. " for " .. cheapest.text
            .. " on " .. entry.holder.Name)
        bought = bought + 1
        task.wait(0.4)
    end

    return bought
end

local function closeFrame()
    local frame = getFocusFrame()
    local exit = frame and frame:FindFirstChild("ExitButton")
    if exit then
        click.Real(exit)
        task.wait(0.3)
    end
end

local function runJob()
    busy = true

    for _, entry in ipairs(occupiedHolders()) do
        if not enabled then
            break
        end

        fireclickdetector(entry.detector)
        task.wait(0.8)

        local frame = getFocusFrame()
        if frame and frame.Visible then
            buyAffordableStats(entry)
            closeFrame()
        end
    end

    busy = false
end

function autoUpgrade.Step()
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

return autoUpgrade

end

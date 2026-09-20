return function(import)
    local Players = game:GetService("Players")
    local createWindow = import("core/ui")(import)
    local i18n = import("core/i18n")
    local antiAfk = import("core/anti_afk")(import)
    local interactionLogger = import("core/interaction_logger")(import)
    local scheduler = import("core/scheduler")(import)
    local config = import("core/config")(import)
    local log = import("core/logger")

    local window = createWindow({
        Subtitle = "My Anime Mine · Mining Hub",
    })

    -- Every toggle below reads its starting state from the saved config and
    -- writes back on change, so a reload comes up exactly as it was left.
    -- AddToggle only renders the default, it doesn't fire the callback, so
    -- a saved-on toggle has to be applied to its module explicitly.
    local function persistentToggle(card, key, apply)
        local saved = config.Get(key, false)
        card:AddToggle(saved, function(state)
            config.Set(key, state)
            apply(state)
        end)
        if saved then
            apply(true)
        end
    end

    -- Same idea for the numeric settings: load, apply, and save on change,
    -- so every automation's tunables live in the menu rather than in the
    -- source.
    local function persistentSlider(tab, title, subtitle, min, max, key, default, apply, suffix)
        local saved = config.Get(key, default)
        tab:AddSlider(title, subtitle, min, max, saved, function(value)
            config.Set(key, value)
            apply(value)
        end, suffix)
        apply(saved)
    end

    local getCurrentPlot = import("games/my_anime_mine/get_current_plot")
    local getPlotParts = import("games/my_anime_mine/get_plot_parts")
    local dumpInstance = import("games/my_anime_mine/debug_dump")
    local dumpRemotes = import("games/my_anime_mine/debug_dump_remotes")(import)
    local dumpSellCards = import("games/my_anime_mine/debug_dump_sell_cards")(import)
    local dumpGui = import("games/my_anime_mine/debug_dump_gui")(import)
    local dumpChest = import("games/my_anime_mine/debug_dump_chest")(import)
    local autoMine = import("games/my_anime_mine/auto_mine")(import)
    local autoPlace = import("games/my_anime_mine/auto_place")(import)
    local autoChest = import("games/my_anime_mine/auto_chest")(import)
    local autoSell = import("games/my_anime_mine/auto_sell")(import)
    local autoUpgrade = import("games/my_anime_mine/auto_upgrade")(import)
    local autoResearch = import("games/my_anime_mine/auto_research")(import)

    -- Standalone: only fires ClickDetectors, which ignore distance, so
    -- these keep working no matter where an exclusive task has taken the
    -- character and never need to wait for a turn.
    scheduler.RegisterStandalone("AutoMine", autoMine.Step, autoMine.IsEnabled)

    -- Exclusive: each needs the character standing somewhere specific (the
    -- server checks real position) or a menu open on screen, so only one
    -- runs at a time. Registration order IS the priority order - collect
    -- the chest, then fill and upgrade every holder, and only sell once
    -- there's nothing left to place. Auto Sell has no HasWork check (you
    -- can't tell what's sellable without opening the menu), so it goes last
    -- and picks up whatever time the others aren't using.
    scheduler.RegisterExclusive("AutoChest", autoChest.Step, autoChest.IsEnabled, autoChest.IsBusy, autoChest.HasWork)
    scheduler.RegisterExclusive("AutoPlace", autoPlace.Step, autoPlace.IsEnabled, autoPlace.IsBusy, autoPlace.HasWork)
    scheduler.RegisterExclusive("AutoUpgrade", autoUpgrade.Step, autoUpgrade.IsEnabled, autoUpgrade.IsBusy)
    scheduler.RegisterExclusive("AutoResearch", autoResearch.Step, autoResearch.IsEnabled, autoResearch.IsBusy)
    scheduler.RegisterExclusive("AutoSell", autoSell.Step, autoSell.IsEnabled, autoSell.IsBusy)

    scheduler.Start()

    local farmTab = window:AddTab("ฟาร์ม", "🏠")

    persistentToggle(farmTab:AddCard(
        "Auto Mine",
        "กดหินอัตโนมัติทุก Node ใน plot ปัจจุบัน (ยิง ClickDetector 'NodeClick')"
    ), "autoMine", autoMine.SetEnabled)

    -- Total click traffic is nodes x clicks x speed per second, so these two
    -- multiply each other - worth turning up deliberately rather than
    -- maxing both.
    persistentSlider(farmTab, "Auto Mine: ความเร็ว", "จำนวนรอบต่อวินาที (ยิ่งสูงยิ่งถี่)",
        1, 30, "autoMineSpeed", 5, autoMine.SetCyclesPerSecond, "/s")
    persistentSlider(farmTab, "Auto Mine: คลิกต่อรอบ", "ยิงซ้ำกี่ครั้งต่อ Node ในแต่ละรอบ",
        1, 10, "autoMineClicks", 1, autoMine.SetClicksPerCycle, "x")

    persistentToggle(farmTab:AddCard(
        "Auto Place Miner",
        "เลือก miner ที่พลังสูงสุดจาก Backpack ไปวางลง Holder ที่ว่างอัตโนมัติ"
    ), "autoPlace", autoPlace.SetEnabled)
    persistentSlider(farmTab, "Auto Place: รอบเช็ค", "เช็คช่องว่าง/ตัวที่ควรเปลี่ยนทุกกี่วินาที",
        1, 60, "autoPlaceInterval", 3, autoPlace.SetCheckInterval, "s")

    persistentToggle(farmTab:AddCard(
        "Auto Chest",
        "เช็คจำนวนของจากป้ายบน chest เงียบๆ ถึงเกณฑ์แล้วค่อยไปเก็บ (ไม่รบกวนตอนยังไม่ถึง)"
    ), "autoChest", autoChest.SetEnabled)
    persistentSlider(farmTab, "Auto Chest: เกณฑ์เก็บ", "เก็บเมื่อของใน chest ถึงกี่ชิ้น",
        50, 3000, "autoChestMinItems", 100, autoChest.SetMinItems, " ชิ้น")
    persistentSlider(farmTab, "Auto Chest: รอบเช็ค", "อ่านป้ายบน chest ทุกกี่วินาที",
        1, 60, "autoChestInterval", 3, autoChest.SetCheckInterval, "s")

    persistentToggle(farmTab:AddCard(
        "Auto Sell",
        "ไปที่ SellStand แล้วกด Select All + Sell อัตโนมัติทุก 45 วินาที"
    ), "autoSell", autoSell.SetEnabled)
    persistentSlider(farmTab, "Auto Sell: รอบขาย", "ไปขายทุกกี่วินาที (ต้องเปิดเมนูทุกครั้ง)",
        10, 300, "autoSellInterval", 45, autoSell.SetCheckInterval, "s")

    persistentToggle(farmTab:AddCard(
        "Auto Upgrade Unit",
        "เปิดหน้าอัปเกรดของ miner ที่วางอยู่ แล้วซื้อ Damage/Speed/Mining ที่ราคาไม่เกินงบ"
    ), "autoUpgrade", autoUpgrade.SetEnabled)
    persistentSlider(farmTab, "Auto Upgrade: รอบเช็ค", "ไล่อัปเกรด miner ทุกกี่วินาที",
        5, 300, "autoUpgradeInterval", 20, autoUpgrade.SetInterval, "s")
    persistentSlider(farmTab, "Auto Upgrade: งบต่อครั้ง", "ไม่ซื้ออะไรที่แพงกว่านี้",
        1000, 1000000, "autoUpgradeMaxSpend", 100000, autoUpgrade.SetMaxSpend, "$")

    persistentToggle(farmTab:AddCard(
        "Auto Research (Plot)",
        "เปิดหน้า Upgrades แล้วซื้อ node ที่ปลดได้ในทุกโซน เรียงจากถูกไปแพง"
    ), "autoResearch", autoResearch.SetEnabled)
    persistentSlider(farmTab, "Auto Research: รอบเช็ค", "เปิดหน้า research ทุกกี่วินาที",
        10, 600, "autoResearchInterval", 30, autoResearch.SetCheckInterval, "s")
    persistentSlider(farmTab, "Auto Research: งบต่อครั้ง", "ไม่ซื้อ node ที่แพงกว่านี้",
        1000, 1000000, "autoResearchMaxSpend", 100000, autoResearch.SetMaxSpend, "$")

    -- Everything below lives in its own tab so shipping a release is just
    -- deleting this block - no debug controls tangled up with the real
    -- ones.
    local debugTab = window:AddTab("ดีบัก", "🐛")

    persistentToggle(
        debugTab:AddCard(
            "Interaction Logger",
            "เปิดแล้วไปกด/แตะอะไรก็ได้ในเกม ทุก prompt/click/ปุ่มจะถูกบันทึกลง MekPro.log"
        ),
        "interactionLogger",
        interactionLogger.SetEnabled
    )

    local debugCard = debugTab:AddCard("Debug: Current Plot", "กดเพื่อเช็ค plot ปัจจุบัน (ผลขึ้นตรงบนปุ่มเอง ไม่ต้องพึ่ง console)")
    -- Forward-declared: the callback below closes over `checkBtn`, but a
    -- `local checkBtn = AddButton(..., function() checkBtn... end)` in one
    -- statement would have the closure see the OUTER (nil) checkBtn - the
    -- new local's scope doesn't start until after the whole statement ends.
    local checkBtn
    checkBtn = debugCard:AddButton("Check", function()
        local plot = getCurrentPlot()
        if not plot then
            checkBtn.Text = "not found"
            log("[MyAnimeMine] not standing in any plot")
            return
        end

        local parts = getPlotParts(plot)
        local nodeCount = parts.Nodes and #parts.Nodes:GetChildren() or 0
        local holderCount = parts.Holders and #parts.Holders:GetChildren() or 0

        checkBtn.Text = plot.Name
        log(string.format(
            "[MyAnimeMine] current plot: %s | Nodes: %d | Holders: %d",
            plot.Name, nodeCount, holderCount
        ))
    end)

    local dumpCard = debugTab:AddCard(
        "Debug: Dump Node/Holder",
        "กดเพื่อบันทึกโครงสร้างข้างใน Node แรกกับ Holder แรกลง MekPro.log"
    )
    local dumpBtn
    dumpBtn = dumpCard:AddButton("Dump", function()
        local plot = getCurrentPlot()
        if not plot then
            dumpBtn.Text = "no plot"
            return
        end

        local ok, err = log("[MyAnimeMine] === Dump start ===")
        if not ok then
            dumpBtn.Text = "log failed"
            dumpCard:SetSubtitle("Error: " .. tostring(err))
            return
        end

        local parts = getPlotParts(plot)

        local firstNode = parts.Nodes and parts.Nodes:GetChildren()[1]
        if firstNode then
            log("[MyAnimeMine] === Node: " .. firstNode.Name .. " ===")
            dumpInstance(firstNode, log)
        else
            log("[MyAnimeMine] no nodes present right now")
        end

        local firstHolder = parts.Holders and parts.Holders:GetChildren()[1]
        if firstHolder then
            log("[MyAnimeMine] === Holder: " .. firstHolder.Name .. " ===")
            dumpInstance(firstHolder, log)
        else
            log("[MyAnimeMine] no holders found")
        end

        dumpBtn.Text = "Done"
    end)

    local toolDumpCard = debugTab:AddCard(
        "Debug: Dump Backpack Tool",
        "กดเพื่อบันทึก attribute/โครงสร้างของ miner ตัวแรกใน Backpack ลง MekPro.log"
    )
    local toolDumpBtn
    toolDumpBtn = toolDumpCard:AddButton("Dump", function()
        local backpack = Players.LocalPlayer:FindFirstChild("Backpack")
        local tool = backpack and backpack:FindFirstChildWhichIsA("Tool")
        if not tool then
            toolDumpBtn.Text = "no tool"
            return
        end

        log("[MyAnimeMine] === Tool: " .. tool.Name .. " ===")
        for attrName, attrValue in pairs(tool:GetAttributes()) do
            log("  [attr] " .. attrName .. " = " .. tostring(attrValue))
        end
        dumpInstance(tool, log)

        toolDumpBtn.Text = "Done"
    end)

    local remoteDumpCard = debugTab:AddCard(
        "Debug: Dump All Remotes",
        "กดเพื่อบันทึกรายชื่อ RemoteEvent/RemoteFunction ทั้งหมดใน ReplicatedStorage ลง MekPro.log"
    )
    local remoteDumpBtn
    remoteDumpBtn = remoteDumpCard:AddButton("Dump", function()
        local count = dumpRemotes()
        remoteDumpBtn.Text = count .. " remotes"
    end)

    local sellCardsDumpCard = debugTab:AddCard(
        "Debug: Dump Sell Cards",
        "เปิดหน้าขายของ (SellStand) ก่อน แล้วกดปุ่มนี้เพื่อดูว่าแต่ละ Card ระบุไอเทมด้วยอะไร"
    )
    local sellCardsDumpBtn
    sellCardsDumpBtn = sellCardsDumpCard:AddButton("Dump", function()
        local count = dumpSellCards()
        sellCardsDumpBtn.Text = count .. " cards"
    end)

    local guiDumpCard = debugTab:AddCard(
        "Debug: Dump Visible GUI",
        "เปิดหน้าจอที่อยากดูก่อน (เช่นหน้า Take All ตอนเปิด chest) แล้วกดปุ่มนี้"
    )
    local guiDumpBtn
    guiDumpBtn = guiDumpCard:AddButton("Dump", function()
        dumpGui()
        guiDumpBtn.Text = "Done"
    end)

    local chestDumpCard = debugTab:AddCard(
        "Debug: Dump Chest Data",
        "หาว่าจำนวนของใน chest ถูกเก็บไว้ที่ไหน จะได้เช็คได้โดยไม่ต้องเปิด UI"
    )
    local chestDumpBtn
    chestDumpBtn = chestDumpCard:AddButton("Dump", function()
        local count = dumpChest()
        chestDumpBtn.Text = count .. " parts"
    end)

    local settingsTab = window:AddTab("ตั้งค่า", "⚙")

    persistentToggle(
        settingsTab:AddCard("Anti-AFK", "ป้องกันถูกเตะออกจากห้องเวลาไม่ได้ขยับตัว"),
        "antiAfk",
        antiAfk.SetEnabled
    )

    local savedScale = config.Get("menuScale", 100)
    settingsTab:AddSlider("ขนาดเมนู", "ย่อขยายเมนูทั้งชุด", 50, 150, savedScale, function(value)
        config.Set("menuScale", value)
        window:SetScale(value)
    end)
    window:SetScale(savedScale)

    local savedLanguage = config.Get("languageIndex", 1)
    settingsTab:AddSegmented({ "ตามเครื่อง", "อังกฤษ", "ไทย" }, savedLanguage, function(index, value)
        local code = ({ "auto", "en", "th" })[index]
        config.Set("languageIndex", index)
        i18n.SetLanguage(code)
    end)
    i18n.SetLanguage(({ "auto", "en", "th" })[savedLanguage] or "auto")

    log("[MekPro] settings file: " .. config.Path())

    -- Without this, closing the UI (or the loader auto-cleaning up a
    -- previous run) leaves these background loops running forever,
    -- invisible and no longer controllable from any toggle.
    window:OnDestroy(function()
        scheduler.Stop()
        autoMine.SetEnabled(false)
        autoPlace.SetEnabled(false)
        autoChest.SetEnabled(false)
        antiAfk.SetEnabled(false)
        interactionLogger.SetEnabled(false)
        autoSell.SetEnabled(false)
        autoUpgrade.SetEnabled(false)
        autoResearch.SetEnabled(false)
    end)
end

return function(import)
    local createWindow = import("core/ui")(import)
    local i18n = import("core/i18n")
    local antiAfk = import("core/anti_afk")(import)
    local buildEnv = import("core/build_env")
    local scheduler = import("core/scheduler")(import)
    local spendPolicy = import("core/spend_policy")(import)
    local config = import("core/config")(import)
    local log = import("core/logger")

    -- First line in every session's log. Several debugging rounds have
    -- been spent on the question "is this log from the build I just
    -- pushed?", and it should never have to be asked again.
    log("[MekPro] build " .. buildEnv.Commit .. " (" .. buildEnv.Env
        .. ", built " .. buildEnv.BuiltAt .. ")")

    local window = createWindow({
        Subtitle = "My Anime Mine · Mining Hub",
    })

    -- Every toggle below reads its starting state from the saved config and
    -- writes back on change, so a reload comes up exactly as it was left.
    -- AddToggle only renders the default, it doesn't fire the callback, so
    -- a saved-on toggle has to be applied to its module explicitly.
    -- `default` matters for the options that ship switched on: without it
    -- the toggle rendered OFF while the module was still ON, so the menu
    -- disagreed with what was running.
    local function persistentToggle(card, key, apply, default)
        local saved = config.Get(key, default or false)
        card:AddToggle(saved, function(state)
            config.Set(key, state)
            apply(state)
        end)
        apply(saved)
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

    local function persistentSegmented(tab, options, values, key, default, apply)
        local savedIndex = config.Get(key, default)
        tab:AddSegmented(options, savedIndex, function(index)
            config.Set(key, index)
            apply(values[index])
        end)
        apply(values[savedIndex] or values[default])
    end

    local autoMine = import("games/my_anime_mine/auto_mine")(import)
    local autoPlace = import("games/my_anime_mine/auto_place")(import)
    local autoChest = import("games/my_anime_mine/auto_chest")(import)
    local autoSell = import("games/my_anime_mine/auto_sell")(import)
    local autoUpgrade = import("games/my_anime_mine/auto_upgrade")(import)
    local autoResearch = import("games/my_anime_mine/auto_research")(import)
    local autoClaim = import("games/my_anime_mine/auto_claim")(import)
    local autoPlot = import("games/my_anime_mine/auto_plot")(import)
    local gameApi = import("games/my_anime_mine/game_api")(import)

    -- Standalone: only fires ClickDetectors, which ignore distance, so
    -- these keep working no matter where an exclusive task has taken the
    -- character and never need to wait for a turn.
    scheduler.RegisterStandalone("AutoMine", autoMine.Step, autoMine.IsEnabled)

    -- Exclusive: each needs the character standing somewhere specific (the
    -- server checks real position) or a menu open on screen, so only one
    -- runs at a time. Registration order IS the priority order - collect
    -- the chest, then fill and upgrade every holder, and only sell once
    -- there's nothing left to place, upgrade and research. Every one of
    -- them can answer HasWork off the client's own state table now, so a
    -- turn is only ever taken by something that has something to do.
    scheduler.RegisterExclusive("AutoChest", autoChest.Step, autoChest.IsEnabled, autoChest.IsBusy, autoChest.HasWork)
    scheduler.RegisterExclusive("AutoPlace", autoPlace.Step, autoPlace.IsEnabled, autoPlace.IsBusy, autoPlace.HasWork)
    scheduler.RegisterExclusive("AutoUpgrade", autoUpgrade.Step, autoUpgrade.IsEnabled, autoUpgrade.IsBusy, autoUpgrade.HasWork)
    scheduler.RegisterExclusive("AutoResearch", autoResearch.Step, autoResearch.IsEnabled, autoResearch.IsBusy, autoResearch.HasWork)
    scheduler.RegisterExclusive("AutoClaim", autoClaim.Step, autoClaim.IsEnabled, autoClaim.IsBusy, autoClaim.HasWork)
    scheduler.RegisterExclusive("AutoPlot", autoPlot.Step, autoPlot.IsEnabled, autoPlot.IsBusy, autoPlot.HasWork)

    -- Sell stays last in the order, but "place before sell" is now stated
    -- as a dependency instead of relying on that position: Auto Sell
    -- refuses to run while Auto Place still has holders to fill, so the
    -- units it would have sold are safe no matter who gets the turn.
    --
    -- That's what makes it safe to let Sell jump the queue quickly. At 90
    -- seconds it ran once while the chest refilled six times over, so
    -- there was never any money and every upgrade pass could afford
    -- exactly one thing. Selling is the faucet; starving it starves
    -- everything downstream.
    autoSell.SetHoldWhile(function()
        return autoPlace.IsEnabled() and autoPlace.HasWork()
    end)
    local sellMaxWait = config.Get("autoSellMaxWait", 20)
    scheduler.RegisterExclusive("AutoSell", autoSell.Step, autoSell.IsEnabled, autoSell.IsBusy, autoSell.HasWork, sellMaxWait)

    -- One spending order across every automation that buys anything.
    -- Each reports what it would spend next; the policy decides whose turn
    -- it is. Free actions - placing miners, handing out pickaxes we
    -- already own, switching zones - are never gated by it.
    spendPolicy.Register("AutoResearch", autoResearch.NextPrice)
    spendPolicy.Register("AutoUpgrade", autoUpgrade.NextPrice)
    spendPolicy.Register("AutoPlot", autoPlot.NextPrice)
    spendPolicy.Register("AutoPlace", autoPlace.NextPrice)

    scheduler.Start()

    local farmTab = window:AddTab("ฟาร์ม", "🏠")

    -- Sits at the top because it governs every buying option below it.
    farmTab:AddSectionHeader("ลำดับการใช้เงินรวมทุกระบบ")
    persistentSegmented(
        farmTab,
        { "ต่างคนต่างซื้อ", "ถูกสุดก่อน", "แพงสุดก่อน" },
        { "off", "cheapest", "dearest" },
        "spendOrder", 1, spendPolicy.SetMode
    )

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
    persistentToggle(
        farmTab:AddCard("Auto Place: เปลี่ยนตัวอ่อนออก",
            "ปิด = เติมเฉพาะช่องว่าง ไม่ยุ่งกับตัวที่วางอยู่แล้ว"),
        "autoPlaceUpgradeWeak", autoPlace.SetUpgradeWeakMiners
    )

    persistentToggle(
        farmTab:AddCard("Auto Place: ดึงตัวเก่งขึ้น hotbar",
            "ยิง MineEquipBest ของเกม - Auto Place วางได้เฉพาะตัวที่อยู่บน hotbar เท่านั้น"),
        "autoPlaceEquipBest", autoPlace.SetUseEquipBest, true
    )
    persistentSlider(farmTab, "Auto Place: รอบดึงตัวเก่ง", "ยิง Equip Best ทุกกี่วินาที",
        5, 300, "autoPlaceEquipBestInterval", 60, autoPlace.SetEquipBestInterval, "s")

    persistentToggle(
        farmTab:AddCard("Auto Place: ปลดล็อกช่อง miner",
            "วาปไปกด E ที่แท่นที่ขึ้น 'Locked miner slot / Unlock' - ทำหลังสุดเมื่อช่องที่มีเต็มแล้ว"),
        "autoPlaceUnlock", autoPlace.SetUnlockSlots
    )
    persistentSlider(farmTab, "Auto Place: เพดานราคาปลดช่อง", "0 = ไม่จำกัด",
        0, 500, "autoPlaceUnlockBudget", 0,
        function(value) autoPlace.SetUnlockBudget(value * 1e6) end, "M")

    persistentToggle(farmTab:AddCard(
        "Auto Chest",
        "อ่านจำนวนจาก state ตรงๆ ถึงเกณฑ์แล้วยิง remote เก็บ (ไม่วาป ไม่เปิด UI)"
    ), "autoChest", autoChest.SetEnabled)
    persistentSlider(farmTab, "Auto Chest: เกณฑ์เก็บ", "เก็บเมื่อของใน chest ถึงกี่ชิ้น",
        50, 3000, "autoChestMinItems", 100, autoChest.SetMinItems, " ชิ้น")
    persistentSlider(farmTab, "Auto Chest: รอบเช็ค", "อ่านป้ายบน chest ทุกกี่วินาที",
        1, 60, "autoChestInterval", 3, autoChest.SetCheckInterval, "s")

    persistentToggle(farmTab:AddCard(
        "Auto Sell",
        "ไปที่ SellStand แล้วกด Select All + Sell อัตโนมัติทุก 45 วินาที"
    ), "autoSell", autoSell.SetEnabled)
    persistentToggle(
        farmTab:AddCard("Auto Sell: ไม่ขาย unit ที่ดีพอจะวาง",
            "ตัวที่ base damage สูงกว่าตัวที่อ่อนที่สุดบน holder = ของไว้อัปเกรด ไม่ใช่ของเหลือ"),
        "autoSellProtectUnits", gameApi.SetProtectUsefulUnits, true
    )
    persistentSlider(farmTab, "Auto Sell: รอบขาย", "ขายทุกกี่วินาที",
        5, 300, "autoSellInterval", 20, autoSell.SetCheckInterval, "s")
    -- Read once at registration, so this one only takes effect on reload.
    farmTab:AddSlider("Auto Sell: รอคิวได้นานสุด",
        "ถ้าโดนงานอื่นแซงเกินเวลานี้จะแทรกคิวเอง (มีผลหลังโหลดใหม่)",
        5, 120, sellMaxWait, function(value)
            config.Set("autoSellMaxWait", value)
        end, "s")

    persistentToggle(farmTab:AddCard(
        "Auto Upgrade Unit",
        "อัปเกรด Damage/Speed/Mining ของ miner ทุกตัวผ่าน remote ตรง (ไม่เปิด UI)"
    ), "autoUpgrade", autoUpgrade.SetEnabled)
    persistentSlider(farmTab, "Auto Upgrade: รอบเช็ค", "ไล่อัปเกรด miner ทุกกี่วินาที",
        5, 300, "autoUpgradeInterval", 20, autoUpgrade.SetInterval, "s")
    persistentSlider(farmTab, "Auto Upgrade: ซื้อสูงสุดต่อรอบ", "กันไม่ให้ใช้เงินหมดในรอบเดียว",
        1, 20, "autoUpgradeMaxPerPass", 5, autoUpgrade.SetMaxPerPass, "x")
    -- These are preferences: the named stat is bought first when it's
    -- affordable, and the lowest-level rule applies to the rest.
    persistentSegmented(
        farmTab,
        { "ต่ำสุดก่อน", "Damage ก่อน", "Speed ก่อน", "Mining ก่อน" },
        { "lowest", "Damage", "Speed", "MineSpeed" },
        "autoUpgradePriority", 1, autoUpgrade.SetPriority
    )
    -- Money is in the millions here, so a raw 0..N slider would be useless.
    -- One step = one million.
    persistentSlider(farmTab, "Auto Upgrade: กันเงินไว้", "ไม่ใช้เงินต่ำกว่าจำนวนนี้",
        0, 500, "autoUpgradeKeepMoney", 0,
        function(value) autoUpgrade.SetKeepMoney(value * 1e6) end, "M")

    persistentToggle(
        farmTab:AddCard("Auto Upgrade: ซื้อ Pickaxe ด้วย",
            "ร้าน pickaxe มีสต็อกจำกัดและรีสต็อกเป็นรอบ - ระบบจะซื้อเฉพาะตอนที่มีของจริง"),
        "autoUpgradePickaxe", autoUpgrade.SetBuyPickaxe, true
    )

    -- The names come from MineConfig, so list the real ones rather than
    -- making the user guess an index. 0 leaves the choice to Auto Upgrade,
    -- which copies the game's own "is a better pickaxe worth buying" rule.
    -- Multiplier is shown because that - not price - is what makes one
    -- pickaxe better than another.
    local pickaxes = gameApi.GetPickaxes()
    local pickaxeLabels = {}
    local highestIndex = 0
    for _, pickaxe in ipairs(pickaxes) do
        pickaxeLabels[pickaxe.index] = pickaxe.name .. " (x" .. pickaxe.multiplier .. ")"
        highestIndex = math.max(highestIndex, pickaxe.index)
    end

    if highestIndex > 0 then
        local pickaxeCard
        local function describePick(index)
            if index == 0 then
                return "0 = เลือกอัตโนมัติ (ตามสูตรของเกมเอง)"
            end
            return "#" .. index .. " " .. (pickaxeLabels[index] or "(ไม่มีตัวนี้ให้ซื้อด้วยเงิน)")
        end

        local savedPick = config.Get("autoUpgradePickaxeIndex", 0)
        pickaxeCard = farmTab:AddSlider(
            "Auto Upgrade: Pickaxe ที่จะซื้อ",
            describePick(savedPick),
            0, highestIndex, savedPick,
            function(value)
                config.Set("autoUpgradePickaxeIndex", value)
                autoUpgrade.SetPickaxeTarget(value)
                pickaxeCard:SetSubtitle(describePick(value))
            end,
            ""
        )
        autoUpgrade.SetPickaxeTarget(savedPick)
    end

    persistentToggle(
        farmTab:AddCard("Auto Upgrade: ไม่ซื้อเกินจำนวน holder",
            "pickaxe มีค่าเฉพาะตอนมีคนถือ - ซื้อเกินจำนวนช่องที่ปลดแล้วก็เปลืองเปล่า"),
        "autoUpgradeLimitPickaxes", autoUpgrade.SetLimitPickaxesToHolders, true
    )

    persistentToggle(
        farmTab:AddCard("Auto Upgrade: แจก Pickaxe ให้ miner",
            "แจกตัวที่ multiplier สูงสุดก่อน ถือซ้ำได้ถ้ามีหลายอัน"),
        "autoUpgradeEquipPickaxe", autoUpgrade.SetEquipPickaxes, true
    )

    persistentToggle(
        farmTab:AddCard("Auto Upgrade: สุ่ม Mutation",
            "รู้ราคาต่อครั้งแล้ว (GetMutationRollCost) แต่ยังเป็นการพนัน - ปิดไว้เป็นค่าเริ่มต้น"),
        "autoUpgradeRollMutation", autoUpgrade.SetRollMutations
    )
    persistentSlider(farmTab, "Mutation: หยุดเมื่อได้ x", "สุ่มจนกว่าตัวคูณจะถึงค่านี้แล้วเลิกยุ่งกับตัวนั้น",
        1, 20, "autoUpgradeMutationTarget", 2, autoUpgrade.SetMutationTarget, "x")
    persistentSlider(farmTab, "Mutation: เพดานราคาต่อครั้ง", "0 = ไม่จำกัด",
        0, 500, "autoUpgradeMutationBudget", 0,
        function(value) autoUpgrade.SetMutationBudget(value * 1e6) end, "M")

    persistentToggle(farmTab:AddCard(
        "Auto Research (Plot)",
        "ซื้อเฉพาะ node ที่เปิดแล้วและยังไม่เต็ม ตามกฎเดียวกับปุ่ม Buy ในเกม"
    ), "autoResearch", autoResearch.SetEnabled)
    persistentSlider(farmTab, "Auto Research: รอบเช็ค", "ไล่ซื้อทุกกี่วินาที",
        10, 600, "autoResearchInterval", 30, autoResearch.SetCheckInterval, "s")
    persistentSlider(farmTab, "Auto Research: ซื้อสูงสุดต่อรอบ", "กันไม่ให้ใช้เงินหมดในรอบเดียว",
        1, 20, "autoResearchMaxPerPass", 5, autoResearch.SetMaxPerPass, "x")
    persistentSlider(farmTab, "Auto Research: กันเงินไว้", "ไม่ใช้เงินต่ำกว่าจำนวนนี้",
        0, 500, "autoResearchKeepMoney", 0,
        function(value) autoResearch.SetKeepMoney(value * 1e6) end, "M")
    persistentToggle(
        farmTab:AddCard("Auto Research: ซื้อสาย Zone",
            "ต้นไม้ของแต่ละโซน (The Underground ฯลฯ)"),
        "autoResearchZones", autoResearch.SetBuyZones, true
    )
    persistentToggle(
        farmTab:AddCard("Auto Research: ซื้อสาย Core",
            "แท็บ Core ใช้ remote คนละตัวต่อหนึ่งอัปเกรด - เมื่อก่อนไม่ได้ซื้อเลย"),
        "autoResearchCore", autoResearch.SetBuyCore, true
    )
    persistentToggle(
        farmTab:AddCard("Auto Research: Core ต่อเมื่อสาย Zone ตันแล้ว",
            "Core ราคาหลักล้าน สาย Zone หลักหมื่น - ถ้าใช้เงินก้อนเดียวกัน Core จะกินเงินที่ Zone รออยู่"),
        "autoResearchCoreLast", autoResearch.SetCoreLastResort, true
    )
    persistentSegmented(
        farmTab,
        { "ถูกสุดก่อน", "แพงสุดก่อน" },
        { true, false },
        "autoResearchCheapestFirst", 1, autoResearch.SetCheapestFirst
    )

    persistentToggle(farmTab:AddCard(
        "Auto Claim (Index)",
        "เก็บรางวัล Index ที่ถึงเกณฑ์แล้วผ่าน remote ตรง (ไม่เปิด UI)"
    ), "autoClaim", autoClaim.SetEnabled)
    persistentSlider(farmTab, "Auto Claim: รอบเช็ค", "เช็ครางวัลที่เก็บได้ทุกกี่วินาที",
        5, 300, "autoClaimInterval", 30, autoClaim.SetCheckInterval, "s")
    persistentSlider(farmTab, "Auto Claim: เก็บสูงสุดต่อรอบ", "เกมเว้น 0.6 วิต่อการเก็บหนึ่งครั้ง",
        1, 30, "autoClaimMaxPerPass", 10, autoClaim.SetMaxPerPass, "x")

    persistentToggle(farmTab:AddCard(
        "Auto Upgrade Plot (Zone)",
        "ซื้อโซนถัดไปและย้ายไปขุดโซนที่ลึกที่สุดที่มีอยู่เสมอ"
    ), "autoPlot", autoPlot.SetEnabled)
    persistentSlider(farmTab, "Auto Plot: รอบเช็ค", "เช็คโซนทุกกี่วินาที",
        5, 300, "autoPlotInterval", 30, autoPlot.SetCheckInterval, "s")
    persistentToggle(
        farmTab:AddCard("Auto Plot: ซื้อโซนถัดไป",
            "ปุ่มบนป้ายใช้ remote เดียวกับการสลับโซน - server เป็นคนตัดสินว่าซื้อหรือย้าย"),
        "autoPlotBuy", autoPlot.SetBuyNextZone, true
    )
    persistentToggle(
        farmTab:AddCard("Auto Plot: ใช้โซนล่าสุดเสมอ",
            "ถ้าเผลอย้ายไปโซนเก่า จะย้ายกลับมาโซนที่ลึกที่สุดให้"),
        "autoPlotLatest", autoPlot.SetUseLatestZone, true
    )
    persistentSlider(farmTab, "Auto Plot: กันเงินไว้", "โซนแพงกว่า research มาก จึงมีเงินสำรองของตัวเอง",
        0, 500, "autoPlotKeepMoney", 0,
        function(value) autoPlot.SetKeepMoney(value * 1e6) end, "M")

    -- The debug tab is built by core/debug_tab and only when this is a dev
    -- build. In a prod bundle scripts/build.py leaves every core/debug_*
    -- module out of the output entirely, so this import has to stay inside
    -- the `if` - at the top of the file it would be a missing-module error.
    local stopDebug = nil
    if buildEnv.IsDev then
        stopDebug = import("core/debug_tab")(import)(window, {
            Toggle = persistentToggle,
            Slider = persistentSlider,
        })
    end


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
        autoSell.SetEnabled(false)
        autoUpgrade.SetEnabled(false)
        autoResearch.SetEnabled(false)
        autoClaim.SetEnabled(false)
        autoPlot.SetEnabled(false)
        if stopDebug then
            stopDebug()
        end
    end)
end

return function(import)
    local Players = game:GetService("Players")
    local createWindow = import("core/ui")(import)
    local i18n = import("core/i18n")
    local antiAfk = import("core/anti_afk")(import)
    local log = import("core/logger")

    local window = createWindow({
        Subtitle = "My Anime Mine · Mining Hub",
    })

    local getCurrentPlot = import("games/my_anime_mine/get_current_plot")
    local getPlotParts = import("games/my_anime_mine/get_plot_parts")
    local dumpInstance = import("games/my_anime_mine/debug_dump")
    local autoMine = import("games/my_anime_mine/auto_mine")(import)
    local autoPlace = import("games/my_anime_mine/auto_place")(import)
    local autoTakeChest = import("games/my_anime_mine/auto_take_chest")(import)

    local farmTab = window:AddTab("ฟาร์ม", "🏠")

    farmTab:AddCard(
        "Auto Mine",
        "กดหินอัตโนมัติทุก Node ใน plot ปัจจุบัน (ยิง ClickDetector 'NodeClick')"
    ):AddToggle(false, function(state)
        autoMine.SetEnabled(state)
    end)

    farmTab:AddCard(
        "Auto Place Miner",
        "หยิบ miner จาก Backpack ไปวางลง Holder ที่ว่างอัตโนมัติ"
    ):AddToggle(false, function(state)
        autoPlace.SetEnabled(state)
    end)

    local debugCard = farmTab:AddCard("Debug: Current Plot", "กดเพื่อเช็ค plot ปัจจุบัน (ผลขึ้นตรงบนปุ่มเอง ไม่ต้องพึ่ง console)")
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

    local dumpCard = farmTab:AddCard(
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

    local toolDumpCard = farmTab:AddCard(
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

    local settingsTab = window:AddTab("ตั้งค่า", "⚙")
    settingsTab:AddCard("Anti-AFK", "ป้องกันถูกเตะออกจากห้องเวลาไม่ได้ขยับตัว"):AddToggle(false, function(state)
        antiAfk.SetEnabled(state)
    end)
    settingsTab:AddSlider("ขนาดเมนู", "ย่อขยายเมนูทั้งชุด", 50, 150, 100, function(value)
        window:SetScale(value)
    end)
    settingsTab:AddSegmented({ "ตามเครื่อง", "อังกฤษ", "ไทย" }, 1, function(index, value)
        local code = ({ "auto", "en", "th" })[index]
        i18n.SetLanguage(code)
    end)

    -- Without this, closing the UI (or the loader auto-cleaning up a
    -- previous run) leaves these background loops running forever,
    -- invisible and no longer controllable from any toggle.
    window:OnDestroy(function()
        autoMine.SetEnabled(false)
        autoPlace.SetEnabled(false)
        autoTakeChest.SetEnabled(false)
        antiAfk.SetEnabled(false)
    end)
end

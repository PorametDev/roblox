return function(import)
    local createWindow = import("core/ui")(import)
    local i18n = import("core/i18n")
    local antiAfk = import("core/anti_afk")(import)
    local log = import("core/logger")

    local window = createWindow({
        Subtitle = "My Anime Mine · Mining Hub",
    })

    local getCurrentPlot = import("games/my_anime_mine/get_current_plot")
    local getPlotParts = import("games/my_anime_mine/get_plot_parts")

    local farmTab = window:AddTab("ฟาร์ม", "🏠")
    -- Business logic for My Anime Mine goes here.

    local debugCard = farmTab:AddCard("Debug: Current Plot", "กดเพื่อเช็ค plot ปัจจุบัน (ผลขึ้นตรงนี้ ไม่ต้องพึ่ง console)")
    debugCard:AddButton("Check", function()
        local plot = getCurrentPlot()
        if not plot then
            debugCard:SetValue("not found")
            log("[MyAnimeMine] not standing in any plot")
            return
        end

        local parts = getPlotParts(plot)
        local nodeCount = parts.Nodes and #parts.Nodes:GetChildren() or 0
        local holderCount = parts.Holders and #parts.Holders:GetChildren() or 0

        debugCard:SetValue(plot.Name)
        log(string.format(
            "[MyAnimeMine] current plot: %s | Nodes: %d | Holders: %d",
            plot.Name, nodeCount, holderCount
        ))
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
end

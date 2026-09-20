return function(import)
    local createWindow = import("core/ui")(import)
    local i18n = import("core/i18n")
    local antiAfk = import("core/anti_afk")

    local window = createWindow({
        Subtitle = "My Anime Mine · Mining Hub",
    })

    local getCurrentPlot = import("games/my_anime_mine/get_current_plot")
    local getPlotParts = import("games/my_anime_mine/get_plot_parts")

    local farmTab = window:AddTab("ฟาร์ม", "🏠")
    -- Business logic for My Anime Mine goes here.

    farmTab:AddCard("Debug: Current Plot", "กดเพื่อพิมพ์ plot ปัจจุบันลง console"):AddButton("Check", function()
        local plot = getCurrentPlot()
        if not plot then
            print("[MyAnimeMine] not standing in any plot")
            return
        end

        local parts = getPlotParts(plot)
        print(
            "[MyAnimeMine] current plot:", plot.Name,
            "| Nodes:", parts.Nodes and #parts.Nodes:GetChildren() or 0,
            "| Holders:", parts.Holders and #parts.Holders:GetChildren() or 0
        )
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

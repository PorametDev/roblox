return function(import)
    local createWindow = import("core/ui")(import)
    local i18n = import("core/i18n")
    local antiAfk = import("core/anti_afk")

    local window = createWindow({
        Subtitle = "My Anime Mine · Mining Hub",
    })

    local farmTab = window:AddTab("ฟาร์ม", "🏠")
    farmTab:AddSectionHeader("สุ่มเด็ก")
    farmTab:AddCard("แพ็คในล่าสุด"):SetValue("—")

    farmTab:AddSectionHeader("งานประจำ")
    local autoClaimCard = farmTab:AddCard(
        "กดรับรางวัลให้อัตโนมัติ",
        "กดรับทั้งภารกิจและรางวัลตามเวลาเล่นทันทีที่ปลดล็อก"
    )
    autoClaimCard:AddToggle(false, function(state)
        print("Auto claim:", state)
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

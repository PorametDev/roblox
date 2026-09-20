local createWindow = loadstring(readfile("core/ui.luau"))()

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
settingsTab:AddSlider("ขนาดเมนู", "ย่อขยายเมนูทั้งชุด", 50, 100, 70, function(value)
    print("Menu scale:", value)
end)
settingsTab:AddSegmented({ "ตามเครื่อง", "อังกฤษ", "ไทย" }, 1, function(index, value)
    print("Language:", value)
end)

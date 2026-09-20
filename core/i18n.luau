local Players = game:GetService("Players")

-- Only the strings core/ui.luau itself owns (search box, footer hint, etc).
-- Per-game text (card titles, tab names) is each game's own responsibility;
-- a game can require this same module and add its own keys to STRINGS if it
-- wants its content translated too.
local STRINGS = {
    en = {
        search_placeholder = "Search functions...",
        open_menu_hint = "Open menu",
    },
    th = {
        search_placeholder = "ค้นหาฟังก์ชัน...",
        open_menu_hint = "ปุ่มเปิดเมนู",
    },
}

local function detectSystemLanguage()
    local player = Players.LocalPlayer
    local locale = player and player.LocaleId or "en-us"
    if locale:sub(1, 2):lower() == "th" then
        return "th"
    end
    return "en"
end

local i18n = {}
i18n.current = detectSystemLanguage()

local listeners = {}

-- code is "en", "th", or "auto" (detect from the player's Roblox locale).
function i18n.SetLanguage(code)
    if code == "auto" then
        code = detectSystemLanguage()
    end
    i18n.current = code
    for _, listener in ipairs(listeners) do
        listener(code)
    end
end

function i18n.T(key)
    local dict = STRINGS[i18n.current] or STRINGS.en
    return dict[key] or STRINGS.en[key] or key
end

-- Returns an unsubscribe function.
function i18n.OnChanged(callback)
    table.insert(listeners, callback)
    return function()
        local index = table.find(listeners, callback)
        if index then
            table.remove(listeners, index)
        end
    end
end

return i18n

-- Prices in this game render as "$4,084" or "$14.4B", so a plain tonumber
-- won't do. Upgrade automations compare these against a spending cap
-- before clicking anything, and reading "14.4B" as 14.4 would happily buy
-- something costing billions.
local SUFFIXES = {
    K = 1e3,
    M = 1e6,
    B = 1e9,
    T = 1e12,
    Qa = 1e15,
    Qi = 1e18,
}

-- Returns nil for text that isn't a price at all, so callers can tell
-- "free" apart from "no price shown".
return function(text)
    if type(text) ~= "string" then
        return nil
    end

    local number, suffix = text:match("%$%s*([%d,%.]+)%s*(%a*)")
    if not number then
        return nil
    end

    local value = tonumber((number:gsub(",", "")))
    if not value then
        return nil
    end

    if suffix ~= "" then
        local multiplier = SUFFIXES[suffix] or SUFFIXES[suffix:sub(1, 1):upper() .. suffix:sub(2)]
        if not multiplier then
            -- An unrecognised suffix means a bigger unit than we know
            -- about, so treat it as unaffordable rather than cheap.
            return math.huge
        end
        value = value * multiplier
    end

    return value
end

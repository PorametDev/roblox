-- One decision about what gets bought next, across every automation that
-- spends money.
--
-- Each buyer used to decide alone: Auto Research bought its cheapest open
-- node, Auto Upgrade bought whatever stat it fancied, Auto Plot bought a
-- zone, and whoever happened to get a scheduler turn first won. That
-- ordering was an accident of registration order, not a choice, and there
-- was no way to say "spend on the cheapest thing anywhere" or "always go
-- for the biggest purchase available".
--
-- So buyers register a probe that answers one question - what would you
-- spend next, and how much - and ask MaySpend() before committing. Under
-- "cheapest" only the buyer holding the globally cheapest candidate is
-- allowed through; under "dearest", the most expensive one.
--
-- The probe is asked for a PRICE, not a promise. Nothing here moves money;
-- it only decides whose turn to spend it is.
-- Deliberately a singleton. `import` caches the factory below, not what it
-- returns, so every `import("core/spend_policy")(import)` would otherwise
-- hand back a fresh table with its own empty probe list - and the buyers
-- would never see one another, which is the entire point of this module.
local instance

return function(import)

if instance then
    return instance
end


local log = import("core/logger")

local policy = {}
local probes = {}
local order = {}
local mode = "off"

-- Blocking a buyer indefinitely is the same trap the scheduler fell into:
-- if the global winner can never actually complete its purchase - the
-- server refuses it, or its price is misread - everyone else waits
-- forever. Past this, a blocked buyer goes ahead regardless.
local MAX_BLOCK = 60
local blockedSince = {}

-- `probe(mode)` returns the price this buyer would spend next under that
-- mode, or nil when it has nothing to buy.
function policy.Register(name, probe)
    if not probes[name] then
        table.insert(order, name)
    end
    probes[name] = probe
    blockedSince[name] = nil
end

-- "off" | "cheapest" | "dearest"
function policy.SetMode(value)
    if value == mode then
        return
    end
    mode = value
    blockedSince = {}
    log("[SpendPolicy] " .. (mode == "off"
        and "off - every automation spends on its own"
        or ("buying the " .. mode .. " thing available first")))
end

function policy.GetMode()
    return mode
end

local function priceFor(name)
    local probe = probes[name]
    if not probe then
        return nil
    end
    local ok, price = pcall(probe, mode)
    if not ok then
        return nil
    end
    return tonumber(price)
end

-- True when this buyer holds the candidate the policy favours - or when
-- nothing else wants to spend, or it has waited too long to keep blocking.
function policy.MaySpend(name)
    if mode == "off" then
        return true
    end

    local price = priceFor(name)
    if not price then
        -- Nothing to buy means nothing to arbitrate.
        blockedSince[name] = nil
        return true
    end

    local beaten = false
    for _, other in ipairs(order) do
        if other ~= name then
            local theirs = priceFor(other)
            if theirs then
                -- Ties let both through: two equal prices have no
                -- meaningful order, and picking one would just be a
                -- second, hidden priority rule.
                if mode == "cheapest" and theirs < price then
                    beaten = true
                    break
                elseif mode == "dearest" and theirs > price then
                    beaten = true
                    break
                end
            end
        end
    end

    if not beaten then
        blockedSince[name] = nil
        return true
    end

    local now = tick()
    blockedSince[name] = blockedSince[name] or now
    if now - blockedSince[name] >= MAX_BLOCK then
        log("[SpendPolicy] " .. name .. " waited "
            .. string.format("%.0f", now - blockedSince[name])
            .. "s behind a purchase that never happened - letting it spend")
        blockedSince[name] = nil
        return true
    end

    return false
end

instance = policy
return instance

end

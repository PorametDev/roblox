-- Hooks every RemoteEvent:FireServer / RemoteFunction:InvokeServer call and
-- logs the remote's full path plus its arguments, so the real remote behind
-- a GUI button/prompt can be found by just watching what fires while you
-- interact with it normally - no need to guess or reverse the client script.
return function(import)

local log = import("core/logger")

local remoteSpy = {}
local originalNamecall = nil

local function serializeArg(value)
    local ok, t = pcall(typeof, value)
    if not ok then
        return "<unreadable>"
    end

    if t == "Instance" then
        local nameOk, fullName = pcall(function()
            return value.ClassName .. "(" .. value:GetFullName() .. ")"
        end)
        return nameOk and fullName or "<Instance>"
    elseif t == "table" then
        local parts = {}
        for k, v in pairs(value) do
            table.insert(parts, tostring(k) .. "=" .. tostring(v))
        end
        return "{" .. table.concat(parts, ", ") .. "}"
    else
        return tostring(value)
    end
end

function remoteSpy.SetEnabled(enabled)
    if enabled == remoteSpy.IsEnabled() then
        return
    end

    if not enabled then
        if originalNamecall then
            pcall(hookmetamethod, game, "__namecall", originalNamecall)
        end
        originalNamecall = nil
        log("[RemoteSpy] disabled")
        return
    end

    if not (hookmetamethod and getnamecallmethod) then
        log("[RemoteSpy] hookmetamethod/getnamecallmethod not available on this executor")
        return
    end

    log("[RemoteSpy] enabled - go interact with the thing you want to trace")

    originalNamecall = hookmetamethod(game, "__namecall", function(self, ...)
        local method = getnamecallmethod()
        local args = { ... }

        local ok, className = pcall(function()
            return self.ClassName
        end)

        if ok
            and (className == "RemoteEvent" or className == "RemoteFunction")
            and (method == "FireServer" or method == "InvokeServer")
        then
            local parts = {}
            for _, arg in ipairs(args) do
                table.insert(parts, serializeArg(arg))
            end

            local pathOk, path = pcall(function()
                return self:GetFullName()
            end)

            log(string.format(
                "[RemoteSpy] %s:%s(%s)",
                pathOk and path or "<unknown remote>", method, table.concat(parts, ", ")
            ))
        end

        return originalNamecall(self, ...)
    end)
end

function remoteSpy.IsEnabled()
    return originalNamecall ~= nil
end

return remoteSpy

end

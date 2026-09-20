-- Prints every descendant's ClassName/Name/relevant properties under an
-- instance, so we can see exactly what a Node or Holder is built from
-- (ProximityPrompt? ClickDetector? RemoteEvent?) before writing real
-- automation against it.
local function dumpInstance(instance, log, indent)
    indent = indent or ""

    for _, child in ipairs(instance:GetChildren()) do
        local line = indent .. child.ClassName .. " '" .. child.Name .. "'"

        if child:IsA("ProximityPrompt") then
            line = line .. string.format(
                " (ActionText=%s ObjectText=%s HoldDuration=%s)",
                child.ActionText, child.ObjectText, tostring(child.HoldDuration)
            )
        elseif child:IsA("ClickDetector") then
            line = line .. string.format(" (MaxActivationDistance=%s)", tostring(child.MaxActivationDistance))
        elseif child:IsA("RemoteEvent") or child:IsA("RemoteFunction") then
            line = line .. " <-- remote, likely fired by the real interaction"
        end

        log(line)

        for attrName, attrValue in pairs(child:GetAttributes()) do
            log(indent .. "  [attr] " .. attrName .. " = " .. tostring(attrValue))
        end

        dumpInstance(child, log, indent .. "  ")
    end
end

return dumpInstance

-- print() output depends on the executor's console working, which isn't
-- reliable across every executor (or every session). This also appends to
-- a local file, so logs survive even when the console doesn't show them -
-- open MekPro.log in the executor's workspace folder to read them.
local LOG_FILE = "MekPro.log"

local function log(message)
    local line = os.date("[%X] ") .. message
    print(line)

    -- Not every executor exposes appendfile; fall back to a manual
    -- read-modify-write with writefile/readfile, which is more widely
    -- supported. Prints the real error instead of swallowing it, so a
    -- failure here is visible even without a working console.
    local ok, err = pcall(function()
        if appendfile then
            appendfile(LOG_FILE, line .. "\n")
        elseif writefile then
            local existing = ""
            if isfile and isfile(LOG_FILE) then
                existing = readfile(LOG_FILE)
            end
            writefile(LOG_FILE, existing .. line .. "\n")
        else
            error("neither appendfile nor writefile is available")
        end
    end)

    if not ok then
        print("[Logger] failed to write " .. LOG_FILE .. ": " .. tostring(err))
    end

    return ok, err
end

return log

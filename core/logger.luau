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
    -- supported. A call not throwing isn't proof it actually wrote
    -- anything (some sandboxes no-op silently), so read the file back
    -- and confirm this line is actually in it before calling it a success.
    local ok, err = pcall(function()
        if appendfile then
            -- appendfile errors (rather than creating it) when the file
            -- doesn't exist yet on this executor.
            if isfile and not isfile(LOG_FILE) then
                writefile(LOG_FILE, "")
            end
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

        if not (isfile and readfile) then
            error("no isfile/readfile available to verify the write")
        end
        if not isfile(LOG_FILE) then
            error("write reported success but " .. LOG_FILE .. " doesn't exist")
        end
        if not readfile(LOG_FILE):find(line, 1, true) then
            error("write reported success but the line isn't in " .. LOG_FILE)
        end
    end)

    if not ok then
        print("[Logger] failed to write " .. LOG_FILE .. ": " .. tostring(err))
    end

    return ok, err
end

return log

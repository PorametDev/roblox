-- print() output depends on the executor's console working, which isn't
-- reliable across every executor (or every session). This also appends to
-- a local file, so logs survive even when the console doesn't show them -
-- open MekPro.log in the executor's workspace folder to read them.
local LOG_FILE = "MekPro.log"

local function log(message)
    print(message)

    pcall(function()
        appendfile(LOG_FILE, os.date("[%X] ") .. message .. "\n")
    end)
end

return log

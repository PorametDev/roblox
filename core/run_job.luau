-- Runs an automation's one-shot job so that its busy flag is always
-- cleared, however the job ends.
--
-- Every automation here follows the same shape: set busy, do the work in a
-- spawned thread, clear busy. The flaw is that task.spawn swallows errors -
-- if anything inside throws, the thread dies at that line and `busy =
-- false` never runs. The flag stays set forever, and because the scheduler
-- blocks every exclusive task while any one of them is busy, a single
-- error anywhere silently freezes the whole hub.
--
-- That is not hypothetical. Auto Sell did exactly this and took ninety
-- seconds of every other automation with it, which then got reported as
-- "Auto Research isn't buying".
--
-- The scheduler's watchdog is the backstop for jobs that hang rather than
-- throw; this is the fix for the ones that throw.
return function(import)

local log = import("core/logger")

-- `name` only appears if something goes wrong, so it can be the module's
-- log prefix.
return function(name, job, clear)
    task.spawn(function()
        local ok, err = pcall(job)
        if not ok then
            log("[" .. name .. "] job failed: " .. tostring(err))
        end
        -- Always, on both paths. The whole point.
        clear()
    end)
end

end

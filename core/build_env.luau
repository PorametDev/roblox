-- Which kind of build this is. scripts/build.py REPLACES this whole file
-- when bundling, so the value here is only what a local `main.luau` run
-- sees - and locally you're always developing.
--
-- The one thing this gates today is the debug tab. A prod bundle doesn't
-- merely hide it: build.py leaves every core/debug_* module out of the
-- bundle entirely, so the decompiler and the dumps aren't even shipped.
-- That means anything behind this flag must be imported lazily, inside the
-- `if`, never at the top of a file.
return {
    Env = "dev",
    IsDev = true,
    -- Filled in properly by the bundler; "local" is what a main.luau run
    -- from disk reports, since there is no bundle to identify.
    Commit = "local",
    BuiltAt = "local",
}

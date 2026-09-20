-- Local dev entry point: resolves modules from disk via readfile.
-- The published build (dist/out.lua, from scripts/build.py) resolves the
-- same "core/xxx" paths from an in-memory table instead — every other
-- source file is written against `import` and never calls readfile itself.
local cache = {}

local function import(path)
    if cache[path] == nil then
        cache[path] = loadstring(readfile(path .. ".luau"))()
    end
    return cache[path]
end

import("core/dispatch")(import)

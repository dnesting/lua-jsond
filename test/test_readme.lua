-- This tests that all of the example code blocks in README.md
-- run correctly and produce the expected output.

local doctests         = require("test/doctests")
local mocks            = require("test/mocks")
local jsond            = require("jsond")

local sandbox          = {
    ByteArray = mocks.ByteArray,
    Tvb       = mocks.Tvb,
    TvbRange  = mocks.TvbRange,
    jsond     = jsond,
    type      = type,
    next      = next,
    tostring  = tostring,
    pairs     = pairs,
    require   = function(name)
        if name == "jsond" then
            return jsond
        else
            error("Module not found: " .. name)
        end
    end,
}

doctests.retry_on_fail = true
doctests.before_retry  = function()
    jsond.set_debug(true)
    jsond.debug_prefix = "  "
    print()
end
doctests.after_retry   = function()
    jsond.set_debug(false)
    print()
end
doctests.verbose       = false
doctests.keep_going    = false

if not doctests.run_from_file("README.md", sandbox) then
    os.exit(1)
end

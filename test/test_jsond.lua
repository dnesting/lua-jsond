local jsond = require("jsont")
local mocks = require("test/mocks")
local ByteArray = mocks.ByteArray
local TvbRange = mocks.TvbRange

local function tvb(str)
    return ByteArray.new(str, true):tvb()()
end

local function str_val(val)
    return string.format("(%s) %s", type(val), tostring(val))
end

local function assert_nil(actual, message)
    if actual ~= nil then
        error((message or "expected nil") ..
            "\n      Actual: " .. str_val(actual) .. "\n", 2)
    end
end

local function assert_eq(actual, expected, message)
    if actual ~= expected then
        error((message or "expectation failed") ..
            "\n    Expected: " .. str_val(expected) ..
            "\n      Actual: " .. str_val(actual) .. "\n", 2)
    end
end

-- Test cases:
--     Test case field 1: JSON string to parse
--     Test case field 2: nil or expected value
--     Test case field 3: error returned by the initial parse
--
-- Expected values are:
--     EV field 1: JSON type of value
--     EV field 2: Lua value
--     EV field 3: The corresponding TvbRange:string() (nil = use test case field 1)
--     EV field 4: If not nil, a substring of the expected parse error
--
-- For arrays, the expected Lua value is instead a list of:
--     Array field 1: A list of expected values.
--     Array field 2: If not nil, a substring of the expected parse error
--
-- For objects, the expected Lua value is instead a list of:
--     Object field 1: A table with key-value pairs.
--         Key: the string key we expect to find in the returned object
--         Value: a pair of {expected value of the key}, {expected value of the value}
--     Object field 2: If not nil, a substring of the expected parse error

local test_cases = {
    -- { "json to parse", { "expected type", "expected value", "expected raw", "expected parse error substring" }, "substring in error" },
    { "",                        nil,                                                    "end of input" },
    -- basic types
    { "42",                      { "number", 42, nil, nil },                             nil },
    { "42.0",                    { "number", 42.0, nil, nil },                           nil },
    { "-42e2",                   { "number", -4200, nil, nil },                          nil },
    { "-42.0",                   { "number", -42.0, nil, nil },                          nil },
    { "true",                    { "boolean", true, nil, nil },                          nil },
    { "false",                   { "boolean", false, nil, nil },                         nil },
    { "null",                    { "null", nil, nil, nil },                              nil },
    { '"hello"',                 { "string", "hello", nil, nil },                        nil },
    { '"hello\\nthere"',         { "string", "hello\nthere", nil, nil },                 nil },
    { '"hello\\tthere\\u0040!"', { "string", "hello\tthere@!", nil, nil },               nil },
    -- arrays
    { "[]",                      { "array", {}, nil, nil },                              nil },
    { "[42]",                    { "array", { { "number", 42, "42", nil } }, nil, nil }, nil },
    { '[42, "abc", true]', { "array", {
        { "number",  42,    "42",    nil },
        { "string",  "abc", '"abc"', nil },
        { "boolean", true,  "true",  nil } }, nil, nil }, nil },
    -- objects
    { "{}",            { "object", {}, nil, nil },                                                                                                     nil },

    { '{"key": "value"}', { "object", {
        key = {
            { "string", "key",   '"key"',   nil },
            { "string", "value", '"value"', nil },
        }
    }, nil, nil }, nil },

    { '{"key": 42}', { "object", {
        key = {
            { "string", "key", '"key"', nil },
            { "number", 42,    "42",    nil },
        }
    }, nil, nil }, nil },

    { '{"key": [1, 2, 3]}', { "object", {
        key = {
            { "string", "key", '"key"', nil },
            { "array", {
                { "number", 1, "1", nil },
                { "number", 2, "2", nil },
                { "number", 3, "3", nil }
            }, "[1, 2, 3]", nil },
        }
    }, nil, nil }, nil },

    -- invalid numbers
    { "42e",           { "number", 42, "42e", "expected digit" },                                                                                      nil },
    { "42e+",          { "number", 42, "42e+", "expected digit" },                                                                                     nil },
    { "42e-",          { "number", 42, "42e-", "expected digit" },                                                                                     nil },

    -- invalid string
    { '"hello',        { "string", "hello", '"hello', "closing quote" },                                                                               nil },
    { '"hello\\',      { "string", "hello\\", '"hello\\', "invalid escape" },                                                                          nil },
    { '"hello\\u"',    { "string", "hello\\u", '"hello\\u"', "hex digits" },                                                                           nil },
    { '"hello\\u0"',   { "string", "hello\\u0", '"hello\\u0"', "hex digits" },                                                                         nil },
    { '"hello\\u00"',  { "string", "hello\\u00", '"hello\\u00"', "hex digits" },                                                                       nil },
    { '"hello\\u000"', { "string", "hello\\u000", '"hello\\u000"', "hex digits" },                                                                     nil },

    -- invalid keyword
    { "tru",           nil,                                                                                                                            "invalid" },
    { "xxx",           nil,                                                                                                                            "invalid" },

    -- invalid array
    { "[",             { "array", {}, "[", "expected number, " },                                                                                      nil },
    { "[42",           { "array", { { "number", 42, "42", nil } }, "[42", "expected , or ]" },                                                         nil },
    { "[42}",          { "array", { { "number", 42, "42", nil } }, "[42}", "expected , or ]" },                                                        nil },
    { "[42,",          { "array", { { "number", 42, "42", nil } }, "[42,", "expected number, " },                                                      nil },
    { "[42,]",         { "array", { { "number", 42, "42", nil } }, "[42,]", "expected number, " },                                                     nil },
    { "[42,,]",        { "array", { { "number", 42, "42", nil } }, "[42,,]", "expected number, " },                                                    nil },
    { "[42, 3.14e+]",  { "array", { { "number", 42, "42", nil }, { "number", 3.14, "3.14e+", "expected digit" } }, "[42, 3.14e+]", "expected digit" }, nil },

    -- invalid object
    { "{",             { "object", {}, "{", "expected string" },                                                                                       nil },
    { '{"key":',       { "object", { key = { { "string", "key", '"key"', nil }, nil } }, '{"key":', "expected number, " },                             nil },
    { '{"key": 42,',   { "object", { key = { { "string", "key", '"key"', nil }, { "number", 42, "42", nil } } }, '{"key": 42,', "expected string" },   nil },
    { '{"key": 42,}',  { "object", { key = { { "string", "key", '"key"', nil }, { "number", 42, "42", nil } } }, '{"key": 42,}', "expected string" },  nil },
    { '{"key": 42,,}', { "object", { key = { { "string", "key", '"key"', nil }, { "number", 42, "42", nil } } }, '{"key": 42,,}', "expected string" }, nil },
    { '{42: 42}',      { "object", { ["42"] = { { "string", "42", "42", "expected string" }, { "number", 42, "42", nil } } }, '{42: 42}', nil },       nil },
    { '{,}',           { "object", {}, "{,}", "expected string" },                                                                                     nil },
}

local function assert_val(got, json_str, expect_type, expect_val, expect_raw, expect_err)
    local got_type = jsond.type(got)
    assert_eq(got_type, expect_type, "returned value JSON type")
    local got_range = jsond.range(got)
    assert(got_range, "returned value should have a TvbRange, got nil")
    local got_raw = got_range:string()
    assert_eq(got_raw, expect_raw, "returned value's TvbRange")
    local got_err = jsond.get_error(got)

    if not expect_raw then
        expect_raw = json_str
    end

    if expect_err then
        assert(got_err, "expected parse error /" .. expect_err .. "/, got nil")
        assert(got_err:find(expect_err), "Expected /" .. expect_err .. "/, got: " .. got_err)
    else
        assert_nil(got_err, "no parse error expected")
    end

    if expect_type == "array" then
        -- expect_val is a list of expected values
        local array_val = jsond.value(got)
        assert_eq(#array_val, #expect_val, "array length")
        for i = 1, #array_val do
            local v = array_val[i]
            local e_type, e_val, e_raw, e_err = table.unpack(expect_val[i])
            assert_val(v, json_str, e_type, e_val, e_raw, e_err)
        end
    elseif expect_type == "object" then
        -- expect_val is a table with key-value pairs, where values are pairs of expected values (one for key, one for value)
        local obj_val = jsond.value(got)
        assert_eq(#obj_val, #expect_val, "object length")
        for got_k, got_v in pairs(obj_val) do
            -- got_k and got_v are both full Value instances
            local got_k_str = jsond.value(got_k)
            assert(got_k_str, "key")

            -- The expected value for the key is a pair of (key, value)
            local exp_pair = expect_val[got_k_str]
            assert(exp_pair, string.format("unexpected key %q found", got_k_str))
            local pair_key, pair_val = table.unpack(exp_pair)

            -- Test the key then the value
            local e_type, e_val, e_raw, e_err = table.unpack(pair_key)
            assert_val(got_k, json_str, e_type, e_val, e_raw, e_err)

            e_type, e_val, e_raw, e_err = table.unpack(pair_val)
            assert_val(got_v, json_str, e_type, e_val, e_raw, e_err)
        end

        -- Check that all expected keys are present
        -- Use got rather than obj_val because we are working with string keys
        -- and obj_val[k] assumes k is a Value instance
        for k, v in pairs(expect_val) do
            if not jsond.contains(got, k) then
                error(string.format("key %q not found in returned object", k))
            end
            if v and v[2] and not got[k] then
                error(string.format("value for key %q not found in expected object", k))
            end
        end
    else
        -- Just a regular value
        assert_eq(jsond.value(got), expect_val, "lua value")
    end
end

local function run_test(tc)
    local json_str, exp, exp_err = table.unpack(tc)
    local buf = tvb(json_str)
    local got, err = jsond.decode(buf)

    if exp_err then
        assert(err, "parse should error, got nil")
        assert(err:find(exp_err), "parse should contain /" .. exp_err .. "/, got: " .. err)
    else
        assert_nil(err, "parse should not error")
    end

    if exp == nil then
        assert_nil(got, "expected nil value")
        return
    end
    local exp_type, exp_val, exp_raw, exp_err = table.unpack(exp)
    assert_val(got, json_str, exp_type, exp_val, exp_raw, exp_err)
end

local function run_tests(keep_going)
    local all_passed = true
    for i, test in ipairs(test_cases) do
        local json_str, _, _, _ = table.unpack(test)
        io.write(string.format("case %2d %q:\t", i, json_str))
        if jsond.debug then
            print()
        end
        local success, err = pcall(run_test, test)
        if not success then
            print("FAIL")
            jsond.set_debug(true)
            jsond.debug_prefix = "  "
            print()
            print(string.format("  %q", json_str))
            print()
            _, err = xpcall(run_test, debug.traceback, test)
            print()
            assert(err)
            err = err:gsub("stack traceback:\n", "")
            err = err:gsub("[[]C[]]: in function 'error'[^\n]*\n", "")
            err = err:gsub("\t", "")
            err = err:gsub("\n", "\n  ")
            err = err:gsub("[^\n]+in function 'xpcall'.*", "")
            print("  " .. err)
            all_passed = false
            jsond.set_debug(false)
            if not keep_going then
                return 1
            end
        else
            print("PASS")
        end
    end
    if all_passed then
        print("PASS")
        return 0
    else
        print("FAIL")
        return 1
    end
end

os.exit(run_tests(false))

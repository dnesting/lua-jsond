-- Mock ByteArray
ByteArray = {}
ByteArray.__index = ByteArray
ByteArray.__name = "ByteArray"

function ByteArray.new(str, raw_bytes)
    local self = setmetatable({}, ByteArray)
    self.data = str
    --print("mock: ByteArray.new(" .. str .. ")")
    return self
end

function ByteArray:tvb(name)
    return Tvb.new(self.data, name)
end

function ByteArray:__tostring()
    return "ByteArray(" .. self.data .. ")"
end

-- Mock Tvb
Tvb = {}
Tvb.__index = Tvb
Tvb.__name = "Tvb"

function Tvb.new(data, name)
    local self = setmetatable({}, Tvb)
    --print("mock: Tvb.new(" .. data .. ")")
    self.data = data
    self.name = name
    return self
end

local function str_range(s, offset, length)
    local ss = s:sub(offset + 1, offset + length)
    --print("mock: range(" .. s .. ", " .. (offset or "<nil>") .. ", " .. (length or "<nil>") .. ") = " .. ss)
    return ss
end

function Tvb:range(offset, length)
    offset = offset or 0
    length = length or #self.data - offset
    --print("mock: TvbRange(" .. tostring(offset) .. ", " .. tostring(length) .. ")")
    return TvbRange.new(str_range(self.data, offset, length))
end

-- implement call
function Tvb:__call(offset, length)
    return self:range(offset, length)
end

function Tvb:__tostring()
    return "Tvb(" .. self.data .. ")"
end

-- Mock TvbRange
TvbRange = {}
TvbRange.__index = TvbRange
TvbRange.__name = "TvbRange"

function TvbRange.new(subdata)
    local self = setmetatable({}, TvbRange)
    --print("mock: TvbRange.new(" .. subdata .. ")")
    self.data = subdata
    return self
end

function TvbRange:__call(offset, length)
    offset = offset or 0
    length = length or #self.data - offset
    --print("mock: TvbRange(" .. tostring(offset) .. ", " .. tostring(length) .. ")")
    return TvbRange.new(str_range(self.data, offset, length))
end

function TvbRange:raw()
    --print("mock: TvbRange:raw() = " .. self.data)
    return self.data
end

function TvbRange:__tostring()
    return "TvbRange(" .. self.data .. ")"
end

function TvbRange:len()
    return #self.data
end

--

local function assert_eq(actual, expected, message)
    if actual ~= expected then
        error((message or "Assertion failed!") ..
            "\nExpected: " .. tostring(expected) ..
            "\nActual: " .. tostring(actual), 2)
    end
end

--

local jsond = require "jsond"

local function make_tvb(str, name)
    return ByteArray.new(str, true):tvb(name)()
end

local function test_mock()
    local x = make_tvb("abcd")
    assert_eq(x:raw(), "abcd", "Expected raw value")
    assert_eq(x(0, 2):raw(), "ab", "Expected first two bytes")
    assert_eq(x(1, 2):raw(), "bc", "Expected second two bytes")
end

local function test_number()
    local tvbr = make_tvb("42")
    local val = jsond.decode(tvbr)
    assert_eq(val:val(), 42, "Expected number value")
    assert_eq(val:range():raw(), "42", "Expected raw value")
end

local function test_string()
    local tvbr = make_tvb('"hello"')
    local val = jsond.decode(tvbr)
    assert_eq(val:val(), "hello", "Expected string value")
    assert_eq(val:range():raw(), "hello", "Expected raw value")

    tvbr = make_tvb('"hello\\nthere"')
    val = jsond.decode(tvbr)
    assert_eq(val:val(), "hello\nthere", "Expected string with newline")
    assert_eq(val:range():raw(), "hello\\nthere", "Expected escaped newline")

    tvbr = make_tvb('""')
    val = jsond.decode(tvbr)
    assert_eq(val:val(), "", "Expected empty string value")
    assert_eq(val:range():raw(), '', "Expected raw value for empty string")
end

local function test_literals()
    local tvbr = make_tvb("true")
    local val = jsond.decode(tvbr)
    assert_eq(val:val(), true, "Expected boolean value")
    assert_eq(val:range():raw(), "true", "Expected raw value")

    tvbr = make_tvb("false")
    val = jsond.decode(tvbr)
    assert_eq(val:val(), false, "Expected boolean value")
    assert_eq(val:range():raw(), "false", "Expected raw value")

    tvbr = make_tvb("null")
    val = jsond.decode(tvbr)
    assert_eq(val:val(), nil, "Expected null value")
    assert_eq(val:range():raw(), "null", "Expected raw value")
end

local function test_array()
    local tvbr = make_tvb("[1, 2, 3]")
    local val = jsond.decode(tvbr)
    assert_eq(val:range():raw(), "[1, 2, 3]", "Expected raw value")

    local e = val[1]
    assert_eq(e:val(), 1, "Expected first element value")
    assert_eq(e:range():raw(), "1", "Expected raw value for first element")
    e = val[2]
    assert_eq(e:val(), 2, "Expected second element value")
    assert_eq(e:range():raw(), "2", "Expected raw value for second element")
    e = val[3]
    assert_eq(e:val(), 3, "Expected third element value")
    assert_eq(e:range():raw(), "3", "Expected raw value for third element")
    e = val[4]
    assert_eq(e, nil, "Expected nil for out of bounds")
    assert_eq(val[4], nil, "Expected nil for out of bounds")

    local found1, found2, found3
    for i, v in ipairs(val) do
        if i == 1 then
            found1 = true
            assert_eq(v:val(), 1, "Expected first element value")
            assert_eq(v:range():raw(), "1", "Expected raw value for first element")
        elseif i == 2 then
            found2 = true
            assert_eq(v:val(), 2, "Expected second element value")
            assert_eq(v:range():raw(), "2", "Expected raw value for second element")
        elseif i == 3 then
            found3 = true
            assert_eq(v:val(), 3, "Expected third element value")
            assert_eq(v:range():raw(), "3", "Expected raw value for third element")
        else
            error("Unexpected index in array: " .. tostring(i))
        end
    end

    if not found1 then
        error("Index 1 not found in array")
    end
    if not found2 then
        error("Index 2 not found in array")
    end
    if not found3 then
        error("Index 3 not found in array")
    end
end

local function test_object()
    local tvbr = make_tvb('{"key1": "value1", "key2": "value2"}')
    local obj = jsond.decode(tvbr)
    local r, _ = obj()
    assert_eq(r:raw(), '{"key1": "value1", "key2": "value2"}', "Expected raw value")
    local e = obj.key1
    assert_eq(e:val(), "value1", "Expected value for key1")
    assert_eq(e:range():raw(), 'value1', "Expected raw value for key1")
    e = obj.key2
    assert_eq(e:val(), "value2", "Expected value for key2")
    assert_eq(e:range():raw(), 'value2', "Expected raw value for key2")
    e = obj.key3
    assert_eq(e, nil, "Expected nil for non-existing key")
    assert_eq(obj.key3, nil, "Expected nil for non-existing key")

    e = obj["key1"]
    assert_eq(e:val(), "value1", "Expected value for key1")
    assert_eq(e:range():raw(), 'value1', "Expected raw value for key1")
    e = obj["key2"]
    assert_eq(e:val(), "value2", "Expected value for key2")
    assert_eq(e:range():raw(), 'value2', "Expected raw value for key2")
    e = obj["key3"]
    assert_eq(e, nil, "Expected nil for non-existing key")
    assert_eq(obj["key3"], nil, "Expected nil for non-existing key")

    local found1, found2
    for k, v in pairs(obj) do
        if k:val() == "key1" then
            found1 = true
            assert_eq(v:val(), "value1", "Expected value for key1")
            assert_eq(v:range():raw(), 'value1', "Expected raw value for key1")
        elseif k:eq("key2") then
            found2 = true
            assert_eq(v:val(), "value2", "Expected value for key2")
            assert_eq(v:range():raw(), 'value2', "Expected raw value for key2")
        else
            error("Unexpected key in object: " .. tostring(k))
        end
    end
    if not found1 then
        error("Key 'key1' not found in object")
    end
    if not found2 then
        error("Key 'key2' not found in object")
    end
end

-- Main runner
local tests = {
    test_mock = test_mock,
    test_number = test_number,
    test_literals = test_literals,
    test_string = test_string,
    test_array = test_array,
    test_object = test_object,
}

local failed = 0

for name, test in pairs(tests) do
    local status, err = true, nil
    --status, err = pcall(test)
    test()
    if status then
        print("[PASS]", name)
    else
        print("[FAIL]", name)
        if err then
            print(err)
        end
        failed = failed + 1
    end
end

if failed > 0 then
    os.exit(1)
else
    print("All tests passed!")
end

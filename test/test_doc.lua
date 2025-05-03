-- All of the code samples from the documentation.
-- TODO: Extract these automatically somehow?

-- Mock ByteArray
local mocks = require("test/mocks")
ByteArray = mocks.ByteArray
Tvb = mocks.Tvb
TvbRange = mocks.TvbRange

local jsond = require("jsond")

local function test_1()
  local json      = '{"num_field": 42, "obj_field": {"obj_num": 43}, "array_field": ["one", "two"]}'
  local tvb_range = ByteArray.new(json, true):tvb()()

  local data      = jsond.decode(tvb_range) -- a Value

  data.num_field()
  data.obj_field.obj_num()

  for i, val in ipairs(data.array_field) do
    if not val then
      error("Expected value to be present")
    end
    local first_letter = val:sub(1, 1) -- "o", "t" Values
    if not first_letter then
      error("Expected first letter to be present")
    end
    if i == 1 and (not first_letter or first_letter:val() ~= "o") then
      error("Expected first letter to be 'o', got " .. tostring(first_letter))
    end
    if i == 2 and (not first_letter or first_letter:val() ~= "t") then
      error("Expected first letter to be 't', got " .. tostring(first_letter))
    end
  end
end

local function test_2()
  local buf  = ByteArray.new("42", true):tvb()()
  local data = jsond.decode(buf) -- Number
  if data:range() ~= buf(0, 2) then
    error("Expected range to be equal")
  end
  if data:val() ~= 42 then
    error("Expected value to be equal")
  end
end

local function test_3()
  local buf  = ByteArray.new("[42]", true):tvb()()
  local data = jsond.decode(buf) -- Array
  if data[1]:range() ~= buf(1, 2) then
    error("Expected range to be equal")
  end
  if data[1]:val() ~= 42 then
    error("Expected value to be equal")
  end
end

local function test_4()
  local buf = ByteArray.new("42", true):tvb()()
  local data = jsond.decode(buf) -- Number
  if jsond.range(data) ~= buf(0, 2) then
    error("Expected range to be equal")
  end
end

local function test_5()
  local buf = ByteArray.new("42", true):tvb()()
  local data = jsond.decode(buf) -- Number
  if jsond.value(data) ~= 42 then
    error("Expected value to be equal")
  end
end

local function test_6()
  local buf = ByteArray.new('""', true):tvb()()
  local data = jsond.decode(buf) -- String
  if not jsond.is_zero(data) then
    error("Expected data to be zero")
  end
end


-- ```lua
-- buf = ByteArray.new('{"b": 2, "a": 1}', true):tvb()()
-- data = jsond.decode(buf)  -- Object
-- for k, v in jsond.sorted(data)
--   print(i, v)
-- end
-- -- a 1
-- -- b 2
-- ```
--
-- ```lua
-- buf = ByteArray.new('["b", "a"]', true):tvb()()
-- data = jsond.decode(buf)  -- Array
-- for i, v in jsond.sorted(data)
--   print(i, v)
-- end
-- -- 1 a
-- -- 2 b
-- ```
--
-- ```lua
-- buf = ByteArray("42"):tvb()()
-- data = jsond.decode(buf)
-- jsond.type(data)  -- "number"
-- ```
--
-- ```lua
-- tree:add(field.my_field, data())
-- tree:add(field.my_field, jsond.range(data), jsond.value(data))
-- ```
--
-- ```lua
-- buf = ByteArray.new("42", true):tvb()()
-- val = jsond.decode(buf)
-- val == 42    -- false (val is a Value, not a number)
-- val:eq(42)   -- true
-- ```
--
-- ```lua
-- buf = ByteArray.new('"foo"'):tvb()()
-- s = jsond.decode(buf)
-- b = s:byte(2)           -- Number
-- b:range() == buf(1, 1)  -- true
-- b:val()   == 111        -- true (ord("o"))
-- ```
--
-- ```lua
-- buf = ByteArray.new('"foobar"'):tvb()()
-- s = jsond.decode(buf)
-- b = s:sub(4, 6)         -- String
-- b:range() == buf(4, 3)  -- true
-- b:val()   == "bar"      -- true
-- ```
--
-- ```lua
-- buf = ByteArray.new('{"field": "value"}', true):tvb()()
-- obj = json.decode(buf)      -- Object
-- field = next(obj)[1]        -- String "field"
-- obj[field] == obj["field"]  -- true
-- obj[field] == obj.field     -- true
-- ```
--

local tests = {
  test_1 = test_1,
  test_2 = test_2,
  test_3 = test_3,
  test_4 = test_4,
  test_5 = test_5,
  test_6 = test_6,
}

local function run_tests()
  for name, test in pairs(tests) do
    local status = true
    local err
    --local status, err = pcall(test)
    test()
    if not status then
      print("Test failed: " .. name .. ": " .. err)
    else
      print("Test passed: " .. name)
    end
  end
end

-- Run the tests
run_tests()

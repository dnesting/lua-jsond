--
-- jsond.lua
--
-- Copyright (c) 2025 David Nesting
-- Copyright (c) 2020 rxi
--
-- Permission is hereby granted, free of charge, to any person obtaining a copy of
-- this software and associated documentation files (the "Software"), to deal in
-- the Software without restriction, including without limitation the rights to
-- use, copy, modify, merge, publish, distribute, sublicense, and/or sell copies
-- of the Software, and to permit persons to whom the Software is furnished to do
-- so, subject to the following conditions:
--
-- The above copyright notice and this permission notice shall be included in all
-- copies or substantial portions of the Software.
--
-- THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
-- IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
-- FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
-- AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
-- LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
-- OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE
-- SOFTWARE.
--

-- This is an implementation of a JSON decoder that retains TvbRanges.
-- The resulting decoded values are callables that return
-- (TvbRange, value) pairs, which can be unpacked into a tree:add statement like:
--
--   jsond = require("jsond")
--   json_bytes = ByteArray.new('{"field1": "value1"}', true)
--   json_tvb_range = json_bytes:tvb("Test Data")()
--   instance = jsond.decode(json_tvb_range)
--
--   tree:add(fields.my_field1, instance.field1())
--   -- equivalent to:
--   tree:add(fields.my_field1, jsond.range(instance), jsond.value(instance))

local jsond = { _version = "0.0.1" }

-- keys for range and value to avoid collisions in Object
local RANGE = {}
local VALUE = {}

-- Class constructor for all types of Values.
local function class(super)
  local c = {}
  c.__index = c
  setmetatable(c, super)
  function c:new(range, value)
    local obj = { [RANGE] = range, [VALUE] = value }
    return setmetatable(obj, c)
  end

  if super then
    c.__call = super.__call
    c.__tostring = super.__tostring
  end

  return c
end

-- Returns true if obj is an instance of cls or a subclass of cls
local function isinstance(obj, cls)
  -- note that when this is used with types like Tvb or TvbRange,
  -- the mocks in test/test_jsond.lua also need to work.
  local mt = getmetatable(obj)
  while mt do
    local success, result = pcall(function() return mt == cls end)
    if success and result then
      return result
    end
    mt = getmetatable(mt)
  end
  return false
end

-- Obtains the TvbRange from the provided Value.
-- Value types other than Object also have a :range() convenience method.
function jsond.range(value)
  return rawget(value, RANGE)
end

-- Obtains the underlying Lua value from the provided Value.
-- Value types other than Object also have a :val() convenience method.
function jsond.value(value)
  return rawget(value, VALUE)
end

-- Returns the JSON type of the provided object, one of "boolean", "number", "string", "array", "object", "null",
-- or nil if obj is not a Value.
function jsond.type(obj)
  local mt = getmetatable(obj)
  if mt and mt.__json_type then
    return mt.__json_type
  end
  local val = rawget(obj, VALUE)
  if type(val) == "boolean" then
    return "boolean"
  end
  return nil -- maybe error?
end

-- Returns true if jsond.value(obj) is non-false and non-nil.
function jsond.bool(obj)
  local val = jsond.value(obj)
  return not not val
end

-- Returns true if jsond.value(obj) is nil, false, 0, "", or {}.
function jsond.is_zero(obj)
  local val = jsond.value(obj)
  if type(val) == "number" then
    return val == 0
  elseif type(val) == "string" then
    return #val == 0
  elseif type(val) == "table" then
    return next(val) == nil
  elseif type(val) == "boolean" then
    return not val
  elseif type(val) == "nil" then
    return true
  end
end

local Value = class()

function Value:__call()
  return jsond.range(self), jsond.value(self)
end

function Value:__tostring()
  return tostring(jsond.value(self))
end

local BasicValue = class(Value)

function BasicValue:range() return rawget(self, RANGE) end

function BasicValue:val() return rawget(self, VALUE) end

function BasicValue:type() return jsond.type(self) end

function BasicValue:raw() return rawget(self, RANGE):raw() end

function BasicValue:bool() return jsond.bool(self) end

function BasicValue:nonzero() return not jsond.is_zero(self) end

-- Ensures a is a Lua type, by calling jsond.value() if needed.
local function reduce(a)
  if isinstance(a, Value) then
    a = jsond.value(a)
  end
  return a
end

-- Comparison functions
function BasicValue.eq(a, b) return reduce(a) == reduce(b) end

function BasicValue.ne(a, b) return reduce(a) ~= reduce(b) end

function BasicValue.lt(a, b) return reduce(a) < reduce(b) end

function BasicValue.le(a, b) return reduce(a) <= reduce(b) end

function BasicValue.gt(a, b) return reduce(a) > reduce(b) end

function BasicValue.ge(a, b) return reduce(a) >= reduce(b) end

local Boolean = class(BasicValue)
Boolean.__json_type = "boolean"

local Null = class(BasicValue)
Null.__json_type = "null"

local Number = class(BasicValue)
Number.__json_type = "number"

function Number:nstime()
  local secs, nsecs = math.modf(self:val())
  return self:range(), NSTime.new(secs, nsecs * 1e9)
end

local parse_string0

local String = class(BasicValue)
String.__json_type = "string"

function String:__len() return #self:val() end

function String:byte(i, j)
  local res = {}
  while i <= j do
    -- use self:sub() since getting the range right can be tricky
    local ch = self:sub(i, i)
    res[i] = Number:new(ch:range(), ch:val():byte())
    i = i + 1
  end
  return table.unpack(res)
end

function String:ether() return self:range(), Address.ether(self:val()) end

function String:ipv4() return self:range(), Address.ipv4(self:val()) end

function String:ipv6() return self:range(), Address.ipv6(self:val()) end

function String:lower() return String:new(self:range(), self:val():lower()) end

function String:number(base)
  local val = self:val()
  local n = tonumber(val, base)
  if n then
    return Number:new(self:range(), n)
  end
  return nil
end

function String:sub(str_start, str_end)
  local range = self:range()
  local rng_start = 0

  if str_start > 1 then
    -- Partially parse range until we have length str_start
    -- to account for ranges that contain escaped characters
    -- that consume more than one byte for one character.
    _, rng_start = parse_string0(range, 0, str_start)
  end

  -- Partially parse range until we have accumulated enough characters
  -- to satisfy str_end.
  local _, rng_after = parse_string0(range, rng_start, str_end - str_start + 1)
  return String:new(
    range(rng_start, rng_after - 1),
    self:val():sub(str_start, str_end))
end

function String:upper() return String:new(self:range(), self:val():upper()) end

-- Don't inherit from Simple since we want any indexing to
-- be passed to the underlying table value.  This means no
-- object methods.
local Object = class(Value)
Object.__json_type = "object"

local LOOKUP = {}

function Object:new(range, value)
  local obj = {
    [RANGE] = range,
    [VALUE] = {},
    [LOOKUP] = {},
  }
  obj = setmetatable(obj, self)
  if value then
    for k, v in pairs(value) do
      obj[k] = v
    end
  end
  return obj
end

function Object:__pairs()
  return pairs(rawget(self, VALUE))
end

function Object:__index(key)
  if Object[key] then
    return Object[key]
  end

  -- simple case, the key is a Value that maps to a table key
  local obj = rawget(self, VALUE)[key]
  if obj then
    return obj
  end

  -- otherwise, it's probably a regular Lua value and the user is
  -- trying to find the corresponding Value that holds that value.
  local real_key = rawget(self, LOOKUP)[key]
  if real_key then
    return rawget(self, VALUE)[real_key]
  end

  return nil
end

function Object:__newindex(key, value)
  -- if key is a Value, we also track its normal Lua value
  -- as an alternative key, so that things like obj["key"] works
  -- when "key" might also be a String(tvbr, "key")
  local real_key = jsond.value(key)
  if real_key then
    local existing = rawget(self, VALUE)[real_key]
    rawget(self, LOOKUP)[real_key] = key
    if existing and existing ~= value then
      rawget(self, VALUE)[existing] = nil
    end
  end

  rawget(self, VALUE)[key] = value
end

local Array = class(BasicValue)
Array.__json_type = "array"

function Array:new(range, value)
  local obj = { [RANGE] = range, [VALUE] = {} }
  obj = setmetatable(obj, self)
  if value then
    for i, v in ipairs(value) do
      obj[i] = v
    end
  end
  return obj
end

function Array:__index(key)
  -- numeric keys always retrieve from the array
  if type(key) == "number" then
    return rawget(self, VALUE)[key]
  end
  -- otherwise use normal __index behavior
  if Array[key] then
    return Array[key]
  end
  return rawget(self, key)
end

function Array:__newindex(key, value)
  if type(key) == "number" then
    if not isinstance(value, Value) then
      error("Array value must be a Value")
    end
    rawget(self, VALUE)[key] = value
    return
  end
  rawset(self, key, value)
end

function Array:__len() return #self:val() end

function Array:__ipairs() return ipairs(self:val()) end

function Array:__pairs() return ipairs(self:val()) end

function Array:sorted() return jsond.sorted(self) end

function Array:sort(comp)
  local ncomp
  if comp then
    ncomp = function(a, b)
      return comp(jsond.value(a), jsond.value(b))
    end
  end
  table.sort(self:val(), ncomp)
end

local function copy_array(obj)
  local res = {}
  for i, v in ipairs(obj:val()) do
    res[i] = v
  end
  return Array:new(obj:range(), res)
end

function jsond.sorted(obj, comp)
  local typ = jsond.type(obj)

  if typ == "array" then
    -- vanilla Lua sort
    obj = copy_array(obj)
    obj:sort(comp)
    return obj
  elseif typ == "object" then
    -- a "sorted" object is an array of pairs of keys and values
    local ncomp
    if comp then
      ncomp = function(a, b)
        -- just sort the key part of the pair
        return comp(jsond.value(a[1]), jsond.value(b[1]))
      end
    end

    local pairs_array = {}
    for k, v in pairs(obj) do
      table.insert(pairs_array, { k, v })
    end

    table.sort(pairs_array, ncomp)
    return pairs_array
  else
    error("Cannot sort object of type " .. typ)
  end
end

local escape_char_map = {
  ["\\"] = "\\",
  ["\""] = "\"",
  ["\b"] = "b",
  ["\f"] = "f",
  ["\n"] = "n",
  ["\r"] = "r",
  ["\t"] = "t",
}

local escape_char_map_inv = { ["/"] = "/" }
for k, v in pairs(escape_char_map) do
  escape_char_map_inv[v] = k
end

local function create_set(...)
  local res = {}
  for i = 1, select("#", ...) do
    res[select(i, ...)] = true
  end
  return res
end

local space_chars  = create_set(" ", "\t", "\r", "\n")
local delim_chars  = create_set(" ", "\t", "\r", "\n", "]", "}", ",")
local escape_chars = create_set("\\", "/", '"', "b", "f", "n", "r", "t", "u")
local literals     = create_set("true", "false", "null")

local literal_map  = {
  ["true"] = true,
  ["false"] = false,
  ["null"] = nil,
}

local function next_char(str, idx, set, negate)
  for i = idx, #str do
    if set[str:sub(i, i)] ~= negate then
      return i
    end
  end
  return #str + 1
end

local function decode_error(str, idx, msg)
  local line_count = 1
  local col_count = 1
  for i = 1, idx - 1 do
    col_count = col_count + 1
    if str:sub(i, i) == "\n" then
      line_count = line_count + 1
      col_count = 1
    end
  end
  error(string.format("%s at line %d col %d", msg, line_count, col_count))
end


local function codepoint_to_utf8(n)
  -- http://scripts.sil.org/cms/scripts/page.php?site_id=nrsi&id=iws-appendixa
  local f = math.floor
  if n <= 0x7f then
    return string.char(n)
  elseif n <= 0x7ff then
    return string.char(f(n / 64) + 192, n % 64 + 128)
  elseif n <= 0xffff then
    return string.char(f(n / 4096) + 224, f(n % 4096 / 64) + 128, n % 64 + 128)
  elseif n <= 0x10ffff then
    return string.char(f(n / 262144) + 240, f(n % 262144 / 4096) + 128,
      f(n % 4096 / 64) + 128, n % 64 + 128)
  end
  error(string.format("invalid unicode codepoint '%x'", n))
end


local function parse_unicode_escape(s)
  local n1 = tonumber(s:sub(1, 4), 16)
  local n2 = tonumber(s:sub(7, 10), 16)
  -- Surrogate pair?
  if n2 then
    return codepoint_to_utf8((n1 - 0xd800) * 0x400 + (n2 - 0xdc00) + 0x10000)
  else
    return codepoint_to_utf8(n1)
  end
end

function parse_string0(tvbr, i, max_len)
  local res = ""
  local str = tvbr:raw()
  local j = i + 1
  local k = j

  while j <= #str and (not max_len or #res + j - k < max_len) do
    local x = str:byte(j)

    if x < 32 then
      decode_error(str, j, "control character in string")
    elseif x == 92 then -- `\`: Escape
      res = res .. str:sub(k, j - 1)
      j = j + 1
      local c = str:sub(j, j)
      if c == "u" then
        local hex = str:match("^[dD][89aAbB]%x%x\\u%x%x%x%x", j + 1)
            or str:match("^%x%x%x%x", j + 1)
            or decode_error(str, j - 1, "invalid unicode escape in string")
        res = res .. parse_unicode_escape(hex)
        j = j + #hex
      else
        if not escape_chars[c] then
          decode_error(str, j - 1, "invalid escape char '" .. c .. "' in string")
        end
        res = res .. escape_char_map_inv[c]
      end
      k = j + 1
    elseif x == 34 then -- `"`: End of string
      res = res .. str:sub(k, j - 1)
      return res, j + 1
      --return String:new(tvbr(i - 1 + 1, j - i - 1), res), j + 1
    end

    j = j + 1
    if max_len and #res + j - k >= max_len then
      return res .. str:sub(k, j - 1), j
    end
  end

  decode_error(str, i, "expected closing quote for string")
end

local function parse_string(tvbr, i, max_len)
  local res, j = parse_string0(tvbr, i, max_len)
  return String:new(tvbr(i - 1 + 1, j - i - 2), res), j
end

local function parse_number(tvbr, i)
  local str = tvbr:raw()
  local x = next_char(str, i, delim_chars)
  local s = str:sub(i, x - 1)
  local n = tonumber(s)
  if not n then
    decode_error(str, i, "invalid number '" .. s .. "'")
  end
  return Number:new(tvbr(i - 1, x - i), n), x
end


local function parse_literal(tvbr, i)
  local str = tvbr:raw()
  local x = next_char(str, i, delim_chars)
  local word = str:sub(i, x - 1)
  if not literals[word] then
    decode_error(str, i, "invalid literal '" .. word .. "'")
  end
  return BasicValue:new(tvbr(i - 1, x - i), literal_map[word]), x
end

local parse

local function parse_array(tvbr, start)
  local res = {}
  local str = tvbr:raw()
  local n = 1
  local i = start
  i = i + 1
  while 1 do
    local x
    i = next_char(str, i, space_chars, true)
    -- Empty / end of array?
    if str:sub(i, i) == "]" then
      i = i + 1
      break
    end
    -- Read token
    x, i = parse(tvbr, i)
    res[n] = x
    n = n + 1
    -- Next token
    i = next_char(str, i, space_chars, true)
    local chr = str:sub(i, i)
    i = i + 1
    if chr == "]" then break end
    if chr ~= "," then decode_error(str, i, "expected ']' or ','") end
  end
  return Array:new(tvbr(start - 1, i - start), res), i
end


local function parse_object(tvbr, start)
  local res = {}
  local str = tvbr:raw()
  local i = start
  i = i + 1
  while 1 do
    local key, val
    i = next_char(str, i, space_chars, true)
    -- Empty / end of object?
    if str:sub(i, i) == "}" then
      i = i + 1
      break
    end
    -- Read key
    if str:sub(i, i) ~= '"' then
      decode_error(str, i, "expected string for key")
    end
    key, i = parse(tvbr, i)
    -- Read ':' delimiter
    i = next_char(str, i, space_chars, true)
    if str:sub(i, i) ~= ":" then
      decode_error(str, i, "expected ':' after key")
    end
    i = next_char(str, i + 1, space_chars, true)
    -- Read value
    val, i = parse(tvbr, i)
    -- Set
    res[key] = val
    -- Next token
    i = next_char(str, i, space_chars, true)
    local chr = str:sub(i, i)
    i = i + 1
    if chr == "}" then break end
    if chr ~= "," then decode_error(str, i, "expected '}' or ','") end
  end
  return Object:new(tvbr(start - 1, i - start), res), i
end


local char_func_map = {
  ['"'] = parse_string,
  ["0"] = parse_number,
  ["1"] = parse_number,
  ["2"] = parse_number,
  ["3"] = parse_number,
  ["4"] = parse_number,
  ["5"] = parse_number,
  ["6"] = parse_number,
  ["7"] = parse_number,
  ["8"] = parse_number,
  ["9"] = parse_number,
  ["-"] = parse_number,
  ["t"] = parse_literal,
  ["f"] = parse_literal,
  ["n"] = parse_literal,
  ["["] = parse_array,
  ["{"] = parse_object,
}

function parse(tvbr, idx)
  local chr = tvbr(idx - 1, 1):raw()
  if chr == '' then
    decode_error(tvbr, idx, "unexpected end of input")
  end
  local f = char_func_map[chr]
  if f then
    return f(tvbr, idx)
  end
  decode_error(tvbr, idx, "unexpected character '" .. chr .. "'")
end

function jsond.decode(tvbr)
  local mt = getmetatable(tvbr)
  local ok
  if mt then
    if mt.__name == "Tvb" then
      tvbr = tvbr()
    elseif mt.__name == "TvbRange" then
      ok = true
    end
  end
  if not ok then
    error("expected Tvb or TvbRange, got " .. type(tvbr))
  end
  local str = tvbr:raw()
  local res, idx = parse(tvbr, next_char(str, 1, space_chars, true))
  idx = next_char(str, idx, space_chars, true)
  if idx <= tvbr:len() then
    decode_error(tvbr, idx, "trailing garbage")
  end
  return res
end

return jsond

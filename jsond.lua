local jsond = {}

-- DEBUGGING

local debugging = false
jsond.debug_prefix = ""

local debug_indent = 0

local function noop(...) return ... end

local function _log(fmt, ...)
    local msg = string.format(fmt or "", ...)
    local prefix = jsond.debug_prefix .. string.rep(". ", debug_indent)
    print(prefix .. msg)
end
local log = noop

local function _debug_in(msg)
    log(msg .. " (")
    debug_indent = debug_indent + 1
end
local function _debug_out()
    debug_indent = debug_indent - 1
    log(")")
end

local debug_in = noop
local debug_out = noop

--- SETS

-- Build sets, keyed on character code points, to try and be fast
local Set = {}
Set.__index = Set

function Set:new(name, ...)
    local s = setmetatable({ name = name }, self)
    for i = 1, select("#", ...) do
        local e = select(i, ...)
        if type(e) == "string" then
            e = string.byte(e)
            s[e] = true
        elseif type(e) == "table" then
            for k, v in pairs(e) do
                if type(k) == "number" then
                    s[k] = v
                end
            end
        elseif type(e) ~= "number" then
            error("set: expected string or number, got " .. type(e))
        end
    end
    return s
end

local function set(name, ...) return Set:new(name, ...) end

function Set.__add(a, b)
    local s = setmetatable({}, Set)
    for k, v in pairs(a) do
        s[k] = v
    end
    for k, v in pairs(b) do
        s[k] = v
    end
    s.name = a.name .. "+" .. b.name
    return s
end

local char_0 = string.byte("0")
local char_9 = string.byte("9")
local char_a = string.byte("a")
local char_z = string.byte("z")
local char_A = string.byte("A")
local char_Z = string.byte("Z")
local char_u = string.byte("u")
local underscore = string.byte("_")

local function is_ident(c)
    return c and ((c >= char_0 and c <= char_9) or
        (c >= char_a and c <= char_z) or
        (c >= char_A and c <= char_Z) or
        (c == underscore))
end

local whitespace = set("whitespace", " ", "\t", "\n", "\r")
local nonzero_digits = set("nonzero_digit", "1", "2", "3", "4", "5", "6", "7", "8", "9")
local digits = set("digits", nonzero_digits, "0")
local number_parts = set("number_part", digits, ".", "e", "E", "-", "+")
local hex_digits = set("hex_digit", digits, "a", "b", "c", "d", "e", "f", "A", "B", "C", "D", "E", "F")

local minus = string.byte("-")
local plus = string.byte("+")
local dot = string.byte(".")
local exponent = string.byte("e")
local exponent_upper = string.byte("E")

local open_brace = string.byte("{")
local close_brace = string.byte("}")
local open_bracket = string.byte("[")
local close_bracket = string.byte("]")
local colon = string.byte(":")
local comma = string.byte(",")
local quote = string.byte('"')
local backslash = string.byte("\\")

local backslash_escape = {
    [quote] = '"',
    [backslash] = '\\',
    [string.byte("/")] = '/',
    [string.byte("b")] = '\b',
    [string.byte("f")] = '\f',
    [string.byte("n")] = '\n',
    [string.byte("r")] = '\r',
    [string.byte("t")] = '\t',
}

--- PARSER

-- Parser is a general-purpose parser, tracking TvbRange and position
local Parser = {}
Parser.__index = Parser

function Parser:new(buf)
    if buf == nil then
        error("buf is nil")
    end
    local p = setmetatable({}, self)

    p.buf = buf
    p.obj_parser = nil

    -- track position
    p.idx = -1 -- where we are in p.buf minus 1
    p.line = 1 -- track line numbers by watching for \n
    p.col = 0  -- column within a line
    p.ch = nil -- current character, or nil if at end of buffer

    -- track our starting position for :restart()
    p.start_idx = 0
    p.start_line = 1
    p.start_col = 0

    p.err = nil    -- any parse error we encountered
    p.done = false -- whether parsing is completed for the object associated with p
    p:next()
    return p
end

-- Parser:copy() returns a shallow copy of the parser.
function Parser:copy()
    local p = setmetatable({}, Parser)
    p.buf = self.buf
    p.start_idx = self.start_idx
    p.idx = self.idx
    p.line = self.line
    p.col = self.col
    p.ch = self.ch
    p.err = self.err
    p.obj_parser = self.obj_parser
    return p
end

-- Spawns a new parser with state copied from the current one
-- The new parser starts at the current position
function Parser:start()
    local p = self:copy()
    p.start_idx = self.idx -- start at current position
    p.start_line = self.line
    p.start_col = self.col
    p.err = nil
    return p
end

-- Restart the parser at the start of the current object
function Parser:restart()
    local p = self:copy()
    p.idx = self.start_idx
    p.line = self.start_line
    p.col = self.start_col
    p.ch = p.buf(self.idx, 1):uint()
    p.err = nil
    return p
end

function Parser:parse(v)
    assert(self.obj_parser)
    return self.obj_parser(v, self)
end

-- Describe the current position in the buffer
function Parser:pos_str()
    return string.format("byte %d line %d:%d", self.idx, self.line, self.col)
end

-- Move the parser to the same position as p.
-- Because we initially do shallow copies, we periodically need to
-- finish parsing another object (which has its own parser) before
-- we can continue parsing this one.  This method catches us up.
function Parser:move_to(p)
    self.idx = p.idx
    self.line = p.line
    self.col = p.col
    self.ch = p.ch
    self.err = p.err
end

-- Advance the parser to the next character
function Parser:next()
    self.idx = self.idx + 1
    if self.idx >= self.buf:len() then
        self.ch = nil
    else
        self.ch = self.buf(self.idx, 1):uint()
    end
    if self.ch == 10 then
        self.line = self.line + 1
        self.col = 0
    else
        self.col = self.col + 1
    end
    return self.ch
end

-- Rewind one character.
-- This is only used in an error situation, and it may leave the
-- parser with bad data on its position.
function Parser:rewind()
    if self.idx > 0 then
        self.idx = self.idx - 1
        self.ch = self.buf(self.idx, 1):uint()
        if self.ch == 10 then
            self.line = self.line - 1
            self.col = 0 -- nonsense
        elseif self.col > 0 then
            self.col = self.col - 1
        end
    end
    return self.ch
end

-- When debugging is enabled, this gives us a way to print
-- out the current state of the parser.
function Parser:__debug(fmt, ...)
    local ch = self.ch
    if ch == nil then
        ch = "nil"
    else
        ch = "'" .. string.char(ch) .. "'"
    end
    local prefix = string.format("[%d [%d:%d]] %s ", self.idx, self.line, self.col, ch)
    log(prefix .. (fmt or ""), ...)
end

Parser.debug = noop

-- parser:debug_tf emits debugging specifically for the case where the last argument
-- is a boolean indicating success or failure.  It returns that final boolean.
function Parser:__debug_tf(fmt, ...)
    -- get the last item from the ...
    local final = not not select(select("#", ...), ...)
    local icon = "\u{2716}\u{FE0F}"
    if final then
        icon = "\u{2705}"
    end
    self:debug("%s " .. fmt, icon, ...)
    return final
end

function Parser:__debug_tf_noop(fmt, ...)
    return not not select(select("#", ...), ...)
end

Parser.debug_tf = Parser.__debug_tf_noop

-- Returns true if the current character matches the given expression.
-- For a nil expression, this returns true if the current character is not nil.
-- The position of the parser is unchanged.
function Parser:matches(exp)
    if exp == nil then
        -- match anything but nil
        return self:debug_tf("matches(nil)\t%q", self.ch ~= nil)
    end

    if type(exp) == "number" then
        -- code point
        if debugging then
            return self:debug_tf("matches(%s)\t%q", string.char(exp), self.ch == exp)
        else
            return self.ch == exp
        end
    elseif type(exp) == "table" then
        -- assume this is a set
        return self:debug_tf("matches(%s)\t%q", exp.name or "unnamed table", exp[self.ch])
    elseif type(exp) == "function" then
        -- func(ch) returns true if matches
        return self:debug_tf("matches(function)\t%q", exp(self.ch))

        -- elseif type(exp) == "string" then
        --     local bytes = exp:byte(1, -1)
        --     for i = 1, #bytes do
        --         if self.ch == bytes[i] then
        --             return self:debug_tf("matches('%s'/%s)\t%q", exp, true)
        --         end
        --     end
        --     return self:debug_tf("matches('%s')\t%q", exp, false)
    end
    error("matches called with unexpected argument: " .. type(exp))
end

-- Like matches, but generates a parse error if the match fails.
-- The position of the parser is unchanged.
function Parser:expect(exp, msg)
    if self:matches(exp) then
        return true
    end
    if msg == nil then
        if type(exp) == "string" then
            msg = "expected one of " .. exp
        elseif type(exp) == "number" then
            msg = "expected " .. string.char(exp)
        else
            msg = "invalid value"
        end
    end
    return nil, self:parse_error(msg)
end

-- Like expect, but assumes the input is an identifier that
-- must match exp (a string) exactly.
-- The position of the parser is unchanged.
function Parser:expect_ident(exp, msg)
    local r = self.buf(self.idx)
    local act
    if r:len() >= #exp then
        act = r(0, #exp):string()
        if act == exp then
            return true
        end
    end
    if not msg then
        msg = "expected '" .. exp .. "' but got '" .. r:string() .. "'"
    else
        msg = msg .. " at '" .. act .. "'"
    end
    return nil, self:parse_error(msg)
end

-- If the current character matches exp, it is consumed.
-- Any leading whitespace is also consumed.
-- The position of the parser is advanced.
function Parser:consume(exp)
    while self:matches(whitespace) do
        self:next()
    end
    if self:matches(exp) then
        self:next()
        return true
    end
    return false
end

-- Keep calling consume(exp) until it returns false.
function Parser:consume_all(exp)
    local ok = false
    while self:consume(exp) do
        ok = true
    end
    return ok
end

-- Consumes characters while the expression does not match.
-- The parser will point to the first character matching exp, or the end of input.
function Parser:consume_until(exp)
    while true do
        if self:matches(exp) then
            return true
        end
        if self:eof() then
            return false
        end
        self:next()
    end
end

-- Produces a text description of the current position in the buffer.
function Parser:err_context()
    local ctx = self.buf(self.idx)
    if ctx:len() > 0 then
        if ctx:len() > 13 then
            ctx = ctx(0, 10):string() .. "..."
        else
            ctx = ctx:string()
        end
        ctx = string.format("%q", ctx)
    else
        ctx = "<end of input>"
    end
    return " at " .. self:pos_str() .. ": " .. ctx
end

-- Signals that a parse error has occurred.
-- Only the first error is saved, unless override is true.
function Parser:parse_error(msg, override)
    msg = msg .. self:err_context()
    if not self.err or override then
        self.err = msg
        self:debug("\u{26D4} parse_error: %s", msg)
    else
        self:debug("\u{26D4} parse_error (extra): %s", msg)
    end
    return "JSON parse: " .. msg
end

function Parser:range_at() return self.buf(self.start_idx) end

function Parser:parsed_range()
    return self.buf(self.start_idx, self.idx - self.start_idx)
end

function Parser:eof()
    return self.ch == nil
end

local PARSER = {}
local VALUE = {}

-- A Value is instantiated with a range, and a position.
-- The value begins at the start of the range, and the position refers to that location in the source byte stream.
-- The value is parsed lazily. Initially neither its length (in the TvbRange) nor value may be known.
-- Note that values can be incompletely parsed
local function class(super)
    local cls = {}
    cls.__index = cls
    if super then
        setmetatable(cls, super)
    end

    function cls:new(prs, value)
        prs:debug("\u{2728} new(%s)", self.__json_type)
        local obj = setmetatable({}, self)
        prs.obj_parser = self.parse
        rawset(obj, PARSER, prs)
        if value then
            rawset(obj, VALUE, value)
            prs:finalize()
        else
            rawset(obj, VALUE, self.__zero())
        end
        return obj
    end

    function cls:__call()
        -- ignore errors
        local r = jsond.range(self)
        local v = jsond.value(self)
        return r, v
    end

    function cls:__tostring()
        local v = jsond.value(self)
        return tostring(v)
    end

    return cls
end

function jsond.type(obj)
    local mt = getmetatable(obj)
    if mt then
        return mt.__json_type
    end
    return nil
end

local function get_parser(obj)
    if not obj then
        error("expected jsond value, got nil", 3)
    end
    return rawget(obj, PARSER)
end

local function get_error(obj)
    return get_parser(obj).err
end

local function is_parsed(obj)
    return get_parser(obj).done
end

function Parser:finalize()
    self:debug("marking done")
    self.buf = self:parsed_range()
    self.done = true
end

function Parser:finish(v)
    if not self.done then
        self:parse(v)
        assert(self.done)
    end
    return not self.err, self.err
end

function jsond.is_value(v)
    local mt = getmetatable(v)
    if not mt then
        return false
    end
    return mt.__json_type ~= nil
end

function jsond.value(v)
    local p = get_parser(v)
    if not p then
        return nil, "not a jsond value"
    end
    p:finish(v)
    return rawget(v, VALUE), p.err
end

local function set_value(v, val)
    return rawset(v, VALUE, val)
end

function jsond.range(v)
    local p = get_parser(v)
    p:finish(v)
    if p.done then
        return p.buf
    end
    return nil, p.err
end

local function sizeof(v)
    local r, err = jsond.range(v)
    if r then
        return r:len()
    end
    return nil, err
end

local BasicValue = class()

function BasicValue:range()
    local r = jsond.range(self)
    return r
end

function BasicValue:val()
    local v = jsond.value(self)
    return v
end

function BasicValue:raw() return self:range():raw() end

function BasicValue:bool() return jsond.bool(self) end

function BasicValue:nonzero() return not jsond.is_zero(self) end

-- Ensures a is a Lua type, by calling jsond.value() if needed.
local function reduce(a)
    if jsond.is_value(a) then
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

local Number = class(BasicValue)
Number.__json_type = "number"
function Number.__zero() return 0 end

function Number:__tostring()
    local v = jsond.value(self)
    if v == nil then
        return "nil"
    end
    return tostring(v)
end

function Number:nstime()
    local secs, nsecs = math.modf(self:val())
    return self:range(), NSTime.new(secs, nsecs * 1e9)
end

function Number:parse(p)
    debug_in("Number.parse")
    if debugging then
        log("parsing: %q", p:range_at():string())
    end
    if p:matches(minus) then
        p:next()
    end
    if p:matches(nonzero_digits) then
        p:consume_all(digits)
    else
        if p:expect(char_0, "expected digit") then
            p:next()
        else
            goto done
        end
    end
    if p:matches(dot) then
        p:next()
        if not p:consume_all(digits) then
            p:parse_error("expected digits after decimal point")
            p:rewind()
            goto done
        end
    end
    if p:matches(exponent) or p:matches(exponent_upper) then
        p:next()
        if p:matches(minus) or p:matches(plus) then
            p:next()
        end
        if not p:consume_all(digits) then
            p:parse_error("expected digits after exponent")
            p:rewind()
            if p:matches(minus) or p:matches(plus) then
                p:rewind()
            end
            goto done
        end
    end
    ::done::
    local num = tonumber(p:parsed_range():string())
    log("parsed_range: %q", num)
    set_value(self, num)
    if p.err then
        p:debug("syncing")
        p:consume_all(number_parts)
    end
    p:finalize()
    debug_out()
end

local String = class(BasicValue)
String.__json_type = "string"

function String.__zero() return "" end

function String:__len() return #self:val() end

function normalize_ij(i, j, len)
    if not i then
        i = 1
    end
    if not j then
        j = -1
    end
    if i < 1 then
        i = len + i + 1
    end
    if j < 1 then
        j = len + j + 1
    end
    return i, j
end

function String:byte(i, j)
    local str = self
    if i > 1 or i == j then
        -- optimize a bit by only re-parsing the part of the string before i a single time
        str = self:sub(i, j)
        i, j = 1, #str

        if i == j then
            return { Number:new(self:range(), self:val():byte(i)) }
        end
    else
        i, j = normalize_ij(i, j, #str)
    end
    local res = {}
    while i <= j do
        local ch = self:sub(i, i)
        res[i - 1] = Number:new(ch:range(), ch:val():byte())
        i = i + 1
    end
    return table.unpack(res)
end

function String:ether() return self:range(), Address.ether(self:val()) end

function String:ipv4() return self:range(), Address.ipv4(self:val()) end

function String:ipv6() return self:range(), Address.ipv6(self:val()) end

function String:lower() return String:new(get_parser(self), self:val():lower()) end

function String:number(base)
    local val = self:val()
    local n = tonumber(val, base)
    if n then
        return Number:new(get_parser(self), n)
    end
    return nil
end

function String:sub(i, j)
    local val = jsond.value(self)
    assert(val)
    if not i then
        i = 1
    end
    if not j or j < 1 then
        j = #val
    end
    if i < 1 then
        i = #val + i + 1
    end

    -- In order to get the range right, we need to re-parse the string.
    -- Start with the part of the string before i
    local p = get_parser(self):restart()
    local prefix = ""
    local more = true
    while more and #prefix < i - 1 do
        -- add character by character until we hit i
        more, prefix = self:parse_next(p, prefix)
    end

    -- Now start accumulating characters in str until we hit j
    local str = ""

    -- Pathologically, if String:parse_next() had a parsing error, it may have added more
    -- than one character to prefix.  We want to keep that, so prepend it to str.
    if #prefix > i - 1 then
        str = prefix:sub(i - 1)
    end

    while more and #str < j - i + 1 do
        -- add character by character until we hit j
        more, str = self:parse_next(p, str)
    end

    -- Same pathological case as above, so cap str to j
    if #str > j - i + 1 then
        str = str:sub(1, j - i + 1)
    end

    return String:new(p, str)
end

function String:parse_next(p, str)
    p:next()
    if not p:expect(nil, "expected closing quote") then
        return false, str
    end
    if p:matches(quote) then
        return false, str
    elseif p:matches(backslash) then
        p:next()
        local c = backslash_escape[p.ch]
        if c then
            if debugging then
                p:debug("escaped \\%q", string.char(p.ch))
            end
            str = str .. c
        elseif p:matches(char_u) then
            -- unicode escape sequence
            local hex = ""
            for j = 1, 4 do
                p:next()
                if not p:expect(hex_digits, "expected 4 hex digits after \\u") then
                    break
                end
                hex = hex .. string.char(p.ch)
            end
            if #hex == 4 then
                str = str .. string.char(tonumber(hex, 16))
            else
                str = str .. "\\u" .. hex
            end
        else
            p:parse_error("invalid escape sequence")
            if p.ch then
                str = str .. "\\" .. string.char(p.ch)
            else
                str = str .. "\\"
            end
        end
    else
        str = str .. string.char(p.ch)
    end
    return true, str
end

function String:parse(p)
    debug_in("String:parse")
    if debugging then
        log("parsing: %q", p:range_at():string())
    end

    local str = ""
    local more = true
    while more do
        more, str = self:parse_next(p, str)
    end
    p:consume(quote)
    log("%s: %q", type(str), str)
    set_value(self, str)
    p:finalize()
    debug_out()
end

local Keyword = class(BasicValue)
Keyword.__zero = function() return "" end

function Keyword:parse(p)
    p:consume_all(is_ident)
    set_value(self, p:parsed_range():string())
    p:finalize()
end

local Null = class(Keyword)
Null.__json_type = "null"

function Null.__zero() return nil end

local Boolean = class(BasicValue)
Boolean.__json_type = "boolean"

function Boolean.__zero() return false end

local comma_or_close_bracket = set(", or ]", ",", "]")

local Array = class(BasicValue)
Array.__json_type = "array"

function Array.__zero() return {} end

function Array:__tostring()
    local v = jsond.value(self)
    if v == nil then
        return "nil"
    end
    local str = "["
    for i = 1, #v do
        if i > 1 then
            str = str .. ", "
        end
        str = str .. tostring(v[i])
    end
    str = str .. "]"
    return str
end

function Array.__len(self)
    local v = jsond.value(self)
    return #v
end

function Array:parse(p)
    debug_in("Array:parse")
    if debugging then
        log("parsing: %q", p:range_at():string())
    end
    local more
    repeat
        _, more = self:_advance(p)
    until not more
    debug_out()
end

local shallow_parse

function Array:_advance(p)
    debug_in("Array:_advance")
    -- incrementally parse one
    local list = rawget(self, VALUE)
    local prev = list[#list]
    local expect_value = false
    local more = false
    local val
    if not prev then
        p:debug("first element")
        if not p:expect(open_bracket, "expected [") then
            -- shouldn't happen
            error(p.err)
        end
        p:next()
    else
        -- we need to know the size of the previous value before we can parse the next one
        local pp = get_parser(prev)
        if debugging then
            p:debug("prior element was %s at %s", jsond.type(prev), pp:pos_str())
        end
        debug_in("parsing to find its length")
        pp:finish(prev)
        debug_out()
        p:move_to(pp)
        p:debug("now caught up")
        if pp.err then
            p:debug("child saw a parse error")
        end
        if pp.err and not p.err then
            error("error not propagated")
        end
        if not p:expect(comma_or_close_bracket, "expected , or ]") then
            p:consume_until(comma_or_close_bracket)
        end
        if p:consume(comma) then
            expect_value = true
        end
    end

    if p:eof() then
        p:parse_error("expected number, string, object, array, true, false or null")
        goto done
    end
    if p:consume(close_bracket) then
        goto done
    end

    val = shallow_parse(p)
    if val then
        expect_value = false
        table.insert(list, val)
        more = true
    end

    ::done::
    if expect_value then
        if not p.err then
            p:parse_error("expected number, string, object, array, true, false or null")
        end
        p:debug("seeking")
        while p:consume(comma) or p:matches(close_bracket) do
            if p:matches(close_bracket) then
                p:next()
                more = false
                break
            end
        end
    end
    if not more then
        p:finalize()
    end
    debug_out()
    return #list, more
end

function Array:_advance_until(p, key)
    debug_in("Array:_advance_until")
    p:debug("looking for %s", key)
    local k
    local more = true
    while more do
        k, more = self:_advance(p)
        if k == key then
            p:debug("found %s", key)
            debug_out()
            return true
        end
        if not more then
            break
        end
    end
    p:debug("no match after exhausting array")
    debug_out()
    return false
end

function Array:__ipairs()
    get_parser(self):finish(self)
    return ipairs(rawget(self, VALUE))
end

function Array:__pairs() return ipairs(rawget(self, VALUE)) end

function Array:__index(key)
    if type(key) == "number" then
        debug_in("Array.__index")
        log("requested %q", key)
        local list = rawget(self, VALUE)
        if list[key] then
            log("found in VALUE table")
            debug_out()
            return list[key]
        end
        local p = get_parser(self)
        if p.done then
            log("parser reports done, so there's nowhere else to look")
            debug_out()
            return nil
        end
        local found = self:_advance_until(p, key)
        if found then
            if debugging then
                log("success: %q -> %q", key, tostring(list[key]:val()))
            end
            debug_out()
            return list[key]
        end
        log("not found")
        debug_out()
        return nil
    end
    return Array[key]
end

local PREV = {}

local function get_prev(v)
    return rawget(v, PREV)
end
local function set_prev(v, prev)
    return rawset(v, PREV, prev)
end

local LOOKUP = {}

local function get_lookup_table(v)
    local lookup = rawget(v, LOOKUP)
    if not lookup then
        lookup = {}
        rawset(v, LOOKUP, lookup)
    end
    return lookup
end

local Object = class()
Object.__json_type = "object"

function Object.__zero() return {} end

function Object:__tostring()
    local v = jsond.value(self)
    if v == nil then
        return "nil"
    end
    local str = "{"
    for k, v in pairs(v) do
        if str ~= "{" then
            str = str .. ", "
        end
        str = str .. tostring(k) .. ": " .. tostring(v)
    end
    str = str .. "}"
    return str
end

function Object:parse(p)
    debug_in("Object:parse")
    local more
    repeat
        _, _, _, more = self:_advance(p)
    until not more
    debug_out()
end

local comma_closebrace = set(", or }", ",", "}")
local comma_closebrace_colon = set(", } or :", ",", "}", ":")

function Object:_advance_start(p)
    debug_in("Object:_advance_start")

    p:consume_all(whitespace)
    local prev = get_prev(self) -- last value we parsed (if any)
    if not prev then
        -- we are at the start of the object
        p:debug("first element")
        if not p:expect(open_brace, "expected {") then
            -- shouldn't happen
            error(p.err)
        end
        p:next()
    else
        -- we have already parsed a key-value pair and we expect more
        -- we need to know the size of the previous value before we can parse the next one
        local prev_parser = get_parser(prev)
        if debugging then
            p:debug("prior element was %s at %s", jsond.type(prev), prev_parser:pos_str())
        end
        debug_in("parsing to find its length")
        prev_parser:finish(prev)
        debug_out()
        p:move_to(prev_parser)
        if debugging then
            p:debug("now caught up to %s", p:pos_str())
        end
        set_prev(self, nil)

        -- we have fully parsed the previous value, so we should be at a , or }
        if not p:expect(comma_closebrace, "expected , or }") then
            -- parse error, let's try to sync forward to the next , or }
            p:consume_until(comma_closebrace)
        end
        -- if we see a comma after the last value, expect that a value will follow
        -- otherwise a } is still fair game
        debug_out()
        return p:consume(comma)
    end
    p:consume_all(whitespace)
    debug_out()
    return false
end

function Object:_advance_key(p)
    debug_in("Object:_advance_key")

    local key = nil
    while true do
        key = shallow_parse(p)
        if key then
            local child_p = get_parser(key)
            child_p:finish(key)
            p:move_to(child_p)
            break
        end
        log("failed to parse key, trying to recover")
        -- shallow_parse will report the parse error on p
        -- let's just try to recover and use the nonsense as a string key
        p:consume_until(comma_closebrace_colon)
        if p:matches(comma) then
            -- start over in a new loop iteration, retaining the errored p
        elseif p:matches(colon) then
            -- probably the intent was whatever we accumulated so far to be some kind of object key
            -- so let's just stringify it and try to use it
            p:finalize()
            key = String:new(p, p.range:string() or "")
            break
        else
            -- } or eof
            break
        end
    end
    debug_out()
    return key
end

local function sync_to_colon_or_null(p)
    p:consume_until(comma_closebrace_colon)
    if not p:matches(colon) then
        -- couldn't recover; we are at a , or } or eof
        -- just synthesize a null value for key
        p:debug("missing value, will fill in with a null")
        local child_p = p:copy()
        local val = Null:new(child_p, nil)
        child_p:finalize()
        debug_out()
        return val
    end
    return nil
end

function Object:_advance_value(p)
    debug_in("Object:_advance_value")
    local val, done
    -- if we aren't at a colon, try to sync ahead to it
    if not p:expect(colon, "expected :") then
        val = sync_to_colon_or_null(p)
    end

    if not val then
        -- we are now guaranteed to be at a :
        p:next()

        -- try to parse the value
        while not p:eof() do
            val = shallow_parse(p)
            if val then
                break
            end
            val = sync_to_colon_or_null(p)
            if val then
                done = true
                break
            end
            p:consume(colon)
        end
    end

    assert(val)
    set_prev(self, val)
    debug_out()
    return val, done
end

function Object:_advance(p)
    -- when this is called, state is:
    -- 1. at the start of the object ('{')
    -- 2. after the first key-value pair, with access to the previous value
    --
    -- When this returns, we should be either at state (2) or
    -- 3. past "}" (and finalized)
    --
    -- parse errors sync to
    -- - the next : (if we are parsing a key)
    -- - the next , or } (if we are parsing a value)
    --
    -- we finalize when we reach } or end of input
    debug_in("Object:_advance")
    p:consume_all(whitespace)
    if p:eof() then
        return nil, false
    end

    local key, key_str, val
    local done = false -- true when we know we are done parsing

    -- process any prior value and move us to the start of the next key-value pair
    local saw_comma = self:_advance_start(p)

    if p:matches(close_brace) or p:eof() then
        if saw_comma then
            p:parse_error("expected string key after ,")
        end
        p:next()
        done = true
        goto done_label
    end

    -- we are at the start of a key-value pair
    key = self:_advance_key(p)
    if not key then
        p:parse_error("expected string key or }")
        done = true
        goto done_label
    end
    key_str = jsond.value(key)
    assert(key_str)

    -- expecting to be at a :, parse the value
    -- this will always return a value, even if we have to make a synthetic null
    val, done = self:_advance_value(p)

    if debugging then
        p:debug("object[%q] = value at %s", key_str, get_parser(val):pos_str())
    end

    ::done_label::
    if key then
        local obj = jsond.value(self)
        obj[key] = val

        -- maintain a separate lookup table so that string access will work
        key_str = jsond.value(key)
        assert(key_str)
        get_lookup_table(self)[key_str] = key
    end
    if done then
        p:finalize()
    end
    debug_out()
    return key, key_str, val, not done
end

function Object:_advance_until(p, key)
    debug_in("Object:_advance_until")
    p:debug("looking for %q", key)
    local more = true
    while more do
        local k, k_str, val
        k, k_str, val, more = self:_advance(p)
        if key == k or key == k_str then
            if debugging then
                p:debug("found %s %q -> %q", type(k), tostring(k:val()), tostring(val:val()))
            end
            debug_out()
            return val
        end
    end
    p:debug("no match after exhausting object")
    debug_out()
    return nil
end

function Object:__index(key)
    if Object[key] then
        return Object[key]
    end
    debug_in("Object:__index")
    if jsond.is_value(key) then
        if debugging then
            local v = jsond.value(key)
            log("requested %s %q", type(key), v)
        end
    elseif type(key) == "table" then
        log("requested non-jsond table %s", type(key))
    else
        log("requested %s %q", type(key), key)
    end
    local list = rawget(self, VALUE)
    if list[key] then
        log("found in VALUE table")
        debug_out()
        return list[key]
    end
    log("not present in VALUE table")
    local lookup = get_lookup_table(self)
    if lookup[key] then
        if not list[lookup[key]] then
            log("found in LOOKUP table, but not in VALUE table")
        else
            log("found in LOOKUP table")
        end
        debug_out()
        return list[lookup[key]]
    end
    log("not present in LOOKUP table")
    local p = get_parser(self)
    if p.done then
        log("no more parsing to do, so not present")
        debug_out()
        return nil
    end
    log("not present, but parsing isn't complete yet, so let's scan forward")
    local found = self:_advance_until(p, key)
    if found then
        if debugging then
            log("success: %q -> %q", key, tostring(found:val()))
        end
        debug_out()
        return found
    end
    log("not present")
    debug_out()
    return nil
end

function Object:__pairs()
    debug_in("Object:__pairs")
    local p = get_parser(self)
    local tbl = rawget(self, VALUE)
    if p.done then
        debug_out()
        log("object is parsed, so just returning pairs(value)")
        return pairs(tbl)
    end
    log("will yield values from _advance()")
    debug_out()
    return function(slf, last_k)
        debug_in("Object:__pairs iterator")
        -- start with known pairs
        local k, v = next(tbl, last_k)
        if k then
            if debugging then
                log("yielding %q from already-parsed table", k:val())
            end
            debug_out()
            return k, v
        end
        -- now try to parse the next key-value pair
        k, _, v, _ = self:_advance(p)
        if k then
            if debugging then
                log("yielding %q from _advance()", k:val())
            end
            debug_out()
            return k, v
        end
        log("no more key-value pairs")
        debug_out()
        return nil, nil
    end, self, nil
end

function shallow_parse(p)
    debug_in("shallow_parse")
    p:consume_all(whitespace)
    local obj
    if p:matches(minus) or p:matches(digits) then
        obj = Number:new(p:start())
    elseif p:matches(quote) then
        obj = String:new(p:start())
    elseif p:matches(open_bracket) then
        obj = Array:new(p:start())
    elseif p:matches(open_brace) then
        obj = Object:new(p:start())
    elseif p:matches(is_ident) then
        local keyword = Keyword:new(p:start())
        local kw = jsond.value(keyword)
        if kw == "true" or kw == "false" then
            setmetatable(keyword, Boolean)
            set_value(keyword, kw == "true")
            obj = keyword
        elseif kw == "null" then
            setmetatable(keyword, Null)
            set_value(keyword, nil)
            obj = keyword
        else
            p:parse_error("invalid keyword, expected true, false or null")
        end
    else
        p:parse_error("expected number, string, object, array, true, false or null")
    end
    debug_out()
    return obj, p.err
end

local function default_comp(a, b)
    return a < b
end

local function make_compare_values(comp)
    comp = comp or default_comp
    return function(a, b)
        local av = jsond.value(a)
        local bv = jsond.value(b)
        return comp(av, bv)
    end
end

function Array:sort(comp)
    table.sort(self:val(), make_compare_values(comp))
end

local function copy_array(arr)
    local res = {}
    for i = 1, #arr do
        res[i] = arr[i]
    end
    return res
end

local function object_pairs(obj)
    local list = {}
    for k, v in pairs(obj) do
        table.insert(list, { k, v })
    end
    return list
end

local function pair_iter(pairs)
    local i = 0
    return function()
        i = i + 1
        local pair = pairs[i]
        if pair then
            return pair[1], pair[2]
        end
        return nil, nil
    end
end

function jsond.sorted(obj, comp)
    local typ = jsond.type(obj)
    comp = make_compare_values(comp)

    if typ == "array" then
        local list = copy_array(obj)
        table.sort(list, comp)
        return ipairs(list)
    elseif typ == "object" then
        local pairs = object_pairs(obj)
        table.sort(pairs, function(a, b)
            -- compare keys
            return comp(a[1], b[1])
        end)
        return pair_iter(pairs)
    else
        error("Cannot sort object of type " .. typ)
    end
end

function jsond.contains(container, value)
    local ctype = jsond.type(container)
    if ctype == "array" then
        if type(value) == "number" then
            return container[value] ~= nil
        end
        return false
    end
    if ctype == "object" then
        if jsond.type(value) then
            return container[value] ~= nil
        end
        return get_lookup_table(container)[value] ~= nil
    end
    error("jsond.contains() called with unexpected container type: " .. ctype)
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
        return #val == 0
    elseif type(val) == "boolean" then
        return not val
    elseif type(val) == "nil" then
        return true
    end
end

function jsond.error(value)
    local p = get_parser(value)
    if p then
        return p.err
    end
    return nil
end

function jsond.set_debug(onoff)
    if onoff then
        debug_in = _debug_in
        debug_out = _debug_out
        log = _log
        Parser.debug = Parser.__debug
        Parser.debug_tf = Parser.__debug_tf
    else
        debug_in = noop
        debug_out = noop
        log = noop
        Parser.debug = noop
        Parser.debug_tf = Parser.__debug_tf_noop
    end
    debugging = onoff
end

function jsond.decode(tvbr)
    local p = Parser:new(tvbr)
    return shallow_parse(p)
end

return jsond

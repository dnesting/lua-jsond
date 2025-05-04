# jsond

This is a Lua library that implements JSON decoding while preserving Wireshark TvbRange references.
This allows you to use JSON fields as dissector fields, allowing the UI to maintain a reference to
the original packet data.

Status:
This is under active development and unstable.
It's also nearly unacceptably slow and its value is questionable.

# Usage

```lua
jsond = require("jsond")

json = '{"num_field": 42, "obj_field": {"obj_num": 43}, "array_field": ["one", "two"]}'
tvb_range = ByteArray.new(json, true):tvb()()

jsond     = require("jsond")
data      = jsond.decode(tvb_range)  -- a Value

tree:add(field.num_field, data.num_field())  -- unpacks into (TvbRange, number)
tree:add(field.obj_num, data.obj_field.obj_num())

for _, val in ipairs(data.array_field) do
  local first_letter = val:sub(1, 1)  -- "o", "t" Values
  tree:add(field.first_letters, first_letter())
end
```

# API Reference

Generally speaking, JSON types are decoded to standard Lua types,
and wrapped in a class that gives you access to the associated
[`TvbRange`](https://www.wireshark.org/docs/wsdg_html_chunked/lua_module_Tvb.html#lua_class_TvbRange)
and value.

## Functions

### `jsond.decode(tvbr)`

Decodes the JSON data contained in `tvbr`.
Returns a `Value` or raises an error.

```lua
buf  = ByteArray.new("42", true):tvb()()
data = jsond.decode(buf)  -- Number
print(data:range() == buf(0, 2))
print(type(data:val()), data:val())
-- true
-- number 42
```

```lua
buf  = ByteArray.new("[42]", true):tvb()()
data = jsond.decode(buf)  -- Array
elem = data[1]            -- Number
print(elem:range() == buf(1, 2))
print(type(elem:val()), elem:val())
-- true
-- number 42
```

### `jsond.range(data)`

Returns the [`TvbRange`](https://www.wireshark.org/docs/wsdg_html_chunked/lua_module_Tvb.html#lua_class_TvbRange) that was the source for the `Value` held by `data`.
This will work for all classes in the tree returned by `jsond.decode`.
Some classes also implement a `value:range()` method as a convenience.

```lua
buf = ByteArray.new("42", true):tvb()()
data = jsond.decode(buf)       -- Number
print(jsond.range(data) == buf(0, 2))
-- true
```

### `jsond.value(data)`

Returns the Lua value represented by `data`.
This will be `nil` only if the `Value` represents a JSON `null`.
Most classes also implement a `value:val()` method as a convenience.

Note that the aggregated types `Array` and `Object` are represented by a Lua table. An `Array`'s elements will be `Value` instances, as are an `Object's` keys and values.

```lua
buf = ByteArray.new("42", true):tvb()()
data = jsond.decode(buf)  -- Number
print(jsond.value(data) == 42)
-- true
```

---

### `jsond.bool(data)`

Returns the Lua truthiness of the Lua value of `data`. Equivalent to `not not jsond.value(data)`.
Most classes also implement a `value:bool()` method as a convenience.

### `jsond.is_zero(data)`

Returns true if `data` is a number == 0, a false boolean, or an empty string, array, or object.
Most classes also implement a `value:nonzero()` method as a convenience, equivalent to `not jsond.is_zero(data)`.

```lua
buf = ByteArray.new('""', true):tvb()()
data = jsond.decode(buf)  -- String
print(jsond.is_zero(data))
-- true
```

### `jsond.sorted(data [, comp])`

Returns an iterator over a sorted copy of `data`, which must be an `Array` or `Object`.

For an `Array`, this is equivalent to sorting its elements according to how the underlying Lua values compare to each other.  If `comp` is provided, it will be provided these underlying values.

For an `Object`, the iterator yields keys and values, sorted by key.  If `comp` is provided, it will be provided the Lua values for each key.  The values yielded by the iterator will be `Value`s.

```lua
buf = ByteArray.new('{"b": 2, "a": 1}', true):tvb()()
data = jsond.decode(buf)  -- Object
for k, v in jsond.sorted(data) do
  print(k, v)
end
-- a 1
-- b 2
```

```lua
buf = ByteArray.new('["b", "a"]', true):tvb()()
data = jsond.decode(buf)  -- Array
for i, v in jsond.sorted(data) do
  print(i, v)
end
-- 1 a
-- 2 b
```

### `jsond.type(data)`

Returns the JSON type held by `data`.
This will be one of "string", "number", "boolean", "array", "object", "null",
or `nil` if data isn't a `Value`.

```lua
buf = ByteArray.new("42", true):tvb()()
data = jsond.decode(buf)
jsond.type(data)  -- "number"
```

## Classes

```
Value
├── BasicValue
│   ├── Array
│   ├── Boolean
│   ├── Nil
│   ├── Number
│   └── String
└── Object
```

### `Value`

The `Value` class is the superclass of the other classes below.
It implements a few methods that are consistent between all classes.

```
Value
├── __call()
└── __string()
```

#### `__call()`

Every `Value` is callable, returning `(TvbRange, value)`.
This is designed to facilitate use in a WireShark tree.
The following two lines are equivalent:

```lua
tree:add(field.my_field, data())
tree:add(field.my_field, jsond.range(data), jsond.value(data))
```

#### `__string()`

Every `Value` supports `tostring(data)`, which is equivalent to
`tostring(jsond.value(data))`.

### `BasicValue` (`Value`)

```
Value
├── __call()
├── __string()
└── BasicValue
    ├── eq, ne, lt, le, gt, ge
    ├── bool()     -- boolean
    ├── nonzero()  -- boolean
    ├── range()    -- TvbRange
    ├── raw()      -- string
    └── val()      -- underlying Lua value
```

A `BasicValue` is the superclass for `Array`, `Boolean`, `Nil`, `Number`, and `String`, implementing shared convenience methods absent from `Object`.

### Comparators

A `BasicValue` has methods allowing for comparisons against other `BasicValues` as well as standard Lua types.  For example:

```lua
buf = ByteArray.new("42", true):tvb()()
val = jsond.decode(buf)
print(val == 42)  -- val is a Value, not a number
print(val:eq(42))
-- false
-- true
```

The following methods are implemented:

- `eq`, `ne`
- `lt`, `le`
- `gt`, `ge`

### `basic:bool()`

Returns the Lua truthiness of this value.
Equivalent to `jsond.bool(basic)`.

### `basic:nonzero()`

Returns true if the value is non-zero, non-false, non-empty, and non-nil.
Equivalent to `not jsond.is_zero(basic)`.

#### `basic:range()`

Returns the `TvbRange` corresponding to this value.  Equivalent to `jsond.range(basic)`.

#### `basic:raw()`

Returns the raw JSON string for this value.  Equivalent to `jsond.range(basic):raw()`.

#### `basic:val()`

Returns the Lua value corresponding to this value. Equivalent to `jsond.value(basic)`.

### `Boolean` (`BasicValue`)

`Boolean` implements no methods beyond those in `BasicValue`.

### `Nil` (`BasicValue`)

`Nil` implements no methods beyond those in `BasicValue` and always holds only a `nil` value (a JSON `null`).

### `Number` (`BasicValue`)

```
Value
├── __call()
├── __string()
└── BasicValue
    ├── eq, ne, lt, le, gt, ge
    ├── bool()     -- boolean
    ├── nonzero()  -- boolean
    ├── range()    -- TvbRange
    ├── raw()      -- string
    ├── val()      -- number
    └── Number
        └── nstime()  -- NSTime
```

#### `n:nstime()`

Interprets the number as the number of seconds since the Unix `time_t` epoch and returns an `NSTime`.  Approximately equivalent to `NSTime.new(jsond.value(n))`,
but can handle fractional seconds as well.

### `String` (`BasicValue`)

```
Value
├── __call()
├── __string()
└── BasicValue
    ├── eq, ne, lt, le, gt, ge
    ├── bool()     -- boolean
    ├── nonzero()  -- boolean
    ├── range()    -- TvbRange
    ├── raw()      -- string
    ├── val()      -- string
    └── String
        ├── __len()
        ├── byte([i [, j]])        -- Number
        ├── ether()                -- Address
        ├── ipv4()                 -- Address
        ├── ipv6()                 -- Address
        ├── lower()                -- String
        ├── number([base])         -- Number
        ├── sub([first [, last]))  -- String
        └── upper()                -- String
```

A `String` holds a string value.

#### `__len()`

`String` supports `#string`.

#### `s:byte([i [, j]])`

Returns one or more `Number` instances representing the Lua code point(s) for the character(s) at index `i` (defaults to 1) through `j`, similar to the standard `string.byte` function.

```lua
buf = ByteArray.new('"abc"'):tvb()()
s = jsond.decode(buf)
b = s:byte(2)           -- Number
print(b:range() == buf(2, 1))
print(b:val())
-- true
-- 98
```

#### `s:ether()`

Equivalent to `Address.ether(jsond.value(s))` or `jsond.range(s):ether()`.

#### `s:ipv4()`

Equivalent to `Address.ipv4(jsond.value(s))` or `jsond.range(s):ipv4()`.

#### `s:ipv6()`

Equivalent to `Address.ipv6(jsond.value(s))` or `jsond.range(s):ipv6()`.

#### `s:lower()`

Returns a `String` containing a lower-cased copy of `s`.

#### `s:number([base])`

If string contains numeric digits, returns a `Number`, using the optional base.

#### `s:sub([first [, last]])`

Returns a `String` containing the substring starting from `first` (index 1) to `last`,
inclusive, similar to Lua's standard string `:sub()` method.

```lua
buf = ByteArray.new('"foobar"'):tvb()()
s = jsond.decode(buf)
b = s:sub(4, 6)         -- String
print(b:range() == buf(4, 3))
print(type(b:val()), b:val())
-- true
-- string bar
```

#### `s:upper()`

Returns a `String` containing an upper-cased copy of the string.

### `Array` (`BasicValue`)

```
Value
├── __call()
├── __string()
└── BasicValue
    ├── eq, ne, lt, le, gt, ge
    ├── bool()     -- boolean
    ├── nonzero()  -- boolean
    ├── range()    -- TvbRange
    ├── raw()      -- string
    ├── val()      -- table
    └── Array
        ├── __len()
        ├── __pairs()       -- Value
        ├── __index()       -- Value
        ├── sorted([comp])  -- Array
        └── sort()
```

An `Array` holds a `table` of `Value` instances,
indexed by numeric position.

#### `__len()`

An `Array` supports `#array`.

#### `__pairs()` and `__ipairs()`

An `Array` supports iteration using `pairs` and `ipairs`.

#### `__index()` and `__newindex()`

An `Array` supports `array[0]`-style indexing.

#### `a:sorted([comp])`

Returns an iterator over the sorted values of `a`.  The `comp` comparator will be provided the underlying Lua values for each element.

#### `a:sort([comp])`

Performs an in-place sort of the array's `Value`s.
The `comp` comparator will be provided the underlying Lua values for each element.

### `Object` (`Value`)

```
Value
├── __call()
├── __string()
└── Object
    ├── __pairs()  -- String, Value
    └── __index()  -- Value
```

An `Object` contains a mapping from `String` keys to `Value`s.  It contains no methods in order to allow indexing of the underlying object's properties without risk of conflict.

Indexing supports indexing by `String`, or a Lua string.  These references are equivalent:

```lua
buf = ByteArray.new('{"field": "value"}', true):tvb()()
obj = jsond.decode(buf)      -- Object
for k, v in pairs(obj) do
  print(obj[k] == obj["field"])
  print(obj[k] == obj.field)
end
-- true
-- true
```
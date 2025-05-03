# jsond

This is a Lua library that implements JSON decoding while preserving Wireshark TvbRange references.
This allows you to use JSON fields as dissector fields, allowing the UI to maintain a reference to
the original packet data.

# Usage

```lua
test_data = ByteArray.new('{"num_field": 42, "obj_field": {"obj_num": 43}, "array_field": ["one", "two"]}')
test_tvbr = test_data.tvb("Test Data")()

jsond     = require("jsond")
data      = jsond.decode(test_tvbr)  -- a Value

tree:add(field.num_field, data.num_field())  -- unpacks into (TvbRange, number)
tree:add(field.obj_num, data["obj_field"]["obj_num"]())

for _, val in ipairs(data.obj_field.array_field) do
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

### `jsond.range(data)`

Returns the [`TvbRange`](https://www.wireshark.org/docs/wsdg_html_chunked/lua_module_Tvb.html#lua_class_TvbRange) that was the source for the `Value` held by `data`.
This will work for all classes in the tree returned by `jsond.decode`.
Some classes also implement a `value:range()` method as a convenience.

### `jsond.value(data)`

Returns the Lua value represented by `data`.
This will be `nil` only if the `Value` represents a JSON `null`.
Most classes also implement a `value:val()` method as a convenience.

Note that the aggregated types `Array` and `Object` are represented by a Lua table. An `Array`'s elements will be `Value` instances, as are an `Object's` keys and values.

---

### `jsond.bool(data)`

Returns the Lua truthiness of the Lua value of data. Equivalent to `not not jsond.value(data)`.
Most classes also implement a `value:bool()` method as a convenience.

### `jsond.is_zero(data)`

Returns true if `data` is a number == 0, a false boolean, or an empty string, array, or object.
Most classes also implement a `value:nonzero()` method as a convenience, equivalent to `not jsond.is_zero(data)`.

### `jsond.sorted(data [, comp])`

If `data` is an `Array`, returns a copy with its `Value` elements sorted according to comp, which will operate on the underlying Lua type for each `Value`. Equivalent to `array:sorted(comp)`.

If `data` is an `Object`, returns a Lua array of key-value pairs.  Both the key and value in each pair are `Value` instances, and the pair itself is a Lua array. The pairs will be sorted by key.  If `comp` is provided, it will receive each key's underlying Lua value.

### `jsond.type(data)`

Returns the JSON type held by `data`.
This will be one of "string", "number", "boolean", "array", "object", "null",
or `nil` if data isn't a `Value`.

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

```
val = jsond.decode("42")
val == 42    -- false (val is a Value, not a number)
val:eq(42)   -- true
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

Returns a copy of `a` sorted according to `array.sort`.

#### `a:sort([comp])`

Performs an in-place sort of the array's `Value`s.
The `comp` comparison function works like `table.sort`'s and will receive each `Value`'s underlying Lua value.

### `Object` (`Value`)

```
Value
├── __call()
├── __string()
└── Object
    ├── __pairs()
    └── __index()  -- Value
```

An `Object` contains a mapping from `String` keys to `Value`s.  It contains no methods in order to indexing of the underlying object's properties without risk of conflict.

Indexing supports indexing by `String`, or a Lua string.  These references are equivalent:

```
obj = json.decode(text)      -- {"field": "value"}

field = next(obj)[1]         -- String "field"
obj[field] == obj["field"]  -- true
```
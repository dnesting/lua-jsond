local mocks = {}

-- Mock ByteArray
mocks.ByteArray = {}
mocks.ByteArray.__index = mocks.ByteArray
mocks.ByteArray.__name = "ByteArray"

function mocks.ByteArray.new(str, raw_bytes)
    local self = setmetatable({}, ByteArray)
    self.data = str
    --print("mock: ByteArray.new(" .. str .. ")")
    return self
end

function mocks.ByteArray:tvb(name)
    return Tvb.new(self.data, name)
end

function mocks.ByteArray:__tostring()
    return "ByteArray(" .. self.data .. ")"
end

-- Mock Tvb
mocks.Tvb = {}
mocks.Tvb.__index = mocks.Tvb
mocks.Tvb.__name = "Tvb"

function mocks.Tvb.new(data, name)
    local self = setmetatable({}, mocks.Tvb)
    self.data = data
    self.name = name
    return self
end

function mocks.Tvb:range(offset, length)
    offset = offset or 0
    length = length or #self.data - offset
    --print("mock: TvbRange(" .. tostring(offset) .. ", " .. tostring(length) .. ")")
    return mocks.TvbRange.new(self.data, offset, length)
end

-- implement call
function mocks.Tvb:__call(offset, length)
    return self:range(offset, length)
end

function mocks.Tvb:__tostring()
    return "Tvb(" .. self.data .. ")"
end

-- Mock TvbRange
mocks.TvbRange = {}
mocks.TvbRange.__index = mocks.TvbRange
mocks.TvbRange.__name = "TvbRange"

function mocks.TvbRange.new(data, idx, size)
    local self = setmetatable({}, TvbRange)
    --print("mock: TvbRange.new(" .. subdata .. ")")
    self.data = data
    self.idx = idx
    self.size = size
    return self
end

function mocks.TvbRange:__call(offset, length)
    offset = offset or 0
    offset = offset + self.idx
    length = length or self.size - offset
    return mocks.TvbRange.new(self.data, offset, length)
end

function mocks.TvbRange.__eq(a, b)
    return a.data == b.data and a.idx == b.idx and a.size == b.size
end

function mocks.TvbRange:raw()
    return self.data:sub(self.idx + 1, self.idx + self.size)
end

function mocks.TvbRange:__tostring()
    return "TvbRange(" .. self:raw() .. ")"
end

function mocks.TvbRange:len()
    return self.size
end

return mocks

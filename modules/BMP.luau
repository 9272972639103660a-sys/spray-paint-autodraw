--!strict
-- BMP Decoder for Luau (Fast, zero-decompression overhead for mobile)
local BMP = {}
BMP.__index = BMP

function BMP.new(bufferString: string)
    assert(#bufferString >= 54, "Invalid BMP file: too short")
    local magic = bufferString:sub(1, 2)
    assert(magic == "BM", "Invalid BMP magic header (expected BM)")

    local function readInt16(offset: number): number
        local b1, b2 = string.byte(bufferString, offset, offset + 1)
        return b1 + b2 * 256
    end

    local function readInt32(offset: number): number
        local b1, b2, b3, b4 = string.byte(bufferString, offset, offset + 3)
        return b1 + b2 * 256 + b3 * 65536 + b4 * 16777216
    end

    local pixelOffset = readInt32(11)
    local width = readInt32(19)
    local height = readInt32(23)
    local bpp = readInt16(29)
    local compression = readInt32(31)

    assert(compression == 0, "Only uncompressed BMP files are supported")
    assert(bpp == 24 or bpp == 32, "Only 24-bit and 32-bit BMP files are supported")

    local isTopDown = false
    if height < 0 then
        isTopDown = true
        height = -height
    end

    local rowSize = math.floor((bpp * width + 31) / 32) * 4
    local self = setmetatable({
        Width = width,
        Height = height,
        Bpp = bpp,
        _buffer = bufferString,
        _pixelOffset = pixelOffset,
        _rowSize = rowSize,
        _isTopDown = isTopDown,
    }, BMP)

    return self
end

function BMP:GetPixel(x: number, y: number): (Color3, number)
    if x < 1 or x > self.Width or y < 1 or y > self.Height then
        return Color3.new(0, 0, 0), 0
    end

    local rowIndex = self._isTopDown and (y - 1) or (self.Height - y)
    local byteOffset = self._pixelOffset + (rowIndex * self._rowSize) + ((x - 1) * (self.Bpp / 8))

    local b = string.byte(self._buffer, byteOffset + 1) or 0
    local g = string.byte(self._buffer, byteOffset + 2) or 0
    local r = string.byte(self._buffer, byteOffset + 3) or 0
    local a = 255

    if self.Bpp == 32 then
        a = string.byte(self._buffer, byteOffset + 4) or 255
    end

    return Color3.fromRGB(r, g, b), a
end

return BMP

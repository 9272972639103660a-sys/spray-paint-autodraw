--[[
    =======================================================================
    SPRAY PAINT AUTODRAW (Mobile & Desktop Custom Edition)
    =======================================================================
    100% Autonomous, Standalone & Self-Contained.
    Zero external dependencies, zero GitHub loadstrings.
    Powered by Custom Visual Graphical Emojis (Procedural & Vector Badges).

    Optimized specifically for mobile touchscreen Roblox executors:
    Delta, Codex, Arceus X, Fluxus, Hydrogen, Vega X, etc.

    Core Capabilities:
    - Direct executor workspace file loader: "SprayPaint_Images/"
    - Direct image URL downloader (PNG / BMP)
    - Pure Luau PNG & High-Speed uncompressed BMP decoders
    - Resolution downscaling to eliminate mobile memory freezes
    - Dynamic Anti-Cheat security hash generation (ErrorModule)
    - Camera Raycast Wall Aiming & 3D Translucent Ghost Preview
    - Custom Touch-Draggable Mobile GUI & Floating Bubble Toggle
    - Procedural & Vector Custom Emojis for all UI elements
    - Raster, Color Clustering (Palette) and Spiral drawing modes
    - Real-time Pause, Resume, and Emergency Cancel controls
    =======================================================================
]]

local Players = game:GetService("Players")
local Workspace = game:GetService("Workspace")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local HttpService = game:GetService("HttpService")
local UserInputService = game:GetService("UserInputService")
local TweenService = game:GetService("TweenService")
local RunService = game:GetService("RunService")
local CoreGui = game:GetService("CoreGui")

local LocalPlayer = Players.LocalPlayer

-- =======================================================================
-- 1. FILE SYSTEM & DIRECTORY INITIALIZATION
-- =======================================================================
local WORKSPACE_FOLDER = "SprayPaint_Images"

local function safeIsFolder(path: string): boolean
    local ok, res = pcall(function()
        if typeof(isfolder) == "function" then
            return isfolder(path)
        end
        return false
    end)
    return ok and res == true
end

local function safeMakeFolder(path: string)
    pcall(function()
        if typeof(makefolder) == "function" and not safeIsFolder(path) then
            makefolder(path)
        end
    end)
end

local function safeWriteFile(path: string, content: string)
    pcall(function()
        if typeof(writefile) == "function" then
            writefile(path, content)
        end
    end)
end

local function safeReadFile(path: string): string?
    local ok, res = pcall(function()
        if typeof(readfile) == "function" then
            return readfile(path)
        end
        return nil
    end)
    return ok and res or nil
end

local function safeListFiles(path: string): {string}
    local ok, res = pcall(function()
        if typeof(listfiles) == "function" then
            return listfiles(path)
        end
        return {}
    end)
    return (ok and typeof(res) == "table") and res or {}
end

-- Initialize workspace directory
safeMakeFolder(WORKSPACE_FOLDER)
safeWriteFile(WORKSPACE_FOLDER .. "/readme.txt", 
    "Place your .png or .bmp files here!\n" ..
    "Recommended resolutions: 50x50 to 100x100 for fast, smooth painting on mobile.\n" ..
    "Press the Refresh button in the script UI to see newly added files."
)

local function getAvailableFiles(): {string}
    local rawList = safeListFiles(WORKSPACE_FOLDER)
    local filtered: {string} = {}

    for _, filePath in ipairs(rawList) do
        local cleanPath = filePath:gsub("\\", "/")
        local fileName = cleanPath:match("([^/]+)$") or cleanPath
        local ext = fileName:match("%.([^.]+)$")
        if ext then
            ext = ext:lower()
            if ext == "png" or ext == "bmp" or ext == "jpg" then
                table.insert(filtered, fileName)
            end
        end
    end

    if #filtered == 0 then
        table.insert(filtered, "No images found in folder")
    end
    return filtered
end

-- =======================================================================
-- 2. EMBEDDED MODULES (BMP, PNG, SECURITY, ENGINE)
-- =======================================================================
local BMP = (function()

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

end)()

local PNG = (function()
local PNG = {}
PNG.__index = PNG

local chunks = {};
local function IDAT(file, chunk)
	local crc = chunk.CRC
	local hash = file.Hash or 0

	local data = chunk.Data
	local buffer = data.Buffer

	file.Hash = bit32.bxor(hash, crc)
	file.ZlibStream = file.ZlibStream .. buffer
end

chunks['IDAT'] = IDAT;

local function IEND(file)
	file.Reading = nil
end
chunks['IEND'] = IEND;

local function IHDR(file, chunk)
	local data = chunk.Data

	file.Width = data:ReadInt32();
	file.Height = data:ReadInt32();

	file.BitDepth = data:ReadByte();
	file.ColorType = data:ReadByte();

	file.Methods =
		{
			Compression = data:ReadByte();
			Filtering   = data:ReadByte();
			Interlace   = data:ReadByte();
		}
end


chunks['IHDR'] = IHDR;

local function PLTE(file, chunk)
	if not file.Palette then
		file.Palette = {}
	end

	local data = chunk.Data
	local palette = data:ReadAllBytes()

	if #palette % 3 ~= 0 then
		error("[ERROR]: Invalid PLTE chunk.")
	end

	for i = 1, #palette, 3 do
		local r = palette[i]
		local g = palette[i + 1]
		local b = palette[i + 2]

		local color = Color3.fromRGB(r, g, b)
		local index = #file.Palette + 1

		file.Palette[index] = color
	end
end


chunks['PLTE'] = PLTE;

local function bKGD(file, chunk)
	local data = chunk.Data

	local bitDepth = file.BitDepth
	local colorType = file.ColorType

	bitDepth = (2 ^ bitDepth) - 1

	if colorType == 3 then
		local index = data:ReadByte()
		file.BackgroundColor = file.Palette[index]
	elseif colorType == 0 or colorType == 4 then
		local gray = data:ReadUInt16() / bitDepth
		file.BackgroundColor = Color3.fromHSV(0, 0, gray)
	elseif colorType == 2 or colorType == 6 then
		local r = data:ReadUInt16() / bitDepth
		local g = data:ReadUInt16() / bitDepth
		local b = data:ReadUInt16() / bitDepth
		file.BackgroundColor = Color3.new(r, g, b)
	end
end

chunks['bKGD'] = bKGD;

local colors = {"White", "Red", "Green", "Blue"}

local function cHRM(file, chunk)
	local chrome = {}
	local data = chunk.Data

	for i = 1, 4 do
		local color = colors[i]

		chrome[color] =
			{
				[1] = data:ReadUInt32() / 10e4;
				[2] = data:ReadUInt32() / 10e4;
			}
	end

	file.Chromaticity = chrome
end

chunks['cHRM'] = cHRM;

local function gAMA(file, chunk)
	local data = chunk.Data
	local value = data:ReadUInt32()
	file.Gamma = value / 10e4
end

chunks['gAMA'] = gAMA;

local function sRGB(file, chunk)
	local data = chunk.Data
	file.RenderIntent = data:ReadByte()
end

chunks['sRGB'] = sRGB;

local function tEXt(file, chunk)
	local data = chunk.Data
	local key, value = "", ""

	for byte in data:IterateBytes() do
		local char = string.char(byte)

		if char == '\0' then
			key = value
			value = ""
		else
			value = value .. char
		end
	end

	file.Metadata[key] = value
end

chunks['tEXt'] = tEXt;

local function tIME(file, chunk)
	local data = chunk.Data

	local timeStamp = 
		{
			Year  = data:ReadUInt16();
			Month = data:ReadByte();
			Day   = data:ReadByte();

			Hour   = data:ReadByte();
			Minute = data:ReadByte();
			Second = data:ReadByte();
		}

	file.TimeStamp = timeStamp
end

chunks['tIME'] = tIME;

local function tRNS(file, chunk)
	local data = chunk.Data

	local bitDepth = file.BitDepth
	local colorType = file.ColorType

	bitDepth = (2 ^ bitDepth) - 1

	if colorType == 3 then
		local palette = file.Palette
		local alphaMap = {}

		for i = 1, #palette do
			local alpha = data:ReadByte()

			if not alpha then
				alpha = 255
			end

			alphaMap[i] = alpha
		end

		file.AlphaData = alphaMap
	elseif colorType == 0 then
		local grayAlpha = data:ReadUInt16()
		file.Alpha = grayAlpha / bitDepth
	elseif colorType == 2 then
		-- TODO: This seems incorrect...
		local r = data:ReadUInt16() / bitDepth
		local g = data:ReadUInt16() / bitDepth
		local b = data:ReadUInt16() / bitDepth
		file.Alpha = Color3.new(r, g, b)
	else
		error("[ERROR]: Invalid tRNS chunk.")
	end	
end


chunks['tRNS'] = tRNS;

local Deflate = {}

local band = bit32.band
local lshift = bit32.lshift
local rshift = bit32.rshift

local BTYPE_NO_COMPRESSION = 0
local BTYPE_FIXED_HUFFMAN = 1
local BTYPE_DYNAMIC_HUFFMAN = 2

local lens = -- Size base for length codes 257..285
	{
		[0] = 3, 4, 5, 6, 7, 8, 9, 10, 11, 13, 15, 17, 19, 23, 27, 31,
		35, 43, 51, 59, 67, 83, 99, 115, 131, 163, 195, 227, 258
	}

local lext = -- Extra bits for length codes 257..285
	{
		[0] = 0, 0, 0, 0, 0, 0, 0, 0, 1, 1, 1, 1, 2, 2, 2, 2,
		3, 3, 3, 3, 4, 4, 4, 4, 5, 5, 5, 5, 0
	}

local dists = -- Offset base for distance codes 0..29
	{
		[0] = 1, 2, 3, 4, 5, 7, 9, 13, 17, 25, 33, 49, 65, 97, 129, 193,
		257, 385, 513, 769, 1025, 1537, 2049, 3073, 4097, 6145,
		8193, 12289, 16385, 24577
	}

local dext = -- Extra bits for distance codes 0..29
	{
		[0] = 0, 0, 0, 0, 1, 1, 2, 2, 3, 3, 4, 4, 5, 5, 6, 6,
		7, 7, 8, 8, 9, 9, 10, 10, 11, 11,
		12, 12, 13, 13
	}

local order = -- Permutation of code length codes
	{
		16, 17, 18, 0, 8, 7, 9, 6, 10, 5, 
		11, 4, 12, 3, 13, 2, 14, 1, 15
	}

-- Fixed literal table for BTYPE_FIXED_HUFFMAN
local fixedLit = {0, 8, 144, 9, 256, 7, 280, 8, 288}

-- Fixed distance table for BTYPE_FIXED_HUFFMAN
local fixedDist = {0, 5, 32}

local function createState(bitStream)
	local state = 
		{
			Output = bitStream;
			Window = {};
			Pos = 1;
		}

	return state
end

local function write(state, byte)
	local pos = state.Pos
	state.Output(byte)
	state.Window[pos] = byte
	state.Pos = pos % 32768 + 1  -- 32K
end

local function memoize(fn)
	local meta = {}
	local memoizer = setmetatable({}, meta)

	function meta:__index(k)
		local v = fn(k)
		memoizer[k] = v

		return v
	end

	return memoizer
end

-- small optimization (lookup table for powers of 2)
local pow2 = memoize(function (n) 
	return 2 ^ n 
end)

-- weak metatable marking objects as bitstream type
local isBitStream = setmetatable({}, { __mode = 'k' })

local function createBitStream(reader)
	local buffer = 0
	local bitsLeft = 0

	local stream = {}
	isBitStream[stream] = true

	function stream:GetBitsLeft()
		return bitsLeft
	end

	function stream:Read(count)
		count = count or 1

		while bitsLeft < count do
			local byte = reader:ReadByte()

			if not byte then 
				return 
			end

			buffer = buffer + lshift(byte, bitsLeft)
			bitsLeft = bitsLeft + 8
		end

		local bits

		if count == 0 then
			bits = 0
		elseif count == 32 then
			bits = buffer
			buffer = 0
		else
			bits = band(buffer, rshift(2^32 - 1, 32 - count))
			buffer = rshift(buffer, count)
		end

		bitsLeft = bitsLeft - count
		return bits
	end

	return stream
end

local function getBitStream(obj)
	if isBitStream[obj] then
		return obj
	end

	return createBitStream(obj)
end

local function sortHuffman(a, b)
	return a.NumBits == b.NumBits and a.Value < b.Value or a.NumBits < b.NumBits
end

local function msb(bits, numBits)
	local res = 0

	for i = 1, numBits do
		res = lshift(res, 1) + band(bits, 1)
		bits = rshift(bits, 1)
	end

	return res
end

local function createHuffmanTable(init, isFull)
	local hTable = {}

	if isFull then
		for val, numBits in pairs(init) do
			if numBits ~= 0 then
				hTable[#hTable + 1] = 
					{
						Value = val;
						NumBits = numBits;
					}
			end
		end
	else
		for i = 1, #init - 2, 2 do
			local firstVal = init[i]

			local numBits = init[i + 1]
			local nextVal = init[i + 2]

			if numBits ~= 0 then
				for val = firstVal, nextVal - 1 do
					hTable[#hTable + 1] = 
						{
							Value = val;
							NumBits = numBits;
						}
				end
			end
		end
	end

	table.sort(hTable, sortHuffman)

	local code = 1
	local numBits = 0

	for i, slide in ipairs(hTable) do
		if slide.NumBits ~= numBits then
			code = code * pow2[slide.NumBits - numBits]
			numBits = slide.NumBits
		end

		slide.Code = code
		code = code + 1
	end

	local minBits = math.huge
	local look = {}

	for i, slide in ipairs(hTable) do
		minBits = math.min(minBits, slide.NumBits)
		look[slide.Code] = slide.Value
	end

	local firstCode = memoize(function (bits) 
		return pow2[minBits] + msb(bits, minBits) 
	end)

	function hTable:Read(bitStream)
		local code = 1 -- leading 1 marker
		local numBits = 0

		while true do
			if numBits == 0 then  -- small optimization (optional)
				local index = bitStream:Read(minBits)
				numBits = numBits + minBits
				code = firstCode[index]
			else
				local bit = bitStream:Read()
				numBits = numBits + 1
				code = code * 2 + bit -- MSB first
			end

			local val = look[code]

			if val then
				return val
			end
		end
	end

	return hTable
end

local function parseZlibHeader(bitStream)
	-- Compression Method
	local cm = bitStream:Read(4)

	-- Compression info
	local cinfo = bitStream:Read(4)  

	-- FLaGs: FCHECK (check bits for CMF and FLG)   
	local fcheck = bitStream:Read(5)

	-- FLaGs: FDICT (present dictionary)
	local fdict = bitStream:Read(1)

	-- FLaGs: FLEVEL (compression level)
	local flevel = bitStream:Read(2)

	-- CMF (Compresion Method and flags)
	local cmf = cinfo * 16  + cm

	-- FLaGs
	local flg = fcheck + fdict * 32 + flevel * 64 

	if cm ~= 8 then -- not "deflate"
		error("[ERROR]: Unrecognized image Compression Method: " .. tostring(cm))
	end

	if cinfo > 7 then
		error("[ERROR]: Invalid image Window Size: cinfo -> " .. tostring(cinfo))
	end

	local windowSize = 2 ^ (cinfo + 8)

	if (cmf * 256 + flg) % 31 ~= 0 then
		error("[ERROR]: Invalid image header (bad fcheck sum)")
	end

	if fdict == 1 then
		error("[TODO]: - FDICT not currently implemented")
	end

	return windowSize
end

local function parseHuffmanTables(bitStream)
	local numLits  = bitStream:Read(5) -- # of literal/length codes - 257
	local numDists = bitStream:Read(5) -- # of distance codes - 1
	local numCodes = bitStream:Read(4) -- # of code length codes - 4

	local codeLens = {}

	for i = 1, numCodes + 4 do
		local index = order[i]
		codeLens[index] = bitStream:Read(3)
	end

	codeLens = createHuffmanTable(codeLens, true)

	local function decode(numCodes)
		local init = {}
		local numBits
		local val = 0

		while val < numCodes do
			local codeLen = codeLens:Read(bitStream)
			local numRepeats

			if codeLen <= 15 then
				numRepeats = 1
				numBits = codeLen
			elseif codeLen == 16 then
				numRepeats = 3 + bitStream:Read(2)
			elseif codeLen == 17 then
				numRepeats = 3 + bitStream:Read(3)
				numBits = 0
			elseif codeLen == 18 then
				numRepeats = 11 + bitStream:Read(7)
				numBits = 0
			end

			for i = 1, numRepeats do
				init[val] = numBits
				val = val + 1
			end
		end

		return createHuffmanTable(init, true)
	end

	local numLitCodes = numLits + 257
	local numDistCodes = numDists + 1

	local litTable = decode(numLitCodes)
	local distTable = decode(numDistCodes)

	return litTable, distTable
end

local function parseCompressedItem(bitStream, state, litTable, distTable)
	local val = litTable:Read(bitStream)

	if val < 256 then -- literal
		write(state, val)
	elseif val == 256 then -- end of block
		return true
	else
		local lenBase = lens[val - 257]
		local numExtraBits = lext[val - 257]

		local extraBits = bitStream:Read(numExtraBits)
		local len = lenBase + extraBits

		local distVal = distTable:Read(bitStream)
		local distBase = dists[distVal]

		local distNumExtraBits = dext[distVal]
		local distExtraBits = bitStream:Read(distNumExtraBits)

		local dist = distBase + distExtraBits

		for i = 1, len do
			local pos = (state.Pos - 1 - dist) % 32768 + 1
			local byte = assert(state.Window[pos], "invalid distance")
			write(state, byte)
		end
	end

	return false
end

local function parseBlock(bitStream, state)
	local bFinal = bitStream:Read(1)
	local bType = bitStream:Read(2)

	if bType == BTYPE_NO_COMPRESSION then
		local left = bitStream:GetBitsLeft()
		bitStream:Read(left)

		local len = bitStream:Read(16)
		local nlen = bitStream:Read(16)

		for i = 1, len do
			local byte = bitStream:Read(8)
			write(state, byte)
		end
	elseif bType == BTYPE_FIXED_HUFFMAN or bType == BTYPE_DYNAMIC_HUFFMAN then
		local litTable, distTable

		if bType == BTYPE_DYNAMIC_HUFFMAN then
			litTable, distTable = parseHuffmanTables(bitStream)
		else
			litTable = createHuffmanTable(fixedLit)
			distTable = createHuffmanTable(fixedDist)
		end

		repeat until parseCompressedItem(bitStream, state, litTable, distTable)
	else
		error("[ERROR]: Unrecognized compression type.")
	end

	return bFinal ~= 0
end

function Deflate:Inflate(io)
	local state = createState(io.Output)
	local bitStream = getBitStream(io.Input)

	repeat until parseBlock(bitStream, state)
end

function Deflate:InflateZlib(io)
	local bitStream = getBitStream(io.Input)
	local windowSize = parseZlibHeader(bitStream)

	self:Inflate
	{
		Input = bitStream;
		Output = io.Output;
	}

	local bitsLeft = bitStream:GetBitsLeft()
	bitStream:Read(bitsLeft)
end

local Unfilter = {}

function Unfilter:None(scanline, pixels, bpp, row)
	for i = 1, #scanline do
		pixels[row][i] = scanline[i]
	end
end

function Unfilter:Sub(scanline, pixels, bpp, row)
	for i = 1, bpp do
		pixels[row][i] = scanline[i]
	end

	for i = bpp + 1, #scanline do
		local x = scanline[i]
		local a = pixels[row][i - bpp]
		pixels[row][i] = bit32.band(x + a, 0xFF)
	end
end

function Unfilter:Up(scanline, pixels, bpp, row)
	if row > 1 then
		local upperRow = pixels[row - 1]

		for i = 1, #scanline do
			local x = scanline[i]
			local b = upperRow[i]
			pixels[row][i] = bit32.band(x + b, 0xFF)
		end
	else
		self:None(scanline, pixels, bpp, row)
	end
end

function Unfilter:Average(scanline, pixels, bpp, row)
	if row > 1 then
		for i = 1, bpp do
			local x = scanline[i]
			local b = pixels[row - 1][i]

			b = bit32.rshift(b, 1)
			pixels[row][i] = bit32.band(x + b, 0xFF)
		end

		for i = bpp + 1, #scanline do
			local x = scanline[i]
			local b = pixels[row - 1][i]

			local a = pixels[row][i - bpp]
			local ab = bit32.rshift(a + b, 1)

			pixels[row][i] = bit32.band(x + ab, 0xFF)
		end
	else
		for i = 1, bpp do
			pixels[row][i] = scanline[i]
		end

		for i = bpp + 1, #scanline do
			local x = scanline[i]
			local b = pixels[row - 1][i]

			b = bit32.rshift(b, 1)
			pixels[row][i] = bit32.band(x + b, 0xFF)
		end
	end
end

function Unfilter:Paeth(scanline, pixels, bpp, row)
	if row > 1 then
		local pr

		for i = 1, bpp do
			local x = scanline[i]
			local b = pixels[row - 1][i]
			pixels[row][i] = bit32.band(x + b, 0xFF)
		end

		for i = bpp + 1, #scanline do
			local a = pixels[row][i - bpp]
			local b = pixels[row - 1][i]
			local c = pixels[row - 1][i - bpp]

			local x = scanline[i]
			local p = a + b - c

			local pa = math.abs(p - a)
			local pb = math.abs(p - b)
			local pc = math.abs(p - c)

			if pa <= pb and pa <= pc then
				pr = a
			elseif pb <= pc then
				pr = b
			else
				pr = c
			end

			pixels[row][i] = bit32.band(x + pr, 0xFF)
		end
	else
		self:Sub(scanline, pixels, bpp, row)
	end
end


local BinaryReader = {}
BinaryReader.__index = BinaryReader

function BinaryReader.new(buffer)
	local reader = 
		{
			Position = 1;
			Buffer = buffer;
			Length = #buffer;
		}

	return setmetatable(reader, BinaryReader)
end

function BinaryReader:ReadByte()
	local buffer = self.Buffer
	local pos = self.Position

	if pos <= self.Length then
		local result = buffer:sub(pos, pos)
		self.Position = pos + 1

		return result:byte()
	end
end

function BinaryReader:ReadBytes(count, asArray)
	local values = {}

	for i = 1, count do
		values[i] = self:ReadByte()
	end

	if asArray then
		return values
	end

	return unpack(values)
end

function BinaryReader:ReadAllBytes()
	return self:ReadBytes(self.Length, true)
end

function BinaryReader:IterateBytes()
	return function ()
		return self:ReadByte()
	end
end

function BinaryReader:TwosComplementOf(value, numBits)
	if value >= (2 ^ (numBits - 1)) then
		value = value - (2 ^ numBits)
	end

	return value
end

function BinaryReader:ReadUInt16()
	local upper, lower = self:ReadBytes(2)
	return (upper * 256) + lower
end

function BinaryReader:ReadInt16()
	local unsigned = self:ReadUInt16()
	return self:TwosComplementOf(unsigned, 16)
end

function BinaryReader:ReadUInt32()
	local upper = self:ReadUInt16()
	local lower = self:ReadUInt16()

	return (upper * 65536) + lower
end

function BinaryReader:ReadInt32()
	local unsigned = self:ReadUInt32()
	return self:TwosComplementOf(unsigned, 32)
end

function BinaryReader:ReadString(length)
	if length == nil then
		length = self:ReadByte()
	end

	local pos = self.Position
	local nextPos = math.min(self.Length, pos + length)

	local result = self.Buffer:sub(pos, nextPos - 1)
	self.Position = nextPos

	return result
end

function BinaryReader:ForkReader(length)
	local chunk = self:ReadString(length)
	return BinaryReader.new(chunk)
end


local function getBytesPerPixel(colorType)
	if colorType == 0 or colorType == 3 then
		return 1
	elseif colorType == 4 then
		return 2
	elseif colorType == 2 then
		return 3
	elseif colorType == 6 then
		return 4
	else
		return 0
	end
end

local function clampInt(value, min, max)
	local num = tonumber(value) or 0
	num = math.floor(num + .5)

	return math.clamp(num, min, max)
end

local function indexBitmap(file, x, y)
	local width = file.Width
	local height = file.Height

	local x = clampInt(x, 1, width) 
	local y = clampInt(y, 1, height)

	local bitmap = file.Bitmap
	local bpp = file.BytesPerPixel

	local i0 = ((x - 1) * bpp) + 1
	local i1 = i0 + bpp

	return bitmap[y], i0, i1
end

function PNG:GetPixel(t,x, y)
	local row, i0, i1 = indexBitmap(t, x, y)
	local colorType = t.ColorType
	self = t;

	local color, alpha do
		if colorType == 0 then
			local gray = unpack(row, i0, i1)
			color = Color3.fromHSV(0, 0, gray)
			alpha = 255
		elseif colorType == 2 then
			local r, g, b = unpack(row, i0, i1)
			color = Color3.fromRGB(r, g, b)
			alpha = 255
		elseif colorType == 3 then
			local palette = self.Palette
			local alphaData = self.AlphaData

			local index = unpack(row, i0, i1)
			index = index + 1

			if palette then
				color = palette[index]
			end

			if alphaData then
				alpha = alphaData[index]
			end
		elseif colorType == 4 then
			local gray, a = unpack(row, i0, i1)
			color = Color3.fromHSV(0, 0, gray)
			alpha = a
		elseif colorType == 6 then
			local r, g, b, a = unpack(row, i0, i1)
			color = Color3.fromRGB(r, g, b, a)
			alpha = a
		end
	end

	if not color then
		color = Color3.new()
	end

	if not alpha then
		alpha = 255
	end

	return color, alpha
end

function PNG.new(buffer)
	-- Create the reader.
	local reader = BinaryReader.new(buffer)

	-- Create the file object.
	local file =
		{
			Chunks = {};
			Metadata = {};

			Reading = true;
			ZlibStream = "";
		}

	-- Verify the file header.
	local header = reader:ReadString(8)

	if header ~= "\137PNG\r\n\26\n" then
		error("[ERROR]: Input data is not a PNG file.")
	end

	while file.Reading do
		local length = reader:ReadInt32()
		local chunkType = reader:ReadString(4)

		local data, crc

		if length > 0 then
			data = reader:ForkReader(length)
			crc = reader:ReadUInt32()
		end

		local chunk = 
			{
				Length = length;
				Type = chunkType;

				Data = data;
				CRC = crc;
			}

		local handler = chunks[chunkType];

		if handler then
			handler(file, chunk)
		end

		table.insert(file.Chunks, chunk)
	end

	-- Decompress the zlib stream.
	local success, response = pcall(function ()
		local result = {}
		local index = 0

		Deflate:InflateZlib
		{
			Input = BinaryReader.new(file.ZlibStream);

			Output = function (byte)
				index = index + 1
				result[index] = string.char(byte)
			end
		}

		return table.concat(result)
	end)

	if not success then
		error("[ERROR]: Unable to unpack PNG data. Response: " .. tostring(response))
	end

	-- Grab expected info from the file.

	local width = file.Width
	local height = file.Height

	local bitDepth = file.BitDepth
	local colorType = file.ColorType

	local buffer = BinaryReader.new(response)
	file.ZlibStream = nil

	local bitmap = {}
	file.Bitmap = bitmap

	local channels = getBytesPerPixel(colorType)
	file.NumChannels = channels

	local bpp = math.max(1, channels * (bitDepth / 8))
	file.BytesPerPixel = bpp

	-- Unfilter the buffer and 
	-- load it into the bitmap.

	for row = 1, height do	
		local filterType = buffer:ReadByte()
		local scanline = buffer:ReadBytes(width * bpp, true)

		bitmap[row] = {}

		if filterType == 0 then
			-- None
			Unfilter:None(scanline, bitmap, bpp, row)
		elseif filterType == 1 then
			-- Sub
			Unfilter:Sub(scanline, bitmap, bpp, row)
		elseif filterType == 2 then
			-- Up
			Unfilter:Up(scanline, bitmap, bpp, row)
		elseif filterType == 3 then
			-- Average
			Unfilter:Average(scanline, bitmap, bpp, row)
		elseif filterType == 4 then
			-- Paeth
			Unfilter:Paeth(scanline, bitmap, bpp, row)
		end
	end

	return setmetatable(file, PNG)
end

return PNG

end)()

local Security = (function()

-- Security & Remote Protocol Handler for Spray Paint!
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Workspace = game:GetService("Workspace")

local Security = {}

local cachedErrorModule = nil
local cachedScriptPath = nil

local function getErrorModule()
    if cachedErrorModule ~= nil then
        return cachedErrorModule
    end

    local success, module = pcall(function()
        local printFolder = ReplicatedStorage:FindFirstChild("Modules")
        if printFolder then
            local p = printFolder:FindFirstChild("Print")
            if p then
                local em = p:FindFirstChild("ErrorModule")
                if em and em:IsA("ModuleScript") then
                    return require(em)
                end
            end
        end
        return nil
    end)

    if success and module then
        cachedErrorModule = module
    else
        cachedErrorModule = false
    end

    return cachedErrorModule
end

local function getLocalScriptFullName(): string?
    if cachedScriptPath then
        return cachedScriptPath
    end

    local lp = Players.LocalPlayer
    if not lp then return nil end

    local pg = lp:FindFirstChild("PlayerGui")
    if pg then
        local paintGui = pg:FindFirstChild("PaintGui")
        if paintGui then
            local ls = paintGui:FindFirstChild("LocalScript")
            if ls then
                cachedScriptPath = ls:GetFullName()
                return cachedScriptPath
            end
        end
    end

    return "Players." .. lp.Name .. ".PlayerGui.PaintGui.LocalScript"
end

-- Returns security arguments (number, hash) or fallback tokens
function Security.getSecurityArgs(): (number, any)
    local errMod = getErrorModule()
    local serverTime = Workspace:GetServerTimeNow()

    if errMod and typeof(errMod) == "function" then
        local scriptPath = getLocalScriptFullName()
        local success, hash = pcall(function()
            return errMod(scriptPath, serverTime * 72000)
        end)

        if success and hash then
            return serverTime, hash
        end
    end

    -- Legacy fallback token
    return 300000, 300000
end

-- Finds the SprayPaint tool in character or backpack
function Security.findSprayPaintTool(): Tool?
    local lp = Players.LocalPlayer
    if not lp then return nil end

    local char = lp.Character
    if char then
        local tool = char:FindFirstChild("SprayPaint")
        if tool and tool:IsA("Tool") then
            return tool
        end
    end

    local bp = lp:FindFirstChild("Backpack")
    if bp then
        local tool = bp:FindFirstChild("SprayPaint")
        if tool and tool:IsA("Tool") then
            return tool
        end
    end

    return nil
end

-- Finds the Remote used for painting (SendPaintInfo)
function Security.findPaintRemote(tool: Tool?): (Instance?, string?)
    local currentTool = tool or Security.findSprayPaintTool()
    if currentTool then
        local remote = currentTool:FindFirstChild("SendPaintInfo")
        if remote then
            if remote:IsA("RemoteFunction") then
                return remote, "InvokeServer"
            elseif remote:IsA("RemoteEvent") then
                return remote, "FireServer"
            end
        end
    end

    -- Check ReplicatedStorage in case remotes moved
    local rsRemotes = ReplicatedStorage:FindFirstChild("Remotes")
    if rsRemotes then
        local paintRemote = rsRemotes:FindFirstChild("SendPaintInfo") or rsRemotes:FindFirstChild("Paint")
        if paintRemote then
            if paintRemote:IsA("RemoteFunction") then
                return paintRemote, "InvokeServer"
            elseif paintRemote:IsA("RemoteEvent") then
                return paintRemote, "FireServer"
            end
        end
    end

    return nil, nil
end

return Security

end)()

local DrawEngine = (function()

-- High Performance Batched Drawing Engine for Spray Paint!
-- Security is in parent scope

local DrawEngine = {}
DrawEngine.__index = DrawEngine

export type DrawPoint = {
    x: number,
    y: number,
    color: Color3,
    alpha: number,
}

export type PaintStroke = {
    scale: number,
    cframe: CFrame,
    color: Color3,
    layer: number,
}

function DrawEngine.new()
    local self = setmetatable({
        _isRunning = false,
        _isPaused = false,
        _isCancelled = false,
        _thread = nil :: thread?,
        
        -- Default settings
        batchSize = 35,
        batchDelay = 0.06,
        pixelScale = 0.25,
        spacingMult = 0.45,
        drawMode = "Raster", -- "Raster", "Palette", "Spiral"
        alphaThreshold = 15,
        skipWhite = false,
        skipBlack = false,
        maxResolution = 80,
    }, DrawEngine)
    return self
end

function DrawEngine:IsRunning(): boolean
    return self._isRunning
end

function DrawEngine:IsPaused(): boolean
    return self._isPaused
end

function DrawEngine:Pause()
    self._isPaused = true
end

function DrawEngine:Resume()
    self._isPaused = false
end

function DrawEngine:Cancel()
    self._isCancelled = true
    self._isRunning = false
    self._isPaused = false
end

-- Collects and downscales/filters pixels from the loaded image
function DrawEngine:ProcessImage(image: any): { points: {DrawPoint}, width: number, height: number }
    local origW = image.Width
    local origH = image.Height

    -- Calculate downscaled dimensions to prevent lag/crash on mobile
    local scaleFactor = 1
    if math.max(origW, origH) > self.maxResolution then
        scaleFactor = self.maxResolution / math.max(origW, origH)
    end

    local finalW = math.clamp(math.floor(origW * scaleFactor), 1, self.maxResolution)
    local finalH = math.clamp(math.floor(origH * scaleFactor), 1, self.maxResolution)

    local points: {DrawPoint} = {}

    for targetY = 1, finalH do
        local sourceY = math.clamp(math.floor((targetY - 0.5) / scaleFactor) + 1, 1, origH)
        for targetX = 1, finalW do
            local sourceX = math.clamp(math.floor((targetX - 0.5) / scaleFactor) + 1, 1, origW)

            local color, alpha = image:GetPixel(sourceX, sourceY)
            alpha = alpha or 255

            local shouldInclude = true

            -- Alpha filter
            if alpha < self.alphaThreshold then
                shouldInclude = false
            end

            -- White background filter (> 245 in all channels)
            if shouldInclude and self.skipWhite then
                if color.R > 0.96 and color.G > 0.96 and color.B > 0.96 then
                    shouldInclude = false
                end
            end

            -- Black background filter (< 15 in all channels)
            if shouldInclude and self.skipBlack then
                if color.R < 0.06 and color.G < 0.06 and color.B < 0.06 then
                    shouldInclude = false
                end
            end

            if shouldInclude then
                table.insert(points, {
                    x = targetX,
                    y = targetY,
                    color = color,
                    alpha = alpha,
                })
            end
        end
    end

    -- Sorting according to draw mode
    if self.drawMode == "Palette" then
        -- Sort points by hue/luminance to cluster colors
        table.sort(points, function(a, b)
            local ha, sa, va = a.color:ToHSV()
            local hb, sb, vb = b.color:ToHSV()
            if math.abs(ha - hb) > 0.05 then
                return ha < hb
            end
            return va < vb
        end)
    elseif self.drawMode == "Spiral" then
        -- Sort points from center outwards
        local midX = finalW / 2
        local midY = finalH / 2
        table.sort(points, function(a, b)
            local distA = (a.x - midX)^2 + (a.y - midY)^2
            local distB = (b.x - midX)^2 + (b.y - midY)^2
            return distA < distB
        end)
    end
    -- "Raster" mode is naturally ordered (by y then x)

    return {
        points = points,
        width = finalW,
        height = finalH,
    }
end

-- Executes the drawing process
function DrawEngine:Draw(
    image: any,
    targetCFrame: CFrame,
    onProgress: (current: number, total: number, pct: number) -> (),
    onComplete: () -> (),
    onError: (msg: string) -> ()
)
    if self._isRunning then
        onError("Drawing is already in progress!")
        return
    end

    local tool = Security.findSprayPaintTool()
    if not tool then
        onError("Spray Paint tool not found! Equip it from your backpack.")
        return
    end

    local remote, remoteMethod = Security.findPaintRemote(tool)
    if not remote or not remoteMethod then
        onError("Paint Remote not found on tool! Make sure you are in Spray Paint.")
        return
    end

    self._isRunning = true
    self._isPaused = false
    self._isCancelled = false

    local processed = self:ProcessImage(image)
    local points = processed.points
    local totalPoints = #points
    local finalW = processed.width
    local finalH = processed.height

    if totalPoints == 0 then
        self._isRunning = false
        onError("No drawable pixels found (all filtered out by alpha or color filters)!")
        return
    end

    self._thread = task.spawn(function()
        local currentIdx = 0
        local batch: {PaintStroke} = {}

        local stepSize = self.pixelScale * self.spacingMult
        local halfW = (finalW * stepSize) / 2
        local halfH = (finalH * stepSize) / 2

        for i, pt in ipairs(points) do
            if self._isCancelled then break end

            while self._isPaused and not self._isCancelled do
                task.wait(0.2)
            end
            if self._isCancelled then break end

            -- Calculate 3D position on the wall
            -- Z-offset (0.0001) avoids Z-fighting between overlapping splats
            local localX = halfW - (pt.x * stepSize)
            local localY = halfH - (pt.y * stepSize)
            local localZ = (pt.y * 0.0001) + (pt.x * 0.0001)

            local strokeCF = targetCFrame * CFrame.new(localX, localY, localZ) * CFrame.Angles(math.rad(-90), 0, 0)

            table.insert(batch, {
                scale = self.pixelScale,
                cframe = strokeCF,
                color = pt.color,
                layer = 20,
            })

            -- Dispatch when batch size reached or at last point
            if #batch >= self.batchSize or i == totalPoints then
                local num, hash = Security.getSecurityArgs()

                local success, err = pcall(function()
                    if remoteMethod == "InvokeServer" then
                        -- Try standard signature with security tokens
                        pcall(function()
                            (remote :: any):InvokeServer(num, hash, batch)
                        end)
                        -- Fallback call format if first form was ignored
                        pcall(function()
                            (remote :: any):InvokeServer({num, hash}, batch)
                        end)
                    else
                        pcall(function()
                            (remote :: any):FireServer(num, hash, batch)
                        end)
                    end
                end)

                currentIdx = i
                local pct = math.floor((currentIdx / totalPoints) * 100)
                if onProgress then
                    onProgress(currentIdx, totalPoints, pct)
                end

                table.clear(batch)
                task.wait(self.batchDelay)
            end
        end

        self._isRunning = false
        if not self._isCancelled and onComplete then
            onComplete()
        end
    end)
end

return DrawEngine

end)()

-- =======================================================================
-- 3. MOBILE 3D TARGETING & PREVIEW GHOST SYSTEM
-- =======================================================================
local PreviewSystem = {
    GhostPart = nil :: BasePart?,
    SelectionBox = nil :: SelectionBox?,
    CurrentCFrame = nil :: CFrame?,
    TargetNormal = Vector3.new(0, 0, 1),
    
    -- Tuning offsets
    RotationDeg = 0,
    OffsetX = 0,
    OffsetY = 0,
    ScaleMultiplier = 1.0,
    BaseWidth = 64,
    BaseHeight = 64,
    PixelScale = 0.25,
    SpacingMult = 0.45,
}

function PreviewSystem.CreateGhost()
    if PreviewSystem.GhostPart then
        PreviewSystem.GhostPart:Destroy()
    end

    local ghost = Instance.new("Part")
    ghost.Name = "SprayPaint_PreviewGhost"
    ghost.Anchored = true
    ghost.CanCollide = false
    ghost.CanTouch = false
    ghost.CanQuery = false
    ghost.Material = Enum.Material.Neon
    ghost.Color = Color3.fromRGB(0, 200, 255)
    ghost.Transparency = 0.8
    ghost.Size = Vector3.new(4, 4, 0.05)
    ghost.Parent = Workspace

    local sBox = Instance.new("SelectionBox")
    sBox.Name = "GhostOutline"
    sBox.Adornee = ghost
    sBox.Color3 = Color3.fromRGB(0, 255, 200)
    sBox.LineThickness = 0.03
    sBox.Parent = ghost

    PreviewSystem.GhostPart = ghost
    PreviewSystem.SelectionBox = sBox
end

function PreviewSystem.UpdateTransform()
    if not PreviewSystem.GhostPart or not PreviewSystem.CurrentCFrame then return end

    local step = PreviewSystem.PixelScale * PreviewSystem.SpacingMult * PreviewSystem.ScaleMultiplier
    local totalW = math.max(PreviewSystem.BaseWidth * step, 0.5)
    local totalH = math.max(PreviewSystem.BaseHeight * step, 0.5)

    PreviewSystem.GhostPart.Size = Vector3.new(totalW, totalH, 0.05)

    local rotCF = CFrame.Angles(0, 0, math.rad(PreviewSystem.RotationDeg))
    local offsetCF = CFrame.new(PreviewSystem.OffsetX, PreviewSystem.OffsetY, -0.05)

    PreviewSystem.GhostPart.CFrame = PreviewSystem.CurrentCFrame * rotCF * offsetCF
end

function PreviewSystem.AimFromCamera(): (boolean, string)
    local cam = Workspace.CurrentCamera
    if not cam then return false, "Camera not found" end

    local origin = cam.CFrame.Position
    local direction = cam.CFrame.LookVector * 200

    local rayParams = RaycastParams.new()
    local char = LocalPlayer.Character
    local filterList = { char }
    if PreviewSystem.GhostPart then
        table.insert(filterList, PreviewSystem.GhostPart)
    end
    rayParams.FilterDescendantsInstances = filterList
    rayParams.FilterType = Enum.RaycastFilterType.Exclude

    local hit = Workspace:Raycast(origin, direction, rayParams)
    if not hit then
        return false, "No wall or surface detected in front of camera."
    end

    local hitPos = hit.Position
    local hitNormal = hit.Normal

    PreviewSystem.TargetNormal = hitNormal
    PreviewSystem.CurrentCFrame = CFrame.lookAt(hitPos, hitPos - hitNormal)

    if not PreviewSystem.GhostPart then
        PreviewSystem.CreateGhost()
    end
    PreviewSystem.UpdateTransform()

    return true, "Target locked on " .. hit.Instance.Name
end

function PreviewSystem.GetDrawCFrame(): CFrame?
    if not PreviewSystem.CurrentCFrame then return nil end
    local rotCF = CFrame.Angles(0, 0, math.rad(PreviewSystem.RotationDeg))
    local offsetCF = CFrame.new(PreviewSystem.OffsetX, PreviewSystem.OffsetY, 0)
    return PreviewSystem.CurrentCFrame * rotCF * offsetCF
end

function PreviewSystem.Destroy()
    if PreviewSystem.GhostPart then
        PreviewSystem.GhostPart:Destroy()
        PreviewSystem.GhostPart = nil
        PreviewSystem.SelectionBox = nil
    end
end

-- =======================================================================
-- 4. IMAGE PARSER WRAPPER
-- =======================================================================
local CurrentLoadedImage = nil
local CurrentImageDetails = {
    Name = "None",
    Width = 0,
    Height = 0,
    Format = "None",
}

local function parseImageBuffer(rawBuffer: string, name: string): (boolean, string)
    if #rawBuffer < 8 then
        return false, "Invalid or empty image data."
    end

    local magic = rawBuffer:sub(1, 4)
    local isPNG = (magic == "\137PNG")
    local isBMP = (rawBuffer:sub(1, 2) == "BM")

    local parsedImg = nil

    if isPNG then
        local success, img = pcall(function()
            return PNG.new(rawBuffer)
        end)
        if not success or not img then
            return false, "Failed to decode PNG: " .. tostring(img)
        end
        parsedImg = img
        CurrentImageDetails.Format = "PNG"
    elseif isBMP then
        local success, img = pcall(function()
            return BMP.new(rawBuffer)
        end)
        if not success or not img then
            return false, "Failed to decode BMP: " .. tostring(img)
        end
        parsedImg = img
        CurrentImageDetails.Format = "BMP"
    else
        return false, "Unsupported format. Only PNG and uncompressed BMP are supported."
    end

    CurrentLoadedImage = parsedImg
    CurrentImageDetails.Name = name
    CurrentImageDetails.Width = parsedImg.Width
    CurrentImageDetails.Height = parsedImg.Height

    PreviewSystem.BaseWidth = parsedImg.Width
    PreviewSystem.BaseHeight = parsedImg.Height
    PreviewSystem.UpdateTransform()

    return true, string.format("Loaded: %s (%dx%d %s)", name, parsedImg.Width, parsedImg.Height, CurrentImageDetails.Format)
end

local function loadImageFromWorkspace(fileName: string): (boolean, string)
    if fileName == "No images found in folder" or fileName == "" then
        return false, "Please select or enter a valid filename."
    end

    local filePath = WORKSPACE_FOLDER .. "/" .. fileName
    local bufferData = safeReadFile(filePath)
    if not bufferData then
        bufferData = safeReadFile(fileName)
    end

    if not bufferData then
        return false, "Could not read file: " .. fileName
    end

    return parseImageBuffer(bufferData, fileName)
end

local function loadImageFromURL(url: string): (boolean, string)
    if not url:match("^https?://") then
        return false, "Invalid URL format. Must begin with http:// or https://"
    end

    local success, response = pcall(function()
        if typeof(request) == "function" then
            local res = request({ Url = url, Method = "GET" })
            return res.Body
        elseif typeof(http_request) == "function" then
            local res = http_request({ Url = url, Method = "GET" })
            return res.Body
        else
            return game:HttpGet(url)
        end
    end)

    if not success or not response then
        return false, "HTTP request failed: " .. tostring(response)
    end

    local name = url:match("([^/]+)$") or "web_image.png"
    return parseImageBuffer(response, name)
end

-- =======================================================================
-- 5. CUSTOM GRAPHICAL EMOJI SYSTEM (Visual badges & Vector icons)
-- =======================================================================
local CustomEmoji = {}

local EMOJI_ASSETS = {
    folder = "rbxassetid://6034306351",
    image = "rbxassetid://6034287594",
    globe = "rbxassetid://6034509993",
    refresh = "rbxassetid://6031097225",
    target = "rbxassetid://6031265976",
    play = "rbxassetid://6031075929",
    pause = "rbxassetid://6031075930",
    stop = "rbxassetid://6031094678",
    settings = "rbxassetid://6031280882",
    palette = "rbxassetid://6031075931",
    eye = "rbxassetid://6031075932",
    check = "rbxassetid://6031094677",
    alert = "rbxassetid://6031086161",
    sparkle = "rbxassetid://6031075931",
}

local EMOJI_THEMES = {
    cyan = { bg = Color3.fromRGB(0, 160, 220), fg = Color3.fromRGB(255, 255, 255) },
    green = { bg = Color3.fromRGB(35, 185, 105), fg = Color3.fromRGB(255, 255, 255) },
    yellow = { bg = Color3.fromRGB(235, 175, 25), fg = Color3.fromRGB(255, 255, 255) },
    red = { bg = Color3.fromRGB(230, 60, 70), fg = Color3.fromRGB(255, 255, 255) },
    purple = { bg = Color3.fromRGB(155, 85, 235), fg = Color3.fromRGB(255, 255, 255) },
    neutral = { bg = Color3.fromRGB(42, 48, 64), fg = Color3.fromRGB(210, 220, 240) },
}

function CustomEmoji.Create(iconName: string, options: { Size: number?, Color: string?, Transparent: boolean? }?): Frame
    options = options or {}
    local size = options.Size or 22
    local colorTheme = options.Color or "cyan"
    local theme = EMOJI_THEMES[colorTheme] or EMOJI_THEMES.cyan

    local badge = Instance.new("Frame")
    badge.Name = "CustomEmoji_" .. iconName
    badge.Size = UDim2.new(0, size, 0, size)
    badge.BackgroundColor3 = theme.bg
    badge.BackgroundTransparency = options.Transparent and 1 or 0.18
    badge.BorderSizePixel = 0

    local badgeCorner = Instance.new("UICorner")
    badgeCorner.CornerRadius = UDim.new(0, math.floor(size * 0.32))
    badgeCorner.Parent = badge

    local stroke = Instance.new("UIStroke")
    stroke.Color = theme.bg
    stroke.Transparency = 0.5
    stroke.Thickness = 1
    stroke.Parent = badge

    local icon = Instance.new("ImageLabel")
    icon.Name = "Graphic"
    local pad = math.floor(size * 0.18)
    icon.Size = UDim2.new(1, -pad * 2, 1, -pad * 2)
    icon.Position = UDim2.new(0, pad, 0, pad)
    icon.BackgroundTransparency = 1
    icon.Image = EMOJI_ASSETS[iconName] or EMOJI_ASSETS.palette
    icon.ImageColor3 = theme.fg
    icon.Parent = badge

    -- Procedural geometric fallback details inside badge
    if iconName == "play" then
        local tri = Instance.new("Frame")
        tri.Size = UDim2.new(0, 0, 0, 0)
        tri.Position = UDim2.new(0.5, 0, 0.5, 0)
        tri.BackgroundTransparency = 1
        tri.Parent = badge
    elseif iconName == "stop" then
        local sq = Instance.new("Frame")
        sq.Size = UDim2.new(0.4, 0, 0.4, 0)
        sq.Position = UDim2.new(0.3, 0, 0.3, 0)
        sq.BackgroundColor3 = theme.fg
        sq.BorderSizePixel = 0
        sq.Parent = badge
        local sqc = Instance.new("UICorner")
        sqc.CornerRadius = UDim.new(0, 2)
        sqc.Parent = sq
    elseif iconName == "pause" then
        local b1 = Instance.new("Frame")
        b1.Size = UDim2.new(0.14, 0, 0.44, 0)
        b1.Position = UDim2.new(0.3, 0, 0.28, 0)
        b1.BackgroundColor3 = theme.fg
        b1.BorderSizePixel = 0
        b1.Parent = badge
        local b1c = Instance.new("UICorner")
        b1c.CornerRadius = UDim.new(0, 1)
        b1c.Parent = b1

        local b2 = Instance.new("Frame")
        b2.Size = UDim2.new(0.14, 0, 0.44, 0)
        b2.Position = UDim2.new(0.56, 0, 0.28, 0)
        b2.BackgroundColor3 = theme.fg
        b2.BorderSizePixel = 0
        b2.Parent = badge
        local b2c = Instance.new("UICorner")
        b2c.CornerRadius = UDim.new(0, 1)
        b2c.Parent = b2
    end

    return badge
end

-- =======================================================================
-- 6. CUSTOM STANDALONE MOBILE GUI ENGINE
-- =======================================================================
local CustomUI = {}
CustomUI.__index = CustomUI

function CustomUI.Init()
    local existing = CoreGui:FindFirstChild("SprayPaint_CustomGUI") or LocalPlayer:WaitForChild("PlayerGui"):FindFirstChild("SprayPaint_CustomGUI")
    if existing then
        existing:Destroy()
    end

    local guiParent = pcall(function() return CoreGui end) and CoreGui or LocalPlayer:WaitForChild("PlayerGui")
    local screenGui = Instance.new("ScreenGui")
    screenGui.Name = "SprayPaint_CustomGUI"
    screenGui.ResetOnSpawn = false
    screenGui.ZIndexBehavior = Enum.ZIndexBehavior.Sibling
    screenGui.DisplayOrder = 999
    screenGui.Parent = guiParent

    -- Palette
    local C_BG = Color3.fromRGB(18, 20, 26)
    local C_PANEL = Color3.fromRGB(24, 27, 36)
    local C_CARD = Color3.fromRGB(30, 34, 46)
    local C_BORDER = Color3.fromRGB(48, 54, 72)
    local C_ACCENT = Color3.fromRGB(0, 190, 240)
    local C_TEXT = Color3.fromRGB(235, 238, 245)
    local C_SUBTEXT = Color3.fromRGB(140, 148, 168)
    local C_SUCCESS = Color3.fromRGB(40, 200, 120)
    local C_DANGER = Color3.fromRGB(240, 70, 70)

    -- Mobile Floating Bubble Button
    local bubble = Instance.new("Frame")
    bubble.Name = "FloatingBubble"
    bubble.Size = UDim2.new(0, 52, 0, 52)
    bubble.Position = UDim2.new(0.03, 0, 0.22, 0)
    bubble.BackgroundColor3 = C_PANEL
    bubble.BorderSizePixel = 0
    bubble.Active = true
    bubble.Parent = screenGui

    local bubbleCorner = Instance.new("UICorner")
    bubbleCorner.CornerRadius = UDim.new(0, 26)
    bubbleCorner.Parent = bubble

    local bubbleStroke = Instance.new("UIStroke")
    bubbleStroke.Color = C_ACCENT
    bubbleStroke.Thickness = 1.8
    bubbleStroke.Parent = bubble

    -- Place Custom Emoji inside Bubble
    local bubbleEmoji = CustomEmoji.Create("palette", { Size = 28, Color = "cyan" })
    bubbleEmoji.Position = UDim2.new(0.5, -14, 0.5, -14)
    bubbleEmoji.Parent = bubble

    -- Main Window
    local window = Instance.new("Frame")
    window.Name = "MainWindow"
    window.Size = UDim2.new(0, 480, 0, 340)
    window.Position = UDim2.new(0.5, -240, 0.5, -170)
    window.BackgroundColor3 = C_BG
    window.BorderSizePixel = 0
    window.Active = true
    window.ClipsDescendants = false
    window.Visible = true
    window.Parent = screenGui

    local windowCorner = Instance.new("UICorner")
    windowCorner.CornerRadius = UDim.new(0, 10)
    windowCorner.Parent = window

    local windowStroke = Instance.new("UIStroke")
    windowStroke.Color = C_BORDER
    windowStroke.Thickness = 1
    windowStroke.Parent = window

    -- Header Bar
    local header = Instance.new("Frame")
    header.Name = "HeaderBar"
    header.Size = UDim2.new(1, 0, 0, 44)
    header.BackgroundColor3 = C_PANEL
    header.BorderSizePixel = 0
    header.Parent = window

    local headerCorner = Instance.new("UICorner")
    headerCorner.CornerRadius = UDim.new(0, 10)
    headerCorner.Parent = header

    local headerBottomPatch = Instance.new("Frame")
    headerBottomPatch.Size = UDim2.new(1, 0, 0, 8)
    headerBottomPatch.Position = UDim2.new(0, 0, 1, -8)
    headerBottomPatch.BackgroundColor3 = C_PANEL
    headerBottomPatch.BorderSizePixel = 0
    headerBottomPatch.Parent = header

    -- Header Custom Emoji Badge
    local headerEmoji = CustomEmoji.Create("palette", { Size = 24, Color = "cyan" })
    headerEmoji.Position = UDim2.new(0, 12, 0, 10)
    headerEmoji.Parent = header

    local titleText = Instance.new("TextLabel")
    titleText.Size = UDim2.new(0, 240, 0, 24)
    titleText.Position = UDim2.new(0, 44, 0, 10)
    titleText.BackgroundTransparency = 1
    titleText.Font = Enum.Font.GothamBold
    titleText.Text = "Spray Paint AutoDraw"
    titleText.TextColor3 = C_TEXT
    titleText.TextSize = 13
    titleText.TextXAlignment = Enum.TextXAlignment.Left
    titleText.Parent = header

    local closeBtn = Instance.new("TextButton")
    closeBtn.Size = UDim2.new(0, 30, 0, 26)
    closeBtn.Position = UDim2.new(1, -38, 0, 9)
    closeBtn.BackgroundColor3 = C_CARD
    closeBtn.Font = Enum.Font.GothamBold
    closeBtn.Text = "X"
    closeBtn.TextColor3 = C_SUBTEXT
    closeBtn.TextSize = 12
    closeBtn.Parent = header

    local closeBtnCorner = Instance.new("UICorner")
    closeBtnCorner.CornerRadius = UDim.new(0, 6)
    closeBtnCorner.Parent = closeBtn

    closeBtn.MouseButton1Click:Connect(function()
        window.Visible = false
    end)

    -- Draggable Floating Bubble
    do
        local dragging = false
        local dragStart = Vector2.zero
        local startPos = UDim2.new()

        bubble.InputBegan:Connect(function(input)
            if input.UserInputType == Enum.UserInputType.Touch or input.UserInputType == Enum.UserInputType.MouseButton1 then
                dragging = true
                dragStart = Vector2.new(input.Position.X, input.Position.Y)
                startPos = bubble.Position
            end
        end)

        UserInputService.InputChanged:Connect(function(input)
            if dragging and (input.UserInputType == Enum.UserInputType.Touch or input.UserInputType == Enum.UserInputType.MouseMovement) then
                local delta = Vector2.new(input.Position.X, input.Position.Y) - dragStart
                bubble.Position = UDim2.new(
                    startPos.X.Scale,
                    startPos.X.Offset + delta.X,
                    startPos.Y.Scale,
                    startPos.Y.Offset + delta.Y
                )
            end
        end)

        UserInputService.InputEnded:Connect(function(input)
            if input.UserInputType == Enum.UserInputType.Touch or input.UserInputType == Enum.UserInputType.MouseButton1 then
                if dragging then
                    dragging = false
                    local dist = (Vector2.new(input.Position.X, input.Position.Y) - dragStart).Magnitude
                    if dist < 8 then
                        window.Visible = not window.Visible
                    end
                end
            end
        end)
    end

    -- Draggable Window Header
    do
        local dragging = false
        local dragStart = Vector2.zero
        local startPos = UDim2.new()

        header.InputBegan:Connect(function(input)
            if input.UserInputType == Enum.UserInputType.Touch or input.UserInputType == Enum.UserInputType.MouseButton1 then
                dragging = true
                dragStart = Vector2.new(input.Position.X, input.Position.Y)
                startPos = window.Position
            end
        end)

        UserInputService.InputChanged:Connect(function(input)
            if dragging and (input.UserInputType == Enum.UserInputType.Touch or input.UserInputType == Enum.UserInputType.MouseMovement) then
                local delta = Vector2.new(input.Position.X, input.Position.Y) - dragStart
                window.Position = UDim2.new(
                    startPos.X.Scale,
                    startPos.X.Offset + delta.X,
                    startPos.Y.Scale,
                    startPos.Y.Offset + delta.Y
                )
            end
        end)

        UserInputService.InputEnded:Connect(function(input)
            if input.UserInputType == Enum.UserInputType.Touch or input.UserInputType == Enum.UserInputType.MouseButton1 then
                dragging = false
            end
        end)
    end

    -- Tab Navigation Strip
    local tabNav = Instance.new("Frame")
    tabNav.Name = "TabNav"
    tabNav.Size = UDim2.new(1, -20, 0, 36)
    tabNav.Position = UDim2.new(0, 10, 0, 52)
    tabNav.BackgroundColor3 = C_PANEL
    tabNav.BorderSizePixel = 0
    tabNav.Parent = window

    local tabNavCorner = Instance.new("UICorner")
    tabNavCorner.CornerRadius = UDim.new(0, 8)
    tabNavCorner.Parent = tabNav

    local tabListLayout = Instance.new("UIListLayout")
    tabListLayout.FillDirection = Enum.FillDirection.Horizontal
    tabListLayout.HorizontalAlignment = Enum.HorizontalAlignment.Center
    tabListLayout.VerticalAlignment = Enum.VerticalAlignment.Center
    tabListLayout.SortOrder = Enum.SortOrder.LayoutOrder
    tabListLayout.Padding = UDim.new(0, 6)
    tabListLayout.Parent = tabNav

    -- Container for Tab Pages
    local pagesContainer = Instance.new("Frame")
    pagesContainer.Name = "PagesContainer"
    pagesContainer.Size = UDim2.new(1, -20, 1, -98)
    pagesContainer.Position = UDim2.new(0, 10, 0, 92)
    pagesContainer.BackgroundTransparency = 1
    pagesContainer.Parent = window

    -- Toast Notifications Container
    local toastBox = Instance.new("Frame")
    toastBox.Name = "ToastBox"
    toastBox.Size = UDim2.new(0, 330, 0, 56)
    toastBox.Position = UDim2.new(0.5, -165, 0.04, 0)
    toastBox.BackgroundTransparency = 1
    toastBox.Visible = false
    toastBox.ZIndex = 25
    toastBox.Parent = screenGui

    local toastFrame = Instance.new("Frame")
    toastFrame.Size = UDim2.new(1, 0, 1, 0)
    toastFrame.BackgroundColor3 = C_CARD
    toastFrame.BorderSizePixel = 0
    toastFrame.Parent = toastBox

    local toastCorner = Instance.new("UICorner")
    toastCorner.CornerRadius = UDim.new(0, 8)
    toastCorner.Parent = toastFrame

    local toastStroke = Instance.new("UIStroke")
    toastStroke.Color = C_ACCENT
    toastStroke.Thickness = 1.2
    toastStroke.Parent = toastFrame

    local toastEmojiHolder = Instance.new("Frame")
    toastEmojiHolder.Name = "EmojiHolder"
    toastEmojiHolder.Size = UDim2.new(0, 24, 0, 24)
    toastEmojiHolder.Position = UDim2.new(0, 10, 0.5, -12)
    toastEmojiHolder.BackgroundTransparency = 1
    toastEmojiHolder.Parent = toastFrame

    local toastTitle = Instance.new("TextLabel")
    toastTitle.Size = UDim2.new(1, -48, 0, 18)
    toastTitle.Position = UDim2.new(0, 42, 0, 8)
    toastTitle.BackgroundTransparency = 1
    toastTitle.Font = Enum.Font.GothamBold
    toastTitle.Text = "Notification"
    toastTitle.TextColor3 = C_ACCENT
    toastTitle.TextSize = 12
    toastTitle.TextXAlignment = Enum.TextXAlignment.Left
    toastTitle.Parent = toastFrame

    local toastDesc = Instance.new("TextLabel")
    toastDesc.Size = UDim2.new(1, -48, 0, 20)
    toastDesc.Position = UDim2.new(0, 42, 0, 26)
    toastDesc.BackgroundTransparency = 1
    toastDesc.Font = Enum.Font.Gotham
    toastDesc.Text = "Description"
    toastDesc.TextColor3 = C_TEXT
    toastDesc.TextSize = 11
    toastDesc.TextWrapped = true
    toastDesc.TextXAlignment = Enum.TextXAlignment.Left
    toastDesc.Parent = toastFrame

    local activeToastId = 0
    local function showToast(title: string, desc: string, iconName: string?, colorTheme: string?, duration: number?)
        activeToastId = activeToastId + 1
        local thisId = activeToastId
        toastTitle.Text = title
        toastDesc.Text = desc

        for _, ch in ipairs(toastEmojiHolder:GetChildren()) do
            ch:Destroy()
        end
        local em = CustomEmoji.Create(iconName or "check", { Size = 24, Color = colorTheme or "cyan" })
        em.Parent = toastEmojiHolder

        toastBox.Visible = true

        task.delay(duration or 4, function()
            if activeToastId == thisId then
                toastBox.Visible = false
            end
        end)
    end

    -- Tab System State
    local tabs = {}
    local tabButtons = {}
    local activeTab = nil

    local function selectTab(tabName: string)
        for name, page in pairs(tabs) do
            if name == tabName then
                page.Visible = true
                tabButtons[name].BackgroundColor3 = C_CARD
            else
                page.Visible = false
                tabButtons[name].BackgroundColor3 = C_PANEL
            end
        end
        activeTab = tabName
    end

    local UIController = {
        Screen = screenGui,
        Window = window,
        Notify = showToast,
        Palette = {
            BG = C_BG,
            Panel = C_PANEL,
            Card = C_CARD,
            Border = C_BORDER,
            Accent = C_ACCENT,
            Text = C_TEXT,
            SubText = C_SUBTEXT,
            Success = C_SUCCESS,
            Danger = C_DANGER,
        }
    }

    function UIController:CreateTab(name: string, label: string, emojiName: string, emojiColor: string)
        local btn = Instance.new("Frame")
        btn.Name = "TabBtn_" .. name
        btn.Size = UDim2.new(0.24, -4, 1, -4)
        btn.BackgroundColor3 = C_PANEL
        btn.BorderSizePixel = 0
        btn.Parent = tabNav

        local btnCorner = Instance.new("UICorner")
        btnCorner.CornerRadius = UDim.new(0, 6)
        btnCorner.Parent = btn

        local btnLayout = Instance.new("UIListLayout")
        btnLayout.FillDirection = Enum.FillDirection.Horizontal
        btnLayout.HorizontalAlignment = Enum.HorizontalAlignment.Center
        btnLayout.VerticalAlignment = Enum.VerticalAlignment.Center
        btnLayout.SortOrder = Enum.SortOrder.LayoutOrder
        btnLayout.Padding = UDim.new(0, 6)
        btnLayout.Parent = btn

        local tabEmoji = CustomEmoji.Create(emojiName, { Size = 16, Color = emojiColor })
        tabEmoji.Parent = btn

        local tabText = Instance.new("TextLabel")
        tabText.Size = UDim2.new(0, 56, 1, 0)
        tabText.BackgroundTransparency = 1
        tabText.Font = Enum.Font.GothamBold
        tabText.Text = label
        tabText.TextColor3 = C_TEXT
        tabText.TextSize = 11
        tabText.TextXAlignment = Enum.TextXAlignment.Left
        tabText.Parent = btn

        local clickDetector = Instance.new("TextButton")
        clickDetector.Size = UDim2.new(1, 0, 1, 0)
        clickDetector.BackgroundTransparency = 1
        clickDetector.Text = ""
        clickDetector.Parent = btn

        tabButtons[name] = btn

        local page = Instance.new("ScrollingFrame")
        page.Name = "TabPage_" .. name
        page.Size = UDim2.new(1, 0, 1, 0)
        page.BackgroundTransparency = 1
        page.BorderSizePixel = 0
        page.ScrollBarThickness = 4
        page.ScrollBarImageColor3 = C_BORDER
        page.CanvasSize = UDim2.new(0, 0, 0, 0)
        page.AutomaticCanvasSize = Enum.AutomaticSize.Y
        page.Visible = false
        page.Parent = pagesContainer

        local pageLayout = Instance.new("UIListLayout")
        pageLayout.SortOrder = Enum.SortOrder.LayoutOrder
        pageLayout.Padding = UDim.new(0, 6)
        pageLayout.Parent = page

        tabs[name] = page

        clickDetector.MouseButton1Click:Connect(function()
            selectTab(name)
        end)

        if not activeTab then
            selectTab(name)
        end

        local TabMethods = {}

        function TabMethods:AddButton(cfg: { title: string, emoji: string, color: string?, callback: () -> () })
            local card = Instance.new("Frame")
            card.Size = UDim2.new(1, -6, 0, 38)
            card.BackgroundColor3 = C_PANEL
            card.BorderSizePixel = 0
            card.Parent = page

            local cardCorner = Instance.new("UICorner")
            cardCorner.CornerRadius = UDim.new(0, 6)
            cardCorner.Parent = card

            -- Custom Emoji Component inside button
            local btnEmoji = CustomEmoji.Create(cfg.emoji, { Size = 22, Color = cfg.color or "cyan" })
            btnEmoji.Position = UDim2.new(0, 8, 0.5, -11)
            btnEmoji.Parent = card

            local bText = Instance.new("TextLabel")
            bText.Size = UDim2.new(1, -44, 1, 0)
            bText.Position = UDim2.new(0, 38, 0, 0)
            bText.BackgroundTransparency = 1
            bText.Font = Enum.Font.GothamBold
            bText.Text = cfg.title
            bText.TextColor3 = C_TEXT
            bText.TextSize = 12
            bText.TextXAlignment = Enum.TextXAlignment.Left
            bText.Parent = card

            local clickArea = Instance.new("TextButton")
            clickArea.Size = UDim2.new(1, 0, 1, 0)
            clickArea.BackgroundTransparency = 1
            clickArea.Text = ""
            clickArea.Parent = card

            clickArea.MouseButton1Click:Connect(function()
                if cfg.callback then
                    cfg.callback()
                end
            end)
            return card
        end

        function TabMethods:AddInput(cfg: { title: string, placeholder: string?, emoji: string?, callback: (string) -> () })
            local card = Instance.new("Frame")
            card.Size = UDim2.new(1, -6, 0, 48)
            card.BackgroundColor3 = C_PANEL
            card.BorderSizePixel = 0
            card.Parent = page

            local cardCorner = Instance.new("UICorner")
            cardCorner.CornerRadius = UDim.new(0, 6)
            cardCorner.Parent = card

            if cfg.emoji then
                local em = CustomEmoji.Create(cfg.emoji, { Size = 14, Color = "neutral", Transparent = true })
                em.Position = UDim2.new(0, 6, 0, 4)
                em.Parent = card
            end

            local label = Instance.new("TextLabel")
            label.Size = UDim2.new(1, -28, 0, 16)
            label.Position = UDim2.new(0, cfg.emoji and 24 or 8, 0, 4)
            label.BackgroundTransparency = 1
            label.Font = Enum.Font.GothamBold
            label.Text = cfg.title
            label.TextColor3 = C_SUBTEXT
            label.TextSize = 10
            label.TextXAlignment = Enum.TextXAlignment.Left
            label.Parent = card

            local box = Instance.new("TextBox")
            box.Size = UDim2.new(1, -16, 0, 22)
            box.Position = UDim2.new(0, 8, 0, 22)
            box.BackgroundColor3 = C_CARD
            box.Font = Enum.Font.Gotham
            box.PlaceholderText = cfg.placeholder or "Enter text here..."
            box.PlaceholderColor3 = C_SUBTEXT
            box.Text = ""
            box.TextColor3 = C_TEXT
            box.TextSize = 11
            box.ClearTextOnFocus = false
            box.Parent = card

            local boxCorner = Instance.new("UICorner")
            boxCorner.CornerRadius = UDim.new(0, 4)
            boxCorner.Parent = box

            box.FocusLost:Connect(function()
                if cfg.callback then
                    cfg.callback(box.Text)
                end
            end)
            return card
        end

        function TabMethods:AddSlider(cfg: { title: string, min: number, max: number, default: number, step: number?, callback: (number) -> () })
            local card = Instance.new("Frame")
            card.Size = UDim2.new(1, -6, 0, 46)
            card.BackgroundColor3 = C_PANEL
            card.BorderSizePixel = 0
            card.Parent = page

            local cardCorner = Instance.new("UICorner")
            cardCorner.CornerRadius = UDim.new(0, 6)
            cardCorner.Parent = card

            local label = Instance.new("TextLabel")
            label.Size = UDim2.new(0.7, 0, 0, 18)
            label.Position = UDim2.new(0, 8, 0, 4)
            label.BackgroundTransparency = 1
            label.Font = Enum.Font.GothamBold
            label.Text = cfg.title
            label.TextColor3 = C_TEXT
            label.TextSize = 11
            label.TextXAlignment = Enum.TextXAlignment.Left
            label.Parent = card

            local valLabel = Instance.new("TextLabel")
            valLabel.Size = UDim2.new(0.28, 0, 0, 18)
            valLabel.Position = UDim2.new(0.7, -4, 0, 4)
            valLabel.BackgroundTransparency = 1
            valLabel.Font = Enum.Font.GothamBold
            valLabel.Text = tostring(cfg.default)
            valLabel.TextColor3 = C_ACCENT
            valLabel.TextSize = 11
            valLabel.TextXAlignment = Enum.TextXAlignment.Right
            valLabel.Parent = card

            local track = Instance.new("Frame")
            track.Size = UDim2.new(1, -16, 0, 10)
            track.Position = UDim2.new(0, 8, 0, 26)
            track.BackgroundColor3 = C_CARD
            track.BorderSizePixel = 0
            track.Active = true
            track.Parent = card

            local trackCorner = Instance.new("UICorner")
            trackCorner.CornerRadius = UDim.new(0, 5)
            trackCorner.Parent = track

            local fill = Instance.new("Frame")
            local initPct = math.clamp((cfg.default - cfg.min) / (cfg.max - cfg.min), 0, 1)
            fill.Size = UDim2.new(initPct, 0, 1, 0)
            fill.BackgroundColor3 = C_ACCENT
            fill.BorderSizePixel = 0
            fill.Parent = track

            local fillCorner = Instance.new("UICorner")
            fillCorner.CornerRadius = UDim.new(0, 5)
            fillCorner.Parent = fill

            local isDragging = false
            local function update(inputX)
                local relX = math.clamp((inputX - track.AbsolutePosition.X) / track.AbsoluteSize.X, 0, 1)
                local rawVal = cfg.min + (cfg.max - cfg.min) * relX
                if cfg.step and cfg.step > 0 then
                    rawVal = math.floor((rawVal / cfg.step) + 0.5) * cfg.step
                end
                rawVal = math.clamp(rawVal, cfg.min, cfg.max)
                valLabel.Text = (cfg.step and cfg.step >= 1) and string.format("%d", rawVal) or string.format("%.2f", rawVal)
                fill.Size = UDim2.new(relX, 0, 1, 0)
                if cfg.callback then
                    cfg.callback(rawVal)
                end
            end

            track.InputBegan:Connect(function(inp)
                if inp.UserInputType == Enum.UserInputType.Touch or inp.UserInputType == Enum.UserInputType.MouseButton1 then
                    isDragging = true
                    update(inp.Position.X)
                end
            end)

            UserInputService.InputChanged:Connect(function(inp)
                if isDragging and (inp.UserInputType == Enum.UserInputType.Touch or inp.UserInputType == Enum.UserInputType.MouseMovement) then
                    update(inp.Position.X)
                end
            end)

            UserInputService.InputEnded:Connect(function(inp)
                if inp.UserInputType == Enum.UserInputType.Touch or inp.UserInputType == Enum.UserInputType.MouseButton1 then
                    isDragging = false
                end
            end)

            return card
        end

        function TabMethods:AddToggle(cfg: { title: string, default: boolean, callback: (boolean) -> () })
            local card = Instance.new("Frame")
            card.Size = UDim2.new(1, -6, 0, 36)
            card.BackgroundColor3 = C_PANEL
            card.BorderSizePixel = 0
            card.Parent = page

            local cardCorner = Instance.new("UICorner")
            cardCorner.CornerRadius = UDim.new(0, 6)
            cardCorner.Parent = card

            local label = Instance.new("TextLabel")
            label.Size = UDim2.new(1, -54, 1, 0)
            label.Position = UDim2.new(0, 8, 0, 0)
            label.BackgroundTransparency = 1
            label.Font = Enum.Font.Gotham
            label.Text = cfg.title
            label.TextColor3 = C_TEXT
            label.TextSize = 11
            label.TextXAlignment = Enum.TextXAlignment.Left
            label.Parent = card

            local switch = Instance.new("Frame")
            switch.Size = UDim2.new(0, 38, 0, 20)
            switch.Position = UDim2.new(1, -44, 0.5, -10)
            switch.BackgroundColor3 = cfg.default and C_ACCENT or C_CARD
            switch.BorderSizePixel = 0
            switch.Parent = card

            local switchCorner = Instance.new("UICorner")
            switchCorner.CornerRadius = UDim.new(0, 10)
            switchCorner.Parent = switch

            local dot = Instance.new("Frame")
            dot.Size = UDim2.new(0, 16, 0, 16)
            dot.Position = cfg.default and UDim2.new(1, -18, 0.5, -8) or UDim2.new(0, 2, 0.5, -8)
            dot.BackgroundColor3 = Color3.fromRGB(255, 255, 255)
            dot.BorderSizePixel = 0
            dot.Parent = switch

            local dotCorner = Instance.new("UICorner")
            dotCorner.CornerRadius = UDim.new(0, 8)
            dotCorner.Parent = dot

            local state = cfg.default
            local clickArea = Instance.new("TextButton")
            clickArea.Size = UDim2.new(1, 0, 1, 0)
            clickArea.BackgroundTransparency = 1
            clickArea.Text = ""
            clickArea.Parent = card

            clickArea.MouseButton1Click:Connect(function()
                state = not state
                switch.BackgroundColor3 = state and C_ACCENT or C_CARD
                dot.Position = state and UDim2.new(1, -18, 0.5, -8) or UDim2.new(0, 2, 0.5, -8)
                if cfg.callback then
                    cfg.callback(state)
                end
            end)

            return card
        end

        function TabMethods:AddDropdown(cfg: { title: string, items: {string}, default: string?, emoji: string?, callback: (string) -> () })
            local card = Instance.new("Frame")
            card.Size = UDim2.new(1, -6, 0, 50)
            card.BackgroundColor3 = C_PANEL
            card.BorderSizePixel = 0
            card.ClipsDescendants = false
            card.ZIndex = 5
            card.Parent = page

            local cardCorner = Instance.new("UICorner")
            cardCorner.CornerRadius = UDim.new(0, 6)
            cardCorner.Parent = card

            if cfg.emoji then
                local em = CustomEmoji.Create(cfg.emoji, { Size = 14, Color = "neutral", Transparent = true })
                em.Position = UDim2.new(0, 6, 0, 4)
                em.Parent = card
            end

            local label = Instance.new("TextLabel")
            label.Size = UDim2.new(1, -28, 0, 16)
            label.Position = UDim2.new(0, cfg.emoji and 24 or 8, 0, 4)
            label.BackgroundTransparency = 1
            label.Font = Enum.Font.GothamBold
            label.Text = cfg.title
            label.TextColor3 = C_SUBTEXT
            label.TextSize = 10
            label.TextXAlignment = Enum.TextXAlignment.Left
            label.Parent = card

            local currentVal = cfg.default or (cfg.items[1] or "None")
            local dropBtn = Instance.new("TextButton")
            dropBtn.Size = UDim2.new(1, -16, 0, 24)
            dropBtn.Position = UDim2.new(0, 8, 0, 22)
            dropBtn.BackgroundColor3 = C_CARD
            dropBtn.Font = Enum.Font.Gotham
            dropBtn.Text = "  " .. currentVal
            dropBtn.TextColor3 = C_TEXT
            dropBtn.TextSize = 11
            dropBtn.TextXAlignment = Enum.TextXAlignment.Left
            dropBtn.ZIndex = 5
            dropBtn.Parent = card

            local dropCorner = Instance.new("UICorner")
            dropCorner.CornerRadius = UDim.new(0, 4)
            dropCorner.Parent = dropBtn

            local dropList = Instance.new("ScrollingFrame")
            dropList.Size = UDim2.new(1, -16, 0, 100)
            dropList.Position = UDim2.new(0, 8, 0, 48)
            dropList.BackgroundColor3 = C_BG
            dropList.BorderSizePixel = 0
            dropList.ScrollBarThickness = 3
            dropList.Visible = false
            dropList.ZIndex = 15
            dropList.Parent = card

            local dropListCorner = Instance.new("UICorner")
            dropListCorner.CornerRadius = UDim.new(0, 4)
            dropListCorner.Parent = dropList

            local listStroke = Instance.new("UIStroke")
            listStroke.Color = C_BORDER
            listStroke.Thickness = 1
            listStroke.Parent = dropList

            local dropLayout = Instance.new("UIListLayout")
            dropLayout.SortOrder = Enum.SortOrder.LayoutOrder
            dropLayout.Parent = dropList

            local function populate(newItems: {string})
                for _, ch in ipairs(dropList:GetChildren()) do
                    if ch:IsA("TextButton") then
                        ch:Destroy()
                    end
                end
                dropList.CanvasSize = UDim2.new(0, 0, 0, #newItems * 24)
                for _, it in ipairs(newItems) do
                    local itBtn = Instance.new("TextButton")
                    itBtn.Size = UDim2.new(1, 0, 0, 24)
                    itBtn.BackgroundColor3 = C_CARD
                    itBtn.Font = Enum.Font.Gotham
                    itBtn.Text = "  " .. it
                    itBtn.TextColor3 = C_TEXT
                    itBtn.TextSize = 11
                    itBtn.TextXAlignment = Enum.TextXAlignment.Left
                    itBtn.ZIndex = 16
                    itBtn.Parent = dropList

                    itBtn.MouseButton1Click:Connect(function()
                        currentVal = it
                        dropBtn.Text = "  " .. it
                        dropList.Visible = false
                        card.ZIndex = 5
                        if cfg.callback then
                            cfg.callback(it)
                        end
                    end)
                end
            end

            populate(cfg.items)

            dropBtn.MouseButton1Click:Connect(function()
                dropList.Visible = not dropList.Visible
                card.ZIndex = dropList.Visible and 10 or 5
            end)

            return {
                Frame = card,
                SetValues = function(_, items: {string})
                    populate(items)
                end,
                SetValue = function(_, val: string)
                    currentVal = val
                    dropBtn.Text = "  " .. val
                end
            }
        end

        function TabMethods:AddStatusCard(title: string, desc: string, emojiName: string?, emojiColor: string?)
            local card = Instance.new("Frame")
            card.Size = UDim2.new(1, -6, 0, 48)
            card.BackgroundColor3 = C_PANEL
            card.BorderSizePixel = 0
            card.Parent = page

            local cardCorner = Instance.new("UICorner")
            cardCorner.CornerRadius = UDim.new(0, 6)
            cardCorner.Parent = card

            local cardEmojiHolder = Instance.new("Frame")
            cardEmojiHolder.Size = UDim2.new(0, 24, 0, 24)
            cardEmojiHolder.Position = UDim2.new(0, 8, 0.5, -12)
            cardEmojiHolder.BackgroundTransparency = 1
            cardEmojiHolder.Parent = card

            local activeEmoji = CustomEmoji.Create(emojiName or "palette", { Size = 24, Color = emojiColor or "cyan" })
            activeEmoji.Parent = cardEmojiHolder

            local tLabel = Instance.new("TextLabel")
            tLabel.Size = UDim2.new(1, -44, 0, 18)
            tLabel.Position = UDim2.new(0, 38, 0, 4)
            tLabel.BackgroundTransparency = 1
            tLabel.Font = Enum.Font.GothamBold
            tLabel.Text = title
            tLabel.TextColor3 = C_ACCENT
            tLabel.TextSize = 11
            tLabel.TextXAlignment = Enum.TextXAlignment.Left
            tLabel.Parent = card

            local dLabel = Instance.new("TextLabel")
            dLabel.Size = UDim2.new(1, -44, 0, 22)
            dLabel.Position = UDim2.new(0, 38, 0, 22)
            dLabel.BackgroundTransparency = 1
            dLabel.Font = Enum.Font.Gotham
            dLabel.Text = desc
            dLabel.TextColor3 = C_SUBTEXT
            dLabel.TextSize = 10
            dLabel.TextXAlignment = Enum.TextXAlignment.Left
            dLabel.Parent = card

            return {
                SetTitle = function(_, t: string)
                    tLabel.Text = t
                end,
                SetDesc = function(_, d: string)
                    dLabel.Text = d
                end,
                SetEmoji = function(_, icon: string, col: string)
                    for _, ch in ipairs(cardEmojiHolder:GetChildren()) do
                        ch:Destroy()
                    end
                    local newEm = CustomEmoji.Create(icon, { Size = 24, Color = col })
                    newEm.Parent = cardEmojiHolder
                end
            }
        end

        return TabMethods
    end

    return UIController
end

-- =======================================================================
-- 7. APPLICATION WIRING & LOGIC
-- =======================================================================
local Engine = DrawEngine.new()
local UI = CustomUI.Init()

local notify = function(title: string, desc: string, icon: string?, col: string?)
    UI.Notify(title, desc, icon or "check", col or "cyan")
end

-- ----------------- TAB 1: IMAGES -----------------
local ImageTab = UI:CreateTab("Images", "Images", "folder", "cyan")

local availableFiles = getAvailableFiles()
local selectedFile = availableFiles[1] or ""
local manualUrl = ""

local FileDropdown = ImageTab:AddDropdown({
    title = "WORKSPACE IMAGE FILE",
    items = availableFiles,
    default = selectedFile,
    emoji = "folder",
    callback = function(val)
        selectedFile = val
    end
})

ImageTab:AddButton({
    title = "Rescan Folder",
    emoji = "refresh",
    color = "cyan",
    callback = function()
        availableFiles = getAvailableFiles()
        FileDropdown:SetValues(availableFiles)
        selectedFile = availableFiles[1] or ""
        FileDropdown:SetValue(selectedFile)
        notify("Scan Complete", string.format("Detected %d image files", #availableFiles), "refresh", "cyan")
    end
})

ImageTab:AddButton({
    title = "Parse Selected Image",
    emoji = "image",
    color = "green",
    callback = function()
        local ok, msg = loadImageFromWorkspace(selectedFile)
        if ok then
            notify("Load Success", msg, "check", "green")
        else
            notify("Load Error", msg, "alert", "red")
        end
    end
})

ImageTab:AddInput({
    title = "WEB IMAGE URL",
    placeholder = "https://i.imgur.com/example.png",
    emoji = "globe",
    callback = function(text)
        manualUrl = text
    end
})

ImageTab:AddButton({
    title = "Download & Parse URL",
    emoji = "globe",
    color = "purple",
    callback = function()
        if manualUrl == "" then
            notify("Input Error", "Please provide an image URL first.", "alert", "red")
            return
        end
        notify("Downloading", "Fetching image bytes...", "globe", "cyan")
        local ok, msg = loadImageFromURL(manualUrl)
        if ok then
            notify("Load Success", msg, "check", "green")
        else
            notify("Download Error", msg, "alert", "red")
        end
    end
})

-- ----------------- TAB 2: CANVAS & PREVIEW -----------------
local CanvasTab = UI:CreateTab("Canvas", "Canvas", "target", "cyan")

CanvasTab:AddButton({
    title = "Lock Wall Surface From Camera",
    emoji = "target",
    color = "cyan",
    callback = function()
        local ok, msg = PreviewSystem.AimFromCamera()
        if ok then
            notify("Surface Locked", msg, "target", "cyan")
        else
            notify("Aim Failed", msg, "alert", "red")
        end
    end
})

CanvasTab:AddToggle({
    title = "Enable 3D Preview Ghost Box",
    default = true,
    callback = function(enabled)
        if enabled then
            if not PreviewSystem.GhostPart then
                PreviewSystem.CreateGhost()
                PreviewSystem.UpdateTransform()
            end
            if PreviewSystem.GhostPart then
                PreviewSystem.GhostPart.Transparency = 0.8
                PreviewSystem.SelectionBox.Visible = true
            end
        else
            if PreviewSystem.GhostPart then
                PreviewSystem.GhostPart.Transparency = 1
                PreviewSystem.SelectionBox.Visible = false
            end
        end
    end
})

CanvasTab:AddDropdown({
    title = "ROTATION ANGLE",
    items = { "0 deg", "90 deg", "180 deg", "270 deg" },
    default = "0 deg",
    emoji = "refresh",
    callback = function(val)
        if val == "90 deg" then PreviewSystem.RotationDeg = 90
        elseif val == "180 deg" then PreviewSystem.RotationDeg = 180
        elseif val == "270 deg" then PreviewSystem.RotationDeg = 270
        else PreviewSystem.RotationDeg = 0 end
        PreviewSystem.UpdateTransform()
    end
})

CanvasTab:AddSlider({
    title = "Scale Multiplier",
    min = 0.2,
    max = 3.0,
    default = 1.0,
    step = 0.1,
    callback = function(val)
        PreviewSystem.ScaleMultiplier = val
        PreviewSystem.UpdateTransform()
    end
})

CanvasTab:AddSlider({
    title = "Offset X (Horizontal)",
    min = -15,
    max = 15,
    default = 0,
    step = 0.5,
    callback = function(val)
        PreviewSystem.OffsetX = val
        PreviewSystem.UpdateTransform()
    end
})

CanvasTab:AddSlider({
    title = "Offset Y (Vertical)",
    min = -15,
    max = 15,
    default = 0,
    step = 0.5,
    callback = function(val)
        PreviewSystem.OffsetY = val
        PreviewSystem.UpdateTransform()
    end
})

-- ----------------- TAB 3: SETTINGS -----------------
local SettingsTab = UI:CreateTab("Settings", "Settings", "settings", "purple")

SettingsTab:AddSlider({
    title = "Max Resolution (Mobile Safety)",
    min = 32,
    max = 120,
    default = 64,
    step = 4,
    callback = function(val)
        Engine.maxResolution = val
    end
})

SettingsTab:AddDropdown({
    title = "RENDER ALGORITHM",
    items = { "Raster (Scanline)", "Palette (Color Clusters)", "Spiral (Center Out)" },
    default = "Raster (Scanline)",
    emoji = "palette",
    callback = function(val)
        if val:find("Palette") then Engine.drawMode = "Palette"
        elseif val:find("Spiral") then Engine.drawMode = "Spiral"
        else Engine.drawMode = "Raster" end
    end
})

SettingsTab:AddSlider({
    title = "Network Batch Packet Size",
    min = 10,
    max = 60,
    default = 35,
    step = 5,
    callback = function(val)
        Engine.batchSize = val
    end
})

SettingsTab:AddSlider({
    title = "Packet Delay (Anti-Kick)",
    min = 0.02,
    max = 0.20,
    default = 0.06,
    step = 0.01,
    callback = function(val)
        Engine.batchDelay = val
    end
})

SettingsTab:AddToggle({
    title = "Skip Transparent Alpha Pixels",
    default = true,
    callback = function(enabled)
        Engine.alphaThreshold = enabled and 15 or 0
    end
})

SettingsTab:AddToggle({
    title = "Filter Pure White Background",
    default = false,
    callback = function(enabled)
        Engine.skipWhite = enabled
    end
})

SettingsTab:AddToggle({
    title = "Filter Pure Black Background",
    default = false,
    callback = function(enabled)
        Engine.skipBlack = enabled
    end
})

-- ----------------- TAB 4: DRAW CONTROLLER -----------------
local DrawTab = UI:CreateTab("Draw", "Draw", "palette", "green")

local StatusCard = DrawTab:AddStatusCard("Status: Idle", "Load image and lock surface to begin.", "palette", "cyan")

DrawTab:AddButton({
    title = "Start Autonomous Drawing",
    emoji = "play",
    color = "green",
    callback = function()
        if not CurrentLoadedImage then
            notify("Missing Image", "No image loaded. Select or download an image first.", "alert", "red")
            return
        end

        local drawCF = PreviewSystem.GetDrawCFrame()
        if not drawCF then
            notify("Missing Target", "Wall position not set. Use Aim in Canvas tab.", "alert", "red")
            return
        end

        if Engine:IsRunning() then
            notify("Active Process", "Drawing process already running.", "alert", "yellow")
            return
        end

        notify("Draw Started", "Transmitting paint batches to server...", "play", "green")
        StatusCard:SetEmoji("play", "green")

        Engine:Draw(
            CurrentLoadedImage,
            drawCF,
            function(current, total, pct)
                StatusCard:SetTitle(string.format("Drawing: %d%%", pct))
                StatusCard:SetDesc(string.format("Splats rendered: %d / %d (%d%%)", current, total, pct))
            end,
            function()
                StatusCard:SetTitle("Status: Complete")
                StatusCard:SetDesc("Artwork rendered successfully.")
                StatusCard:SetEmoji("check", "green")
                notify("Finished", "Autonomous draw finished successfully.", "check", "green")
            end,
            function(err)
                StatusCard:SetTitle("Status: Error")
                StatusCard:SetDesc("Engine stopped: " .. tostring(err))
                StatusCard:SetEmoji("alert", "red")
                notify("Engine Error", tostring(err), "alert", "red")
            end
        )
    end
})

DrawTab:AddButton({
    title = "Toggle Pause / Resume",
    emoji = "pause",
    color = "yellow",
    callback = function()
        if not Engine:IsRunning() then return end
        if Engine:IsPaused() then
            Engine:Resume()
            StatusCard:SetTitle("Status: Resumed")
            StatusCard:SetEmoji("play", "green")
            notify("Resumed", "Drawing resumed.", "play", "green")
        else
            Engine:Pause()
            StatusCard:SetTitle("Status: Paused")
            StatusCard:SetEmoji("pause", "yellow")
            notify("Paused", "Drawing paused. Tap again to resume.", "pause", "yellow")
        end
    end
})

DrawTab:AddButton({
    title = "Emergency Abort",
    emoji = "stop",
    color = "red",
    callback = function()
        if Engine:IsRunning() then
            Engine:Cancel()
            StatusCard:SetTitle("Status: Aborted")
            StatusCard:SetDesc("Process cancelled by user.")
            StatusCard:SetEmoji("stop", "red")
            notify("Cancelled", "Drawing halted immediately.", "stop", "red")
        end
    end
})

-- Ready status notification with custom palette emoji
notify("Ready", "Place images in workspace/" .. WORKSPACE_FOLDER .. "/", "palette", "cyan")

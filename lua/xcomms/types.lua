local type = type
local string_pack, string_unpack = string.pack, string.unpack
local blshift, brshift, band, bor = bit.lshift, bit.rshift, bit.band, bit.bor

xcomms.types = {
	int8 = {
		type = "int8",
		luatype = "number",
		size = 1,
		Check = function(value)
			return type(value) == "number"
		end,
		Encode = function(num)
			return string_pack("c", num)
		end,
		Decode = function(data, pos)
			return string_unpack(data, "c", pos)
		end
	},
	uint8 = {
		type = "uint8",
		luatype = "number",
		size = 1,
		Check = function(value)
			return type(value) == "number"
		end,
		Encode = function(num)
			return string_pack("b", num)
		end,
		Decode = function(data, pos)
			return string_unpack(data, "b", pos)
		end
	},
	int16 = {
		type = "int16",
		luatype = "number",
		size = 2,
		Check = function(value)
			return type(value) == "number"
		end,
		Encode = function(num)
			return string_pack(">h", num)
		end,
		Decode = function(data, pos)
			return string_unpack(data, ">h", pos)
		end
	},
	uint16 = {
		type = "uint16",
		luatype = "number",
		size = 2,
		Check = function(value)
			return type(value) == "number"
		end,
		Encode = function(num)
			return string_pack(">H", num)
		end,
		Decode = function(data, pos)
			return string_unpack(data, ">H", pos)
		end
	},
	int32 = {
		type = "int32",
		luatype = "number",
		size = 4,
		Check = function(value)
			return type(value) == "number"
		end,
		Encode = function(num)
			return string_pack(">i", num)
		end,
		Decode = function(data, pos)
			return string_unpack(data, ">i", pos)
		end
	},
	uint32 = {
		type = "uint32",
		luatype = "number",
		size = 4,
		Check = function(value)
			return type(value) == "number"
		end,
		Encode = function(num)
			return string_pack(">I", num)
		end,
		Decode = function(data, pos)
			return string_unpack(data, ">I", pos)
		end
	},
	int64 = {
		type = "int64",
		luatype = "number",
		size = 8,
		Check = function(value)
			return type(value) == "number"
		end,
		Encode = function(num)
			return string_pack(">s", num)
		end,
		Decode = function(data, pos)
			return string_unpack(data, ">s", pos)
		end
	},
	uint64 = {
		type = "uint64",
		luatype = "number",
		size = 8,
		Check = function(value)
			return type(value) == "number"
		end,
		Encode = function(num)
			return string_pack(">S", num)
		end,
		Decode = function(data, pos)
			return string_unpack(data, ">S", pos)
		end
	},
	varint = {
		type = "varint",
		luatype = "number",
		minsize = 1,
		maxsize = 5,
		Check = function(value)
			return type(value) == "number"
		end,
		Encode = function(num)
			local data = ""

			repeat
				local sevenbits = band(num, 0x7F)
				num = brshift(num, 7)
				data = data .. string_pack("b", num == 0 and sevenbits or bor(sevenbits, 0x80))
			until num == 0

			return data
		end,
		Decode = function(data, pos)
			local num, b = 0

			repeat
				pos, b = string_unpack(data, "b", pos)
				assert(b ~= nil, "not enough data to decode varint")
				num = bor(blshift(num, 7), band(b, 0x7F))
			until band(b, 0x80) == 0

			return pos, num
		end
	},
	float = {
		type = "float",
		luatype = "number",
		size = 4,
		Check = function(value)
			return type(value) == "number"
		end,
		Encode = function(num)
			return string_pack(">f", num)
		end,
		Decode = function(data, pos)
			return string_unpack(data, ">f", pos)
		end
	},
	double = {
		type = "double",
		luatype = "number",
		size = 8,
		Check = function(value)
			return type(value) == "number"
		end,
		Encode = function(num)
			return string_pack(">d", num)
		end,
		Decode = function(data, pos)
			return string_unpack(data, ">d", pos)
		end
	},
	boolean = {
		type = "boolean",
		luatype = "boolean",
		size = 1,
		Check = function(value)
			return type(value) == "boolean"
		end,
		Encode = function(boolean)
			return string_pack("b", boolean and 1 or 0)
		end,
		Decode = function(data, pos)
			local newpos, num = string_unpack(data, "b", pos)
			return newpos, num == 1
		end
	},
	string = {
		type = "string",
		luatype = "string",
		minsize = 1,
		maxsize = math.huge,
		Check = function(value)
			return type(value) == "string"
		end,
		Encode = function(str)
			return string_pack("z", str)
		end,
		Decode = function(data, pos)
			return string_unpack(data, "z", pos)
		end
	},
	binary = {
		type = "binary",
		luatype = "string",
		minsize = 2,
		maxsize = math.huge,
		Check = function(value)
			return type(value) == "string"
		end,
		Encode = function(bin)
			return string_pack("P", bin)
		end,
		Decode = function(data, pos)
			return string_unpack(data, "P", pos)
		end
	}
}

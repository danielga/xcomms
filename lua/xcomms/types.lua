local string_pack, string_unpack, string_rep = string.pack, string.unpack, string.rep
local blshift, brshift, band, bor = bit.lshift, bit.rshift, bit.band, bit.bor

xcomms.types = {
	int8 = {
		Type = "int8",
		LuaType = "number",
		Encode = function(num)
			return string_pack("c", num)
		end,
		Decode = function(data, pos)
			return string_unpack(data, "c", pos)
		end,
		Size = 1
	},
	uint8 = {
		Type = "uint8",
		LuaType = "number",
		Encode = function(num)
			return string_pack("b", num)
		end,
		Decode = function(data, pos)
			return string_unpack(data, "b", pos)
		end,
		Size = 1
	},
	int16 = {
		Type = "int16",
		LuaType = "number",
		Encode = function(num)
			return string_pack(">h", num)
		end,
		Decode = function(data, pos)
			return string_unpack(data, ">h", pos)
		end,
		Size = 2
	},
	uint16 = {
		Type = "uint16",
		LuaType = "number",
		Encode = function(num)
			return string_pack(">H", num)
		end,
		Decode = function(data, pos)
			return string_unpack(data, ">H", pos)
		end,
		Size = 2
	},
	int32 = {
		Type = "int32",
		LuaType = "number",
		Encode = function(num)
			return string_pack(">i", num)
		end,
		Decode = function(data, pos)
			return string_unpack(data, ">i", pos)
		end,
		Size = 4
	},
	uint32 = {
		Type = "uint32",
		LuaType = "number",
		Encode = function(num)
			return string_pack(">I", num)
		end,
		Decode = function(data, pos)
			return string_unpack(data, ">I", pos)
		end,
		Size = 4
	},
	int64 = {
		Type = "int64",
		LuaType = "number",
		Encode = function(num)
			return string_pack(">s", num)
		end,
		Decode = function(data, pos)
			return string_unpack(data, ">s", pos)
		end,
		Size = 8
	},
	uint64 = {
		Type = "uint64",
		LuaType = "number",
		Encode = function(num)
			return string_pack(">S", num)
		end,
		Decode = function(data, pos)
			return string_unpack(data, ">S", pos)
		end,
		Size = 8
	},
	varint = {
		Type = "varint",
		LuaType = "number",
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
		end,
		MinSize = 1,
		MaxSize = 5
	},
	float = {
		Type = "float",
		LuaType = "number",
		Encode = function(num)
			return string_pack(">f", num)
		end,
		Decode = function(data, pos)
			return string_unpack(data, ">f", pos)
		end,
		Size = 4
	},
	double = {
		Type = "double",
		LuaType = "number",
		Encode = function(num)
			return string_pack(">d", num)
		end,
		Decode = function(data, pos)
			return string_unpack(data, ">d", pos)
		end,
		Size = 8
	},
	boolean = {
		Type = "boolean",
		LuaType = "boolean",
		Encode = function(boolean)
			return string_pack("b", boolean and 1 or 0)
		end,
		Decode = function(data, pos)
			local newpos, num = string_unpack(data, "b", pos)
			return newpos, num == 1
		end,
		Size = 1
	},
	string = {
		Type = "string",
		LuaType = "string",
		Encode = function(str)
			return string_pack("z", str)
		end,
		Decode = function(data, pos)
			return string_unpack(data, "z", pos)
		end,
		MinSize = 1,
		MaxSize = math.huge
	},
	binary = {
		Type = "binary",
		LuaType = "string",
		Encode = function(bin)
			return string_pack("P", bin)
		end,
		Decode = function(data, pos)
			return string_unpack(data, "P", pos)
		end,
		MinSize = 2,
		MaxSize = math.huge
	}
}

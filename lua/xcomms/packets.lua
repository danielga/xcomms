include("types.lua")

local xcomms = xcomms
local setmetatable, assert, type = setmetatable, assert, type
local table_concat, table_insert, table_copy = table.concat, table.insert, table.Copy
local string_pack, string_unpack, string_format, string_find = string.pack, string.unpack, string.format, string.find
local hook_Call = hook.Call

xcomms.PacketTypes = {}

local function EvaluateMembers(members)
	local min, max = 0, 0
	for i = 1, #members do
		local member = members[i]

		if member.Repeated then
			min = min + xcomms.Types.varint.MinSize
			max = math.huge
		elseif member.Members ~= nil then
			local m, M = EvaluateMembers(member.Members)
			min = min + m
			max = max + M
		else
			if member.Condition == nil then
				min = min + (member.Type.Size or member.Type.MinSize)
			end

			max = max + (member.Type.Size or member.Type.MaxSize)
		end
	end

	return min, max
end

function xcomms.RegisterPacket(ptype, tab)
	assert(ptype >= 0 and ptype <= 255, "type ID must be between 0 and 255")

	local min, max = EvaluateMembers(tab)

	local function PackMember(self, member, data, results)
		local memberdata = data[member.Name]
		assert(memberdata ~= nil or member.Condition ~= nil, string_format("incomplete data to generate packet of type %d (member '%s')", self.Type, member.Name))

		if member.Condition == nil or member.Condition(self, data) then
			table_insert(results, member.Type.Encode(memberdata))
		end
	end

	local function PackComplexMember(self, members, data, results)
		for i = 1, #members do
			PackMember(self, members[i], data, results)
		end
	end

	local function PackRepeatedMember(self, member, data, results)
		local count = #data
		table_insert(results, xcomms.Types.varint.Encode(count))

		for i = 1, count do
			if member.Members == nil then
				PackMember(self, member, data[i], results)
			else
				PackComplexMember(self, member.Members, data[i], results)
			end
		end
	end

	local function UnpackMember(self, member, availdata, data, pos)
		local value
		if member.Condition == nil or member.Condition(self, availdata) then
			pos, value = member.Type.Decode(data, pos)
			assert(value ~= nil, string_format("not enough data to fully unpack packet of type %d", self.Type))
		end

		return pos, value
	end

	local function UnpackComplexMember(self, members, data, pos)
		local values = {}
		local value
		for i = 1, #members do
			local member = members[i]
			pos, value = UnpackMember(self, member, values, data, pos)
			values[member.Name] = value
		end

		return pos, values
	end

	local function UnpackRepeatedMember(self, member, data, pos)
		local count
		pos, count = xcomms.Types.varint.Decode(data, pos)
		assert(count ~= nil, string_format("not enough data to fully unpack packet of type %d", self.Type))

		local values = {}
		local value
		for i = 1, count do
			if member.Members == nil then
				pos, value = UnpackMember(self, member, self.Data, data, pos)
			else
				pos, value = UnpackComplexMember(self, member.Members, data, pos)
			end

			values[i] = value
		end

		return pos, values
	end

	local function GetMember(members, key)
		for i = 1, #members do
			if members[i].Name == key then
				return members[i]
			end
		end
	end

	xcomms.PacketTypes[ptype] = {
		Type = ptype,
		MinSize = min,
		MaxSize = max,
		Members = tab,
		Get = function(self, key, default)
			assert(type(key) == "string", "key provided is not a string")
			local member = GetMember(self.Members, key)
			assert(member ~= nil, string_format("packet does not have member '%s'", key))

			local value = self.Data[key]
			return value ~= nil and value or default
		end,
		Set = function(self, key, value)
			assert(type(key) == "string", "key provided is not a string")
			local member = GetMember(self.Members, key)
			assert(member ~= nil, string_format("packet does not have member '%s'", key))
			if member.Repeated then
				assert(type(value) == "table", "value type is not a table (repeated member)")
			else
				assert(type(value) == member.LuaType, "value type is not the same as the member's type")
			end

			self.Dirty = self.Data[key] ~= value
			self.Data[key] = value
		end,
		Add = function(self, key, value)
			assert(type(key) == "string", "key provided is not a string")
			local member = GetMember(self.Members, key)
			assert(member ~= nil, string_format("packet does not have member '%s'", key))
			assert(type(value) == member.LuaType, "value type is not the same as the member's type")

			self.Dirty = true
			if self.Data[key] == nil then
				self.Data[key] = {value}
				return 1
			end

			return table_insert(self.Data[key], value)
		end,
		Pack = function(self)
			if not self.Dirty then
				return self.Cache
			end

			local data = {}
			for i = 1, #self.Members do
				local member = self.Members[i]
				if member.Repeated then
					PackRepeatedMember(self, member, self.Data[member.Name], data)
				elseif members.Members ~= nil then
					PackComplexMember(self, member, self.Data[member.Name], data)
				else
					PackMember(self, member, self.Data[member.Name], data)
				end
			end

			self.Cache = table_concat(data)
			self.Dirty = false
			return self.Cache
		end,
		Unpack = function(self, data, pos)
			pos = pos or 1

			local value
			for i = 1, #self.Members do
				local member = self.Members[i]
				if member.Repeated then
					pos, value = UnpackRepeatedMember(self, member, data, pos)
				elseif members.Members ~= nil then
					pos, value = UnpackComplexMember(self, member, data, pos)
				else
					pos, value = UnpackMember(self, member, self.Data, data, pos)
				end

				self.Data[member.Name] = value
			end
		end
	}
	xcomms.PacketTypes[ptype].__index = xcomms.PacketTypes[ptype]
end

function xcomms.CreatePacket(ptype)
	if xcomms.PacketTypes[ptype] == nil then
		return
	end

	return setmetatable({Data = {}}, xcomms.PacketTypes[ptype])
end

function xcomms.Send(packet)
	local data = packet:Pack()
	data = "XSERVERS" .. string_pack(">bb", xcomms.CurrentProtocol, packet.Type) .. data

	for i = 1, #xcomms.AddressesCount do
		local peer = xcomms.Peers[i]
		if peer ~= nil then
			peer:send(data, 1, packet.Reliable and "reliable" or "unsequenced")
		end
	end
end

function xcomms.Receive(source, data)
	if string_find(data, "^XSERVERS") == nil or #data < 12 then
		return false -- not an xcomms packet
	end

	local _, proto, ptype = string_unpack(data, ">bb", 9)
	if proto ~= xcomms.CurrentProtocol then
		return false	-- protocol differs, don't bother with it
						-- we don't need multiple protocols at the
						-- same time in here
	end

	local packet = xcomms.CreatePacket(ptype)
	if packet == nil then
		return false -- unrecognized packet type
	end

	packet:Unpack(data, 11)

	hook_Call("XServersIncomingPacket", nil, packet)

	return true
end
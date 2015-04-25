include("types.lua")

local xservers = xservers
local setmetatable, assert, type = setmetatable, assert, type
local table_concat, table_insert, table_copy = table.concat, table.insert, table.Copy
local string_pack, string_unpack, string_format, string_find = string.pack, string.unpack, string.format, string.find
local hook_Call = hook.Call

xservers.PacketTypes = {}

local function EvaluateMembers(members)
	local min, max = 0, 0
	for i = 1, #members do
		local member = members[i]

		if member.Repeated then
			min = min + xservers.Types.varint.MinSize
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

function xservers.RegisterPacket(ptype, tab)
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
		table_insert(results, xservers.Types.varint.Encode(count))

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
		pos, count = xservers.Types.varint.Decode(data, pos)
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

	xservers.PacketTypes[ptype] = {
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
	xservers.PacketTypes[ptype].__index = xservers.PacketTypes[ptype]
end

function xservers.CreatePacket(ptype)
	if xservers.PacketTypes[ptype] == nil then
		return
	end

	return setmetatable({Data = {}}, xservers.PacketTypes[ptype])
end

function xservers.Send(packet)
	local data = packet:Pack()
	data = "XSERVERS" .. string_pack(">bbH", xservers.CurrentProtocol, packet.Type, #data) .. data
	if packet.Reliable then
		for i = 1, #xservers.Connections do
			local sock = xservers.Connections[i]
			if sock ~= nil then
				sock:send(data)
			end
		end
	else
		for i = 1, xservers.AddressesCount do
			local addr = xservers.Addresses[i]
			if addr ~= nil and addr ~= xservers.Address then
				xservers.Unreliable:sendto(data, addr, xservers.UnreliablePort)
			end
		end
	end

	return true
end

local function Process(data, reliable)
	if string_find(data, "^XSERVERS") == nil or #data < 12 then
		return false -- not an xservers packet
	end

	local _, proto, ptype, psize = string_unpack(data, ">bbH", 9)
	if proto ~= xservers.CurrentProtocol then
		return false	-- protocol differs, don't bother with it
						-- we don't need multiple protocols at the
						-- same time in here
	end

	local packet = xservers.CreatePacket(ptype)
	if packet == nil then
		return false -- unrecognized packet type
	end

	packet:Unpack(data, 13)
	if packet.Reliable ~= reliable then
		packet.Reliable = reliable
	end

	hook_Call("XServersIncomingPacket", nil, packet)

	return true
end

function xservers.Receive()
	for i = 1, xservers.AddressesCount do
		if xservers.Connections[i] ~= nil then
			local data, err, partial = xservers.Connections[i]:receive(65535)
			if data == nil then
				if err == "closed" then
					xservers.Connections[i]:close()
					xservers.Connections[i] = nil
				end

				continue
			end

			return Process(data, true)
		end
	end

	local data, extra1, extra2 = xservers.Unreliable:receivefrom(65535)
	if data == nil then
		return false
	end

	return Process(data, false)
end
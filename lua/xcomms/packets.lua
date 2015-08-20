include("types.lua")

local xcomms = xcomms
local setmetatable, assert, type = setmetatable, assert, type
local table_concat, table_insert = table.concat, table.insert
local string_pack, string_unpack, string_find = string.pack, string.unpack, string.find

xcomms.packets = {}

local function EvaluateMembers(members)
	local min, max = 0, 0
	for i = 1, #members do
		local member = members[i]

		if member.repeated then
			min = min + xcomms.types.varint.minsize
			max = math.huge
		elseif member.members ~= nil then
			local m, M = EvaluateMembers(member.members)
			min = min + m
			max = max + M
		else
			if member.Condition == nil then
				min = min + (member.type.size or member.type.minsize)
			end

			max = max + (member.type.size or member.type.maxsize)
		end
	end

	return min, max
end

function xcomms.RegisterPacket(ptype, tab)
	assert(ptype >= 0 and ptype <= 255, "type ID must be between 0 and 255")

	local min, max = EvaluateMembers(tab)

	local function PackMember(self, member, data, results)
		local memberdata = data[member.name]
		assert(memberdata ~= nil or member.Condition ~= nil, "incomplete data to generate packet of type " .. self.type .. " (member '" .. member.name .. "')")

		if member.Condition == nil or member.Condition(self, data) then
			table_insert(results, member.type.Encode(memberdata))
		end
	end

	local function PackComplexMember(self, members, data, results)
		for i = 1, #members do
			PackMember(self, members[i], data, results)
		end
	end

	local function PackRepeatedMember(self, member, data, results)
		local count = #data
		table_insert(results, xcomms.types.varint.Encode(count))

		for i = 1, count do
			if member.members == nil then
				PackMember(self, member, data[i], results)
			else
				PackComplexMember(self, member.members, data[i], results)
			end
		end
	end

	local function UnpackMember(self, member, availdata, data, pos)
		local value
		if member.Condition == nil or member.Condition(self, availdata) then
			pos, value = member.type.Decode(data, pos)
			assert(value ~= nil, "not enough data to fully unpack packet of type " .. self.type)
		end

		return pos, value
	end

	local function UnpackComplexMember(self, members, data, pos)
		local values = {}
		local value
		for i = 1, #members do
			local member = members[i]
			pos, value = UnpackMember(self, member, values, data, pos)
			values[member.name] = value
		end

		return pos, values
	end

	local function UnpackRepeatedMember(self, member, data, pos)
		local count
		pos, count = xcomms.types.varint.Decode(data, pos)
		assert(count ~= nil, "not enough data to fully unpack packet of type " .. self.type)

		local values = {}
		local value
		for i = 1, count do
			if member.members == nil then
				pos, value = UnpackMember(self, member, self.data, data, pos)
			else
				pos, value = UnpackComplexMember(self, member.members, data, pos)
			end

			values[i] = value
		end

		return pos, values
	end

	local function GetMember(members, key)
		for i = 1, #members do
			if members[i].name == key then
				return members[i]
			end
		end
	end

	xcomms.packets[ptype] = {
		type = ptype,
		minsize = min,
		maxsize = max,
		members = tab,
		Get = function(self, key, default)
			assert(type(key) == "string", "key provided is not a string")
			local member = GetMember(self.members, key)
			assert(member ~= nil, "packet does not have member '" .. key .. "'")

			local value = self.data[key]
			return value ~= nil and value or default
		end,
		Set = function(self, key, value)
			assert(type(key) == "string", "key provided is not a string")
			local member = GetMember(self.members, key)
			assert(member ~= nil, "packet does not have member '" .. key .. "'")
			if member.repeated then
				assert(type(value) == "table", "value type is not a table (repeated member)")
			else
				assert(member.Check(value), "value type is not the same as the member's type")
			end

			self.dirty = self.data[key] ~= value
			self.data[key] = value
		end,
		Add = function(self, key, value)
			assert(type(key) == "string", "key provided is not a string")
			local member = GetMember(self.members, key)
			assert(member ~= nil, "packet does not have member '" .. key .. "'")
			assert(member.Check(value), "value type is not the same as the member's type")

			self.dirty = true
			if self.data[key] == nil then
				self.data[key] = {}
			end

			return table_insert(self.data[key], value)
		end,
		Pack = function(self)
			if not self.dirty then
				return self.cache
			end

			local data = {}
			for i = 1, #self.members do
				local member = self.members[i]
				if member.repeated then
					PackRepeatedMember(self, member, self.data[member.name], data)
				elseif members.members ~= nil then
					PackComplexMember(self, member, self.data[member.name], data)
				else
					PackMember(self, member, self.data[member.name], data)
				end
			end

			self.cache = table_concat(data)
			self.dirty = false
			return self.cache
		end,
		Unpack = function(self, data, pos)
			pos = pos or 1

			local value
			for i = 1, #self.members do
				local member = self.members[i]
				if member.repeated then
					pos, value = UnpackRepeatedMember(self, member, data, pos)
				elseif members.members ~= nil then
					pos, value = UnpackComplexMember(self, member, data, pos)
				else
					pos, value = UnpackMember(self, member, self.Data, data, pos)
				end

				self.data[member.Name] = value
			end
		end
	}
	xcomms.packets[ptype].__index = xcomms.packets[ptype]
end

function xcomms.CreatePacket(ptype)
	if xcomms.packets[ptype] == nil then
		return
	end

	return setmetatable({data = {}}, xcomms.packets[ptype])
end

function xcomms.Send(packet)
	local data = "XCOMMS" .. string_pack(">bb", xcomms.protocol, packet.type) .. packet:Pack()

	for i = 1, xcomms.maxpeers do
		local peer = xcomms.peers[i]
		if peer ~= nil then
			peer:send(data, 1, packet.reliable and "reliable" or "unsequenced")
		end
	end
end

function xcomms.Receive(source, data)
	if string_find(data, "^XCOMMS") == nil or #data < 8 then
		return nil, "unknown packet"
	end

	local _, proto, ptype = string_unpack(data, ">bb", 7)
	if proto ~= xcomms.protocol then
		-- protocol differs, don't bother with it
		-- we don't need multiple protocols at the
		-- same time in here
		return nil, "different protocol"
	end

	local packet = xcomms.CreatePacket(ptype)
	if packet == nil then
		return nil, "unknown packet type"
	end

	packet:Unpack(data, 11)
	return packet
end

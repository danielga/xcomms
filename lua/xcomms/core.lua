require("enet")
require("pack")

xcomms = xcomms or {
	initialized = false,
	protocol = 1,
	whitelist = {},
	address = "*",
	port = 50000,
	peers = {},
	maxpeers = 5,
	callbacks = {}
}

local xcomms = xcomms
local assert, type, tostring = assert, type, tostring
local table_insert, table_remove = table.insert, table.remove
local string_match = string.match

do
	local _, bigendian = string.unpack(string.pack(">I", 1), "=I") == 1
	xcomms.bigendian = bigendian
end

include("packets.lua")

function xcomms.Initialize(addr, port, maxpeers)
	xcomms.Shutdown()

	if addr ~= nil then
		assert(type(addr) == "string", "provided address value is not a string")
		xcomms.address = addr
	end

	if port ~= nil then
		assert(type(port) == "number", "provided port value is not a number")
		xcomms.port = port
	end

	if maxpeers ~= nil then
		assert(type(maxpeers) == "number", "provided max peers value is not a number")
		xcomms.maxpeers = maxpeers
	end

	xcomms.host = enet.host_create(xcomms.address .. ":" .. xcomms.port, xcomms.maxpeers)
	assert(xcomms.host ~= nil, "failed to create ENet host")

	xcomms.initialized = true
	return true
end

function xcomms.AddServer(addr)
	assert(type(addr) == "string", "provided address value is not a string")
	local index = table_insert(xcomms.whitelist, addr)
	xcomms.whitelist[addr] = index
	return index
end

function xcomms.Connect(serverid)
	assert(type(serverid) == "number", "provided server ID value is not a number")
	local addr = xcomms.whitelist[serverid]
	assert(addr ~= nil, "unknown server ID " .. serverid)
	local peer = xcomms.host:connect(addr .. ":" .. xcomms.port)
	assert(peer ~= nil, "failed to create ENet peer")
	peer.serverid = serverid
	xcomms.peers[serverid] = peer
	return peer
end

function xcomms.Shutdown()
	if not xcomms.initialized then
		return false
	end

	xcomms.host:destroy()
	xcomms.host = nil

	xcomms.initialized = false
	return true
end

function xcomms.RegisterCallback(ptype, callback)
	assert(type(ptype) == "number", "provided packet type value is not a number")
	assert(type(callback) == "function", "provided callback value is not a function")

	local callbacks = xcomms.callbacks[ptype]
	if callbacks == nil then
		callbacks = {}
		xcomms.callbacks[ptype] = callbacks
	else
		for i = 1, #callbacks do
			if callbacks[i] == callback then
				return false
			end
		end
	end

	table_insert(callbacks, callback)
	return true
end

function xcomms.RemoveCallback(ptype, callback)
	assert(type(ptype) == "number", "provided packet type value is not a number")
	assert(type(callback) == "function", "provided callback value is not a function")

	local callbacks = xcomms.callbacks[ptype]
	if callbacks == nil then
		return false
	end

	for i = 1, #callbacks do
		if callbacks[i] == callback then
			table_remove(callbacks, i)
			return true
		end
	end

	return false
end

function xcomms.Think()
	if not xcomms.initialized then
		return false
	end

	for i = 1, 10 do
		local event = xcomms.host:service()
		if event == nil or event.peer == nil then
			break
		end

		local peer = event.peer
		local serverid = peer.serverid
		if event.type == "connect" then
			if serverid == nil then
				serverid = xcomms.whitelist[string_match(tostring(peer), "^([^:]+)")]
			end

			if serverid == nil then
				peer:disconnect_now()
			else
				peer.serverid = serverid
				xcomms.peers[serverid] = peer
			end
		elseif event.type == "disconnect" then
			if peer.serverid ~= nil then
				xcomms.peers[peer.serverid] = nil
			end
		elseif event.type == "receive" then
			if serverid ~= nil then
				xcomms.Receive(serverid, event.data)
			end
		end
	end

	return true
end

local function Call(packet)
	local callbacks = xcomms.callbacks[packet.type]
	if callbacks == nil then
		return false
	end

	for i = 1, #callbacks do
		if callbacks[i](packet) == true then
			break
		end
	end

	return true
end

-- Garry's Mod support code
if hook ~= nil and hook.Add ~= nil and hook.Call ~= nil then
	hook.Add("Think", "xcomms logic hook", xcomms.Think)

	local hook_Call = hook.Call
	function xcomms.Call(packet)
		return hook_Call("XCommsIncomingPacket", nil, packet) == true or Call(packet)
	end
else
	xcomms.Call = Call
end

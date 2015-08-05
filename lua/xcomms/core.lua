require("enet")
require("pack")

xcomms = xcomms or {
	initialized = false,
	protocol = 1,
	whitelist = {},
	address = "*",
	port = 50000,
	peers = {},
	maxpeers = 5
}

local xcomms = xcomms
local assert, type, tostring = assert, type, tostring
local table_KeyFromValue, table_insert = table.KeyFromValue, table.insert
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

hook.Add("Think", "xcomms logic hook", function()
	if not xcomms.initialized then
		return
	end

	for i = 1, 10 do
		local event = xcomms.host:service()
		if event == nil or event.peer == nil then
			return
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
end)

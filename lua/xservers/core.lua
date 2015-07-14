require("enet")
require("pack")

xservers = xservers or {
	CurrentProtocol = 1,
	Addresses = {},
	Port = 50000,
	MaxPeers = 5,
	Peers = {}
}

local xservers = xservers
local assert, print, CurTime = assert, print, CurTime
local table_KeyFromValue = table.KeyFromValue
local string_format, string_match = string.format, string.match

do
	local _, bigendian = string.unpack(string.pack(">I", 1), "=I") == 1
	xservers.BigEndian = bigendian

	local addr = GetConVarNumber("hostip")
	assert(addr ~= nil, "unable to retrieve this server address")
	xservers.Address = string_format(
		"%d.%d.%d.%d",
		bit.band(bit.rshift(addr, 24), 0xFF),
		bit.band(bit.rshift(addr, 16), 0xFF),
		bit.band(bit.rshift(addr, 8), 0xFF),
		bit.band(addr, 0xFF)
	)
end

if xservers.Host == nil then
	xservers.Host = enet.host_create(string_format("%s:%d", xservers.Address, xservers.Port), xservers.MaxPeers)
	assert(xservers.Host ~= nil, "failed to create ENet host")
end

include("packets.lua")

function xservers.AddServer(addr)
	return table.insert(xservers.Addresses)
end

function xservers.Connect(serverid)
	local addr = xservers.Addresses[serverid]
	assert(addr ~= nil, string_format("invalid or unknown server ID %d", serverid))
	assert(xservers.Host:connect(string_format("%s:%d", addr, xservers.Port)) ~= nil, "failed to create ENet peer")
end

function xservers.Shutdown()
	for i = 1, #xservers.Peers do
		if xservers.Peers[i] ~= nil then
			xservers.Peers[i]:disconnect_now()
		end
	end

	xservers.Peers = {}

	xservers.Host:destroy()
	xservers.Host = nil
end

hook.Add("Think", "xservers logic hook", function()
	for i = 1, 10 do
		local event = xservers.Host:service()
		if event == nil or event.peer == nil then
			return
		end

		local peer = event.peer
		local serverid = table_KeyFromValue(xservers.Peers, peer)
		if event.type == "connect" then
			if serverid == nil then
				serverid = table_KeyFromValue(xservers.Addresses, string_match(tostring(peer), "^([^:]+)"))
			end

			if serverid == nil then
				peer:disconnect_now()
			else
				xservers.Peers[serverid] = peer
			end
		elseif event.type == "disconnect" then
			if serverid ~= nil then
				xservers.Peers[serverid] = nil
			end
		elseif event.type == "receive" then
			if serverid ~= nil then
				xservers.Receive(serverid, event.data)
			end
		end
	end
end)
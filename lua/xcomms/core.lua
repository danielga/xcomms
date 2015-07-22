require("enet")
require("pack")

xcomms = xcomms or {
	CurrentProtocol = 1,
	Addresses = {},
	Port = 50000,
	MaxPeers = 5,
	Peers = {}
}

local xcomms = xcomms
local assert, print, CurTime = assert, print, CurTime
local table_KeyFromValue = table.KeyFromValue
local string_format, string_match = string.format, string.match

do
	local _, bigendian = string.unpack(string.pack(">I", 1), "=I") == 1
	xcomms.BigEndian = bigendian

	local addr = GetConVarNumber("hostip")
	assert(addr ~= nil, "unable to retrieve this server address")
	xcomms.Address = string_format(
		"%d.%d.%d.%d",
		bit.band(bit.rshift(addr, 24), 0xFF),
		bit.band(bit.rshift(addr, 16), 0xFF),
		bit.band(bit.rshift(addr, 8), 0xFF),
		bit.band(addr, 0xFF)
	)
end

if xcomms.Host == nil then
	xcomms.Host = enet.host_create(string_format("%s:%d", xcomms.Address, xcomms.Port), xcomms.MaxPeers)
	assert(xcomms.Host ~= nil, "failed to create ENet host")
end

include("packets.lua")

function xcomms.AddServer(addr)
	return table.insert(xcomms.Addresses)
end

function xcomms.Connect(serverid)
	local addr = xcomms.Addresses[serverid]
	assert(addr ~= nil, string_format("invalid or unknown server ID %d", serverid))
	assert(xcomms.Host:connect(string_format("%s:%d", addr, xcomms.Port)) ~= nil, "failed to create ENet peer")
end

function xcomms.Shutdown()
	for i = 1, #xcomms.Peers do
		if xcomms.Peers[i] ~= nil then
			xcomms.Peers[i]:disconnect_now()
		end
	end

	xcomms.Peers = {}

	xcomms.Host:destroy()
	xcomms.Host = nil
end

hook.Add("Think", "xcomms logic hook", function()
	for i = 1, 10 do
		local event = xcomms.Host:service()
		if event == nil or event.peer == nil then
			return
		end

		local peer = event.peer
		local serverid = table_KeyFromValue(xcomms.Peers, peer)
		if event.type == "connect" then
			if serverid == nil then
				serverid = table_KeyFromValue(xcomms.Addresses, string_match(tostring(peer), "^([^:]+)"))
			end

			if serverid == nil then
				peer:disconnect_now()
			else
				xcomms.Peers[serverid] = peer
			end
		elseif event.type == "disconnect" then
			if serverid ~= nil then
				xcomms.Peers[serverid] = nil
			end
		elseif event.type == "receive" then
			if serverid ~= nil then
				xcomms.Receive(serverid, event.data)
			end
		end
	end
end)
require("serverid")
require("enet")
require("pack")

xservers = xservers or {
	CurrentProtocol = 1,
	AddressesCount = 5,
	Addresses = {
		"195.154.232.234", -- #1
		nil, -- #2
		nil, -- #3
		nil, -- #4
		"94.23.170.2" -- #5
	},
	Port = 50000,
	MaxPeers = 5,
	Peers = {}
}

do
	local _, bigendian = string.unpack(string.pack(">I", 1), "=I") == 1
	xservers.BigEndian = bigendian
end

include("packets.lua")

local xservers = xservers
local assert, print, CurTime = assert, print, CurTime
local table_KeyFromValue = table.KeyFromValue
local string_format, string_match = string.format, string.match

xservers.Address = xservers.Addresses[SERVERID]
assert(xservers.Address ~= nil, string_format("invalid or unknown server ID %d", SERVERID))

if xservers.Host == nil then
	xservers.Host = enet.host_create(string_format("%s:%d", xservers.Address, xservers.Port), xservers.MaxPeers)
	assert(xservers.Host ~= nil, "failed to create lua-enet host")
end

function xservers.Connect(serverid)
	local addr = xservers.Addresses[serverid]
	assert(addr ~= nil, string_format("invalid or unknown server ID %d", serverid))
	assert(xservers.Host:connect(string_format("%s:%d", addr, xservers.Port)) ~= nil, "failed to create lua-enet peer")
end

function xservers.Shutdown()
	for i = 1, xservers.AddressesCount do
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
		local serverid = table.KeyFromValue(xservers.Peers, peer)
		if event.type == "connect" then
			if serverid == nil then
				serverid = table.KeyFromValue(xservers.Addresses, string_match(tostring(peer), "^([^:]+)"))
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
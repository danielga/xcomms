require("serverid")
require("luasocket")
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
	ReliablePort = 50000,
	UnreliablePort = 50001,
	MaxBacklog = 5,
	AcceptInterval = 1,
	LastAccept = 0,
	Connections = {}
}

do
	local _, bigendian = string.unpack(string.pack(">I", 1), "=I") == 1
	xservers.BigEndian = bigendian
end

include("packets.lua")

local xservers = xservers
local assert, print, CurTime = assert, print, CurTime
local table_KeyFromValue = table.KeyFromValue
local string_format = string.format

xservers.Address = xservers.Addresses[SERVERID]
assert(xservers.Address ~= nil, string_format("invalid or unknown server ID %d", SERVERID))

if xservers.Reliable == nil then
	local sock, err = socket.tcp()
	assert(sock ~= nil, err)

	sock:settimeout(0)
	local ret, err = sock:bind(xservers.Address, xservers.ReliablePort)
	assert(ret ~= nil, err)

	local ret, err = sock:listen(xservers.MaxBacklog)
	assert(ret ~= nil, err)

	xservers.Reliable = sock
end

if xservers.Unreliable == nil then
	local sock, err = socket.udp()
	assert(sock ~= nil, err)

	sock:settimeout(0)
	local ret, err = sock:setsockname(xservers.Address, xservers.UnreliablePort)
	assert(ret ~= nil, err)

	xservers.Unreliable = sock
end

function xservers.AcceptConnection()
	local sock = xservers.Reliable:accept()
	if sock == nil then
		return nil
	end

	local ip, port = sock:getpeername()
	if ip == nil then
		sock:close()
		return nil
	end

	local serverid = table_KeyFromValue(xservers.Addresses, ip) 
	if serverid == nil then
		sock:close()
		return false, ip
	end

	xservers.Connections[serverid] = sock
	return true, serverid
end

function xservers.Shutdown()
	xservers.Reliable:close()
	xservers.Reliable = nil

	xservers.Unreliable:close()
	xservers.Unreliable = nil

	for i = 1, xservers.AddressesCount do
		if xservers.Connections[i] ~= nil then
			xservers.Connections[i]:close()
		end
	end
	xservers.Connections = {}
end

hook.Add("Think", "xservers logic hook", function()
	if CurTime() >= xservers.LastAccept + xservers.AcceptInterval then
		xservers.LastAccept = CurTime()

		local status, id = xservers.AcceptConnection()
		while status ~= nil do
			if status then
				print(string_format("[xservers] Server #%d connected to us.", id))
			else
				print(string_format("[xservers] Unknown client address %s tried to connect.", id))
			end

			status, id = xservers.AcceptConnection()
		end
	end

	for i = 1, 10 do
		if not xservers.Receive() then
			break
		end
	end
end)
local band = bit.band

PACKET_PLAYERSYNC = 1

xservers.RegisterPacket(PACKET_PLAYERSYNC, {
	{ -- this is a repeated complex member
		Name = "players", -- this is the name of the member
		Repeated = true, -- this member may be repeated multiple times
		Members = {
			{
				Name = "steamid", -- a member of the repeated complex member
				Type = xservers.Types.uint64 -- type of this member
			},
			{
				Name = "flags",
				Type = xservers.Types.uint8
			},
			{
				Name = "name",
				Type = xservers.Types.string,
				Condition = function(packet) -- this member is optional and should be used if Condition
					return band(packet:Get("flags", 0), 0x01) ~= 0
				end
			},
			{
				Name = "health",
				Type = xservers.Types.int8,
				Condition = function(packet)
					return band(packet:Get("flags", 0), 0x02) ~= 0
				end
			},
			{
				Name = "x",
				Type = xservers.Types.int16,
				Condition = function(packet)
					return band(packet:Get("flags", 0), 0x04) ~= 0
				end
			},
			{
				Name = "y",
				Type = xservers.Types.int16,
				Condition = function(packet)
					return band(packet:Get("flags", 0), 0x04) ~= 0
				end
			},
			{
				Name = "z",
				Type = xservers.Types.int16,
				Condition = function(packet)
					return band(packet:Get("flags", 0), 0x04) ~= 0
				end
			},
			{
				Name = "p",
				Type = xservers.Types.int8,
				Condition = function(packet)
					return band(packet:Get("flags", 0), 0x08) ~= 0
				end
			},
			{
				Name = "yw",
				Type = xservers.Types.int8,
				Condition = function(packet)
					return band(packet:Get("flags", 0), 0x08) ~= 0
				end
			},
			{
				Name = "r",
				Type = xservers.Types.int8,
				Condition = function(packet)
					return band(packet:Get("flags", 0), 0x08) ~= 0
				end
			}
		}
	}
})
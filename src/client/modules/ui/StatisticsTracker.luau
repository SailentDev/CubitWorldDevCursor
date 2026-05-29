--!strict
local RunService = game:GetService("RunService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

-- Explicitly targeting the Blink client network module
local Blink = require(ReplicatedStorage.Shared.Blink.network_client)

local StatisticsTracker = {}
local heartbeatConnection: RBXScriptConnection? = nil
local updateThread: thread? = nil

local frameCount = 0
local serverRegion: string = "Loading..."

function StatisticsTracker.Init(label: TextLabel): ()
	-- Safely reset running states to prevent duplicate routines
	StatisticsTracker.Stop()

	frameCount = 0
	
	-- Increment frame count every frame (negligible performance footprint)
	heartbeatConnection = RunService.Heartbeat:Connect(function()
		frameCount += 1
	end)

	local localPlayer = Players.LocalPlayer

	-- Throttled update thread running once per second to minimize layout costs
	updateThread = task.spawn(function()
		while true do
			task.wait(1)
			
			local currentFps = frameCount
			frameCount = 0 -- Reset counter for next interval

			local ping = 0
			if localPlayer then
				-- GetNetworkPing returns one-way latency in seconds
				ping = math.round(localPlayer:GetNetworkPing() * 1000)
			end

			-- Updated to display our human-readable region instead of JobId
			label.Text = string.format("FPS: %d | Ping: %d ms | Region: %s", currentFps, ping, serverRegion)
		end
	end)
end

function StatisticsTracker.Stop(): ()
	if heartbeatConnection then
		heartbeatConnection:Disconnect()
		heartbeatConnection = nil
	end
	if updateThread then
		task.cancel(updateThread)
		updateThread = nil
	end
end

-- Listen for the Server's SyncRegion packet to update local memory cache
Blink.SyncRegion.On(function(regionName: string)
	if typeof(regionName) == "string" then
		serverRegion = regionName
	end
end)

return StatisticsTracker
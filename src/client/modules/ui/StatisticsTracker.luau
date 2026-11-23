--!strict
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local Blink = require(ReplicatedStorage.Shared.Blink.network_client)

local StatisticsTracker = {}

local localPlayer = Players.LocalPlayer :: Player
local frameCount = 0
local serverRegion = "Unknown"

local updateThread: thread? = nil
local heartbeatConnection: RBXScriptConnection? = nil
local label: TextLabel? = nil

function StatisticsTracker.OnInit(): ()
	Blink.SyncRegion.On(function(regionName: string)
		if typeof(regionName) == "string" and #regionName > 0 then
			serverRegion = regionName
		end
	end)
end

function StatisticsTracker.Start(passedLabel: TextLabel): ()
	label = passedLabel
	frameCount = 0

	if not heartbeatConnection then
		heartbeatConnection = RunService.Heartbeat:Connect(function()
			frameCount += 1
		end)
	end

	if not updateThread then
		updateThread = task.spawn(function()
			local lastSampleTime = os.clock()
			while true do
				task.wait(1)

				local now = os.clock()
				local elapsed = math.max(now - lastSampleTime, 1e-4)
				lastSampleTime = now

				local currentFps = math.round(frameCount / elapsed)
				frameCount = 0

				local ping = if localPlayer then math.max(0, math.round(localPlayer:GetNetworkPing() * 1000)) else 0

				local currentLabel = label
				if currentLabel then
					currentLabel.Text = string.format("FPS: %d | Ping: %d ms | Region: %s", currentFps, ping, serverRegion)
				end
			end
		end)
	end
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

	frameCount = 0
end

return StatisticsTracker
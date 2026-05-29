--!strict
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerScriptService = game:GetService("ServerScriptService")

-- Service requirements
local DataManager = require(ServerScriptService.services.DataManager)
local SettingsServer = require(ServerScriptService.services.SettingsServer)
local RegionTracker = require(ServerScriptService.services.RegionTracker)
local ServerOptimization = require(ServerScriptService.services.ServerOptimization)
local Types = require(ReplicatedStorage.Shared.Types)

-- Explicitly targeting the Blink server network module
local Blink = require(ReplicatedStorage.Shared.Blink.network_server)

local ACTION_COOLDOWN = 0.1
local lastRequestTimes: { [Player]: number } = {}

-- Initialize optimizations module
ServerOptimization.Init()

-- Listen for client setting updates
Blink.UpdateSettings.On(function(player: Player, data: any)
	local now = os.clock()
	local lastTime = lastRequestTimes[player] or 0

	if now - lastTime < ACTION_COOLDOWN then
		return
	end

	lastRequestTimes[player] = now

	if typeof(data) == "table" then
		SettingsServer.ProcessUpdate(player, data)
	end
end)

-- Send initial profile sync settings and server region on join
local function handlePlayerSync(player: Player)
	task.spawn(function()
		local profile = DataManager:GetProfile(player)
		local retries = 0

		while not profile and retries < 20 do
			task.wait(0.5)
			profile = DataManager:GetProfile(player)
			retries += 1
		end

		if profile then
			-- Replicate profile configurations
			Blink.SyncSettings.Fire(player, profile.Data.Settings)
			
			-- Replicate verified server physical location to client
			Blink.SyncRegion.Fire(player, RegionTracker.GetRegion())
		end
	end)
end

Players.PlayerAdded:Connect(handlePlayerSync)
Players.PlayerRemoving:Connect(function(player)
	lastRequestTimes[player] = nil
end)

for _, player in ipairs(Players:GetPlayers()) do
	task.spawn(handlePlayerSync, player)
end
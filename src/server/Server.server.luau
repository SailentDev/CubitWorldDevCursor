--!strict
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerScriptService = game:GetService("ServerScriptService")

local DataManager = require(ServerScriptService.services.DataManager)
local SettingsServer = require(ServerScriptService.services.SettingsServer)
local Types = require(ReplicatedStorage.Shared.Types)

local Blink = require(ReplicatedStorage.Shared.Blink.network_server)

-- Reduced global cooldown to accommodate fast sequential slider adjustments
local ACTION_COOLDOWN = 0.1
local lastRequestTimes: { [Player]: number } = {}

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
			Blink.SyncSettings.Fire(player, profile.Data.Settings)
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
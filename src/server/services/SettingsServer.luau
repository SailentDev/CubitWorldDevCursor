--!strict
--!native
local Players = game:GetService("Players")
local ServerScriptService = game:GetService("ServerScriptService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Types = require(ReplicatedStorage.Shared.Types)
local DataManager = require(ServerScriptService.services.DataManager)
local Blink = require(ReplicatedStorage.Shared.Blink.network_server)

local SettingsServer = {}

local MIN_FOV = 30
local MAX_FOV = 120
local MIN_VOLUME = 0
local MAX_VOLUME = 100

local playerDebounceThreads: { [Player]: thread? } = {}

local function isNaN(value: number): boolean
	return value ~= value
end

function SettingsServer.ProcessUpdate(player: Player, incomingData: Types.SettingsUpdate)
	local profile = DataManager:GetProfile(player)
	if not profile then
		return
	end

	local currentSettings = profile.Data.Settings
	local dataChanged = false

	if incomingData.FOV ~= nil then
		local incomingFOV = incomingData.FOV
		if typeof(incomingFOV) == "number" and not isNaN(incomingFOV) then
			local clamped = math.clamp(incomingFOV, MIN_FOV, MAX_FOV)
			if currentSettings.FOV ~= clamped then
				currentSettings.FOV = clamped
				dataChanged = true
			end
		end
	end

	if incomingData.MusicVol ~= nil then
		local incomingVol = incomingData.MusicVol
		if typeof(incomingVol) == "number" and not isNaN(incomingVol) then
			local clamped = math.clamp(incomingVol, MIN_VOLUME, MAX_VOLUME)
			if currentSettings.MusicVol ~= clamped then
				currentSettings.MusicVol = clamped
				dataChanged = true
			end
		end
	end

	if incomingData.ShowFPS ~= nil then
		local incomingFPS = incomingData.ShowFPS
		if typeof(incomingFPS) == "boolean" then
			if currentSettings.ShowFPS ~= incomingFPS then
				currentSettings.ShowFPS = incomingFPS
				dataChanged = true
			end
		end
	end

	if incomingData.GlobalShadows ~= nil then
		local incomingShadows = incomingData.GlobalShadows
		if typeof(incomingShadows) == "boolean" then
			if currentSettings.GlobalShadows ~= incomingShadows then
				currentSettings.GlobalShadows = incomingShadows
				dataChanged = true
			end
		end
	end

	if dataChanged then
		if playerDebounceThreads[player] then
			task.cancel(playerDebounceThreads[player] :: thread)
		end

		-- Cancel thread and push sync back down to the client after visual updates settle
		playerDebounceThreads[player] = task.delay(0.2, function()
			playerDebounceThreads[player] = nil
			if player.Parent then
				Blink.SyncSettings.Fire(player, currentSettings)
			end
		end)
	end
end

Players.PlayerRemoving:Connect(function(player)
	if playerDebounceThreads[player] then
		task.cancel(playerDebounceThreads[player] :: thread)
		playerDebounceThreads[player] = nil
	end
end)

return SettingsServer
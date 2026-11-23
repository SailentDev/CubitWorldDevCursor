--!strict
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerScriptService = game:GetService("ServerScriptService")

local Blink = require(ReplicatedStorage.Shared.Blink.network_server)
local DataManager = require(ServerScriptService.services.DataManager)
local RateLimiter = require(ServerScriptService.Util.RateLimiter)
local Types = require(ReplicatedStorage.Shared.Types)

local SettingsServer = {}

local MIN_FOV = 30
local MAX_FOV = 120
local MIN_VOLUME = 0
local MAX_VOLUME = 100
local SYNC_DEBOUNCE_SECONDS = 0.2

local MAX_BUCKET_TOKENS = 12
local REFILL_TOKENS_PER_SEC = 8

local playerDebounceThreads: { [Player]: thread } = {}
local rateLimiter = RateLimiter.new(MAX_BUCKET_TOKENS, REFILL_TOKENS_PER_SEC)

local function isFiniteNumber(value: unknown): boolean
	return typeof(value) == "number" and value == value and math.abs(value) < math.huge
end

local function buildSyncPayload(settings: Types.Settings): {
	FOV: number?,
	MusicVol: number?,
	ShowFPS: boolean?,
	GlobalShadows: boolean,
}
	return {
		FOV = settings.FOV,
		MusicVol = settings.MusicVol,
		ShowFPS = settings.ShowFPS,
		GlobalShadows = settings.GlobalShadows,
	}
end

function SettingsServer.ProcessUpdate(player: Player, incomingData: Types.SettingsUpdate): ()
	local profile = DataManager:GetProfile(player)
	if not profile then
		return
	end

	local currentSettings = profile.Data.Settings
	local dataChanged = false

	local incomingFOV = incomingData.FOV
	if incomingFOV ~= nil and isFiniteNumber(incomingFOV) then
		local clamped = math.round(math.clamp(incomingFOV, MIN_FOV, MAX_FOV))
		if currentSettings.FOV ~= clamped then
			currentSettings.FOV = clamped
			dataChanged = true
		end
	end

	local incomingVol = incomingData.MusicVol
	if incomingVol ~= nil and isFiniteNumber(incomingVol) then
		local clamped = math.round(math.clamp(incomingVol, MIN_VOLUME, MAX_VOLUME))
		if currentSettings.MusicVol ~= clamped then
			currentSettings.MusicVol = clamped
			dataChanged = true
		end
	end

	local incomingFPS = incomingData.ShowFPS
	if incomingFPS ~= nil and typeof(incomingFPS) == "boolean" then
		if currentSettings.ShowFPS ~= incomingFPS then
			currentSettings.ShowFPS = incomingFPS
			dataChanged = true
		end
	end

	local incomingShadows = incomingData.GlobalShadows
	if incomingShadows ~= nil and typeof(incomingShadows) == "boolean" then
		if currentSettings.GlobalShadows ~= incomingShadows then
			currentSettings.GlobalShadows = incomingShadows
			dataChanged = true
		end
	end

	if dataChanged then
		local existingThread = playerDebounceThreads[player]
		if existingThread then
			task.cancel(existingThread)
		end

		playerDebounceThreads[player] = task.delay(SYNC_DEBOUNCE_SECONDS, function()
			playerDebounceThreads[player] = nil
			if player:IsDescendantOf(Players) then
				Blink.SyncSettings.Fire(player, buildSyncPayload(currentSettings))
			end
		end)
	end
end

function SettingsServer.OnInit(): ()
end

function SettingsServer.OnStart(): ()
	Blink.UpdateSettings.On(function(player: Player, data: Types.SettingsUpdate)
		if typeof(data) ~= "table" then
			return
		end

		if not rateLimiter:Consume(player) then
			return
		end

		SettingsServer.ProcessUpdate(player, data)
	end)

	Players.PlayerRemoving:Connect(function(player: Player)
		local pendingThread = playerDebounceThreads[player]
		if pendingThread then
			task.cancel(pendingThread)
			playerDebounceThreads[player] = nil
		end
		rateLimiter:Clear(player)
	end)
end

return SettingsServer
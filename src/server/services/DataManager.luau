--!strict
local Players = game:GetService("Players")
local ServerScriptService = game:GetService("ServerScriptService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local ProfileStore = require(ServerScriptService.services.ProfileStore)
local Types = require(ReplicatedStorage.Shared.Types)

-- Moduły wymagane do synchronizacji sieciowej i regionu
local RegionTracker = require(ServerScriptService.services.RegionTracker)
local Blink = require(ReplicatedStorage.Shared.Blink.network_server)

local DataManager = {}

local DEFAULT_DATA: Types.ProfileData = {
	Coins = 0,
	Pets = {} :: { string },
	Settings = {
		FOV = 70,
		MusicVol = 50,
		ShowFPS = false,
		GlobalShadows = true,
	},
}

-- Strongly type activeProfiles using ProfileStore's generic profile structure
local activeProfiles: { [Player]: ProfileStore.Profile<Types.ProfileData> } = {}
-- Cast to any here to satisfy ProfileStore's strict serializability constraint
local profileStore: ProfileStore.ProfileStore<Types.ProfileData> = ProfileStore.New("Production_PlayerProfiles_v1", DEFAULT_DATA :: any)

local function onPlayerAdded(player: Player)
	local profileKey = "Player_" .. player.UserId
	local profile = profileStore:StartSessionAsync(profileKey, {})

	if profile then
		if player.Parent then
			activeProfiles[player] = profile

			-- Synchronizacja sieciowa i regionu przy wejściu gracza (with boundary cast)
			Blink.SyncSettings.Fire(player, profile.Data.Settings :: any)
			Blink.SyncRegion.Fire(player, RegionTracker.GetRegion())

			profile.OnSessionEnd:Connect(function()
				activeProfiles[player] = nil
				if player:IsDescendantOf(Players) then
					player:Kick("Your data profile session has been released on the backend.")
				end
			end)
		else
			profile:EndSession() 
		end
	else
		player:Kick("Failed to initialize profile data session.")
	end
end

local function onPlayerRemoving(player: Player)
	local profile = activeProfiles[player]
	if profile then
		activeProfiles[player] = nil
		profile:EndSession()
	end
end

function DataManager:GetProfile(player: Player): ProfileStore.Profile<Types.ProfileData>?
	return activeProfiles[player]
end

-- Funkcje dla Loader'a
function DataManager.OnInit()
	-- Przygotowanie modułu (puste, ale potrzebne dla architektury)
end

function DataManager.OnStart()
	Players.PlayerAdded:Connect(onPlayerAdded)
	Players.PlayerRemoving:Connect(onPlayerRemoving)

	for _, player in ipairs(Players:GetPlayers()) do
		task.spawn(onPlayerAdded, player)
	end

	game:BindToClose(function()
		for player, profile in pairs(activeProfiles) do
			task.spawn(function()
				profile:EndSession()
			end)
		end
	end)
end

return DataManager
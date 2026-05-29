--!strict
local Players = game:GetService("Players")
local ServerScriptService = game:GetService("ServerScriptService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local ProfileStore = require(ServerScriptService.services.ProfileStore)
local Types = require(ReplicatedStorage.Shared.Types)

local DataManager = {}

local DEFAULT_DATA: Types.ProfileData = {
	Coins = 0,
	Pets = {},
	Settings = {
		FOV = 70,
		MusicVol = 50,
		ShowFPS = false,
		GlobalShadows = true,
	},
}

local activeProfiles: { [Player]: any } = {}
local profileStore = ProfileStore.New("Production_PlayerProfiles_v1", DEFAULT_DATA)

local function onPlayerAdded(player: Player)
	local profileKey = "Player_" .. player.UserId
	local profile = profileStore:StartSessionAsync(profileKey)

	if profile then
		if player.Parent then
			activeProfiles[player] = profile

			-- POPRAWIONE: Wykorzystujemy właściwy dla Twojej wersji sygnał zakończenia sesji
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

function DataManager:GetProfile(player: Player): any
	return activeProfiles[player]
end

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

return DataManager
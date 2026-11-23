--!strict
local HttpService = game:GetService("HttpService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local ServerScriptService = game:GetService("ServerScriptService")

local Blink = require(ReplicatedStorage.Shared.Blink.network_server)
local PetDatabase = require(ReplicatedStorage.Shared.PetDatabase)
local Types = require(ReplicatedStorage.Shared.Types)

local ProfileStore = require(ServerScriptService.services.ProfileStore)
local RegionTracker = require(ServerScriptService.services.RegionTracker)

local DataManager = {}

type ProfileEventCallback = (player: Player, profile: Types.PlayerProfile) -> ()

local CURRENT_DATA_VERSION = 1
local STARTING_COINS = 0 -- Set to 500+ locally if testing shop purchases without a coin source
local PROFILE_STORE_NAME = "Production_PlayerProfiles_v98989823"
local ACTIVE_STORE_NAME = if RunService:IsStudio()
	then PROFILE_STORE_NAME .. "_Studio"
	else PROFILE_STORE_NAME

local DEFAULT_DATA: Types.ProfileData = {
	DataVersion = CURRENT_DATA_VERSION,
	Coins = STARTING_COINS,
	Pets = {},
	Eggs = {},
	EquippedPets = {},
	Settings = {
		FOV = 70,
		MusicVol = 50,
		ShowFPS = false,
		GlobalShadows = true,
	},
}

local activeProfiles: { [Player]: Types.PlayerProfile } = {}
local readyPlayers: { [Player]: boolean } = {}
local syncedPlayers: { [Player]: boolean } = {}
local pendingInitialSync: { [Player]: boolean } = {}
local profileLoadedCallbacks: { ProfileEventCallback } = {}
local initialSyncCallbacks: { ProfileEventCallback } = {}

local profileStore = ProfileStore.New(ACTIVE_STORE_NAME, DEFAULT_DATA)

local function migrateProfileData(rawData: { [string]: unknown }): ()
	local dataVersion = if typeof(rawData.DataVersion) == "number" then rawData.DataVersion else 0

	if dataVersion < 1 then
		local rawPets = rawData.Pets
		if typeof(rawPets) == "table" then
			local petsTable = rawPets :: { [string]: unknown }
			local oldPetsToMigrate: { [string]: number } = {}

			for key, value in petsTable do
				if typeof(value) == "number" then
					oldPetsToMigrate[tostring(key)] = math.max(0, math.floor(value))
				elseif typeof(value) == "table" then
					local petEntry = value :: { [string]: unknown }
					if petEntry.petName == nil then
						local amount = if typeof(petEntry.amount) == "number" then math.max(0, math.floor(petEntry.amount)) else 1
						oldPetsToMigrate[tostring(key)] = amount
					end
				end
			end

			for petName, amount in oldPetsToMigrate do
				petsTable[petName] = nil
				if PetDatabase.GetPetInfo(petName) then
					for _ = 1, amount do
						local newUUID = HttpService:GenerateGUID(false)
						petsTable[newUUID] = {
							petName = petName,
							level = 1,
						}
					end
				end
			end

			-- Drop unregistered legacy pet IDs rather than granting invalid or high-tier defaults
			for petUUID, petEntry in petsTable do
				if typeof(petEntry) == "table" then
					local typedEntry = petEntry :: { [string]: unknown }
					local petName = typedEntry.petName
					if typeof(petName) ~= "string" or not PetDatabase.GetPetInfo(petName) then
						petsTable[petUUID] = nil
					end
				else
					petsTable[petUUID] = nil
				end
			end
		end

		rawData.DataVersion = 1
	end
end

local function runInitialSyncCallback(callback: ProfileEventCallback, player: Player, profile: Types.PlayerProfile): ()
	local success, err = pcall(callback, player, profile)
	if not success then
		warn(`[DataManager] OnInitialSync callback error for {player.Name}: {tostring(err)}`)
	end
end

function DataManager.OnProfileLoaded(callback: ProfileEventCallback): ()
	table.insert(profileLoadedCallbacks, callback)
end

function DataManager.OnInitialSync(callback: ProfileEventCallback): ()
	table.insert(initialSyncCallbacks, callback)
end

function DataManager:GetProfile(player: Player): Types.PlayerProfile?
	local profile = activeProfiles[player]
	if profile and profile:IsActive() then
		return profile
	end
	return nil
end

function DataManager:SyncPlayerData(player: Player): ()
	if syncedPlayers[player] then
		return
	end

	if not readyPlayers[player] then
		if player:IsDescendantOf(Players) then
			pendingInitialSync[player] = true
		end
		return
	end

	local profile = DataManager:GetProfile(player)
	if not profile then
		return
	end

	syncedPlayers[player] = true
	pendingInitialSync[player] = nil

	local settingsData = profile.Data.Settings
	Blink.SyncSettings.Fire(player, {
		FOV = settingsData.FOV,
		MusicVol = settingsData.MusicVol,
		ShowFPS = settingsData.ShowFPS,
		GlobalShadows = settingsData.GlobalShadows,
	})

	Blink.SyncRegion.Fire(player, RegionTracker.GetRegion())

	Blink.SyncCurrency.Fire(player, {
		currencyType = "Coins",
		value = profile.Data.Coins or 0,
	})

	for eggName, amount in profile.Data.Eggs do
		if amount > 0 then
			Blink.SyncEggs.Fire(player, {
				eggName = eggName,
				amount = amount,
			})
		end
	end

	for petUUID, petData in profile.Data.Pets do
		Blink.SyncPets.Fire(player, {
			isRemoved = false,
			level = petData.level or 1,
			petName = petData.petName,
			uuid = petUUID,
		})
	end

	for _, callback in initialSyncCallbacks do
		task.spawn(runInitialSyncCallback, callback, player, profile)
	end
end

local function onPlayerAdded(player: Player): ()
	local profileKey = "Player_" .. tostring(player.UserId)
	local rawProfile = profileStore:StartSessionAsync(profileKey, {})

	if not rawProfile then
		if player:IsDescendantOf(Players) then
			player:Kick("Unable to load your player data. Please rejoin.")
		end
		return
	end

	if not player:IsDescendantOf(Players) then
		rawProfile:EndSession()
		return
	end

	local profile = (rawProfile :: unknown) :: Types.PlayerProfile
	profile:AddUserId(player.UserId)
	migrateProfileData((profile.Data :: unknown) :: { [string]: unknown })
	profile:Reconcile()

	activeProfiles[player] = profile

	profile.OnSessionEnd:Connect(function()
		activeProfiles[player] = nil
		readyPlayers[player] = nil
		syncedPlayers[player] = nil
		pendingInitialSync[player] = nil

		if player:IsDescendantOf(Players) then
			player:Kick("Your session was ended on this server.")
		end
	end)

	for _, callback in profileLoadedCallbacks do
		local success, err = pcall(callback, player, profile)
		if not success then
			warn(`[DataManager] OnProfileLoaded callback error for {player.Name}: {tostring(err)}`)
		end
	end

	if not player:IsDescendantOf(Players) or activeProfiles[player] ~= profile or not profile:IsActive() then
		return
	end

	readyPlayers[player] = true

	if pendingInitialSync[player] then
		DataManager:SyncPlayerData(player)
	end
end

local function onPlayerRemoving(player: Player): ()
	readyPlayers[player] = nil
	syncedPlayers[player] = nil
	pendingInitialSync[player] = nil

	local profile = activeProfiles[player]
	if profile then
		activeProfiles[player] = nil
		profile:EndSession()
	end
end

function DataManager.OnInit(): ()
end

function DataManager.OnStart(): ()
	Players.PlayerAdded:Connect(onPlayerAdded)
	Players.PlayerRemoving:Connect(onPlayerRemoving)

	Blink.RequestInitialSync.On(function(player: Player)
		if syncedPlayers[player] then
			return
		end

		if readyPlayers[player] then
			DataManager:SyncPlayerData(player)
		elseif player:IsDescendantOf(Players) then
			pendingInitialSync[player] = true
		end
	end)

	RegionTracker.OnRegionResolved(function(resolvedRegion: string)
		for player, _ in syncedPlayers do
			if player:IsDescendantOf(Players) then
				Blink.SyncRegion.Fire(player, resolvedRegion)
			end
		end
	end)

	for _, player in Players:GetPlayers() do
		task.spawn(onPlayerAdded, player)
	end
end

return DataManager
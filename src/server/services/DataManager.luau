--!strict
local Players = game:GetService("Players")
local ServerScriptService = game:GetService("ServerScriptService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local HttpService = game:GetService("HttpService")

local ProfileStore = require(ServerScriptService.services.ProfileStore)
local Types = require(ReplicatedStorage.Shared.Types)

local PetDatabase = require(ReplicatedStorage.Shared.PetDatabase)
local RegionTracker = require(ServerScriptService.services.RegionTracker)
local Blink = require(ReplicatedStorage.Shared.Blink.network_server)

local DataManager = {}

local CURRENT_DATA_VERSION = 1

local DEFAULT_DATA: Types.ProfileData = {
	DataVersion = CURRENT_DATA_VERSION,
	Coins = 99999999,
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

local activeProfiles: { [Player]: any } = {}
local profileStore = ProfileStore.New("Production_PlayerProfiles_v98989823", DEFAULT_DATA)

-- ==================== MIGROWANIE DANYCH ====================
local function MigrateProfileData(data: any)
	if not data.DataVersion then
		data.DataVersion = 0
	end

	if data.DataVersion < 1 then
		if data.Pets then
			local oldPetsToMigrate: { [string]: number } = {}
			
			for key, value in pairs(data.Pets) do
				if type(value) == "number" or (type(value) == "table" and value.petName == nil) then
					local petName = tostring(key)
					local amount = type(value) == "number" and value or (value.amount or 1)
					oldPetsToMigrate[petName] = amount
				end
			end
			
			for petName, amount in pairs(oldPetsToMigrate) do
				data.Pets[petName] = nil 
				for i = 1, amount do
					local newUUID = HttpService:GenerateGUID(false)
					data.Pets[newUUID] = {
						petName = petName,
						level = 1
					}
				end
			end
			
			for petUUID, petData in pairs(data.Pets) do
				if type(petData) == "table" and petData.petName then
					local petInfo = PetDatabase.GetPetInfo(petData.petName)
					if not petInfo then
						petData.petName = "Pyrodon"
					end
				end
			end
		end
		data.DataVersion = 1
	end
end

-- ==================== SYNCHRONIZACJA DANYCH ====================
function DataManager:SyncPlayerData(player: Player)
	local profile = activeProfiles[player]
	if not profile then return end

	print(string.format("[DATA -> SYNC] Synchronizacja danych dla: %s", player.Name))

	-- 1. Wysyłamy dane do gracza, który dołączył
	Blink.SyncSettings.Fire(player, profile.Data.Settings)
	Blink.SyncRegion.Fire(player, RegionTracker.GetRegion(player))
	
	Blink.SyncCurrency.Fire(player, {
		currencyType = "Coins",
		value = profile.Data.Coins or 0
	})

	if profile.Data.Eggs then
		for eggName, amount in pairs(profile.Data.Eggs) do
			Blink.SyncEggs.Fire(player, {
				eggName = eggName,
				amount = amount
			})
		end
	end
	
	if profile.Data.Pets then
		for petUUID, petData in pairs(profile.Data.Pets) do
			Blink.SyncPets.Fire(player, {
				isRemoved = false,
				level = petData.level or 1,
				petName = petData.petName,
				uuid = petUUID
			})
		end
	end

	-- 2. Synchronizujemy pety WSZYSTKICH graczy na serwerze dla nowego gracza
	for _, otherPlayer in ipairs(Players:GetPlayers()) do
		local otherProfile = activeProfiles[otherPlayer]
		if otherProfile and otherProfile.Data.EquippedPets then
			local equippedPetsData = {}
			for _, uuid in ipairs(otherProfile.Data.EquippedPets) do
				local petData = otherProfile.Data.Pets[uuid]
				if petData then
					table.insert(equippedPetsData, {
						uuid = uuid,
						petName = petData.petName
					})
				end
			end

			Blink.SyncEquippedPets.Fire(player, {
				userId = otherPlayer.UserId,
				equippedPets = equippedPetsData
			})
		end
	end
end

-- ==================== CYKL ŻYCIA GRACZA ====================
local function onPlayerAdded(player: Player)
	print(string.format("[DATA -> SESSION] Rozpoczynam wczytywanie profilu: %s", player.Name))
	local profileKey = "Player_" .. player.UserId
	local profile = profileStore:StartSessionAsync(profileKey, {})

	if profile then
		if player.Parent then
			profile:Reconcile()
			MigrateProfileData(profile.Data)

			activeProfiles[player] = profile
			print(string.format("[DATA -> SUCCESS] Profil gracza %s załadowany!", player.Name))

			profile.OnSessionEnd:Connect(function()
				print(string.format("[DATA -> RELEASE] Sesja zakończona dla: %s", player.Name))
				activeProfiles[player] = nil
				if player:IsDescendantOf(Players) then
					player:Kick("Twoja sesja została zamknięta na serwerze.")
				end
			end)
		else
			profile:EndSession() 
		end
	else
		player:Kick("Nie udało się pobrać danych profilu.")
	end
end

local function onPlayerRemoving(player: Player)
	local profile = activeProfiles[player]
	if profile then
		activeProfiles[player] = nil
		profile:EndSession()
		print(string.format("[DATA -> REMOVING SUCCESS] Zakończono sesję dla: %s", player.Name))
	end
end

function DataManager:GetProfile(player: Player): any
	return activeProfiles[player]
end

function DataManager.OnInit()
	print("[DATA] DataManager.OnInit uruchomiony.")
end

function DataManager.OnStart()
	Players.PlayerAdded:Connect(onPlayerAdded)
	Players.PlayerRemoving:Connect(onPlayerRemoving)

	-- Nasłuchiwanie Blink z użyciem metody .On()
	Blink.RequestInitialSync.On(function(player: Player)
		local timeout = 5
		local startTime = os.clock()
		while not DataManager:GetProfile(player) and player.Parent and (os.clock() - startTime) < timeout do
			task.wait(0.1)
		end
		DataManager:SyncPlayerData(player)
	end)

	for _, player in ipairs(Players:GetPlayers()) do
		task.spawn(onPlayerAdded, player)
	end

	-- BEZPIECZNE ZAMYKANIE SERWERA
	game:BindToClose(function()
		print("[DATA] Zamykanie serwera - trwa zapisywanie danych graczy...")
		for player, profile in pairs(activeProfiles) do
			task.spawn(function()
				profile:EndSession()
			end)
		end

		local timeout = 10
		local startTime = os.clock()
		while next(activeProfiles) ~= nil and (os.clock() - startTime) < timeout do
			task.wait(0.1)
		end
		print("[DATA] Wszystkie dane zostały bezpiecznie zapisane w DataStore.")
	end)
end

return DataManager
--!strict
local Players = game:GetService("Players")
local ServerScriptService = game:GetService("ServerScriptService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local HttpService = game:GetService("HttpService")

local ProfileStore = require(ServerScriptService.services.ProfileStore)
local Types = require(ReplicatedStorage.Shared.Types)

local PetDatabase = require(ReplicatedStorage.Shared:WaitForChild("PetDatabase") :: ModuleScript)
local RegionTracker = require(ServerScriptService.services.RegionTracker)
local Blink = require(ReplicatedStorage.Shared.Blink.network_server)

local DataManager = {}

local DEFAULT_DATA: Types.ProfileData = {
	Coins = 999999999,
	Pets = {},
	Eggs = {},
	EquippedPets = {}, -- NAPRAWIONE: Zabezpieczenie przed nil dla nowych profilów
	Settings = {
		FOV = 70,
		MusicVol = 50,
		ShowFPS = false,
		GlobalShadows = true,
	},
}

local activeProfiles: { [Player]: any } = {}
local profileStore = ProfileStore.New("Production_PlayerProfiles_v99999", DEFAULT_DATA)

-- ==================== BEZPIECZNA SYNCHRONIZACJA NA ŻĄDANIE KLIENTA ====================
function DataManager:SyncPlayerData(player: Player)
	local profile = activeProfiles[player]
	if not profile then return end

	print(string.format("[DATA -> SYNC] Klient %s jest gotowy. Wysyłam pakiety danych...", player.Name))

	-- Podstawowe systemy
	Blink.SyncSettings.Fire(player, profile.Data.Settings)
	Blink.SyncRegion.Fire(player, RegionTracker.GetRegion())
	
	-- Portfel
	local startCoins = profile.Data.Coins or 0
	Blink.SyncCurrency.Fire(player, {
		currencyType = "Coins",
		value = startCoins
	})

	-- Jajka
	if profile.Data.Eggs then
		for eggName, amount in pairs(profile.Data.Eggs) do
			Blink.SyncEggs.Fire(player, {
				eggName = eggName,
				amount = amount
			})
		end
	end
	
	-- Pety (Ekwipunek)
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

	-- NAPRAWIONE: Mapowanie UUID na strukturę akceptowaną przez nowy event Blink!
	local equippedPetsData = {}
	if profile.Data.EquippedPets then
		for _, uuid in ipairs(profile.Data.EquippedPets) do
			local petData = profile.Data.Pets[uuid]
			if petData then
				table.insert(equippedPetsData, {
					uuid = uuid,
					petName = petData.petName
				})
			end
		end
	end

	Blink.SyncEquippedPets.FireAll({
		userId = player.UserId,
		equippedPets = equippedPetsData -- Zgodne z nowym .blink (equippedPets zamiast equippedUUIDs)
	})
	
	print(string.format("[DATA -> SYNC SUCCESS] Zsynchronizowano pomyślnie gracza %s", player.Name))
end

local function onPlayerAdded(player: Player)
	print(string.format("[DATA -> SESSION] Gracz %s dołączył. Rozpoczynam wczytywanie profilu...", player.Name))
	local profileKey = "Player_" .. player.UserId
	local profile = profileStore:StartSessionAsync(profileKey)

	if profile then
		if player.Parent then
			activeProfiles[player] = profile
			print(string.format("[DATA -> SUCCESS] Profil gracza %s załadowany pomyślnie!", player.Name))

			-- Zapewnienie stałej struktury tabeli EquippedPets
			if not profile.Data.EquippedPets then
				profile.Data.EquippedPets = {}
			end

			-- ==================== MIGROWANIE I NAPRAWA DANYCH (TYLKO NA SERWERZE) ====================
			if profile.Data.Pets then
				local oldPetsToMigrate = {}
				
				for key, value in pairs(profile.Data.Pets) do
					if type(value) == "number" or (type(value) == "table" and value.petName == nil) then
						local petName = key
						local amount = 1
						if type(value) == "number" then
							amount = value
						elseif type(value) == "table" then
							amount = value.amount or 1
						end
						oldPetsToMigrate[petName] = amount
					end
				end
				
				for petName, amount in pairs(oldPetsToMigrate) do
					profile.Data.Pets[petName] = nil 
					for i = 1, amount do
						local newUUID = HttpService:GenerateGUID(false)
						profile.Data.Pets[newUUID] = {
							petName = petName,
							level = 1
						}
					end
				end
				
				for petUUID, petData in pairs(profile.Data.Pets) do
					if type(petData) == "table" and petData.petName then
						local petInfo = PetDatabase.GetPetInfo(petData.petName)
						if not petInfo then
							petData.petName = "Pyrodon"
						end
					end
				end
			end
			-- ==================================================================================

			profile.OnSessionEnd:Connect(function()
				print(string.format("[DATA -> RELEASE] Sesja profilu gracza %s została zakończona.", player.Name))
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
		print(string.format("[DATA -> REMOVING SUCCESS] Zakończono sesję dla %s", player.Name))
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

	local remote = Instance.new("RemoteEvent")
	remote.Name = "RequestInitialSync"
	remote.Parent = ReplicatedStorage

	remote.OnServerEvent:Connect(function(player)
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

	game:BindToClose(function()
		for player, profile in pairs(activeProfiles) do
			task.spawn(function()
				profile:EndSession()
			end)
		end
	end)
end

return DataManager
--!strict
local Players = game:GetService("Players")
local ServerScriptService = game:GetService("ServerScriptService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local HttpService = game:GetService("HttpService")

local ProfileStore = require(ServerScriptService.services.ProfileStore)
local Types = require(ReplicatedStorage.Shared.Types)

-- Import bazy danych petów do weryfikacji nazw
local PetDatabase = require(ReplicatedStorage.Shared:WaitForChild("PetDatabase") :: ModuleScript)
local RegionTracker = require(ServerScriptService.services.RegionTracker)
local Blink = require(ReplicatedStorage.Shared.Blink.network_server)

local DataManager = {}

local DEFAULT_DATA: Types.ProfileData = {
	Coins = 999999999,
	Pets = {},
	Eggs = {},
	Settings = {
		FOV = 70,
		MusicVol = 50,
		ShowFPS = false,
		GlobalShadows = true,
	},
}

local activeProfiles: { [Player]: any } = {}
local profileStore = ProfileStore.New("Production_PlayerProfiles_v99999", DEFAULT_DATA)

local function onPlayerAdded(player: Player)
	print(string.format("[DATA -> SESSION] Gracz %s dołączył. Rozpoczynam wczytywanie profilu...", player.Name))
	local profileKey = "Player_" .. player.UserId
	local profile = profileStore:StartSessionAsync(profileKey)

	if profile then
		if player.Parent then
			activeProfiles[player] = profile
			print(string.format("[DATA -> SUCCESS] Profil gracza %s załadowany pomyślnie!", player.Name))

			-- ==================== SYNCHRONIZACJA NA WEJŚCIE ====================
			Blink.SyncSettings.Fire(player, profile.Data.Settings)
			Blink.SyncRegion.Fire(player, RegionTracker.GetRegion())
			
			-- NOWOŚĆ: Synchronizacja stanu portfela na start, żeby klient od razu widział kasę
			local startCoins = profile.Data.Coins or 0
			Blink.SyncCurrency.Fire(player, {
				currencyType = "Coins",
				value = startCoins
			})
			print(string.format("[DATA -> INITIAL SYNC] Wysłano stan portfela dla %s: Coins x%d", player.Name, startCoins))

			-- Synchronizacja zapisanego ekwipunku jajek po wejściu do gry
			if profile.Data.Eggs then
				for eggName, amount in pairs(profile.Data.Eggs) do
					Blink.SyncEggs.Fire(player, {
						eggName = eggName,
						amount = amount
					})
					print(string.format("[DATA -> INITIAL SYNC] Wysłano stan jajka z bazy dla %s: %s x%d", player.Name, eggName, amount))
				end
			end
			
			-- ==================== SYNCHRONIZACJA I NAPRAWA UNIKALNYCH PETÓW ====================
			if profile.Data.Pets then
				local oldPetsToMigrate = {}
				
				-- KROK 1: Wykrywanie starych formatów danych (zapis ilościowy zamiast słownika UUID)
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
				
				-- KROK 2: Automatyczna migracja (zamiana starych danych na instancje UUID)
				for petName, amount in pairs(oldPetsToMigrate) do
					profile.Data.Pets[petName] = nil 
					for i = 1, amount do
						local newUUID = HttpService:GenerateGUID(false)
						profile.Data.Pets[newUUID] = {
							petName = petName,
							level = 1
						}
						print(string.format("[DATA -> MIGRATION] Przekonwertowano stary zapis %s na unikalne UUID: %s", petName, newUUID))
					end
				end
				
				-- KROK 2.5: SYSTEM AUTONAPRAWY SKAŻONYCH DANYCH (Nowość!)
				-- Jeśli nazwa peta nie istnieje w PetDatabase (bo jest dziwnym ciągiem znaków), naprawiamy ją na "Pyrodon"
				for petUUID, petData in pairs(profile.Data.Pets) do
					if type(petData) == "table" and petData.petName then
						local petInfo = PetDatabase.GetPetInfo(petData.petName)
						if not petInfo then
							warn(string.format("[DATA -> SELF HEAL] Wykryto skażoną nazwę peta '%s' pod UUID %s. Przywracanie poprawnej nazwy: 'Pyrodon'!", tostring(petData.petName), petUUID))
							petData.petName = "Pyrodon" -- Tutaj podstawiamy realną nazwę z Twojej gry
						end
					end
				end
				
				-- KROK 3: Prawidłowa wysyłka przefiltrowanych i bezpiecznych petów do klienta
				for petUUID, petData in pairs(profile.Data.Pets) do
					Blink.SyncPets.Fire(player, {
						isRemoved = false,
						level = petData.level or 1,
						petName = petData.petName,
						uuid = petUUID
					})
					print(string.format("[DATA -> INITIAL SYNC] Wysłano unikalnego peta dla %s: %s (Lvl %d) | UUID: %s", player.Name, petData.petName, petData.level or 1, petUUID))
				end
			end
			-- ==================================================================================
			
			print(string.format("[DATA -> BLINK] Wysłano wszystkie startowe pakiety synchronizacji dla %s", player.Name))

			profile.OnSessionEnd:Connect(function()
				print(string.format("[DATA -> RELEASE] Sesja profilu gracza %s została zakończona przez backend.", player.Name))
				activeProfiles[player] = nil
				if player:IsDescendantOf(Players) then
					player:Kick("Your data profile session has been released on the backend.")
				end
			end)
		else
			print(string.format("[DATA -> ABORT] Gracz %s wyszedł zanim profil się załadował. Zamykam sesję.", player.Name))
			profile:EndSession() 
		end
	else
		warn(string.format("[DATA -> CRITICAL] Błąd krytyczny! Nie udało się załadować profilu dla %s", player.Name))
		player:Kick("Failed to initialize profile data session.")
	end
end

local function onPlayerRemoving(player: Player)
	print(string.format("[DATA -> REMOVING] Gracz %s opuszcza grę. Zapisuję i zamykam sesję...", player.Name))
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
	print("[DATA] DataManager.OnStart podłącza eventy graczy.")
	Players.PlayerAdded:Connect(onPlayerAdded)
	Players.PlayerRemoving:Connect(onPlayerRemoving)

	for _, player in ipairs(Players:GetPlayers()) do
		task.spawn(onPlayerAdded, player)
	end

	game:BindToClose(function()
		print("[DATA -> SHUTDOWN] Wykryto zamknięcie serwera! Zamykanie wszystkich aktywnych sesji...")
		for player, profile in pairs(activeProfiles) do
			task.spawn(function()
				print("[DATA -> SHUTDOWN] Zamykanie profilu dla " .. player.Name)
				profile:EndSession()
			end)
		end
		print("[DATA -> SHUTDOWN] Zakończono pętlę awaryjną wyłączania serwera.")
	end)
end

return DataManager
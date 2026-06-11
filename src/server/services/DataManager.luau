--!strict
local Players = game:GetService("Players")
local ServerScriptService = game:GetService("ServerScriptService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local ProfileStore = require(ServerScriptService.services.ProfileStore)
local Types = require(ReplicatedStorage.Shared.Types)

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
			
			-- ==================== SYNCHRONIZACJA PETÓW NA WEJŚCIE ====================
if profile.Data.Pets then
	for petName, value in pairs(profile.Data.Pets) do
		-- ZABEZPIECZENIE: Jeśli w bazie siedzą stare testowe dane (tabela zamiast liczby), naprawiamy to w locie
		local realAmount = 1
		if type(value) == "number" then
			realAmount = value
		elseif type(value) == "table" then
			realAmount = value.amount or 1
		end

		-- Wysyłamy poprawną tabelę z kluczami do Blinka
		Blink.SyncPets.Fire(player, {
			petName = petName,
			amount = realAmount
		})
		print(string.format("[DATA -> INITIAL SYNC] Wysłano stan peta z bazy dla %s: %s x%d", player.Name, petName, realAmount))
	end
end
			-- ==================================================================================
			
			print(string.format("[DATA -> BLINK] Wysłano wszystkie startowe pakiety synchronizacji dla %s", player.Name))
			-- ====================================================================

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
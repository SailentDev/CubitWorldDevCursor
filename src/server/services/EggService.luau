--!strict
local ServerScriptService = game:GetService("ServerScriptService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local DataManager = require(ServerScriptService.services.DataManager)
local Blink = require(ReplicatedStorage.Shared.Blink.network_server)
local EggDatabase = require(ReplicatedStorage.Shared.EggDatabase)

local EggService = {}

-- Funkcja pomocnicza: losuje peta na podstawie szans procentowych z bazy danych
local function rollPetFromEgg(eggName: string): string?
	local eggInfo = EggDatabase.GetEggInfo(eggName)
	if not eggInfo then return nil end

	-- 1. Obliczamy sumę wszystkich szans (wag)
	local totalWeight = 0
	for _, weight in pairs(eggInfo.DropChances) do
		totalWeight += weight
	end

	-- 2. Losujemy liczbę od 0 do sumy wag
	local randomValue = math.random() * totalWeight
	local currentWeight = 0

	-- 3. Przechodzimy po petach i sprawdzamy, w który przedział wpadł los
	for petName, weight in pairs(eggInfo.DropChances) do
		currentWeight += weight
		if randomValue <= currentWeight then
			return petName
		end
	end

	return nil
end

function EggService.OnInit()
	print("[SERVER -> EGG SERVICE] Initialization (OnInit)...")
end

function EggService.OnStart()
	print("[SERVER -> EGG SERVICE] Egg System Ready! (OnStart)")
	
	-- ==================== NOWOŚĆ: OBSŁUGA ZAKUPU JAJKA W SKLEPIE ====================
	Blink.RequestBuyEgg.On(function(player: Player, data: { eggName: string })
		local eggName = data.eggName
		print(string.format("[SERVER -> SHOP] Gracz %s żąda zakupu jajka: %s", player.Name, eggName))
		
		local profile = DataManager:GetProfile(player)
		if not profile then return end
		
		local eggInfo = EggDatabase.GetEggInfo(eggName)
		if not eggInfo then return end
		
		-- Sprawdzamy czy gracz ma odpowiednią ilość monet
		if profile.Data.Coins >= eggInfo.Price then
			-- Pobieramy koszty i dodajemy jajko do profilu
			profile.Data.Coins -= eggInfo.Price
			profile.Data.Eggs[eggName] = (profile.Data.Eggs[eggName] or 0) + 1
			local newEggAmount = profile.Data.Eggs[eggName]
			
			print(string.format("[SERVER -> SHOP] Pomyślnie zakupiono %s dla %s. Stan: %dx", eggName, player.Name, newEggAmount))
			
			-- 1. Aktualizacja szafki u klienta (struktura jawna w pliku .blink -> wysyłamy tabelę)
			Blink.SyncEggs.Fire(player, {
				eggName = eggName,
				amount = newEggAmount
			})
			
			-- 2. Aktualizacja stanu portfela u klienta
			Blink.SyncCurrency.Fire(player, {
				currencyType = eggInfo.CurrencyType,
				value = profile.Data.Coins
			})
		else
			warn(string.format("[SERVER -> SHOP] Odmowa! %s ma za mało monet (%d/%d)", player.Name, profile.Data.Coins, eggInfo.Price))
		end
	end)
	-- ===============================================================================

	-- OBSŁUGA OTWIERANIA (HATCH) JAJKA
	Blink.RequestHatch.On(function(player: Player, data: { eggName: string, amount: number })
		local eggName = data.eggName
		local amount = data.amount
		
		print(string.format("[SERVER -> HATCH] Gracz %s żąda otwarcia %dx %s", player.Name, amount, eggName))
		
		if amount <= 0 or (amount ~= 1 and amount ~= 2 and amount ~= 5 and amount ~= 10) then
			warn(string.format("[SERVER -> SECURITY] Gracz %s wysłał nieprawidłową ilość: %d!", player.Name, amount))
			return
		end
		
		local profile = DataManager:GetProfile(player)
		if not profile then
			warn("[SERVER -> HATCH] Nie znaleziono profilu danych dla gracza: " .. player.Name)
			return
		end
		
		local currentAmount = profile.Data.Eggs[eggName] or 0
		if currentAmount < amount then
			warn(string.format("[SERVER -> HATCH] Odmowa! %s ma tylko %dx %s (wymagane: %d)", player.Name, currentAmount, eggName, amount))
			return
		end
		
		profile.Data.Eggs[eggName] = currentAmount - amount
		local newAmount = profile.Data.Eggs[eggName]

		Blink.SyncEggs.Fire(player, {
			eggName = eggName,
			amount = newAmount
		})
		
		print(string.format("[SERVER -> HATCH] Rozpoczynam otwieranie %dx jajek dla %s...", amount, player.Name))
		
		for i = 1, amount do
			local rolledPet = rollPetFromEgg(eggName)
			
			if rolledPet then
				profile.Data.Pets[rolledPet] = (profile.Data.Pets[rolledPet] or 0) + 1
				local totalPetAmount = profile.Data.Pets[rolledPet]
				
				print(string.format("  -> Wykluwam jajko %d/%d: WYLOSOWANO -> %s!", i, amount, rolledPet))
				else
				print("[SERVER -> ERROR] Nie udało się wylosować peta z jajka: " .. eggId) -- Linia 129
				-- POPRAWKA: Anonimowa struktura inline -> płaskie argumenty alfabetycznie (amount, petName)
Blink.SyncPets.Fire(player, {
	petName = rolledPet,
	amount = totalPetAmount
})
			end
		end
		
		print(string.format("[SERVER -> HATCH SUCCESS] Pomyślnie przetworzono otwieranie dla %s", player.Name))
	end)
end

return EggService
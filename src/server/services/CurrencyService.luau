--!strict
local ServerScriptService = game:GetService("ServerScriptService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local DataManager = require(ServerScriptService.services.DataManager)
local Blink = require(ReplicatedStorage.Shared.Blink.network_server)

local CurrencyService = {}

-- ==================== Loader lifecycle ====================
function CurrencyService.OnInit()
	print("[CURRENCY] OnInit: Inicjalizacja CurrencyService...")
end

function CurrencyService.OnStart()
	print("[CURRENCY] OnStart: Usługa walutowa gotowa do pracy.")
end

-- ==================== Utility validation ====================
local function validateParams(player: Player, amount: number, currencyType: string): boolean
	if typeof(player) ~= "Instance" or not player:IsA("Player") then
		warn("[CURRENCY -> VALIDATION] Invalid player argument")
		return false
	end
	
	if typeof(amount) ~= "number" or amount <= 0 then
		warn("[CURRENCY -> VALIDATION] Amount must be a positive number")
		return false
	end
	
	if typeof(currencyType) ~= "string" or #currencyType == 0 then
		warn("[CURRENCY -> VALIDATION] currencyType must be a non‑empty string")
		return false
	end
	
	return true
end

-- ==================== Public API ====================

function CurrencyService:HasEnoughCurrency(player: Player, amount: number, currencyType: string): boolean
	print(string.format("[CURRENCY] Sprawdzanie portfela gracza %s: Wymagane %d %s", player.Name, amount, currencyType))
	if not validateParams(player, amount, currencyType) then
		return false
	end
	
	local profile = DataManager:GetProfile(player)
	if not profile then
		warn("[CURRENCY] Brak profilu danych dla gracza " .. player.Name)
		return false
	end
	
	local current: number = profile.Data[currencyType] or 0
	local hasEnough = current >= amount
	print(string.format("[CURRENCY] Gracz %s posiada: %d / %d %s. Wynik: %s", player.Name, current, amount, currencyType, tostring(hasEnough)))
	return hasEnough
end

function CurrencyService:AddCurrency(player: Player, amount: number, currencyType: string)
	print(string.format("[CURRENCY] Próba dodania %d %s dla gracza %s", amount, currencyType, player.Name))
	if not validateParams(player, amount, currencyType) then
		return
	end
	
	local profile = DataManager:GetProfile(player)
	assert(profile, "Missing profile for player " .. player.Name)
	
	local newValue: number = (profile.Data[currencyType] or 0) + amount
	profile.Data[currencyType] = newValue
	print(string.format("[CURRENCY -> DATA SUCCESS] Nowy stan konta gracza %s: %d %s", player.Name, newValue, currencyType))
	
	-- POPRAWIONE: Pakujemy dane w tabelę (słownik) zgodnie ze strukturą CurrencySyncData
	Blink.SyncCurrency.Fire(player, {
		currencyType = currencyType,
		value = newValue
	})
	print("[CURRENCY -> BLINK] Wysłano Blink.SyncCurrency do klienta.")
end

function CurrencyService:RemoveCurrency(player: Player, amount: number, currencyType: string): boolean
	print(string.format("[CURRENCY] Próba pobrania %d %s od gracza %s", amount, currencyType, player.Name))
	if not validateParams(player, amount, currencyType) then
		return false
	end
	
	local profile = DataManager:GetProfile(player)
	assert(profile, "Missing profile for player " .. player.Name)
	
	local current: number = profile.Data[currencyType] or 0
	if current < amount then
		warn(string.format("[CURRENCY -> FAIL] Za mało waluty! Posiada: %d, Wymagane: %d", current, amount))
		return false
	end
	
	local newValue: number = current - amount
	profile.Data[currencyType] = newValue
	print(string.format("[CURRENCY -> DATA SUCCESS] Pobrano pomyślnie. Nowy stan konta %s: %d %s", player.Name, newValue, currencyType))
	
	-- POPRAWIONE: Pakujemy dane w tabelę (słownik) zgodnie ze strukturą CurrencySyncData
	Blink.SyncCurrency.Fire(player, {
		currencyType = currencyType,
		value = newValue
	})
	print("[CURRENCY -> BLINK] Wysłano Blink.SyncCurrency (pobranie) do klienta.")
	return true
end

return CurrencyService
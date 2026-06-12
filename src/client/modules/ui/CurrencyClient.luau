--!strict
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local LocalPlayer = Players.LocalPlayer
local PlayerGui = LocalPlayer:WaitForChild("PlayerGui")

-- Import Blink
local Blink = require(ReplicatedStorage.Shared.Blink.network_client)

local CurrencyClient = {}

-- Funkcja pomocnicza do ładnego formatowania liczb (np. 10500 -> 10,500)
local function formatNumber(value: number): string
	local formatted = tostring(math.floor(value))
	while true do  
		local k
		formatted, k = string.gsub(formatted, "^(-?%d+)(%d%d%d)", '%1,%2')
		if k == 0 then break end
	end
	return formatted
end

local function formatNumber(value: number): string
	if value < 1000 then
		return tostring(math.floor(value))
	end

	local suffixes = {"", "K", "M", "B", "T", "Qd", "Qn"}
	
	-- Wyliczamy indeks skrótu
	local i = math.floor(math.log10(value) / 3)
	local shortValue = value / (10 ^ (i * 3))
	
	-- Ucinamy bezwzględnie do 3 miejsc po przecinku (widoczne tysiące i dziesiątki tysięcy)
	local cutValue = math.floor(shortValue * 1000) / 1000
	
	-- Formatujemy do tekstu z wymuszonymi 3 miejscami po przecinku (np. "999.999")
	local formatted = string.format("%.3f", cutValue)
	
	-- Inteligentne usuwanie zbędnych zer z końca (np. "50.500" -> "50.5", a "100.000" -> "100")
	formatted = string.gsub(formatted, "%.?0+$", "")
	
	local suffix = suffixes[i + 1] or "Inf"
	return formatted .. suffix
end

-- ==================== Loader lifecycle ====================
function CurrencyClient.OnInit()
	print("[CLIENT -> CURRENCY] Initialization (OnInit)...")
end

function CurrencyClient.OnStart()
	print("[CLIENT -> CURRENCY] Currency System Ready! (OnStart)")
	
	-- Referencje do UI (Pobierane w OnStart, żeby upewnić się, że MainHUD już istnieje)
	local mainHUD = PlayerGui:WaitForChild("MainHUD") :: ScreenGui
	local currencyFrame = mainHUD:WaitForChild("CurrencyFrame") :: Frame
	local coinsLabel = currencyFrame:WaitForChild("CoinsLabel") :: TextLabel

	-- ==================== SYNCHRONIZACJA WALUTY ====================
	Blink.SyncCurrency.On(function(data: { currencyType: string, value: number })
		-- Sprawdzamy, czy serwer przesłał akurat aktualizację monet
		if data.currencyType == "Coins" then 
			coinsLabel.Text = "$" .. formatNumber(data.value)
			print(string.format("[CLIENT -> CURRENCY] Zaktualizowano portfel: $%s", formatNumber(data.value)))
		end
	end)
end

return CurrencyClient
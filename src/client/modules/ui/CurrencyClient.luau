--!strict
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Blink = require(ReplicatedStorage.Shared.Blink.network_client)

local CurrencyClient = {}

local SUFFIXES = { "", "K", "M", "B", "T", "Qd", "Qn" }

local function formatNumber(value: number): string
	if value ~= value then
		return "0"
	end
	if value >= math.huge then
		return "Inf"
	end
	if value <= -math.huge then
		return "-Inf"
	end

	local sign = if value < 0 then "-" else ""
	local absValue = math.abs(value)

	if absValue < 1000 then
		return sign .. tostring(math.floor(absValue))
	end

	local index = math.floor(math.log10(absValue) / 3)
	local suffix = SUFFIXES[index + 1]
	if not suffix then
		return sign .. "Inf"
	end

	local shortValue = absValue / (10 ^ (index * 3))
	local cutValue = math.floor(shortValue * 1000) / 1000
	local formatted = string.gsub(string.format("%.3f", cutValue), "%.?0+$", "")

	return sign .. formatted .. suffix
end

function CurrencyClient.OnInit(): ()
end

function CurrencyClient.OnStart(): ()
	local localPlayer = Players.LocalPlayer :: Player
	local playerGui = localPlayer:WaitForChild("PlayerGui") :: PlayerGui
	local mainHUD = playerGui:WaitForChild("MainHUD", 10)
	local currencyFrame = if mainHUD then mainHUD:WaitForChild("CurrencyFrame", 5) else nil
	local coinsLabel = if currencyFrame then currencyFrame:WaitForChild("CoinsLabel", 5) else nil

	if not coinsLabel or not coinsLabel:IsA("TextLabel") then
		warn("[CurrencyClient] CoinsLabel missing")
		return
	end

	Blink.SyncCurrency.On(function(data: { currencyType: string, value: number })
		if data.currencyType == "Coins" then
			coinsLabel.Text = "$" .. formatNumber(data.value)
		end
	end)
end

return CurrencyClient
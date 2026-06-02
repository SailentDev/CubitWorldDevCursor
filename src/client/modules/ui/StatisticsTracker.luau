--!strict
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService") -- DODANE: Liczy klatki gry
local Blink = require(ReplicatedStorage.Shared.Blink.network_client)

local StatisticsTracker = {}

local localPlayer = Players.LocalPlayer :: Player
local frameCount = 0
local serverRegion = "Unknown"

-- Referencje do wątków i połączeń
local updateThread: thread? = nil
local heartbeatConnection: RBXScriptConnection? = nil
local label: TextLabel? = nil 

function StatisticsTracker.OnInit()
	-- Puste, bo SettingsClient przekazuje nam gotowy label bezpośrednio do OnStart
end

function StatisticsTracker.OnStart(passedLabel: TextLabel)
	-- Łapiemy label przekazany z SettingsClient
	label = passedLabel

	-- SILNIK LICZNIKA: Co każdą klatkę gry dodajemy +1 do frameCount
	if not heartbeatConnection then
		heartbeatConnection = RunService.Heartbeat:Connect(function()
			frameCount += 1
		end)
	end

	-- PĘTLA AKTUALIZUJĄCA: Co sekundę przepisuje wynik i go zeruje
	if not updateThread then
		updateThread = task.spawn(function()
			while true do
				task.wait(1)
				
				local currentFps = frameCount
				frameCount = 0 -- Reset na nową sekundę
				
				local ping = 0
				if localPlayer then
					ping = math.round(localPlayer:GetNetworkPing() * 1000)
				end
				
				if label then
					label.Text = string.format("FPS: %d | Ping: %d ms | Region: %s", currentFps, ping, serverRegion)
				end
			end
		end)
	end

	-- Nasłuchiwanie regionu z serwera
	Blink.SyncRegion.On(function(regionName: string)
		if typeof(regionName) == "string" then
			serverRegion = regionName
		end
	end)
end

function StatisticsTracker.Stop(): ()
	if heartbeatConnection then
		heartbeatConnection:Disconnect()
		heartbeatConnection = nil
	end
	if updateThread then
		task.cancel(updateThread)
		updateThread = nil
	end
end

return StatisticsTracker
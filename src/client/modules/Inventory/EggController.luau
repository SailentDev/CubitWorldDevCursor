--!strict
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Blink = require(ReplicatedStorage.Shared.Blink.network_client)

local EggController = {}

function EggController.OnInit()
	print("[CLIENT -> EGG CONTROLLER] OnInit gotowy.")
end

function EggController.OnStart()
	print("[CLIENT -> EGG CONTROLLER] OnStart: Nasłuchiwanie na serwerowy event Blink.EggHatched...")
	
	-- Zmiana z .Listen na .On
	Blink.EggHatched.On(function(data: { petName: string })
		print("[CLIENT -> BLINK RECEIVE] Sukces! Serwer potwierdził wyklucie: **" .. data.petName .. "**")
		-- TODO: Trigger 3D visual effects here
	end)
end

function EggController:RequestPurchase(eggName: string)
	print("[CLIENT -> UI EVENT] Kliknięto przycisk zakupu. Wysyłam Blink.RequestBuyEgg dla: " .. eggName)
	Blink.RequestBuyEgg.Fire({ eggName = eggName })
	print("[CLIENT -> BLINK SEND] Pakiet wysłany przez sieć do serwera.")
end

return EggController
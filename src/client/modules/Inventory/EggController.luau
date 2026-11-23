--!strict
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Blink = require(ReplicatedStorage.Shared.Blink.network_client)

local EggController = {}

local PURCHASE_DEBOUNCE = 0.25
local lastPurchaseTime = 0

function EggController.OnInit(): ()
end

function EggController.OnStart(): ()
	Blink.EggHatched.On(function(_data: { petName: string })
		-- Hook 3D egg hatch animation/VFX here
	end)
end

function EggController.RequestPurchase(eggName: string): ()
	local now = os.clock()
	if (now - lastPurchaseTime) < PURCHASE_DEBOUNCE then
		return
	end
	lastPurchaseTime = now

	Blink.RequestBuyEgg.Fire({ eggName = eggName })
end

return EggController
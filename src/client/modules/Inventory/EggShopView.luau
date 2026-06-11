--!strict
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local EggDatabase = require(ReplicatedStorage.Shared.EggDatabase)
local EggController = require(script.Parent.EggController)

local EggShopView = {}

function EggShopView.Populate(scrollingFrame: ScrollingFrame)
	print("[CLIENT -> UI SHOP] Rozpoczynam populację (wypełnianie) GUI Sklepu...")
	local templates = ReplicatedStorage:WaitForChild("Shared"):WaitForChild("Templates")
	local eggTemplate = templates:WaitForChild("EggTemplate")

	-- Czyścimy poprzednie
	local clearedCount = 0
	for _, child in pairs(scrollingFrame:GetChildren()) do
		if child:IsA("GuiObject") then 
			child:Destroy() 
			clearedCount += 1
		end
	end
	print(string.format("[CLIENT -> UI SHOP] Wyczyszczono %d starych obiektów UI.", clearedCount))

	-- Generujemy listę
	local generatedCount = 0
	for eggName, info in pairs(EggDatabase.GetAllEggs()) do
		print(string.format("[CLIENT -> UI SHOP] Klonowanie szablonu dla jajka: %s, Cena: %d", eggName, info.Price))
		local clone = eggTemplate:Clone()
		local buyButton = clone:FindFirstChild("PriceBuyButton") :: TextButton
		
		buyButton.Text = "Kup: " .. info.Price
		buyButton.MouseButton1Click:Connect(function()
			print(string.format("[CLIENT -> UI SHOP CLICK] Gracz nacisnął fizyczny przycisk kupna dla %s", eggName))
			EggController:RequestPurchase(eggName)
		end)
		
		clone.Parent = scrollingFrame
		generatedCount += 1
	end
	print(string.format("[CLIENT -> UI SHOP] Generowanie zakończone. Utworzono %d przycisków jajek.", generatedCount))
end

return EggShopView
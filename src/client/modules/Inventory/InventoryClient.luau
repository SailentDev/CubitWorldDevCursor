--!strict
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local LocalPlayer = Players.LocalPlayer
local PlayerGui = LocalPlayer:WaitForChild("PlayerGui")

-- Import widoku sklepu oraz sieci klienta Blink
local EggShopView = require(script.Parent.EggShopView)
local Blink = require(ReplicatedStorage.Shared.Blink.network_client)

local InventoryClient = {}

-- Referencje do UI Ekwipunku
local InventoryGui = PlayerGui:WaitForChild("InventoryGui")
local InventoryFrame = InventoryGui:WaitForChild("InventoryFrame")
local InventoryScrollingFrame = InventoryFrame:WaitForChild("ScrollingFrame")

-- Referencja do okienka wyboru ilości oraz jego dzieci
local HatchPromptFrame = InventoryFrame:WaitForChild("HatchPromptFrame") :: Frame
local CloseButton = HatchPromptFrame:WaitForChild("CloseButton") :: TextButton
local Open1x = HatchPromptFrame:WaitForChild("Open1x") :: TextButton
local Open2x = HatchPromptFrame:WaitForChild("Open2x") :: TextButton
local Open5x = HatchPromptFrame:WaitForChild("Open5x") :: TextButton
local Open10x = HatchPromptFrame:WaitForChild("Open10x") :: TextButton

-- Referencja do szablonów
local Templates = ReplicatedStorage:WaitForChild("Shared"):WaitForChild("Templates")
local EggTemplate = Templates:WaitForChild("EggTemplate")
local PetTemplate = Templates:WaitForChild("PetTemplate") :: Frame

-- Zmienna pomocnicza: przechowuje nazwę jajka, które gracz właśnie kliknął
local currentSelectedEgg: string? = nil

-- Funkcja otwierająca okienko wyboru ilości
local function openHatchPrompt(eggName: string)
	currentSelectedEgg = eggName
	HatchPromptFrame.Visible = true
	print("[CLIENT -> UI] Otwarto prompt ilości dla jajka: " .. eggName)
end

-- Funkcja zamykająca okienko wyboru ilości
local function closeHatchPrompt()
	currentSelectedEgg = nil
	HatchPromptFrame.Visible = false
end

function InventoryClient.OnInit()
	print("[CLIENT -> INVENTORY] Initialization (OnInit)...")
	local shopGui = PlayerGui:WaitForChild("EggShopGui")
	
	print("[CLIENT -> INVENTORY] Pobieranie ramki przewijanej i ładowanie widoku sklepu...")
	EggShopView.Populate(shopGui.EggShopFrame.ScrollingFrame)
end

function InventoryClient.OnStart()
	print("[CLIENT -> INVENTORY] Inventory System Ready! (OnStart)")
	
	-- Podłączenie akcji pod przyciski ilościowe z aktywnym przesyłaniem danych przez Blink
	Open1x.MouseButton1Click:Connect(function()
		if currentSelectedEgg then
			print(string.format("[CLIENT -> HATCH] Żądanie otwarcia 1x jajka: %s", currentSelectedEgg))
			Blink.RequestHatch.Fire({
				eggName = currentSelectedEgg,
				amount = 1
			})
			closeHatchPrompt()
		end
	end)

	Open2x.MouseButton1Click:Connect(function()
		if currentSelectedEgg then
			print(string.format("[CLIENT -> HATCH] Żądanie otwarcia 2x jajka: %s", currentSelectedEgg))
			Blink.RequestHatch.Fire({
				eggName = currentSelectedEgg,
				amount = 2
			})
			closeHatchPrompt()
		end
	end)

	Open5x.MouseButton1Click:Connect(function()
		if currentSelectedEgg then
			print(string.format("[CLIENT -> HATCH] Żądanie otwarcia 5x jajka: %s", currentSelectedEgg))
			Blink.RequestHatch.Fire({
				eggName = currentSelectedEgg,
				amount = 5
			})
			closeHatchPrompt()
		end
	end)

	Open10x.MouseButton1Click:Connect(function()
		if currentSelectedEgg then
			print(string.format("[CLIENT -> HATCH] Żądanie otwarcia 10x jajka: %s", currentSelectedEgg))
			Blink.RequestHatch.Fire({
				eggName = currentSelectedEgg,
				amount = 10
			})
			closeHatchPrompt()
		end
	end)

	-- Podłączenie przycisku zamknięcia okienka (CloseButton)
	CloseButton.MouseButton1Click:Connect(closeHatchPrompt)
	
	-- Nasłuchiwanie na serwerowe pakiety o zmianie stanu posiadanych jajek (JAJKA ZOSTAJĄ STAKOWANE)
	Blink.SyncEggs.On(function(data: { eggName: string, amount: number })
		print(string.format("[CLIENT -> INVENTORY] Odebrano aktualizację ekwipunku: %s x%d", data.eggName, data.amount))
		
		local existingSlot = InventoryScrollingFrame:FindFirstChild(data.eggName)
		
		if existingSlot then
			local amountLabel = existingSlot:FindFirstChild("AmmoutLabel") :: TextLabel
			if amountLabel then
				amountLabel.Text = tostring(data.amount) .. "x"
				print(string.format("[CLIENT -> UI] Zaktualizowano ilość dla %s na %dx", data.eggName, data.amount))
			end
		else
			local newSlot = EggTemplate:Clone() :: Frame
			newSlot.Name = data.eggName
			
			local priceBuyButton = newSlot:FindFirstChild("PriceBuyButton") :: GuiObject
			if priceBuyButton then
				priceBuyButton.Visible = false
			end
			
			local amountLabel = newSlot:FindFirstChild("AmmoutLabel") :: TextLabel
			if amountLabel then
				amountLabel.Text = tostring(data.amount) .. "x"
			end
			
			local eggIcon = newSlot:FindFirstChild("EggIcon") :: ImageButton
			if eggIcon then
				eggIcon.MouseButton1Click:Connect(function()
					openHatchPrompt(data.eggName)
				end)
			else
				warn("[CLIENT -> ERROR] Nie znaleziono elementu EggIcon w szablonie dla " .. data.eggName)
			end
			
			newSlot.Parent = InventoryScrollingFrame
			print("[CLIENT -> UI] Utworzono nowy slot ekwipunku dla jajka: " .. data.eggName)
		end
	end)

	-- ==================== NOWA LOGIKA: PETY KAZDY OSOBNO (UNSTAKED) ====================
	Blink.SyncPets.On(function(data: { petName: string, amount: number })
		print(string.format("[CLIENT -> INVENTORY] Synchronicacja petów dla %s. Oczekiwana ilość w UI: %d", data.petName, data.amount))
		
		-- 1. Znajdujemy i zliczamy wszystkie istniejące już kafelki tego konkretnego peta
		local existingPetSlots = {}
		for _, child in ipairs(InventoryScrollingFrame:GetChildren()) do
			if child.Name == data.petName and child:IsA("Frame") then
				table.insert(existingPetSlots, child)
			end
		end
		
		local currentCount = #existingPetSlots
		
		-- 2. Jeśli w UI jest MNIEJ kafelków niż podaje serwer -> klonujemy brakujące
		if currentCount < data.amount then
			local toCreate = data.amount - currentCount
			for i = 1, toCreate do
				local newSlot = PetTemplate:Clone() :: Frame
				newSlot.Name = data.petName
				
				-- Ponieważ pety są osobno, tekst "1x/6x" jest zbędny. Ukrywamy licznik ilości.
				local amountLabel = newSlot:FindFirstChild("AmmoutLabel") or newSlot:FindFirstChild("AmountLabel") :: TextLabel?
				if amountLabel then
					amountLabel.Visible = false
				end
				
				-- Tutaj w przyszłości dodasz logikę kliknięcia na dany slot (np. zakłądanie peta)
				
				newSlot.Parent = InventoryScrollingFrame
				print(string.format("[CLIENT -> UI] Utworzono OSOBNY kafelek dla peta: %s", data.petName))
			end
			
		-- 3. Jeśli w UI jest WIĘCEJ kafelków niż podaje serwer (np. gdybyś kiedyś usunął/sprzedał peta) -> usuwamy nadmiar
		elseif currentCount > data.amount then
			local toDestroy = currentCount - data.amount
			for i = 1, toDestroy do
				local slotToRemove = existingPetSlots[#existingPetSlots]
				if slotToRemove then
					slotToRemove:Destroy()
					table.remove(existingPetSlots, #existingPetSlots)
				end
			end
		end
	end)
	-- ==================================================================================
end

return InventoryClient
--!strict
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local LocalPlayer = Players.LocalPlayer
local PlayerGui = LocalPlayer:WaitForChild("PlayerGui")

local EggShopView = require(script.Parent.EggShopView)
local Blink = require(ReplicatedStorage.Shared.Blink.network_client)
local PetDatabase = require(ReplicatedStorage.Shared:WaitForChild("PetDatabase") :: ModuleScript)
local PetClient = require(script.Parent.Parent:WaitForChild("PetClient") :: ModuleScript)

local InventoryClient = {}

local InventoryGui = PlayerGui:WaitForChild("InventoryGui")
local InventoryFrame = InventoryGui:WaitForChild("InventoryFrame")
local InventoryScrollingFrame = InventoryFrame:WaitForChild("ScrollingFrame")

local DetailsFrame = InventoryFrame:WaitForChild("DetailsFrame") :: Frame
local PetNameLabel = DetailsFrame:WaitForChild("PetNameLabel") :: TextLabel
local RarityLabel = DetailsFrame:WaitForChild("RarityLabel") :: TextLabel
local ElementLabel = DetailsFrame:WaitForChild("ElementLabel") :: TextLabel
local DamageLabel = DetailsFrame:WaitForChild("DamageLabel") :: TextLabel
local HealthLabel = DetailsFrame:WaitForChild("HealthLabel") :: TextLabel
local EquipToggleButton = DetailsFrame:WaitForChild("EquipToggleButton") :: TextButton

local HatchPromptFrame = InventoryFrame:WaitForChild("HatchPromptFrame") :: Frame
local CloseButton = HatchPromptFrame:WaitForChild("CloseButton") :: TextButton
local Open1x = HatchPromptFrame:WaitForChild("Open1x") :: TextButton
local Open2x = HatchPromptFrame:WaitForChild("Open2x") :: TextButton
local Open5x = HatchPromptFrame:WaitForChild("Open5x") :: TextButton
local Open10x = HatchPromptFrame:WaitForChild("Open10x") :: TextButton

local Templates = ReplicatedStorage:WaitForChild("Shared"):WaitForChild("Templates")
local EggTemplate = Templates:WaitForChild("EggTemplate")
local PetTemplate = Templates:WaitForChild("PetTemplate") :: Frame

local currentSelectedEgg: string? = nil
local eggAmounts: { [string]: number } = {}

local function updatePetDetails(petId: string, level: number, uuid: string)
	local petInfo = PetDatabase.GetPetInfo(petId)
	
	if not petInfo then
		warn("[CLIENT -> ERROR] Brak danych w PetDatabase dla ID: " .. petId)
		return
	end
	
	local levelMultiplier = 1 + (level - 1) * 0.1
	local currentDamage = math.round(petInfo.BaseDamage * levelMultiplier)
	local currentHp = math.round(petInfo.BaseHp * levelMultiplier)
	
	PetNameLabel.Text = string.format("%s (Lvl %d)", petInfo.Name, level)
	RarityLabel.Text = "Rarity: " .. petInfo.Rarity
	ElementLabel.Text = "Element: " .. tostring(petInfo.Element)
	DamageLabel.Text = "Damage: " .. tostring(currentDamage)
	HealthLabel.Text = "Health: " .. tostring(currentHp)
	
	-- Odświeżenie tekstu przycisku w zależności od stanu
	local isEquipped = PetClient.IsPetEquipped(uuid)
	EquipToggleButton.Text = isEquipped and "Unequip" or "Equip"
	
	EquipToggleButton.Visible = true
	print(string.format("[CLIENT -> UI] Wyświetlono statystyki dla %s na poziomie %d", petId, level))
end

local function openHatchPrompt(eggName: string)
	currentSelectedEgg = eggName
	local currentAmount = eggAmounts[eggName] or 0
	
	Open1x.Visible = currentAmount >= 1
	Open2x.Visible = currentAmount >= 2
	Open5x.Visible = currentAmount >= 5
	Open10x.Visible = currentAmount >= 10
	
	HatchPromptFrame.Visible = true
	print(string.format("[CLIENT -> UI] Otwarto HatchPrompt dla %s. Ilość: %d.", eggName, currentAmount))
end

local function closeHatchPrompt()
	currentSelectedEgg = nil
	HatchPromptFrame.Visible = false
end

function InventoryClient.OnInit()
	print("[CLIENT -> INVENTORY] Initialization (OnInit)...")
	local shopGui = PlayerGui:WaitForChild("EggShopGui")
	EggShopView.Populate(shopGui.EggShopFrame.ScrollingFrame)
	
	EquipToggleButton.Visible = false
end

function InventoryClient.OnStart()
	print("[CLIENT -> INVENTORY] Inventory System Ready! (OnStart)")
	
	Open1x.MouseButton1Click:Connect(function()
		if currentSelectedEgg then Blink.RequestHatch.Fire({ eggName = currentSelectedEgg, amount = 1 }) closeHatchPrompt() end
	end)
	Open2x.MouseButton1Click:Connect(function()
		if currentSelectedEgg then Blink.RequestHatch.Fire({ eggName = currentSelectedEgg, amount = 2 }) closeHatchPrompt() end
	end)
	Open5x.MouseButton1Click:Connect(function()
		if currentSelectedEgg then Blink.RequestHatch.Fire({ eggName = currentSelectedEgg, amount = 5 }) closeHatchPrompt() end
	end)
	Open10x.MouseButton1Click:Connect(function()
		if currentSelectedEgg then Blink.RequestHatch.Fire({ eggName = currentSelectedEgg, amount = 10 }) closeHatchPrompt() end
	end)

	CloseButton.MouseButton1Click:Connect(closeHatchPrompt)
	
	Blink.SyncEggs.On(function(data: { eggName: string, amount: number })
		local existingSlot = InventoryScrollingFrame:FindFirstChild(data.eggName)
		if data.amount <= 0 then
			eggAmounts[data.eggName] = nil
			if existingSlot then existingSlot:Destroy() end
			return
		end
		
		eggAmounts[data.eggName] = data.amount
		if existingSlot then
			local amountLabel = existingSlot:FindFirstChild("AmmoutLabel") :: TextLabel
			if amountLabel then amountLabel.Text = tostring(data.amount) .. "x" end
		else
			local newSlot = EggTemplate:Clone() :: Frame
			newSlot.Name = data.eggName
			local priceBuyButton = newSlot:FindFirstChild("PriceBuyButton") :: GuiObject
			if priceBuyButton then priceBuyButton.Visible = false end
			local amountLabel = newSlot:FindFirstChild("AmmoutLabel") :: TextLabel
			if amountLabel then amountLabel.Text = tostring(data.amount) .. "x" end
			
			local eggIcon = newSlot:FindFirstChild("EggIcon") :: ImageButton
			if eggIcon then
				eggIcon.MouseButton1Click:Connect(function() openHatchPrompt(data.eggName) end)
			end
			newSlot.Parent = InventoryScrollingFrame
		end
	end)

	EquipToggleButton.MouseButton1Click:Connect(function()
		local selectedUUID = DetailsFrame:GetAttribute("SelectedPetUUID")
		if selectedUUID and typeof(selectedUUID) == "string" then
			-- NAPRAWIONE: Natychmiastowa zmiana wizualna dla responsywności UI
			if EquipToggleButton.Text == "Equip" then
				EquipToggleButton.Text = "Unequip"
			else
				EquipToggleButton.Text = "Equip"
			end
			
			Blink.RequestEquip.Fire({ uuid = selectedUUID })
			print("[InventoryClient] RequestEquip fired for UUID:", selectedUUID)
		else
			warn("[InventoryClient] Cannot equip: no pet selected or invalid UUID")
		end
	end)

	-- NAPRAWIONE: Bezpieczne mapowanie struktury tabeli petów z Blinka u klienta
	PetClient.EquippedChanged:Connect(function(equippedUUIDs)
		local selectedUUID = DetailsFrame:GetAttribute("SelectedPetUUID")
		if selectedUUID then
			local isEquipped = false
			for _, item in ipairs(equippedUUIDs) do
				if typeof(item) == "table" and item.uuid == selectedUUID then
					isEquipped = true
					break
				elseif typeof(item) == "string" and item == selectedUUID then
					isEquipped = true
					break
				end
			end
			EquipToggleButton.Text = isEquipped and "Unequip" or "Equip"
		end
	end)

	Blink.SyncPets.On(function(data: { uuid: string, petName: string, level: number, isRemoved: boolean? })
		print(string.format("[CLIENT -> INVENTORY] Aktualizacja peta: %s, Lvl: %d, UUID: %s", data.petName, data.level, data.uuid))
		
		-- Najpierw rejestrujemy nazwę w module 3D
		PetClient.OnPetSynced(data)
		
		local existingSlot = InventoryScrollingFrame:FindFirstChild(data.uuid)
		if data.isRemoved then
			if existingSlot then existingSlot:Destroy() end
			return
		end
		
		if existingSlot then
			existingSlot:SetAttribute("Level", data.level)
		else
			local newSlot = PetTemplate:Clone() :: Frame
			newSlot.Name = data.uuid 
			newSlot:SetAttribute("PetId", data.petName)
			newSlot:SetAttribute("Level", data.level)
			
			local amountLabel = newSlot:FindFirstChild("AmmoutLabel") or newSlot:FindFirstChild("AmountLabel") :: TextLabel?
			if amountLabel then amountLabel.Visible = false end
			
			local petIcon = newSlot:FindFirstChild("PetIcon") :: ImageButton
			if petIcon then
				petIcon.MouseButton1Click:Connect(function()
					local currentLevel = newSlot:GetAttribute("Level") or 1
					local currentName = newSlot:GetAttribute("PetId") or data.petName
					
					DetailsFrame:SetAttribute("SelectedPetUUID", data.uuid)
					updatePetDetails(currentName, currentLevel, data.uuid)
				end)
			else
				warn("[CLIENT -> ERROR] Nie znaleziono PetIcon w szablonie peta!")
			end
			
			newSlot.Parent = InventoryScrollingFrame
		end
	end)

	local syncRemote = ReplicatedStorage:WaitForChild("RequestInitialSync") :: RemoteEvent
	syncRemote:FireServer()
	print("[InventoryClient] Zażądano wstępnej synchronizacji danych z DataManagera.")
end

return InventoryClient
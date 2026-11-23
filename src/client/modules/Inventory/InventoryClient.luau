--!strict
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Blink = require(ReplicatedStorage.Shared.Blink.network_client)
local PetDatabase = require(ReplicatedStorage.Shared.PetDatabase)
local Types = require(ReplicatedStorage.Shared.Types)

local EggShopView = require(script.Parent:WaitForChild("EggShopView"))
local PetClient = require(script.Parent.Parent:WaitForChild("PetClient"))

local InventoryClient = {}

local EQUIP_DEBOUNCE = 0.2

local inventoryScrollingFrame: ScrollingFrame? = nil
local detailsFrame: Frame? = nil
local petNameLabel: TextLabel? = nil
local rarityLabel: TextLabel? = nil
local elementLabel: TextLabel? = nil
local damageLabel: TextLabel? = nil
local healthLabel: TextLabel? = nil
local equipToggleButton: TextButton? = nil

local hatchPromptFrame: Frame? = nil
local closeButton: TextButton? = nil
local open1x: TextButton? = nil
local open2x: TextButton? = nil
local open5x: TextButton? = nil
local open10x: TextButton? = nil

local eggTemplate: Instance? = nil
local petTemplate: Instance? = nil

local currentSelectedEgg: string? = nil
local eggAmounts: { [string]: number } = {}
local lastEquipClick = 0

local function clearPetDetails(): ()
	if detailsFrame then
		detailsFrame:SetAttribute("SelectedPetUUID", nil)
	end
	if petNameLabel then
		petNameLabel.Text = ""
	end
	if rarityLabel then
		rarityLabel.Text = ""
	end
	if elementLabel then
		elementLabel.Text = ""
	end
	if damageLabel then
		damageLabel.Text = ""
	end
	if healthLabel then
		healthLabel.Text = ""
	end
	if equipToggleButton then
		equipToggleButton.Visible = false
	end
end

local function updatePetDetails(petId: string, level: number, uuid: string): ()
	local petInfo = PetDatabase.GetPetInfo(petId)
	if not petInfo then
		warn("[InventoryClient] Missing PetDatabase entry for:", petId)
		return
	end

	local levelMultiplier = 1 + (level - 1) * 0.1
	local currentDamage = math.round(petInfo.BaseDamage * levelMultiplier)
	local currentHp = math.round(petInfo.BaseHp * levelMultiplier)

	if petNameLabel then
		petNameLabel.Text = string.format("%s (Lvl %d)", petInfo.Name, level)
	end
	if rarityLabel then
		rarityLabel.Text = "Rarity: " .. petInfo.Rarity
	end
	if elementLabel then
		elementLabel.Text = "Element: " .. petInfo.Element
	end
	if damageLabel then
		damageLabel.Text = "Damage: " .. tostring(currentDamage)
	end
	if healthLabel then
		healthLabel.Text = "Health: " .. tostring(currentHp)
	end

	if equipToggleButton then
		equipToggleButton.Text = if PetClient.IsPetEquipped(uuid) then "Unequip" else "Equip"
		equipToggleButton.Visible = true
	end
end

local function refreshHatchPromptButtons(): ()
	if not currentSelectedEgg then
		return
	end

	local amount = eggAmounts[currentSelectedEgg] or 0
	if amount <= 0 then
		currentSelectedEgg = nil
		if hatchPromptFrame then
			hatchPromptFrame.Visible = false
		end
		return
	end

	if open1x then
		open1x.Visible = amount >= 1
	end
	if open2x then
		open2x.Visible = amount >= 2
	end
	if open5x then
		open5x.Visible = amount >= 5
	end
	if open10x then
		open10x.Visible = amount >= 10
	end
end

local function openHatchPrompt(eggName: string): ()
	currentSelectedEgg = eggName
	refreshHatchPromptButtons()
	if hatchPromptFrame and currentSelectedEgg then
		hatchPromptFrame.Visible = true
	end
end

local function closeHatchPrompt(): ()
	currentSelectedEgg = nil
	if hatchPromptFrame then
		hatchPromptFrame.Visible = false
	end
end

local function sendHatchRequest(amount: number): ()
	if currentSelectedEgg then
		Blink.RequestHatch.Fire({
			eggName = currentSelectedEgg,
			amount = amount,
		})
		closeHatchPrompt()
	end
end

function InventoryClient.OnInit(): ()
	local localPlayer = Players.LocalPlayer :: Player
	local playerGui = localPlayer:WaitForChild("PlayerGui") :: PlayerGui

	local inventoryGui = playerGui:WaitForChild("InventoryGui", 10)
	local inventoryFrame = if inventoryGui then inventoryGui:WaitForChild("InventoryFrame", 5) else nil
	if not inventoryFrame then
		warn("[InventoryClient] InventoryFrame missing")
		return
	end

	inventoryScrollingFrame = inventoryFrame:WaitForChild("ScrollingFrame") :: ScrollingFrame

	local details = inventoryFrame:WaitForChild("DetailsFrame") :: Frame
	detailsFrame = details
	petNameLabel = details:WaitForChild("PetNameLabel") :: TextLabel
	rarityLabel = details:WaitForChild("RarityLabel") :: TextLabel
	elementLabel = details:WaitForChild("ElementLabel") :: TextLabel
	damageLabel = details:WaitForChild("DamageLabel") :: TextLabel
	healthLabel = details:WaitForChild("HealthLabel") :: TextLabel

	local equipBtn = details:WaitForChild("EquipToggleButton") :: TextButton
	equipToggleButton = equipBtn
	equipBtn.Visible = false

	local prompt = inventoryFrame:WaitForChild("HatchPromptFrame") :: Frame
	hatchPromptFrame = prompt
	closeButton = prompt:WaitForChild("CloseButton") :: TextButton
	open1x = prompt:WaitForChild("Open1x") :: TextButton
	open2x = prompt:WaitForChild("Open2x") :: TextButton
	open5x = prompt:WaitForChild("Open5x") :: TextButton
	open10x = prompt:WaitForChild("Open10x") :: TextButton

	local sharedFolder = ReplicatedStorage:WaitForChild("Shared") :: Folder
	local templates = sharedFolder:WaitForChild("Templates") :: Folder
	eggTemplate = templates:WaitForChild("EggTemplate")
	petTemplate = templates:WaitForChild("PetTemplate")

	local shopGui = playerGui:WaitForChild("EggShopGui", 10)
	local shopFrame = if shopGui then shopGui:WaitForChild("EggShopFrame", 5) else nil
	local shopScrolling = if shopFrame then shopFrame:WaitForChild("ScrollingFrame", 5) else nil
	if shopScrolling and shopScrolling:IsA("ScrollingFrame") then
		EggShopView.Populate(shopScrolling)
	end
end

function InventoryClient.OnStart(): ()
	if open1x then
		open1x.Activated:Connect(function() sendHatchRequest(1) end)
	end
	if open2x then
		open2x.Activated:Connect(function() sendHatchRequest(2) end)
	end
	if open5x then
		open5x.Activated:Connect(function() sendHatchRequest(5) end)
	end
	if open10x then
		open10x.Activated:Connect(function() sendHatchRequest(10) end)
	end
	if closeButton then
		closeButton.Activated:Connect(closeHatchPrompt)
	end

	if equipToggleButton then
		equipToggleButton.Activated:Connect(function()
			local now = os.clock()
			if (now - lastEquipClick) < EQUIP_DEBOUNCE then
				return
			end
			lastEquipClick = now

			local selectedUUID = if detailsFrame then detailsFrame:GetAttribute("SelectedPetUUID") else nil
			if typeof(selectedUUID) == "string" and #selectedUUID > 0 then
				Blink.RequestEquip.Fire({ uuid = selectedUUID })
			end
		end)
	end

	PetClient.EquippedChanged:Connect(function(equippedList: { Types.EquippedPetInfo })
		local selectedUUID = if detailsFrame then detailsFrame:GetAttribute("SelectedPetUUID") else nil
		if typeof(selectedUUID) ~= "string" or not equipToggleButton then
			return
		end

		local isEquipped = false
		for _, item in equippedList do
			if item.uuid == selectedUUID then
				isEquipped = true
				break
			end
		end
		equipToggleButton.Text = if isEquipped then "Unequip" else "Equip"
	end)

	Blink.SyncEggs.On(function(data: { eggName: string, amount: number })
		local container = inventoryScrollingFrame
		if not container then
			return
		end

		local existingSlot = container:FindFirstChild(data.eggName)
		if data.amount <= 0 then
			eggAmounts[data.eggName] = nil
			if existingSlot then
				existingSlot:Destroy()
			end
			if currentSelectedEgg == data.eggName then
				refreshHatchPromptButtons()
			end
			return
		end

		eggAmounts[data.eggName] = data.amount
		if existingSlot then
			local amountLabel = existingSlot:FindFirstChild("AmmoutLabel") or existingSlot:FindFirstChild("AmountLabel")
			if amountLabel and amountLabel:IsA("TextLabel") then
				amountLabel.Text = tostring(data.amount) .. "x"
			end
		elseif eggTemplate then
			local newSlot = eggTemplate:Clone()
			newSlot.Name = data.eggName

			local priceBuyButton = newSlot:FindFirstChild("PriceBuyButton")
			if priceBuyButton and priceBuyButton:IsA("GuiObject") then
				priceBuyButton.Visible = false
			end

			local amountLabel = newSlot:FindFirstChild("AmmoutLabel") or newSlot:FindFirstChild("AmountLabel")
			if amountLabel and amountLabel:IsA("TextLabel") then
				amountLabel.Text = tostring(data.amount) .. "x"
			end

			local eggIcon = newSlot:FindFirstChild("EggIcon")
			if eggIcon and eggIcon:IsA("GuiButton") then
				eggIcon.Activated:Connect(function()
					openHatchPrompt(data.eggName)
				end)
			end

			newSlot.Parent = container
		end

		if currentSelectedEgg == data.eggName and hatchPromptFrame and hatchPromptFrame.Visible then
			refreshHatchPromptButtons()
		end
	end)

	Blink.SyncPets.On(function(data: { uuid: string, petName: string, level: number, isRemoved: boolean? })
		local container = inventoryScrollingFrame
		if not container then
			return
		end

		local selectedUUID = if detailsFrame then detailsFrame:GetAttribute("SelectedPetUUID") else nil
		local existingSlot = container:FindFirstChild(data.uuid)

		if data.isRemoved then
			if existingSlot then
				existingSlot:Destroy()
			end
			if selectedUUID == data.uuid then
				clearPetDetails()
			end
			return
		end

		if existingSlot then
			existingSlot:SetAttribute("Level", data.level)
			existingSlot:SetAttribute("PetId", data.petName)
			if selectedUUID == data.uuid then
				updatePetDetails(data.petName, data.level, data.uuid)
			end
			return
		end

		if not petTemplate then
			return
		end

		local newSlot = petTemplate:Clone()
		newSlot.Name = data.uuid
		newSlot:SetAttribute("PetId", data.petName)
		newSlot:SetAttribute("Level", data.level)

		local amountLabel = newSlot:FindFirstChild("AmmoutLabel") or newSlot:FindFirstChild("AmountLabel")
		if amountLabel and amountLabel:IsA("GuiObject") then
			amountLabel.Visible = false
		end

		local petIcon = newSlot:FindFirstChild("PetIcon")
		if petIcon and petIcon:IsA("ImageButton") then
			local petInfo = PetDatabase.GetPetInfo(data.petName)
			if petInfo and petInfo.IconId ~= "" then
				petIcon.Image = petInfo.IconId
			end

			petIcon.Activated:Connect(function()
				local rawLevel = newSlot:GetAttribute("Level")
				local rawPetId = newSlot:GetAttribute("PetId")
				local currentLevel = if typeof(rawLevel) == "number" then rawLevel else data.level
				local currentName = if typeof(rawPetId) == "string" then rawPetId else data.petName

				if detailsFrame then
					detailsFrame:SetAttribute("SelectedPetUUID", data.uuid)
				end
				updatePetDetails(currentName, currentLevel, data.uuid)
			end)
		end

		newSlot.Parent = container
	end)
end

return InventoryClient
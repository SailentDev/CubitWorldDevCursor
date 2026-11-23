--!strict
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local Blink = require(ReplicatedStorage.Shared.Blink.network_client)
local PetDatabase = require(ReplicatedStorage.Shared.PetDatabase)
local PetStats = require(ReplicatedStorage.Shared.PetStats)
local Types = require(ReplicatedStorage.Shared.Types)

local EggShopView = require(script.Parent:WaitForChild("EggShopView"))
local PetClient = require(script.Parent.Parent:WaitForChild("PetClient"))

local InventoryClient = {}

type QueueItem = {
	kind: "Egg" | "Pet",
	key: string,
}

type PendingPetData = {
	uuid: string,
	petName: string,
	level: number,
}

local EQUIP_DEBOUNCE = 0.2
local SLOTS_PER_FRAME = 15

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

local eggTemplate: Frame? = nil
local petTemplate: Frame? = nil
local defaultPetIconImage = ""

local currentSelectedEgg: string? = nil
local eggAmounts: { [string]: number } = {}
local lastEquipClick = 0

local eggSlots: { [string]: Frame } = {}
local petSlots: { [string]: Frame } = {}
local eggSlotPool: { Frame } = {}
local petSlotPool: { Frame } = {}

local pendingEggData: { [string]: number } = {}
local pendingPetData: { [string]: PendingPetData } = {}
local creationQueue: { QueueItem } = {}
local queueHead = 1
local queueConnection: RBXScriptConnection? = nil

local function waitForChildPath(parent: Instance, childName: string, timeout: number, parentPath: string): Instance?
	local found = parent:WaitForChild(childName, timeout)
	if not found then
		warn(`[InventoryClient] Missing instance at path: {parentPath}.{childName}`)
		return nil
	end
	return found
end

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

	local currentDamage = PetStats.GetDamage(petInfo, level)
	local currentHp = PetStats.GetHp(petInfo, level)

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

local function configureEggSlot(slot: Frame, eggName: string, amount: number): ()
	slot.Name = eggName
	slot:SetAttribute("EggName", eggName)

	local priceBuyButton = slot:FindFirstChild("PriceBuyButton")
	if priceBuyButton and priceBuyButton:IsA("GuiObject") then
		priceBuyButton.Visible = false
	end

	local amountLabel = slot:FindFirstChild("AmmoutLabel") or slot:FindFirstChild("AmountLabel")
	if amountLabel and amountLabel:IsA("TextLabel") then
		amountLabel.Text = tostring(amount) .. "x"
	end
end

local function createOrReuseEggSlot(container: ScrollingFrame, eggName: string, amount: number): ()
	local slot: Frame
	local pooledCount = #eggSlotPool
	if pooledCount > 0 then
		slot = eggSlotPool[pooledCount]
		eggSlotPool[pooledCount] = nil
	else
		local template = eggTemplate
		if not template then
			return
		end
		slot = template:Clone()
		local eggIcon = slot:FindFirstChild("EggIcon")
		if eggIcon and eggIcon:IsA("GuiButton") then
			eggIcon.Activated:Connect(function()
				local rawEggName = slot:GetAttribute("EggName")
				if typeof(rawEggName) == "string" and #rawEggName > 0 then
					openHatchPrompt(rawEggName)
				end
			end)
		end
	end

	configureEggSlot(slot, eggName, amount)
	slot.Visible = true
	slot.Parent = container
	eggSlots[eggName] = slot
end

local function releaseEggSlot(eggName: string): ()
	local slot = eggSlots[eggName]
	if not slot then
		return
	end
	eggSlots[eggName] = nil
	slot:SetAttribute("EggName", nil)
	slot.Visible = false
	slot.Parent = nil
	table.insert(eggSlotPool, slot)
end

local function configurePetSlot(slot: Frame, data: PendingPetData): ()
	slot.Name = data.uuid
	slot:SetAttribute("UUID", data.uuid)
	slot:SetAttribute("PetId", data.petName)
	slot:SetAttribute("Level", data.level)

	local amountLabel = slot:FindFirstChild("AmmoutLabel") or slot:FindFirstChild("AmountLabel")
	if amountLabel and amountLabel:IsA("GuiObject") then
		amountLabel.Visible = false
	end

	local petIcon = slot:FindFirstChild("PetIcon")
	if petIcon and petIcon:IsA("ImageButton") then
		local petInfo = PetDatabase.GetPetInfo(data.petName)
		if petInfo and petInfo.IconId ~= "" then
			petIcon.Image = petInfo.IconId
		else
			petIcon.Image = defaultPetIconImage
		end
	end
end

local function createOrReusePetSlot(container: ScrollingFrame, data: PendingPetData): ()
	local slot: Frame
	local pooledCount = #petSlotPool
	if pooledCount > 0 then
		slot = petSlotPool[pooledCount]
		petSlotPool[pooledCount] = nil
	else
		local template = petTemplate
		if not template then
			return
		end
		slot = template:Clone()
		local petIcon = slot:FindFirstChild("PetIcon")
		if petIcon and petIcon:IsA("ImageButton") then
			petIcon.Activated:Connect(function()
				local rawUUID = slot:GetAttribute("UUID")
				local rawLevel = slot:GetAttribute("Level")
				local rawPetId = slot:GetAttribute("PetId")
				if typeof(rawUUID) ~= "string" or typeof(rawPetId) ~= "string" then
					return
				end
				local currentLevel = if typeof(rawLevel) == "number" then rawLevel else 1

				if detailsFrame then
					detailsFrame:SetAttribute("SelectedPetUUID", rawUUID)
				end
				updatePetDetails(rawPetId, currentLevel, rawUUID)
			end)
		end
	end

	configurePetSlot(slot, data)
	slot.Visible = true
	slot.Parent = container
	petSlots[data.uuid] = slot
end

local function releasePetSlot(uuid: string): ()
	local slot = petSlots[uuid]
	if not slot then
		return
	end
	petSlots[uuid] = nil
	slot:SetAttribute("UUID", nil)
	slot:SetAttribute("PetId", nil)
	slot:SetAttribute("Level", nil)
	slot.Visible = false
	slot.Parent = nil
	table.insert(petSlotPool, slot)
end

local function processCreationQueue(): ()
	local container = inventoryScrollingFrame
	if not container then
		table.clear(creationQueue)
		queueHead = 1
		if queueConnection then
			queueConnection:Disconnect()
			queueConnection = nil
		end
		return
	end

	local createdThisFrame = 0
	while createdThisFrame < SLOTS_PER_FRAME and queueHead <= #creationQueue do
		local item = creationQueue[queueHead]
		queueHead += 1

		if item.kind == "Egg" then
			local amount = pendingEggData[item.key]
			if amount and amount > 0 then
				pendingEggData[item.key] = nil
				if not eggSlots[item.key] then
					createOrReuseEggSlot(container, item.key, amount)
					createdThisFrame += 1
				end
			end
		elseif item.kind == "Pet" then
			local petData = pendingPetData[item.key]
			if petData then
				pendingPetData[item.key] = nil
				if not petSlots[item.key] then
					createOrReusePetSlot(container, petData)
					createdThisFrame += 1
				end
			end
		end
	end

	if queueHead > #creationQueue then
		table.clear(creationQueue)
		queueHead = 1
		if queueConnection then
			queueConnection:Disconnect()
			queueConnection = nil
		end
	end
end

local function ensureQueueRunning(): ()
	if not queueConnection then
		queueConnection = RunService.Heartbeat:Connect(processCreationQueue)
	end
end

function InventoryClient.OnInit(): ()
	local localPlayer = Players.LocalPlayer :: Player
	local playerGuiInst = waitForChildPath(localPlayer, "PlayerGui", 5, "LocalPlayer")
	if not playerGuiInst or not playerGuiInst:IsA("PlayerGui") then
		return
	end

	local inventoryGui = waitForChildPath(playerGuiInst, "InventoryGui", 5, "PlayerGui")
	if not inventoryGui then
		return
	end

	local inventoryFrame = waitForChildPath(inventoryGui, "InventoryFrame", 3, "PlayerGui.InventoryGui")
	if not inventoryFrame or not inventoryFrame:IsA("Frame") then
		if inventoryFrame then
			warn("[InventoryClient] PlayerGui.InventoryGui.InventoryFrame is not a Frame")
		end
		return
	end

	local scrollingInst = waitForChildPath(inventoryFrame, "ScrollingFrame", 3, "PlayerGui.InventoryGui.InventoryFrame")
	if not scrollingInst or not scrollingInst:IsA("ScrollingFrame") then
		if scrollingInst then
			warn("[InventoryClient] PlayerGui.InventoryGui.InventoryFrame.ScrollingFrame is not a ScrollingFrame")
		end
		return
	end

	local detailsInst = waitForChildPath(inventoryFrame, "DetailsFrame", 3, "PlayerGui.InventoryGui.InventoryFrame")
	if not detailsInst or not detailsInst:IsA("Frame") then
		if detailsInst then
			warn("[InventoryClient] PlayerGui.InventoryGui.InventoryFrame.DetailsFrame is not a Frame")
		end
		return
	end

	local detailsPath = "PlayerGui.InventoryGui.InventoryFrame.DetailsFrame"
	local petNameInst = waitForChildPath(detailsInst, "PetNameLabel", 3, detailsPath)
	local rarityInst = waitForChildPath(detailsInst, "RarityLabel", 3, detailsPath)
	local elementInst = waitForChildPath(detailsInst, "ElementLabel", 3, detailsPath)
	local damageInst = waitForChildPath(detailsInst, "DamageLabel", 3, detailsPath)
	local healthInst = waitForChildPath(detailsInst, "HealthLabel", 3, detailsPath)
	local equipBtnInst = waitForChildPath(detailsInst, "EquipToggleButton", 3, detailsPath)

	if not petNameInst or not petNameInst:IsA("TextLabel")
		or not rarityInst or not rarityInst:IsA("TextLabel")
		or not elementInst or not elementInst:IsA("TextLabel")
		or not damageInst or not damageInst:IsA("TextLabel")
		or not healthInst or not healthInst:IsA("TextLabel")
		or not equipBtnInst or not equipBtnInst:IsA("TextButton")
	then
		return
	end

	local promptInst = waitForChildPath(inventoryFrame, "HatchPromptFrame", 3, "PlayerGui.InventoryGui.InventoryFrame")
	if not promptInst or not promptInst:IsA("Frame") then
		if promptInst then
			warn("[InventoryClient] PlayerGui.InventoryGui.InventoryFrame.HatchPromptFrame is not a Frame")
		end
		return
	end

	local promptPath = "PlayerGui.InventoryGui.InventoryFrame.HatchPromptFrame"
	local closeInst = waitForChildPath(promptInst, "CloseButton", 3, promptPath)
	local open1Inst = waitForChildPath(promptInst, "Open1x", 3, promptPath)
	local open2Inst = waitForChildPath(promptInst, "Open2x", 3, promptPath)
	local open5Inst = waitForChildPath(promptInst, "Open5x", 3, promptPath)
	local open10Inst = waitForChildPath(promptInst, "Open10x", 3, promptPath)

	if not closeInst or not closeInst:IsA("TextButton")
		or not open1Inst or not open1Inst:IsA("TextButton")
		or not open2Inst or not open2Inst:IsA("TextButton")
		or not open5Inst or not open5Inst:IsA("TextButton")
		or not open10Inst or not open10Inst:IsA("TextButton")
	then
		return
	end

	local sharedFolder = waitForChildPath(ReplicatedStorage, "Shared", 5, "ReplicatedStorage")
	if not sharedFolder then
		return
	end
	local templates = waitForChildPath(sharedFolder, "Templates", 3, "ReplicatedStorage.Shared")
	if not templates then
		return
	end
	local eggTemplateInst = waitForChildPath(templates, "EggTemplate", 3, "ReplicatedStorage.Shared.Templates")
	local petTemplateInst = waitForChildPath(templates, "PetTemplate", 3, "ReplicatedStorage.Shared.Templates")
	if not eggTemplateInst or not eggTemplateInst:IsA("Frame") then
		if eggTemplateInst then
			warn("[InventoryClient] ReplicatedStorage.Shared.Templates.EggTemplate is not a Frame")
		end
		return
	end
	if not petTemplateInst or not petTemplateInst:IsA("Frame") then
		if petTemplateInst then
			warn("[InventoryClient] ReplicatedStorage.Shared.Templates.PetTemplate is not a Frame")
		end
		return
	end

	inventoryScrollingFrame = scrollingInst
	detailsFrame = detailsInst
	petNameLabel = petNameInst
	rarityLabel = rarityInst
	elementLabel = elementInst
	damageLabel = damageInst
	healthLabel = healthInst
	equipToggleButton = equipBtnInst
	equipBtnInst.Visible = false

	hatchPromptFrame = promptInst
	closeButton = closeInst
	open1x = open1Inst
	open2x = open2Inst
	open5x = open5Inst
	open10x = open10Inst

	eggTemplate = eggTemplateInst
	petTemplate = petTemplateInst

	local defaultIcon = petTemplateInst:FindFirstChild("PetIcon")
	if defaultIcon and defaultIcon:IsA("ImageButton") then
		defaultPetIconImage = defaultIcon.Image
	end

	local shopGui = waitForChildPath(playerGuiInst, "EggShopGui", 5, "PlayerGui")
	if not shopGui then
		return
	end
	local shopFrame = waitForChildPath(shopGui, "EggShopFrame", 3, "PlayerGui.EggShopGui")
	if not shopFrame then
		return
	end
	local shopScrolling = waitForChildPath(shopFrame, "ScrollingFrame", 3, "PlayerGui.EggShopGui.EggShopFrame")
	if not shopScrolling or not shopScrolling:IsA("ScrollingFrame") then
		if shopScrolling then
			warn("[InventoryClient] PlayerGui.EggShopGui.EggShopFrame.ScrollingFrame is not a ScrollingFrame")
		end
		return
	end

	EggShopView.Populate(shopScrolling)
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

		if data.amount <= 0 then
			eggAmounts[data.eggName] = nil
			pendingEggData[data.eggName] = nil
			releaseEggSlot(data.eggName)
			if currentSelectedEgg == data.eggName then
				refreshHatchPromptButtons()
			end
			return
		end

		eggAmounts[data.eggName] = data.amount
		local existingSlot = eggSlots[data.eggName]
		if existingSlot then
			configureEggSlot(existingSlot, data.eggName, data.amount)
		else
			local wasQueued = pendingEggData[data.eggName] ~= nil
			pendingEggData[data.eggName] = data.amount
			if not wasQueued then
				table.insert(creationQueue, {
					kind = "Egg",
					key = data.eggName,
				})
				ensureQueueRunning()
			end
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

		if data.isRemoved then
			pendingPetData[data.uuid] = nil
			releasePetSlot(data.uuid)
			if selectedUUID == data.uuid then
				clearPetDetails()
			end
			return
		end

		local existingSlot = petSlots[data.uuid]
		if existingSlot then
			configurePetSlot(existingSlot, {
				uuid = data.uuid,
				petName = data.petName,
				level = data.level,
			})
			if selectedUUID == data.uuid then
				updatePetDetails(data.petName, data.level, data.uuid)
			end
			return
		end

		local wasQueued = pendingPetData[data.uuid] ~= nil
		pendingPetData[data.uuid] = {
			uuid = data.uuid,
			petName = data.petName,
			level = data.level,
		}
		if not wasQueued then
			table.insert(creationQueue, {
				kind = "Pet",
				key = data.uuid,
			})
			ensureQueueRunning()
		end
	end)
end

return InventoryClient
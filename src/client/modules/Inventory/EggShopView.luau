--!strict
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local EggDatabase = require(ReplicatedStorage.Shared.EggDatabase)
local Types = require(ReplicatedStorage.Shared.Types)

local EggController = require(script.Parent:WaitForChild("EggController"))

local EggShopView = {}

type EggEntry = {
	id: string,
	info: Types.EggInfo,
}

local function waitForChildPath(parent: Instance, childName: string, timeout: number, parentPath: string): Instance?
	local found = parent:WaitForChild(childName, timeout)
	if not found then
		warn(`[EggShopView] Missing instance at path: {parentPath}.{childName}`)
		return nil
	end
	return found
end

function EggShopView.Populate(scrollingFrame: ScrollingFrame): ()
	local sharedFolder = waitForChildPath(ReplicatedStorage, "Shared", 5, "ReplicatedStorage")
	if not sharedFolder then
		return
	end

	local templates = waitForChildPath(sharedFolder, "Templates", 3, "ReplicatedStorage.Shared")
	if not templates then
		return
	end

	local eggTemplate = waitForChildPath(templates, "EggTemplate", 3, "ReplicatedStorage.Shared.Templates")
	if not eggTemplate or not eggTemplate:IsA("GuiObject") then
		if eggTemplate then
			warn("[EggShopView] ReplicatedStorage.Shared.Templates.EggTemplate is not a GuiObject")
		end
		return
	end

	for _, child in scrollingFrame:GetChildren() do
		if child:IsA("GuiObject") then
			child:Destroy()
		end
	end

	local sortedEggs: { EggEntry } = {}
	for eggName, info in EggDatabase.GetAllEggs() do
		table.insert(sortedEggs, { id = eggName, info = info })
	end

	table.sort(sortedEggs, function(a: EggEntry, b: EggEntry): boolean
		if a.info.LayoutOrder ~= b.info.LayoutOrder then
			return a.info.LayoutOrder < b.info.LayoutOrder
		end
		return a.id < b.id
	end)

	for _, entry in sortedEggs do
		local eggName = entry.id
		local info = entry.info

		local clone = eggTemplate:Clone()
		clone.Name = eggName
		clone.LayoutOrder = info.LayoutOrder
		clone.Visible = true

		local amountLabel = clone:FindFirstChild("AmmoutLabel") or clone:FindFirstChild("AmountLabel")
		if amountLabel and amountLabel:IsA("GuiObject") then
			amountLabel.Visible = false
		end

		local buyButton = clone:FindFirstChild("PriceBuyButton")
		if buyButton and buyButton:IsA("TextButton") then
			buyButton.Text = "Kup: " .. tostring(info.Price)
			buyButton.Activated:Connect(function()
				EggController.RequestPurchase(eggName)
			end)
		end

		clone.Parent = scrollingFrame
	end
end

function EggShopView.OnInit(): ()
	local localPlayer = Players.LocalPlayer :: Player
	local playerGui = waitForChildPath(localPlayer, "PlayerGui", 5, "LocalPlayer")
	if not playerGui then
		return
	end

	local shopGui = waitForChildPath(playerGui, "EggShopGui", 5, "PlayerGui")
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
			warn("[EggShopView] PlayerGui.EggShopGui.EggShopFrame.ScrollingFrame is not a ScrollingFrame")
		end
		return
	end

	EggShopView.Populate(shopScrolling)
end

return EggShopView
--!strict
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local EggDatabase = require(ReplicatedStorage.Shared.EggDatabase)
local Types = require(ReplicatedStorage.Shared.Types)

local EggController = require(script.Parent:WaitForChild("EggController"))

local EggShopView = {}

type EggEntry = {
	id: string,
	info: Types.EggInfo,
}

function EggShopView.Populate(scrollingFrame: ScrollingFrame): ()
	local sharedFolder = ReplicatedStorage:WaitForChild("Shared", 5)
	if not sharedFolder then
		warn("[EggShopView] Missing instance at path: ReplicatedStorage.Shared")
		return
	end

	local templates = sharedFolder:WaitForChild("Templates", 3)
	if not templates then
		warn("[EggShopView] Missing instance at path: ReplicatedStorage.Shared.Templates")
		return
	end

	local eggTemplate = templates:WaitForChild("EggTemplate", 3)
	if not eggTemplate then
		warn("[EggShopView] Missing instance at path: ReplicatedStorage.Shared.Templates.EggTemplate")
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
		if clone:IsA("GuiObject") then
			clone.LayoutOrder = info.LayoutOrder
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

return EggShopView
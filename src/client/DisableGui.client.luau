--!strict
local StarterGui = game:GetService("StarterGui")

local MAX_RETRIES = 30
local RETRY_INTERVAL = 0.5

local STANDARD_ELEMENTS: { Enum.CoreGuiType } = {
	Enum.CoreGuiType.Health,
	Enum.CoreGuiType.PlayerList,
	Enum.CoreGuiType.Backpack,
	Enum.CoreGuiType.EmotesMenu,
}

for _, element in STANDARD_ELEMENTS do
	pcall(function()
		StarterGui:SetCoreGuiEnabled(element, false)
	end)
end

task.spawn(function()
	for _ = 1, MAX_RETRIES do
		local success = pcall(function()
			StarterGui:SetCoreGuiEnabled(Enum.CoreGuiType.Captures, false)
			StarterGui:SetCoreGuiEnabled(Enum.CoreGuiType.SelfView, false)
		end)
		if success then
			return
		end
		task.wait(RETRY_INTERVAL)
	end
end)
local StarterGui = game:GetService("StarterGui")

-- 1. Standardowe wyłączanie (Health, PlayerList, Backpack, Emotes)
local elementsToDisable = {
	Enum.CoreGuiType.Health,
	Enum.CoreGuiType.PlayerList,
	Enum.CoreGuiType.Backpack,
	Enum.CoreGuiType.EmotesMenu
}

for _, element in ipairs(elementsToDisable) do
	StarterGui:SetCoreGuiEnabled(element, false)
end

-- 2. Wyłączanie Captures (aparatu) i SelfView (kamery)
-- Musimy to robić w pętli/pcall, bo te funkcje ładują się z opóźnieniem
task.spawn(function()
	local success = false
	while not success do
		success = pcall(function()
			-- To wyłącza ikonkę aparatu (Captures)
			StarterGui:SetCoreGuiEnabled(Enum.CoreGuiType.Captures, false)
			-- To wyłącza podgląd własnej twarzy (Self View)
			StarterGui:SetCoreGuiEnabled(Enum.CoreGuiType.SelfView, false)
		end)
		task.wait(0.5) -- Czekamy chwilę, żeby nie przeciążyć procesora
	end
end)
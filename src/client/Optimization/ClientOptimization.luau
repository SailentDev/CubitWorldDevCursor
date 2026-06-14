--!strict
local Players = game:GetService("Players")
local localPlayer = Players.LocalPlayer

local ClientOptimization = {}

-- Funkcja optymalizująca postać lokalnego gracza
local function optimizeLocalCharacter(character: Model)
	local humanoid = character:WaitForChild("Humanoid", 5) :: Humanoid?
	if not humanoid then return end

	-- 1. Blokada wchodzenia na pionowe ściany (45 stopni to standard dla gier platformowych/RPG)
	humanoid.MaxSlopeAngle = 45 

	-- 2. Wyłączenie niepotrzebnych stanów fizycznych bezwzględnie po stronie klienta
	humanoid:SetStateEnabled(Enum.HumanoidStateType.Climbing, false)
	humanoid:SetStateEnabled(Enum.HumanoidStateType.Swimming, false)
	humanoid:SetStateEnabled(Enum.HumanoidStateType.Seated, false)   -- wyłącz, jeśli nie masz krzeseł/pojazdów
	humanoid:SetStateEnabled(Enum.HumanoidStateType.Ragdoll, false)
end

function ClientOptimization.OnInit()
	-- Puste przygotowanie, jeśli potrzebne w przyszłości
end

function ClientOptimization.OnStart()
	-- Jeśli postać już istnieje w momencie ładowania
	if localPlayer.Character then
		task.spawn(optimizeLocalCharacter, localPlayer.Character)
	end

	-- Obsługa każdego kolejnego odrodzenia (respawnu) postaci
	localPlayer.CharacterAdded:Connect(function(character)
		optimizeLocalCharacter(character)
	end)
end

return ClientOptimization
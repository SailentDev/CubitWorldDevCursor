--!strict
local Players = game:GetService("Players")

local localPlayer = Players.LocalPlayer :: Player

local ClientOptimization = {}

local function optimizeLocalCharacter(character: Model): ()
	local humanoid = character:FindFirstChildOfClass("Humanoid")
		or (character:WaitForChild("Humanoid", 5) :: Humanoid?)
	if not humanoid or not humanoid:IsA("Humanoid") then
		return
	end

	humanoid.MaxSlopeAngle = 45

	humanoid:SetStateEnabled(Enum.HumanoidStateType.Climbing, false)
	humanoid:SetStateEnabled(Enum.HumanoidStateType.Swimming, false)
	humanoid:SetStateEnabled(Enum.HumanoidStateType.Seated, false)
	humanoid:SetStateEnabled(Enum.HumanoidStateType.Ragdoll, false)
	humanoid:SetStateEnabled(Enum.HumanoidStateType.FallingDown, false)
end

function ClientOptimization.OnInit(): ()
end

function ClientOptimization.OnStart(): ()
	if localPlayer.Character then
		task.spawn(optimizeLocalCharacter, localPlayer.Character)
	end

	localPlayer.CharacterAdded:Connect(optimizeLocalCharacter)
end

return ClientOptimization
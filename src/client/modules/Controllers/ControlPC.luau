--!strict
--!native
local GuiService = game:GetService("GuiService")
local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local UserInputService = game:GetService("UserInputService")
local Workspace = game:GetService("Workspace")

export type ControlPC = {
	Enable: (self: ControlPC) -> (),
	Disable: (self: ControlPC) -> (),
}

type MoveAction = "Forward" | "Backward" | "Left" | "Right"

type InputState = {
	Forward: number,
	Backward: number,
	Left: number,
	Right: number,
}

local MOVE_KEYS: { [Enum.KeyCode]: MoveAction } = {
	[Enum.KeyCode.W] = "Forward",
	[Enum.KeyCode.S] = "Backward",
	[Enum.KeyCode.A] = "Left",
	[Enum.KeyCode.D] = "Right",
}

local localPlayer = Players.LocalPlayer :: Player
local activeConnections: { RBXScriptConnection } = {}
local updateConnection: RBXScriptConnection? = nil

local isJumping = false
local cachedHumanoid: Humanoid? = nil
local charWaitGeneration = 0
local inputState: InputState = { Forward = 0, Backward = 0, Left = 0, Right = 0 }

local ControlPC = {} :: ControlPC

local function setActionState(action: MoveAction, active: number): ()
	if action == "Forward" then
		inputState.Forward = active
	elseif action == "Backward" then
		inputState.Backward = active
	elseif action == "Left" then
		inputState.Left = active
	elseif action == "Right" then
		inputState.Right = active
	end
end

local function updateCharacterCache(character: Model): ()
	charWaitGeneration += 1
	local myGen = charWaitGeneration

	local hum = character:FindFirstChildOfClass("Humanoid") or character:WaitForChild("Humanoid", 5)
	if myGen == charWaitGeneration and hum and hum:IsA("Humanoid") and character.Parent then
		cachedHumanoid = hum
	end
end

local function shouldUpdate(): boolean
	return isJumping
		or inputState.Forward > 0
		or inputState.Backward > 0
		or inputState.Left > 0
		or inputState.Right > 0
end

local function onUpdate(): ()
	local humanoid = cachedHumanoid
	if not humanoid then
		return
	end

	humanoid.Jump = isJumping

	local camera = Workspace.CurrentCamera
	local moveX = inputState.Right - inputState.Left
	local moveZ = inputState.Forward - inputState.Backward

	if (moveX ~= 0 or moveZ ~= 0) and camera then
		local camCFrame = camera.CFrame
		local flatForward = Vector3.new(camCFrame.LookVector.X, 0, camCFrame.LookVector.Z)
		local flatRight = Vector3.new(camCFrame.RightVector.X, 0, camCFrame.RightVector.Z)

		if flatForward.Magnitude > 1e-4 and flatRight.Magnitude > 1e-4 then
			local dir = (flatForward.Unit * moveZ) + (flatRight.Unit * moveX)
			humanoid:Move(dir, false)
			return
		end
	end

	humanoid:Move(Vector3.zero, false)
end

local function evaluateUpdateLoop(): ()
	if shouldUpdate() then
		if not updateConnection then
			updateConnection = RunService.PreSimulation:Connect(onUpdate)
		end
	else
		if updateConnection then
			updateConnection:Disconnect()
			updateConnection = nil
			if cachedHumanoid then
				cachedHumanoid:Move(Vector3.zero, false)
				cachedHumanoid.Jump = false
			end
		end
	end
end

local function resetInputState(): ()
	isJumping = false
	inputState.Forward = 0
	inputState.Backward = 0
	inputState.Left = 0
	inputState.Right = 0
	evaluateUpdateLoop()
end

local function handleInput(input: InputObject, isProcessed: boolean, active: number): ()
	-- Only gate InputBegan on gameProcessed; always process InputEnded to prevent stuck keys
	if active == 1 and isProcessed then
		return
	end

	local action = MOVE_KEYS[input.KeyCode]
	if action then
		setActionState(action, active)
		evaluateUpdateLoop()
		return
	end

	if input.KeyCode == Enum.KeyCode.Space then
		isJumping = (active == 1)
		evaluateUpdateLoop()
	end
end

function ControlPC:Enable(): ()
	self:Disable()

	if localPlayer.Character then
		task.spawn(updateCharacterCache, localPlayer.Character)
	end

	table.insert(activeConnections, localPlayer.CharacterAdded:Connect(function(char: Model)
		task.spawn(updateCharacterCache, char)
	end))

	table.insert(activeConnections, localPlayer.CharacterRemoving:Connect(function()
		charWaitGeneration += 1
		cachedHumanoid = nil
		evaluateUpdateLoop()
	end))

	table.insert(activeConnections, UserInputService.InputBegan:Connect(function(input: InputObject, processed: boolean)
		handleInput(input, processed, 1)
	end))

	table.insert(activeConnections, UserInputService.InputEnded:Connect(function(input: InputObject, processed: boolean)
		handleInput(input, processed, 0)
	end))

	table.insert(activeConnections, GuiService.MenuOpened:Connect(resetInputState))
	table.insert(activeConnections, UserInputService.WindowFocusReleased:Connect(resetInputState))

	evaluateUpdateLoop()
end

function ControlPC:Disable(): ()
	for _, connection in activeConnections do
		connection:Disconnect()
	end
	table.clear(activeConnections)

	if updateConnection then
		updateConnection:Disconnect()
		updateConnection = nil
	end

	charWaitGeneration += 1
	resetInputState()
	cachedHumanoid = nil
end

return ControlPC
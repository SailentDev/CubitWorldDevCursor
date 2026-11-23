--!strict
--!native
local GuiService = game:GetService("GuiService")
local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local UserInputService = game:GetService("UserInputService")
local Workspace = game:GetService("Workspace")

export type ControlPhone = {
	Enable: (self: ControlPhone) -> (),
	Disable: (self: ControlPhone) -> (),
}

type JoystickData = {
	IsDragging: boolean,
	TouchId: InputObject?,
	MoveVector: Vector2,
}

local ZONE_WIDTH_LIMIT = 0.4
local ZONE_HEIGHT_LIMIT = 0.33

local localPlayer = Players.LocalPlayer :: Player
local activeConnections: { RBXScriptConnection } = {}
local updateConnection: RBXScriptConnection? = nil

local joystickState: JoystickData = { IsDragging = false, TouchId = nil, MoveVector = Vector2.zero }
local isJumping = false
local jumpTouchId: InputObject? = nil
local cachedHumanoid: Humanoid? = nil
local charWaitGeneration = 0
local viewportSize: Vector2 = Vector2.zero

local joystickBase: Frame? = nil
local joystickThumb: ImageButton? = nil

local ControlPhone = {} :: ControlPhone

local function isPointerInput(input: InputObject): boolean
	return input.UserInputType == Enum.UserInputType.Touch
		or (RunService:IsStudio() and input.UserInputType == Enum.UserInputType.MouseButton1)
end

local function updateCharacterCache(character: Model): ()
	charWaitGeneration += 1
	local myGen = charWaitGeneration

	local hum = character:FindFirstChildOfClass("Humanoid") or character:WaitForChild("Humanoid", 5)
	if myGen == charWaitGeneration and hum and hum:IsA("Humanoid") and character.Parent then
		cachedHumanoid = hum
	end
end

local function isWithinTouchZone(pos: Vector3): boolean
	if viewportSize.X <= 0 then
		return false
	end
	return pos.X < (viewportSize.X * ZONE_WIDTH_LIMIT) and pos.Y > (viewportSize.Y * ZONE_HEIGHT_LIMIT)
end

local function shouldUpdate(): boolean
	return isJumping or joystickState.IsDragging
end

local function onUpdate(): ()
	local humanoid = cachedHumanoid
	if not humanoid then
		return
	end

	humanoid.Jump = isJumping

	local camera = Workspace.CurrentCamera
	if camera and joystickState.MoveVector.Magnitude > 0 then
		local camCF = camera.CFrame
		local flatForward = Vector3.new(camCF.LookVector.X, 0, camCF.LookVector.Z)
		local flatRight = Vector3.new(camCF.RightVector.X, 0, camCF.RightVector.Z)

		if flatForward.Magnitude > 1e-4 and flatRight.Magnitude > 1e-4 then
			local dir = (flatForward.Unit * -joystickState.MoveVector.Y) + (flatRight.Unit * joystickState.MoveVector.X)
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

local function resetTouchState(): ()
	joystickState.IsDragging = false
	joystickState.TouchId = nil
	joystickState.MoveVector = Vector2.zero
	isJumping = false
	jumpTouchId = nil
	if joystickBase then
		joystickBase.Visible = false
	end
	evaluateUpdateLoop()
end

local function updateJoystickPosition(input: InputObject): ()
	local base = joystickBase
	local thumb = joystickThumb
	if not base or not thumb then
		return
	end

	local radius = base.AbsoluteSize.X / 2
	if radius <= 0 then
		return
	end

	local baseCenter = base.AbsolutePosition + (base.AbsoluteSize / 2)
	local diff = Vector2.new(input.Position.X, input.Position.Y) - baseCenter
	local dist = math.min(diff.Magnitude, radius)
	local dir = if diff.Magnitude > 1e-4 then diff.Unit else Vector2.zero

	joystickState.MoveVector = dir * (dist / radius)
	thumb.Position = UDim2.fromOffset(
		(base.AbsoluteSize.X / 2) + (dir.X * dist),
		(base.AbsoluteSize.Y / 2) + (dir.Y * dist)
	)
end

function ControlPhone:Enable(): ()
	self:Disable()

	local playerGui = localPlayer:WaitForChild("PlayerGui") :: PlayerGui
	local hud = playerGui:WaitForChild("GameHUD", 10)
	if not hud or not hud:IsA("ScreenGui") then
		warn("[ControlPhone] GameHUD missing")
		return
	end

	local joystickBaseInst = hud:WaitForChild("JoystickBase", 5)
	local jumpButtonInst = hud:WaitForChild("JumpButton", 5)
	if not joystickBaseInst or not joystickBaseInst:IsA("Frame") or not jumpButtonInst or not jumpButtonInst:IsA("ImageButton") then
		warn("[ControlPhone] JoystickBase or JumpButton missing")
		return
	end

	local joystickThumbInst = joystickBaseInst:WaitForChild("JoystickThumb", 5)
	if not joystickThumbInst or not joystickThumbInst:IsA("ImageButton") then
		warn("[ControlPhone] JoystickThumb missing")
		return
	end

	joystickBase = joystickBaseInst
	joystickThumb = joystickThumbInst

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

	local camera = Workspace.CurrentCamera
	if camera then
		viewportSize = camera.ViewportSize
		table.insert(activeConnections, camera:GetPropertyChangedSignal("ViewportSize"):Connect(function()
			viewportSize = camera.ViewportSize
		end))
	end

	table.insert(activeConnections, UserInputService.InputBegan:Connect(function(input: InputObject, processed: boolean)
		if processed then
			return
		end

		if isPointerInput(input) and isWithinTouchZone(input.Position) then
			joystickState.IsDragging = true
			joystickState.TouchId = input

			joystickBaseInst.Position = UDim2.fromOffset(input.Position.X, input.Position.Y)
			joystickThumbInst.Position = UDim2.fromScale(0.5, 0.5)
			joystickState.MoveVector = Vector2.zero
			joystickBaseInst.Visible = true
			evaluateUpdateLoop()
		end
	end))

	table.insert(activeConnections, UserInputService.InputChanged:Connect(function(input: InputObject)
		if joystickState.IsDragging and input == joystickState.TouchId then
			updateJoystickPosition(input)
		end
	end))

	table.insert(activeConnections, UserInputService.InputEnded:Connect(function(input: InputObject)
		if input == joystickState.TouchId then
			joystickState.IsDragging = false
			joystickState.TouchId = nil
			joystickState.MoveVector = Vector2.zero
			joystickBaseInst.Visible = false
			evaluateUpdateLoop()
		elseif input == jumpTouchId then
			jumpTouchId = nil
			isJumping = false
			evaluateUpdateLoop()
		end
	end))

	table.insert(activeConnections, jumpButtonInst.InputBegan:Connect(function(input: InputObject)
		if isPointerInput(input) then
			jumpTouchId = input
			isJumping = true
			evaluateUpdateLoop()
		end
	end))

	table.insert(activeConnections, jumpButtonInst.InputEnded:Connect(function(input: InputObject)
		if input == jumpTouchId or isPointerInput(input) then
			jumpTouchId = nil
			isJumping = false
			evaluateUpdateLoop()
		end
	end))

	table.insert(activeConnections, GuiService.MenuOpened:Connect(resetTouchState))
	table.insert(activeConnections, UserInputService.WindowFocusReleased:Connect(resetTouchState))

	evaluateUpdateLoop()
end

function ControlPhone:Disable(): ()
	for _, connection in activeConnections do
		connection:Disconnect()
	end
	table.clear(activeConnections)

	if updateConnection then
		updateConnection:Disconnect()
		updateConnection = nil
	end

	charWaitGeneration += 1
	resetTouchState()
	cachedHumanoid = nil
end

return ControlPhone
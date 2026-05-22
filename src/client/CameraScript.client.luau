--!strict
--[[
	CameraScript
	Main camera controller: initializes PC/Phone modules, detects input device in real time,
	and drives the active module on RenderStep. Preserves rotation/zoom when switching.
]]

local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local UserInputService = game:GetService("UserInputService")

local CameraPC = require(script.Parent.modules.CameraPC)
local CameraPhone = require(script.Parent.modules.CameraPhone)

type CameraViewState = CameraPC.CameraViewState
type CameraController = CameraPC.CameraPC | CameraPhone.CameraPhone

local RENDER_STEP_NAME = "CubitCombatCustomCamera"
local RENDER_STEP_PRIORITY = Enum.RenderPriority.Camera.Value
local FOCUS_HEIGHT_OFFSET = 2

-- Keyboard/mouse input types force the PC module, even on touch-capable devices.
local KEYBOARD_MOUSE_INPUT_TYPES: { [Enum.UserInputType]: boolean } = {
	[Enum.UserInputType.Keyboard] = true,
	[Enum.UserInputType.MouseButton1] = true,
	[Enum.UserInputType.MouseButton2] = true,
	[Enum.UserInputType.MouseButton3] = true,
	[Enum.UserInputType.MouseWheel] = true,
	[Enum.UserInputType.MouseMovement] = true,
}

local player = Players.LocalPlayer :: Player
local cameraPC = CameraPC.new()
local cameraPhone = CameraPhone.new()

local isCameraRunning = false
local lastInputType: Enum.UserInputType? = UserInputService:GetLastInputType()

--[[
	Returns true when the given input type is keyboard or mouse driven.
]]
local function isKeyboardMouseInput(inputType: Enum.UserInputType): boolean
	return KEYBOARD_MOUSE_INPUT_TYPES[inputType] == true
end

--[[
	Returns true when Bluetooth/desktop keyboard or mouse hardware is available.
]]
local function hasKeyboardMouseHardware(): boolean
	return UserInputService.KeyboardEnabled or UserInputService.MouseEnabled
end

--[[
	Decides whether the PC module should be active from hardware and recent input.
	Touch-only mobile stays on Phone until keyboard/mouse is used or detected.
]]
local function shouldUsePCModule(recentInputType: Enum.UserInputType?): boolean
	if recentInputType and isKeyboardMouseInput(recentInputType) then
		return true
	end

	if recentInputType == Enum.UserInputType.Touch then
		return false
	end

	return hasKeyboardMouseHardware()
end

local activeController: CameraController = if shouldUsePCModule(lastInputType)
	then cameraPC
	else cameraPhone

--[[
	Returns the world position the camera should look at for the local character.
]]
local function getFocusOrigin(character: Model): Vector3?
	local rootPart = character:FindFirstChild("HumanoidRootPart") :: BasePart?
	if not rootPart then
		return nil
	end

	return rootPart.Position + Vector3.new(0, FOCUS_HEIGHT_OFFSET, 0)
end

--[[
	Builds the exclude list for CameraCore spherecasts.
]]
local currentCharacter: Model? = nil
local currentFilterInstances: { Instance } = {}

local function getFilterInstances(character: Model): { Instance }
	-- Jeśli postać się nie zmieniła, użyj tej samej tabeli w pamięci
	if character == currentCharacter then
		return currentFilterInstances
	end
	
	-- Zaktualizuj tylko, gdy postać jest nowa (np. po śmierci)
	currentCharacter = character
	currentFilterInstances = { character }
	return currentFilterInstances
end

--[[
	Activates PC or Phone module and transfers the current camera view state.
]]
local function setActiveController(usePCModule: boolean): ()
	local incoming: CameraController = if usePCModule then cameraPC else cameraPhone
	if incoming == activeController then
		incoming:Enable()
		return
	end

	local outgoing = activeController
	local viewState: CameraViewState = outgoing:GetViewState()

	outgoing:Disable()
	incoming:ApplyViewState(viewState)
	incoming:Enable()
	activeController = incoming
end

--[[
	Re-evaluates the active module from the latest input type and hardware flags.
]]
local function updateActiveControllerFromInput(recentInputType: Enum.UserInputType?): ()
	setActiveController(shouldUsePCModule(recentInputType))
end

--[[
	Render-step callback: one Update per frame, then apply CFrame to the workspace camera.
]]
local function onRenderStep(deltaTime: number): ()
	local character = player.Character
	if not character then
		return
	end

	local focusOrigin = getFocusOrigin(character)
	if not focusOrigin then
		return
	end

	local output = activeController:Update({
		focusOrigin = focusOrigin,
		deltaTime = deltaTime,
		filterInstances = getFilterInstances(character),
	})

	local camera = workspace.CurrentCamera
	if not camera then
		return
	end

	camera.CameraType = Enum.CameraType.Scriptable
	camera.CFrame = output.cframe
	camera.Focus = CFrame.new(output.focus)
end

--[[
	Initializes scriptable camera control and binds the render-step loop.
]]
local function startCamera(): ()
	if isCameraRunning then
		return
	end

	isCameraRunning = true

	local camera = workspace.CurrentCamera
	if camera then
		camera.CameraType = Enum.CameraType.Scriptable
	end

	updateActiveControllerFromInput(lastInputType)
	RunService:BindToRenderStep(RENDER_STEP_NAME, RENDER_STEP_PRIORITY, onRenderStep)
end

--[[
	Stops custom camera control and restores default camera behavior.
]]
local function stopCamera(): ()
	if not isCameraRunning then
		return
	end

	isCameraRunning = false

	RunService:UnbindFromRenderStep(RENDER_STEP_NAME)
	cameraPC:Disable()
	cameraPhone:Disable()

	local camera = workspace.CurrentCamera
	if camera then
		camera.CameraType = Enum.CameraType.Custom
	end
end

local function onCharacterAdded(_character: Instance): ()
	startCamera()
end

local function onCharacterRemoving(): ()
	stopCamera()
end

-- Initialize modules and input switching before the first character spawns.
cameraPC:Disable()
cameraPhone:Disable()
updateActiveControllerFromInput(UserInputService:GetLastInputType())

UserInputService.LastInputTypeChanged:Connect(function(inputType: Enum.UserInputType)
	lastInputType = inputType
	if not isCameraRunning then
		return
	end

	updateActiveControllerFromInput(inputType)
end)

player.CharacterAdded:Connect(onCharacterAdded)
player.CharacterRemoving:Connect(onCharacterRemoving)

if player.Character then
	startCamera()
end
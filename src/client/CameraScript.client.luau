--!strict
--!native
--[[
    CameraScript (LocalScript Exception)
    Main camera controller: Drives the active module on RenderStep.
    Consumes InputManager for device context.
]]

local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local Workspace = game:GetService("Workspace")

-- Modules
local Modules = script.Parent.modules
local CameraPC = require(Modules.CameraPC)
local CameraPhone = require(Modules.CameraPhone)
local InputManager = require(Modules.InputManager)

-- Types
type CameraViewState = any -- Defined in CameraPC/Phone modules

-- Constants
local RENDER_STEP_NAME = "CubitCombatCustomCamera"
local RENDER_STEP_PRIORITY = Enum.RenderPriority.Camera.Value
local FOCUS_HEIGHT_OFFSET = 2

-- Localization (Rule 3.2)
local vector3_new = Vector3.new
local cframe_new = CFrame.new

-- State
local _player = Players.LocalPlayer
local _cameraPC = CameraPC.new()
local _cameraPhone = CameraPhone.new()
local _isCameraRunning = false
local _isPCActive = true

local _currentCharacter: Model? = nil
local _currentFilterInstances: { Instance } = {}

--[[
    Returns the world position the camera should look at.
]]
local function getFocusOrigin(character: Model): Vector3?
	local rootPart = character:FindFirstChild("HumanoidRootPart") :: BasePart?
	if not rootPart then return nil end
	return rootPart.Position + vector3_new(0, FOCUS_HEIGHT_OFFSET, 0)
end

--[[
    Builds the exclude list for spherecasts.
]]
local function getFilterInstances(character: Model): { Instance }
	if character == _currentCharacter then
		return _currentFilterInstances
	end
	_currentCharacter = character
	_currentFilterInstances = { character }
	return _currentFilterInstances
end

--[[
    Activates the correct module and transfers ViewState.
]]
local function setActiveController(device: "PC" | "Phone"): ()
	local usePC = (device == "PC")
	
	if usePC == _isPCActive then
		if usePC then _cameraPC:Enable() else _cameraPhone:Enable() end
		return
	end

	local viewState: CameraViewState
	if _isPCActive then
		viewState = _cameraPC:GetViewState()
		_cameraPC:Disable()
		_cameraPhone:ApplyViewState(viewState)
		_cameraPhone:Enable()
	else
		viewState = _cameraPhone:GetViewState()
		_cameraPhone:Disable()
		_cameraPC:ApplyViewState(viewState)
		_cameraPC:Enable()
	end

	_isPCActive = usePC
end

--[[
    Render-step callback.
]]
local function onRenderStep(deltaTime: number): ()
	local character = _player.Character
	if not character then return end

	local focusOrigin = getFocusOrigin(character)
	if not focusOrigin then return end

	local input = {
		focusOrigin = focusOrigin,
		deltaTime = deltaTime,
		filterInstances = getFilterInstances(character),
	}

	local output
	if _isPCActive then
		output = _cameraPC:Update(input)
	else
		output = _cameraPhone:Update(input)
	end

	local camera = Workspace.CurrentCamera
	if not camera then return end

	camera.CameraType = Enum.CameraType.Scriptable
	camera.CFrame = output.cframe
	camera.Focus = cframe_new(output.focus)
end

local function startCamera(): ()
	if _isCameraRunning then return end
	_isCameraRunning = true

	local camera = Workspace.CurrentCamera
	if camera then camera.CameraType = Enum.CameraType.Scriptable end

	setActiveController(InputManager:GetDeviceType())
	RunService:BindToRenderStep(RENDER_STEP_NAME, RENDER_STEP_PRIORITY, onRenderStep)
end

local function stopCamera(): ()
	if not _isCameraRunning then return end
	_isCameraRunning = false

	RunService:UnbindFromRenderStep(RENDER_STEP_NAME)
	_cameraPC:Disable()
	_cameraPhone:Disable()

	local camera = Workspace.CurrentCamera
	if camera then camera.CameraType = Enum.CameraType.Custom end
end

-- Initialization
_cameraPC:Disable()
_cameraPhone:Disable()

-- Listen for device changes from InputManager
InputManager:OnDeviceChanged(function(newDevice)
	if _isCameraRunning then
		setActiveController(newDevice)
	end
end)

_player.CharacterAdded:Connect(startCamera)
_player.CharacterRemoving:Connect(stopCamera)

if _player.Character then
	startCamera()
end
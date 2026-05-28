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
local Controllers = Modules.Controllers

local CameraPC = require(Controllers.CameraPC)
local CameraPhone = require(Controllers.CameraPhone)
local InputManager = require(Modules.InputManager)
local CameraCore = require(Controllers.CameraCore)

-- Types
type CameraViewState = any -- Defined in CameraPC/Phone modules

-- Constants
local RENDER_STEP_NAME = "CubitCombatCustomCamera"
local RENDER_STEP_PRIORITY = Enum.RenderPriority.Camera.Value
local FOCUS_HEIGHT_OFFSET = 2

-- Localization (Rule 3.2)
local vector3_new = Vector3.new
local cframe_new = CFrame.new

-- Orchestrator Interface for Controllers
local CameraScript = {}

-- State
local _player = Players.LocalPlayer
local _isShiftLocked = false
local _cameraPC = CameraPC.new({ orchestrator = CameraScript })
local _cameraPhone = CameraPhone.new()
local _isCameraRunning = false
local _isPCActive = true

local _currentCharacter: Model? = nil
local _currentFilterInstances: { Instance } = {}

local _playerGui = _player:WaitForChild("PlayerGui")
local _buttonConnection: RBXScriptConnection? = nil

--[[
    Attempts to safely locate the ShiftlockButton in the PlayerGui with timeouts to avoid yielding.
]]
local function getShiftlockButton(): GuiButton?
	local mainHUD = _playerGui:FindFirstChild("MainHUD") or _playerGui:WaitForChild("MainHUD", 5)
	if not mainHUD then return nil end
	
	local buttons = mainHUD:FindFirstChild("Buttons") or mainHUD:WaitForChild("Buttons", 5)
	if not buttons then return nil end
	
	return (buttons:FindFirstChild("ShiftlockButton") or buttons:WaitForChild("ShiftlockButton", 5)) :: GuiButton?
end

--[[
    Toggles the internal Shift Lock state and updates the underlying CameraCore instances.
]]
function CameraScript:ToggleShiftLock(): ()
	_isShiftLocked = not _isShiftLocked
	
	-- Update the active core logic instances
	if _cameraPC and _cameraPC._core then
		_cameraPC._core:ApplyShiftLock(_isShiftLocked)
	end
	if _cameraPhone and (_cameraPhone :: any)._core then
		(_cameraPhone :: any)._core:ApplyShiftLock(_isShiftLocked)
	end
end

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
    Activates the correct module, transfers ViewState, and handles ShiftlockButton visibility.
]]
local function setActiveController(device: "PC" | "Phone"): ()
	local usePC = (device == "PC")
	_isPCActive = usePC

	-- Control UI visibility based on the active controller
	local button = getShiftlockButton()
	if button then
		button.Visible = not usePC
	end
	
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
end

--[[
    Sets up the ShiftlockButton click event and updates its visibility.
]]
local function setupShiftlockButton(): ()
	if _buttonConnection then
		_buttonConnection:Disconnect()
		_buttonConnection = nil
	end

	local button = getShiftlockButton()
	if button then
		button.Visible = not _isPCActive
		
		_buttonConnection = button.Activated:Connect(function()
			CameraScript:ToggleShiftLock()
		end)
	end
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
	setupShiftlockButton()
	RunService:BindToRenderStep(RENDER_STEP_NAME, RENDER_STEP_PRIORITY, onRenderStep)
end

local function stopCamera(): ()
	if not _isCameraRunning then return end
	_isCameraRunning = false

	-- Clean up active Shift Lock connections to prevent memory/physics loops on character reset
	if _isShiftLocked then
		CameraScript:ToggleShiftLock()
	end

	if _buttonConnection then
		_buttonConnection:Disconnect()
		_buttonConnection = nil
	end

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
--!strict
--!native
local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local UserInputService = game:GetService("UserInputService")
local Workspace = game:GetService("Workspace")

local modulesFolder = script.Parent:WaitForChild("modules") :: Folder
local controllersFolder = modulesFolder:WaitForChild("Controllers") :: Folder

local CameraInput = require(controllersFolder:WaitForChild("CameraInput"))
local CharacterManager = require(controllersFolder:WaitForChild("CharacterManager"))
local InputManager = require(controllersFolder:WaitForChild("InputManager"))

local CameraScript = {}

local STARTING_ZOOM = 15
local STARTING_PITCH = math.rad(-4)
local MIN_PITCH = math.rad(-70)
local MAX_PITCH = math.rad(70)
local MIN_ZOOM = 0.5
local MAX_ZOOM = 25
local ZOOM_LERP_SPEED = 32
local FOCUS_OFFSET = Vector3.new(0, 2, 0)
local SPHERE_RADIUS = 0.4
local COLLISION_PADDING = 0.1

local yaw: number = 0
local pitch: number = STARTING_PITCH
local targetZoom: number = STARTING_ZOOM
local actualZoom: number = STARTING_ZOOM
local isShiftLocked: boolean = false
local isRunning: boolean = false
local startGeneration: number = 0

local activeCamera: Camera? = Workspace.CurrentCamera
local currentMouseBehavior: Enum.MouseBehavior = Enum.MouseBehavior.Default
local currentMouseIconEnabled: boolean = true
local cachedRootPart: BasePart? = nil

local raycastParams = RaycastParams.new()
raycastParams.CollisionGroup = "Camera"
raycastParams.IgnoreWater = true
raycastParams.RespectCanCollide = true

Workspace:GetPropertyChangedSignal("CurrentCamera"):Connect(function()
	activeCamera = Workspace.CurrentCamera
end)

local function resolveCollision(focus: Vector3, lookVector: Vector3, distance: number): Vector3
	if distance < 1e-4 then
		return focus
	end

	local backward = -lookVector
	local castVector = backward * distance
	local result = Workspace:Spherecast(focus, SPHERE_RADIUS, castVector, raycastParams)
	if result then
		local safeDistance = math.max(result.Distance - COLLISION_PADDING, 0)
		return focus + backward * safeDistance
	end

	return focus + castVector
end

function CameraScript.ToggleShiftLock(): ()
	isShiftLocked = not isShiftLocked
end

local function onRenderStep(deltaTime: number): ()
	local rootPart = cachedRootPart
	if not rootPart or not rootPart.Parent then
		return
	end

	local isRMBDown = CameraInput.IsDragging()
	local shouldLockMouse = isShiftLocked or isRMBDown
	local targetBehavior = if shouldLockMouse then Enum.MouseBehavior.LockCurrentPosition else Enum.MouseBehavior.Default
	local targetIconEnabled = not shouldLockMouse

	if currentMouseBehavior ~= targetBehavior then
		currentMouseBehavior = targetBehavior
		UserInputService.MouseBehavior = targetBehavior
	end

	if currentMouseIconEnabled ~= targetIconEnabled then
		currentMouseIconEnabled = targetIconEnabled
		UserInputService.MouseIconEnabled = targetIconEnabled
	end

	local dyaw, dpitch, dzoom = CameraInput.GetDeltas()
	if isShiftLocked then
		dzoom = 0
	end

	yaw = (yaw + dyaw) % (math.pi * 2)
	pitch = math.clamp(pitch + dpitch, MIN_PITCH, MAX_PITCH)
	targetZoom = math.clamp(targetZoom + dzoom, MIN_ZOOM, MAX_ZOOM)

	if deltaTime > 0 then
		local alpha = 1 - math.exp(-ZOOM_LERP_SPEED * math.min(deltaTime, 0.1))
		actualZoom = actualZoom + (targetZoom - actualZoom) * alpha
	end

	local isFirstPerson = actualZoom <= MIN_ZOOM + 0.1
	local shouldRotateCharacter = isShiftLocked or isFirstPerson

	local rotation = CFrame.fromEulerAnglesYXZ(pitch, yaw, 0)
	local lookVector = rotation.LookVector
	local focus = rootPart.Position + FOCUS_OFFSET
	local cameraDistance = if isFirstPerson then 0 else actualZoom
	local cameraPos = resolveCollision(focus, lookVector, cameraDistance)

	local camera = activeCamera
	if camera then
		if camera.CameraType ~= Enum.CameraType.Scriptable then
			camera.CameraType = Enum.CameraType.Scriptable
		end
		camera.CFrame = rotation + cameraPos
		camera.Focus = CFrame.new(focus)
	end

	CharacterManager.Update(isFirstPerson, shouldRotateCharacter, lookVector)
end

function CameraScript.Start(targetCharacter: Model?): ()
	local localPlayer = Players.LocalPlayer :: Player
	local character = targetCharacter or localPlayer.Character
	if not character then
		return
	end

	startGeneration += 1
	local myGeneration = startGeneration

	local foundRoot = character:FindFirstChild("HumanoidRootPart") or character:WaitForChild("HumanoidRootPart", 5)
	if myGeneration ~= startGeneration or not character.Parent or not foundRoot or not foundRoot:IsA("BasePart") then
		return
	end

	if isRunning then
		RunService:UnbindFromRenderStep("CustomCameraSystem")
	end
	isRunning = true

	raycastParams.FilterDescendantsInstances = { character }
	cachedRootPart = foundRoot
	CharacterManager.SetCharacter(character, foundRoot)

	local camera = activeCamera
	if camera then
		local _, cy, _ = camera.CFrame:ToEulerAnglesYXZ()
		pitch = STARTING_PITCH
		yaw = cy
		targetZoom = STARTING_ZOOM
		actualZoom = STARTING_ZOOM
	end

	RunService:BindToRenderStep("CustomCameraSystem", Enum.RenderPriority.Camera.Value, onRenderStep)
end

function CameraScript.Stop(): ()
	startGeneration += 1
	if not isRunning then
		return
	end

	isRunning = false
	RunService:UnbindFromRenderStep("CustomCameraSystem")

	raycastParams.FilterDescendantsInstances = {}
	cachedRootPart = nil
	CharacterManager.SetCharacter(nil)

	if isShiftLocked then
		CameraScript.ToggleShiftLock()
	end

	currentMouseBehavior = Enum.MouseBehavior.Default
	currentMouseIconEnabled = true
	UserInputService.MouseBehavior = Enum.MouseBehavior.Default
	UserInputService.MouseIconEnabled = true

	if activeCamera then
		activeCamera.CameraType = Enum.CameraType.Custom
	end
end

UserInputService.InputBegan:Connect(function(input: InputObject, gameProcessed: boolean)
	if not gameProcessed and input.KeyCode == Enum.KeyCode.LeftShift then
		CameraScript.ToggleShiftLock()
	end
end)

task.spawn(function()
	local localPlayer = Players.LocalPlayer :: Player
	local playerGui = localPlayer:WaitForChild("PlayerGui") :: PlayerGui
	local mainHUD = playerGui:WaitForChild("MainHUD", 10)
	local buttons = if mainHUD then mainHUD:WaitForChild("Buttons", 5) else nil
	local btn = if buttons then buttons:WaitForChild("ShiftlockButton", 5) else nil

	if btn and btn:IsA("GuiButton") then
		btn.Activated:Connect(CameraScript.ToggleShiftLock)
		btn.Visible = (InputManager:GetDeviceType() == "Phone")

		InputManager:OnDeviceChanged(function(newDevice)
			btn.Visible = (newDevice == "Phone")
		end)
	end
end)

local localPlayer = Players.LocalPlayer :: Player
localPlayer.CharacterAdded:Connect(function(character: Model)
	CameraScript.Start(character)
end)
localPlayer.CharacterRemoving:Connect(function()
	CameraScript.Stop()
end)

if localPlayer.Character then
	task.spawn(CameraScript.Start, localPlayer.Character)
end

return CameraScript
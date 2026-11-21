--!strict
--!native
local RunService = game:GetService("RunService")
local Workspace = game:GetService("Workspace")
local Players = game:GetService("Players")
local UserInputService = game:GetService("UserInputService")

-- Pathing based on your Explorer hierarchy
local Modules = script.Parent:WaitForChild("modules")
local Controllers = Modules:WaitForChild("controllers")

local CameraInput = require(Controllers:WaitForChild("CameraInput"))
local CharacterManager = require(Controllers:WaitForChild("CharacterManager"))

local CameraScript = {}

-- Constants
local STARTING_ZOOM = 15
local STARTING_PITCH = math.rad(-4) 

local MIN_PITCH = math.rad(-70)
local MAX_PITCH = math.rad(70)
local MIN_ZOOM = 0.5
local MAX_ZOOM = 25
local ZOOM_LERP_SPEED = 32
local FOCUS_OFFSET = Vector3.new(0, 2, 0)
local SHIFT_LOCK_OFFSET = Vector3.new(0, 0, 0)
local SPHERE_RADIUS = 0.4
local COLLISION_PADDING = 0.1
local ORIGIN_EPSILON = 0

-- State
local yaw: number = 0
local pitch: number = STARTING_PITCH
local targetZoom: number = STARTING_ZOOM
local actualZoom: number = STARTING_ZOOM
local isShiftLocked: boolean = false
local isRunning: boolean = false

-- Cached Engine States & Instances (Micro-optimization)
local activeCamera: Camera? = Workspace.CurrentCamera -- Optimized: Cache camera object directly
local currentMouseBehavior: Enum.MouseBehavior = Enum.MouseBehavior.Default
local currentMouseIconEnabled: boolean = true
local cachedFilterArray: {Instance} = {}
local cachedRootPart: BasePart? = nil

local raycastParams = RaycastParams.new()
raycastParams.CollisionGroup = "Camera"
raycastParams.IgnoreWater = true
raycastParams.RespectCanCollide = true

-- Optimized: Watch for Camera changes globally
Workspace:GetPropertyChangedSignal("CurrentCamera"):Connect(function()
    activeCamera = Workspace.CurrentCamera
end)

local function resolveCollision(focus: Vector3, lookVector: Vector3, distance: number): Vector3
    if distance < 1e-4 then return focus end
    
    local backward = -lookVector
    local castOrigin = focus + backward * ORIGIN_EPSILON
    local castDistance = math.max(distance - ORIGIN_EPSILON, 0)
    local castVector = backward * castDistance
    
    if castDistance < 1e-4 then
        return focus + backward * distance
    end
    
    local result = Workspace:Spherecast(castOrigin, SPHERE_RADIUS, castVector, raycastParams)
    if result then
        local safeDistance = math.max(result.Distance - COLLISION_PADDING, 0)
        return castOrigin + backward * safeDistance
    end
    
    return focus + backward * distance
end

function CameraScript.ToggleShiftLock()
    isShiftLocked = not isShiftLocked
end

local function onRenderStep(deltaTime: number)
    if not cachedRootPart then return end
    
    -- Enforce Mouse State for PC Right-Click & Shift Lock (Optimized)
    local isRMBDown = CameraInput.IsDragging()
    local shouldLockMouse = isShiftLocked or isRMBDown
    local targetBehavior = shouldLockMouse and Enum.MouseBehavior.LockCurrentPosition or Enum.MouseBehavior.Default
    local targetIconEnabled = not shouldLockMouse
    
    -- Only write to the engine API if the state actually changed
    if currentMouseBehavior ~= targetBehavior then
        currentMouseBehavior = targetBehavior
        UserInputService.MouseBehavior = targetBehavior
    end
    
    if currentMouseIconEnabled ~= targetIconEnabled then
        currentMouseIconEnabled = targetIconEnabled
        UserInputService.MouseIconEnabled = targetIconEnabled
    end
    
    -- 1. Accumulate Input
    local dyaw, dpitch, dzoom = CameraInput.GetDeltas()
    
    -- Discard zoom input if Shift Lock is active
    if isShiftLocked then
        dzoom = 0
    end
    
    yaw = (yaw + dyaw) % (math.pi * 2)
    pitch = math.clamp(pitch + dpitch, MIN_PITCH, MAX_PITCH)
    targetZoom = math.clamp(targetZoom + dzoom, MIN_ZOOM, MAX_ZOOM)
    
    -- 2. Lerp Zoom
    if deltaTime > 0 then
        local alpha = 1 - math.exp(-ZOOM_LERP_SPEED * math.min(deltaTime, 0.1))
        actualZoom = actualZoom + (targetZoom - actualZoom) * alpha
    end
    
    local isFirstPerson = actualZoom <= MIN_ZOOM + 0.1
    local shouldRotateCharacter = isShiftLocked or isFirstPerson
    
    -- 3. Calculate Pose
    local rotation = CFrame.fromEulerAnglesYXZ(pitch, yaw, 0)
    local lookVector = rotation.LookVector
    
    local focus = cachedRootPart.Position + FOCUS_OFFSET
    if isShiftLocked and not isFirstPerson then
        focus += rotation * SHIFT_LOCK_OFFSET
    end
    
    local cameraDistance = isFirstPerson and 0 or actualZoom
    local cameraPos = resolveCollision(focus, lookVector, cameraDistance)
    
    -- 4. Apply to Camera (Optimized with cached camera & write reduction)
    local camera = activeCamera
    if camera then
        if camera.CameraType ~= Enum.CameraType.Scriptable then
            camera.CameraType = Enum.CameraType.Scriptable
        end
        camera.CFrame = rotation + cameraPos 
        camera.Focus = CFrame.new(focus)
    end
    
    -- 5. Update Character
    CharacterManager.Update(isFirstPerson, shouldRotateCharacter, lookVector)
end

function CameraScript.Start()
    if isRunning then return end
    isRunning = true
    
    local player = Players.LocalPlayer
    local character = player and player.Character
    
    -- Cache the character array and RootPart once upon starting
    if character then
        cachedFilterArray = {character}
        raycastParams.FilterDescendantsInstances = cachedFilterArray
        cachedRootPart = character:WaitForChild("HumanoidRootPart", 5) :: BasePart?
        CharacterManager.SetCharacter(character)
    end
    
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

function CameraScript.Stop()
    if not isRunning then return end
    isRunning = false
    RunService:UnbindFromRenderStep("CustomCameraSystem")
    
    -- Clear the cached array to prevent memory leaks
    cachedFilterArray = {}
    raycastParams.FilterDescendantsInstances = cachedFilterArray
    cachedRootPart = nil
    CharacterManager.SetCharacter(nil)
    
    if isShiftLocked then CameraScript.ToggleShiftLock() end
    if activeCamera then activeCamera.CameraType = Enum.CameraType.Custom end
end

-- Input & UI Setup
UserInputService.InputBegan:Connect(function(input, gameProcessed)
    if not gameProcessed and input.KeyCode == Enum.KeyCode.LeftShift then
        CameraScript.ToggleShiftLock()
    end
end)

task.spawn(function()
    local playerGui = Players.LocalPlayer:WaitForChild("PlayerGui") :: PlayerGui
    local mainHUD = playerGui:WaitForChild("MainHUD", 5)
    local buttons = mainHUD and mainHUD:WaitForChild("Buttons", 5)
    local btn = buttons and buttons:WaitForChild("ShiftlockButton", 5) :: GuiButton?
    
    if btn then
        btn.Activated:Connect(CameraScript.ToggleShiftLock)
        btn.Visible = UserInputService.TouchEnabled
    end
end)

-- Auto-Start Lifecycle
task.spawn(function()
    local player = Players.LocalPlayer
    if not player then
        Players:GetPropertyChangedSignal("LocalPlayer"):Wait()
        player = Players.LocalPlayer
    end
    
    local confirmedPlayer = player :: Player
    
    confirmedPlayer.CharacterAdded:Connect(function() CameraScript.Start() end)
    confirmedPlayer.CharacterRemoving:Connect(function() CameraScript.Stop() end)
    
    if confirmedPlayer.Character then 
        CameraScript.Start() 
    end
end)

return CameraScript
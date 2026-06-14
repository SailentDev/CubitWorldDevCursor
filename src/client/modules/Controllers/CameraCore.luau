--!strict
--!native
--[[
	CameraCore
	Shared third-person camera math: spherecast collision, smoothed zoom distance,
	and instantaneous positional/orientational updates for responsive feel.
	Includes highly optimized First-Person logic with part caching.
]]

local Players = game:GetService("Players")
local UserInputService = game:GetService("UserInputService")
local Workspace = game:GetService("Workspace")

local LocalPlayer = Players.LocalPlayer

export type CameraCoreConfig = {
	sphereRadius: number?,
	minDistance: number?,
	maxDistance: number?,
	defaultDistance: number?,
	zoomLerpSpeed: number?,
	collisionPadding: number?,
	raycastOriginEpsilon: number?,
}

export type CameraUpdateInput = {
	focusOrigin: Vector3,
	rotation: CFrame,
	targetDistance: number,
	deltaTime: number,
	filterInstances: { Instance }?,
}

export type CameraUpdateOutput = {
	cframe: CFrame,
	focus: Vector3,
	distance: number,
}

export type CameraCore = {
	_sphereRadius: number,
	_minDistance: number,
	_maxDistance: number,
	_zoomLerpSpeed: number,
	_collisionPadding: number,
	_raycastOriginEpsilon: number,
	_smoothedDistance: number,
	_raycastParams: RaycastParams,
	_shiftLockActive: boolean,
	
	-- Caching for performance
	_lastCharacter: Model?,
	_lastRootPart: BasePart?,
	_cachedCharacterParts: { BasePart },
	_characterAddedConn: RBXScriptConnection?,
	_characterDescendantAddedConn: RBXScriptConnection?,
	
	Update: (self: CameraCore, input: CameraUpdateInput) -> CameraUpdateOutput,
	SetFilterInstances: (self: CameraCore, instances: { Instance }) -> (),
	GetSmoothedDistance: (self: CameraCore) -> number,
	ResetZoom: (self: CameraCore, distance: number?) -> (),
	_resolveCollision: (self: CameraCore, focus: Vector3, lookVector: Vector3, distance: number) -> Vector3,
	GetLimits: (self: CameraCore) -> (number, number),
	ApplyShiftLock: (self: CameraCore, isActive: boolean) -> (),
	_updateCharacterCache: (self: CameraCore, character: Model) -> (),
}

local DEFAULT_SPHERE_RADIUS = 0.25
local DEFAULT_MIN_DISTANCE = 0.5 -- Lowered for first person
local DEFAULT_MAX_DISTANCE = 28
local DEFAULT_DISTANCE = 20
local DEFAULT_ZOOM_LERP_SPEED = 16
local DEFAULT_COLLISION_PADDING = 0.15
local DEFAULT_ORIGIN_EPSILON = 0.1

local SHIFT_LOCK_OFFSET = Vector3.new(0, 0, 0)
local EPSILON = 1e-4

local CameraCore = {}
CameraCore.__index = CameraCore

local function lerpZoom(current: number, target: number, speed: number, deltaTime: number): number
	if deltaTime <= 0 then return target end
	local clampedDT = math.min(deltaTime, 0.1)
	local alpha = 1 - math.exp(-speed * clampedDT)
	return current + (target - current) * alpha
end

function CameraCore.new(config: CameraCoreConfig?): CameraCore
	local resolvedConfig: CameraCoreConfig = config or {}
	local self = setmetatable({}, CameraCore) :: any

	self._sphereRadius = resolvedConfig.sphereRadius or DEFAULT_SPHERE_RADIUS
	self._minDistance = resolvedConfig.minDistance or DEFAULT_MIN_DISTANCE
	self._maxDistance = resolvedConfig.maxDistance or DEFAULT_MAX_DISTANCE
	self._zoomLerpSpeed = resolvedConfig.zoomLerpSpeed or DEFAULT_ZOOM_LERP_SPEED
	self._collisionPadding = resolvedConfig.collisionPadding or DEFAULT_COLLISION_PADDING
	self._raycastOriginEpsilon = resolvedConfig.raycastOriginEpsilon or DEFAULT_ORIGIN_EPSILON

	local defaultDistance = resolvedConfig.defaultDistance or DEFAULT_DISTANCE
	self._smoothedDistance = math.clamp(defaultDistance, self._minDistance, self._maxDistance)

	self._raycastParams = RaycastParams.new()
	self._raycastParams.CollisionGroup = "Camera"
	self._raycastParams.IgnoreWater = true
	self._raycastParams.RespectCanCollide = true
	
	self._shiftLockActive = false
	self._lastCharacter = nil
	self._lastRootPart = nil
	self._cachedCharacterParts = {}

	return (self :: any) :: CameraCore
end

-- Updates the internal cache of character parts to avoid calling GetDescendants() every frame
function CameraCore._updateCharacterCache(self: CameraCore, character: Model)
	self._lastCharacter = character
	self._lastRootPart = character:FindFirstChild("HumanoidRootPart") :: BasePart?
	
	table.clear(self._cachedCharacterParts)
	
	for _, descendant in character:GetDescendants() do
		if descendant:IsA("BasePart") and descendant.Name ~= "HumanoidRootPart" then
			table.insert(self._cachedCharacterParts, descendant)
		end
	end
	
	-- Listen for new parts (like equipping tools or armor)
	if self._characterDescendantAddedConn then
		self._characterDescendantAddedConn:Disconnect()
	end
	self._characterDescendantAddedConn = character.DescendantAdded:Connect(function(descendant)
		if descendant:IsA("BasePart") and descendant.Name ~= "HumanoidRootPart" then
			table.insert(self._cachedCharacterParts, descendant)
		end
	end)
end

function CameraCore.SetFilterInstances(self: CameraCore, instances: { Instance }): () end

function CameraCore.GetSmoothedDistance(self: CameraCore): number
	return self._smoothedDistance
end

function CameraCore.ResetZoom(self: CameraCore, distance: number?): ()
	local resolved = distance or self._smoothedDistance
	self._smoothedDistance = math.clamp(resolved, self._minDistance, self._maxDistance)
end

function CameraCore._resolveCollision(self: CameraCore, focus: Vector3, lookVector: Vector3, distance: number): Vector3
	local backward = -lookVector
	local castDirection = backward * distance
	local castLength = castDirection.Magnitude

	if castLength < EPSILON then return focus end

	local castOrigin = focus + backward.Unit * self._raycastOriginEpsilon
	local castVector = backward * math.max(castLength - self._raycastOriginEpsilon, 0)

	if castVector.Magnitude < EPSILON then return focus + castDirection end

	local result = Workspace:Spherecast(castOrigin, self._sphereRadius, castVector, self._raycastParams)
	if not result then return focus + castDirection end

	local safeDistance = math.max(result.Distance - self._collisionPadding, 0)
	return castOrigin + backward.Unit * safeDistance
end

function CameraCore.Update(self: CameraCore, input: CameraUpdateInput): CameraUpdateOutput
	local clampedTarget = math.clamp(input.targetDistance, self._minDistance, self._maxDistance)
	self._smoothedDistance = lerpZoom(self._smoothedDistance, clampedTarget, self._zoomLerpSpeed, input.deltaTime)

	local isFirstPerson = clampedTarget <= self._minDistance + 0.1
	local shouldRotateCharacter = self._shiftLockActive or isFirstPerson

	if LocalPlayer then
		local character = LocalPlayer.Character
		if character then
			-- Update cache if character changed
			if character ~= self._lastCharacter then
				self:_updateCharacterCache(character)
			end
			
			-- 1. Handle Humanoid AutoRotate
			local humanoid = character:FindFirstChildOfClass("Humanoid")
			if humanoid then
				if humanoid.AutoRotate == shouldRotateCharacter then
					humanoid.AutoRotate = not shouldRotateCharacter
				end
			end

			-- 2. Handle Character Rotation
			if shouldRotateCharacter then
				local rootPart = self._lastRootPart
				if rootPart then
					local lookVector = input.rotation.LookVector
					local horizontalLook = Vector3.new(lookVector.X, 0, lookVector.Z)
					if horizontalLook.Magnitude > EPSILON then
						rootPart.CFrame = CFrame.lookAt(rootPart.Position, rootPart.Position + horizontalLook.Unit)
					end
				end
			end

			-- 3. Handle First Person Character Transparency (Using Cache)
			-- Note: Roblox's engine resets LocalTransparencyModifier every frame, so we MUST apply it every frame.
			local transparency = isFirstPerson and 1 or 0
			for _, part in self._cachedCharacterParts do
				-- Keep tools visible in first person
				if not part:FindFirstAncestorOfClass("Tool") then
					part.LocalTransparencyModifier = transparency
				end
			end
		end
	end

	local focus = input.focusOrigin

	if self._shiftLockActive and not isFirstPerson then
		local offsetWorld = input.rotation:VectorToWorldSpace(SHIFT_LOCK_OFFSET)
		focus = focus + offsetWorld
	end

	local lookVector = input.rotation.LookVector
	local actualDistance = isFirstPerson and 0 or self._smoothedDistance
	local cameraPosition = self:_resolveCollision(focus, lookVector, actualDistance)

	local cframe = input.rotation + cameraPosition

	return {
		cframe = cframe,
		focus = focus,
		distance = (cameraPosition - focus).Magnitude,
	}
end

function CameraCore.GetLimits(self: CameraCore) : (number, number)
	return self._minDistance, self._maxDistance
end

function CameraCore.ApplyShiftLock(self: CameraCore, isActive: boolean): ()
	self._shiftLockActive = isActive

	if isActive then
		if UserInputService.MouseBehavior ~= Enum.MouseBehavior.LockCurrentPosition then
			UserInputService.MouseBehavior = Enum.MouseBehavior.LockCurrentPosition
		end
		if UserInputService.MouseIconEnabled then
			UserInputService.MouseIconEnabled = false
		end
	else
		if UserInputService.MouseBehavior ~= Enum.MouseBehavior.Default then
			UserInputService.MouseBehavior = Enum.MouseBehavior.Default
		end
		if not UserInputService.MouseIconEnabled then
			UserInputService.MouseIconEnabled = true
		end
	end
end

return CameraCore
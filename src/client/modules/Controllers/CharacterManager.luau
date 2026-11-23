--!strict
local CharacterManager = {}

local cachedParts: { BasePart } = {}
local isToolPart: { [BasePart]: boolean } = {}

local descendantAddedConn: RBXScriptConnection? = nil
local descendantRemovingConn: RBXScriptConnection? = nil
local currentCharacter: Model? = nil

local cachedHumanoid: Humanoid? = nil
local cachedRootPart: BasePart? = nil
local currentTransparencyState: number? = nil

local function onDescendantAdded(descendant: Instance): ()
	if descendant:IsA("BasePart") and descendant.Name ~= "HumanoidRootPart" then
		table.insert(cachedParts, descendant)
		local inTool = descendant:FindFirstAncestorOfClass("Tool") ~= nil
		isToolPart[descendant] = inTool

		if currentTransparencyState == 1 and not inTool then
			descendant.LocalTransparencyModifier = 1
		end
	end
end

local function onDescendantRemoving(descendant: Instance): ()
	if descendant:IsA("BasePart") then
		isToolPart[descendant] = nil

		local index = table.find(cachedParts, descendant)
		if index then
			local last = #cachedParts
			if index ~= last then
				cachedParts[index] = cachedParts[last]
			end
			table.remove(cachedParts)
		end
	end
end

function CharacterManager.SetCharacter(character: Model?, rootPartOverride: BasePart?): ()
	if currentCharacter == character then
		return
	end
	currentCharacter = character

	if descendantAddedConn then
		descendantAddedConn:Disconnect()
		descendantAddedConn = nil
	end
	if descendantRemovingConn then
		descendantRemovingConn:Disconnect()
		descendantRemovingConn = nil
	end

	table.clear(cachedParts)
	table.clear(isToolPart)
	currentTransparencyState = nil

	if character then
		cachedHumanoid = character:FindFirstChildOfClass("Humanoid")
		local foundRoot = rootPartOverride or character:FindFirstChild("HumanoidRootPart")
		if foundRoot and foundRoot:IsA("BasePart") then
			cachedRootPart = foundRoot
		else
			local awaited = character:WaitForChild("HumanoidRootPart", 5)
			cachedRootPart = if awaited and awaited:IsA("BasePart") then awaited else nil
		end

		for _, desc in character:GetDescendants() do
			onDescendantAdded(desc)
		end
		descendantAddedConn = character.DescendantAdded:Connect(onDescendantAdded)
		descendantRemovingConn = character.DescendantRemoving:Connect(onDescendantRemoving)
	else
		cachedHumanoid = nil
		cachedRootPart = nil
	end
end

function CharacterManager.Update(isFirstPerson: boolean, shouldRotateCharacter: boolean, lookVector: Vector3): ()
	if not currentCharacter then
		return
	end

	local humanoid = cachedHumanoid
	if humanoid and humanoid.AutoRotate == shouldRotateCharacter then
		humanoid.AutoRotate = not shouldRotateCharacter
	end

	if shouldRotateCharacter then
		local canRotate = not humanoid or (humanoid.Health > 0 and not humanoid.PlatformStand)
		local rootPart = cachedRootPart
		if canRotate and rootPart then
			local flatLook = Vector3.new(lookVector.X, 0, lookVector.Z)
			if flatLook.Magnitude > 1e-4 then
				flatLook = flatLook.Unit
				local right = Vector3.new(-flatLook.Z, 0, flatLook.X)
				local up = Vector3.new(0, 1, 0)
				rootPart.CFrame = CFrame.fromMatrix(rootPart.Position, right, up, -flatLook)
			end
		end
	end

	local targetTransparency = if isFirstPerson then 1 else 0
	if currentTransparencyState ~= targetTransparency then
		currentTransparencyState = targetTransparency
		for _, part in cachedParts do
			if not isToolPart[part] then
				part.LocalTransparencyModifier = targetTransparency
			end
		end
	end
end

return CharacterManager
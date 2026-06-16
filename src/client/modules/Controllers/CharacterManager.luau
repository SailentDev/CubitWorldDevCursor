--!strict
local CharacterManager = {}

local cachedParts: { BasePart } = {}
local isToolPart: { [BasePart]: boolean } = {} -- Szybki cache O(1) zapobiegający lagom

local descendantAddedConn: RBXScriptConnection?
local descendantRemovingConn: RBXScriptConnection?
local currentCharacter: Model?

-- Micro-optimization: File-level caches
local cachedHumanoid: Humanoid? = nil 
local cachedRootPart: BasePart? = nil

local function onDescendantAdded(descendant: Instance)
    if descendant:IsA("BasePart") and descendant.Name ~= "HumanoidRootPart" then
        local part = descendant :: BasePart
        table.insert(cachedParts, part)
        -- Szukamy Toolda TYLKO RAZ przy dodaniu części, oszczędzając masę CPU co klatkę
        isToolPart[part] = descendant:FindFirstAncestorOfClass("Tool") ~= nil
    end
end

local function onDescendantRemoving(descendant: Instance)
    if descendant:IsA("BasePart") then
        local part = descendant :: BasePart
        isToolPart[part] = nil -- Zapobieganie wyciekom pamięci
        
        local index = table.find(cachedParts, part)
        if index then
            local last = #cachedParts
            cachedParts[index] = cachedParts[last]
            cachedParts[last] = nil :: any
        end
    end
end

function CharacterManager.SetCharacter(character: Model?)
    if currentCharacter == character then return end
    currentCharacter = character
    
    if descendantAddedConn then descendantAddedConn:Disconnect() end
    if descendantRemovingConn then descendantRemovingConn:Disconnect() end
    table.clear(cachedParts)
    table.clear(isToolPart)
    
    if character then
        cachedHumanoid = character:FindFirstChildOfClass("Humanoid") :: Humanoid?
        cachedRootPart = character:WaitForChild("HumanoidRootPart", 5) :: BasePart?
        
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

function CharacterManager.Update(isFirstPerson: boolean, shouldRotateCharacter: boolean, lookVector: Vector3)
    if not currentCharacter then return end
    
    local humanoid = cachedHumanoid
    if humanoid and humanoid.AutoRotate == shouldRotateCharacter then
        humanoid.AutoRotate = not shouldRotateCharacter
    end
    
    if shouldRotateCharacter then
        local rootPart = cachedRootPart
        if rootPart then
            local flatLook = Vector3.new(lookVector.X, 0, lookVector.Z)
            if flatLook.Magnitude > 1e-4 then
                flatLook = flatLook.Unit
                -- Wysoce zoptymalizowana macierz rotacji (pomija lookAt)
                local right = Vector3.new(-flatLook.Z, 0, flatLook.X)
                local up = Vector3.new(0, 1, 0)
                rootPart.CFrame = CFrame.fromMatrix(rootPart.Position, right, up, -flatLook)
            end
        end
    end
    
    -- Pętla wymuszona przez silnik Roblox co klatkę, ale z błyskawicznym odczytem ze słownika
    local transparency = isFirstPerson and 1 or 0
    for i = 1, #cachedParts do
        local part = cachedParts[i]
        if not isToolPart[part] then 
            part.LocalTransparencyModifier = transparency
        end
    end
end

return CharacterManager
--!strict
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Shared = ReplicatedStorage:WaitForChild("Shared")
local Types = require(Shared:WaitForChild("Types") :: ModuleScript)

local PetDatabase = {}

local Database: { [string]: Types.PetInfo } = {
	["Dog"] = {
		Name = "Dog",
		Rarity = "Common",
		BaseDamage = 10,
		BaseHp = 100,
		IconId = "rbxassetid://18635593259",
		IconOffset = Vector2.new(0, 0),
		IconSize = Vector2.new(150, 150),
	},
	["Pyrodon"] = {
		Name = "Pyrodon",
		Rarity = "Mythical",
		BaseDamage = 250,
		BaseHp = 1500,
		IconId = "rbxassetid://18635593999",
		IconOffset = Vector2.new(0, 0),
		IconSize = Vector2.new(150, 150),
	},
}

function PetDatabase.GetPetInfo(id: string): Types.PetInfo?
	return Database[id]
end

return PetDatabase
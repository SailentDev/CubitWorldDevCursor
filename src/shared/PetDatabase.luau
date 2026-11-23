--!strict
local Types = require(script.Parent.Types)

local PetDatabase = {}

local Database: { [string]: Types.PetInfo } = {
	Dog = table.freeze({
		Name = "Dog",
		Rarity = "Common" :: Types.PetRarity,
		BaseDamage = 10,
		BaseHp = 100,
		Element = "Water" :: Types.PetElement,
		IconId = "rbxassetid://18635593259",
		IconOffset = Vector2.new(0, 0),
		IconSize = Vector2.new(150, 150),
	}),
	Pyrodon = table.freeze({
		Name = "Pyrodon",
		Rarity = "Mythical" :: Types.PetRarity,
		BaseDamage = 250,
		BaseHp = 1500,
		Element = "Fire" :: Types.PetElement,
		IconId = "rbxassetid://18635593999",
		IconOffset = Vector2.new(0, 0),
		IconSize = Vector2.new(150, 150),
	}),
}

table.freeze(Database)

function PetDatabase.GetPetInfo(id: string): Types.PetInfo?
	return Database[id]
end

function PetDatabase.GetAllPets(): { [string]: Types.PetInfo }
	return Database
end

return PetDatabase
--!strict
local Types = require(script.Parent.Types)

local EggDatabase = {}

local Database: { [string]: Types.EggInfo } = {
	OriginEgg = table.freeze({
		Name = "Origin Egg",
		Price = 500,
		CurrencyType = "Coins" :: Types.CurrencyType,
		LayoutOrder = 1,
		DropChances = table.freeze({
			Dog = 50.0,
			Pyrodon = 50.0,
		}),
	}),
}

table.freeze(Database)

function EggDatabase.GetEggInfo(id: string): Types.EggInfo?
	return Database[id]
end

function EggDatabase.GetAllEggs(): { [string]: Types.EggInfo }
	return Database
end

return EggDatabase
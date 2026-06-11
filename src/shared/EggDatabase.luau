--!strict
local EggDatabase = {}

export type EggInfo = {
	Name: string,
	Price: number,
	CurrencyType: string,
	DropChances: { [string]: number }
}

local Database: { [string]: EggInfo } = {
	["OriginEgg"] = {
		Name = "Origin Egg",
		Price = 500, 
		CurrencyType = "Coins", 
		DropChances = {
			["Dog"] = 99.0,      
			["Pyrodon"] = 1.0,   
		}
	},
}

function EggDatabase.GetEggInfo(id: string): EggInfo?
	print("[DATABASE] Zapytanie o dane jajka o ID: " .. tostring(id))
	local info = Database[id]
	if not info then
		warn("[DATABASE] Nie znaleziono jajka o ID: " .. tostring(id))
	end
	return info
end

function EggDatabase.GetAllEggs(): { [string]: EggInfo }
	print("[DATABASE] Pobranie całej bazy danych jajek.")
	return Database
end

return EggDatabase
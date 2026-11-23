--!strict
local Types = require(script.Parent.Types)

local PetStats = {}

function PetStats.GetLevelMultiplier(level: number): number
	if typeof(level) ~= "number" or level ~= level then
		return 1
	end
	local safeLevel = math.max(1, math.floor(level))
	return 1 + (safeLevel - 1) * 0.1
end

function PetStats.GetDamage(info: Types.PetInfo, level: number): number
	return math.round(info.BaseDamage * PetStats.GetLevelMultiplier(level))
end

function PetStats.GetHp(info: Types.PetInfo, level: number): number
	return math.round(info.BaseHp * PetStats.GetLevelMultiplier(level))
end

return PetStats
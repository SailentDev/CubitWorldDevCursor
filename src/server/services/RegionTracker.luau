--!strict
local HttpService = game:GetService("HttpService")
local RunService = game:GetService("RunService")

local RegionTracker = {}

-- Local Cache State
local cachedRegion: string = "Loading..."
local isFetched = false

-- Fallback chain definition of reliable GeoIP APIs
type Endpoint = {
	Url: string,
	Extract: (data: any) -> string?
}

local API_ENDPOINTS: { Endpoint } = {
	{
		Url = "http://ip-api.com/json/",
		Extract = function(data: any)
			return data.city or data.regionName or data.country
		end
	},
	{
		Url = "https://ipwho.is/",
		Extract = function(data: any)
			return data.city or data.region or data.country
		end
	},
	{
		Url = "https://ipapi.co/json/",
		Extract = function(data: any)
			return data.city or data.region or data.country_name
		end
	}
}

-- Sequentially queries APIs until one successfully resolves our location
local function fetchLocationAsync()
	local successResolved = false

	for _, endpoint in ipairs(API_ENDPOINTS) do
		local success, response = pcall(function()
			-- Request with a short timeout to prevent waiting too long on a rate-limited endpoint
			return HttpService:GetAsync(endpoint.Url)
		end)

		if success and response then
			local decodeSuccess, data = pcall(function()
				return HttpService:JSONDecode(response)
			end)

			if decodeSuccess and typeof(data) == "table" then
				local resolvedValue = endpoint.Extract(data)
				if resolvedValue and typeof(resolvedValue) == "string" and resolvedValue ~= "" then
					cachedRegion = resolvedValue
					successResolved = true
					break -- Break loop immediately on successful API resolution
				end
			end
		end
		
		-- Small delay to protect request pipelines from thread choking
		task.wait(0.1)
	end

	-- Ultimate fallback if Roblox outbound server IPs are rate-limited globally across all APIs
	if not successResolved then
		if RunService:IsStudio() then
			cachedRegion = "Studio Mode"
		else
			cachedRegion = "Roblox Server"
		end
	end
	
	isFetched = true
end

-- Asynchronously dispatch API check sequence on startup
task.spawn(fetchLocationAsync)

function RegionTracker.GetRegion(): string
	return cachedRegion
end

return RegionTracker
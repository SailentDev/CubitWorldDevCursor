--!strict
local HttpService = game:GetService("HttpService")
local RunService = game:GetService("RunService")

local RegionTracker = {}

type RegionResolvedCallback = (region: string) -> ()

type Endpoint = {
	Url: string,
	Extract: (data: { [string]: unknown }) -> string?,
}

local cachedRegion: string = "Loading..."
local isResolved = false
local resolvedCallbacks: { RegionResolvedCallback } = {}

local function extractStringField(data: { [string]: unknown }, keys: { string }): string?
	for _, key in keys do
		local value = data[key]
		if typeof(value) == "string" and #value > 0 then
			return value
		end
	end
	return nil
end

local API_ENDPOINTS: { Endpoint } = {
	{
		Url = "https://ipwho.is/",
		Extract = function(data: { [string]: unknown }): string?
			return extractStringField(data, { "country", "region", "city" })
		end,
	},
	{
		Url = "https://ipapi.co/json/",
		Extract = function(data: { [string]: unknown }): string?
			return extractStringField(data, { "country_name", "region", "city" })
		end,
	},
	{
		Url = "http://ip-api.com/json/",
		Extract = function(data: { [string]: unknown }): string?
			return extractStringField(data, { "country", "regionName", "city" })
		end,
	},
}

local function notifyResolved(region: string): ()
	for _, callback in resolvedCallbacks do
		task.spawn(callback, region)
	end
	table.clear(resolvedCallbacks)
end

local function fetchLocationAsync(): ()
	local successResolved = false

	for _, endpoint in API_ENDPOINTS do
		local success, response = pcall(function(): string
			return HttpService:GetAsync(endpoint.Url)
		end)

		if success and typeof(response) == "string" then
			local decodeSuccess, decoded = pcall(function(): unknown
				return HttpService:JSONDecode(response)
			end)

			if decodeSuccess and typeof(decoded) == "table" then
				local resolvedValue = endpoint.Extract(decoded :: { [string]: unknown })
				if resolvedValue then
					cachedRegion = resolvedValue
					successResolved = true
					break
				end
			end
		end

		task.wait(0.1)
	end

	if not successResolved then
		cachedRegion = if RunService:IsStudio() then "Studio Mode" else "Roblox Server"
	end

	isResolved = true
	notifyResolved(cachedRegion)
end

function RegionTracker.GetRegion(): string
	return cachedRegion
end

function RegionTracker.OnRegionResolved(callback: RegionResolvedCallback): ()
	if isResolved then
		task.spawn(callback, cachedRegion)
		return
	end
	table.insert(resolvedCallbacks, callback)
end

function RegionTracker.OnInit(): ()
end

function RegionTracker.OnStart(): ()
	task.spawn(fetchLocationAsync)
end

return RegionTracker
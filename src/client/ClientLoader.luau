--!strict
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Blink = require(ReplicatedStorage.Shared.Blink.network_client)

local starterPlayerScripts = script.Parent :: Instance
local modulesFolder = starterPlayerScripts:WaitForChild("modules") :: Folder
local uiFolder = modulesFolder:WaitForChild("ui") :: Folder
local inventoryFolder = modulesFolder:WaitForChild("Inventory") :: Folder
local optimizationFolder = starterPlayerScripts:WaitForChild("Optimization") :: Folder

local ClientLoader = {}

type ClientModule = {
	OnInit: (() -> ())?,
	OnStart: (() -> ())?,
}

type LoadedModule = {
	name: string,
	module: ClientModule,
}

local MODULE_PRIORITY: { [string]: number } = {
	StatisticsTracker = 1,
	SettingsClient = 2,
	CurrencyClient = 3,
	UIManager = 4,
	PetClient = 5,
	EggController = 6,
	InventoryClient = 7,
	ClientOptimization = 8,
}

local function getModulePriority(name: string): number
	return MODULE_PRIORITY[name] or 100
end

local function collectModuleScripts(container: Folder, list: { ModuleScript }): ()
	for _, child in container:GetChildren() do
		if child:IsA("ModuleScript") then
			table.insert(list, child)
		end
	end
end

function ClientLoader.Boot(): ()
	local startTime = os.clock()
	local modulesToLoad: { ModuleScript } = {}

	collectModuleScripts(modulesFolder, modulesToLoad)
	collectModuleScripts(uiFolder, modulesToLoad)
	collectModuleScripts(inventoryFolder, modulesToLoad)
	collectModuleScripts(optimizationFolder, modulesToLoad)

	table.sort(modulesToLoad, function(a: ModuleScript, b: ModuleScript): boolean
		local pa = getModulePriority(a.Name)
		local pb = getModulePriority(b.Name)
		if pa ~= pb then
			return pa < pb
		end
		return a.Name < b.Name
	end)

	local initializedModules: { LoadedModule } = {}

	print("==================================================")
	print("[CLIENT BOOT] Starting Cubit World client modules...")
	print("==================================================")

	-- Phase 1: Synchronous OnInit
	for _, moduleScript in modulesToLoad do
		local requireSuccess, result = pcall(require, moduleScript)
		if not requireSuccess then
			warn(`[CLIENT REQUIRE ERROR] Failed to load '{moduleScript.Name}': {tostring(result)}`)
			continue
		end

		if typeof(result) ~= "table" then
			warn(`[CLIENT WARN] Module '{moduleScript.Name}' did not return a table.`)
			continue
		end

		local clientModule = result :: ClientModule
		local initFn = clientModule.OnInit

		if typeof(initFn) == "function" then
			local initSuccess, initErr = pcall(initFn)
			if initSuccess then
				print(`  [OnInit] {moduleScript.Name}`)
				table.insert(initializedModules, {
					name = moduleScript.Name,
					module = clientModule,
				})
			else
				warn(`  [OnInit Error] '{moduleScript.Name}': {tostring(initErr)}`)
			end
		else
			table.insert(initializedModules, {
				name = moduleScript.Name,
				module = clientModule,
			})
		end
	end

	-- Phase 2: Parallel OnStart with completion barrier before InitialSync
	local pendingStartCount = 0
	for _, entry in initializedModules do
		local onStartFn = entry.module.OnStart
		if typeof(onStartFn) == "function" then
			pendingStartCount += 1
			task.spawn(function()
				local startSuccess, startErr = pcall(onStartFn)
				if startSuccess then
					print(`  [OnStart] {entry.name}`)
				else
					warn(`  [OnStart Error] '{entry.name}': {tostring(startErr)}`)
				end
				pendingStartCount -= 1
			end)
		end
	end

	local waitDeadline = os.clock() + 10
	while pendingStartCount > 0 and os.clock() < waitDeadline do
		task.wait()
	end

	-- Fire initial sync only after all client Blink listeners are active
	Blink.RequestInitialSync.Fire()

	local totalMs = math.round((os.clock() - startTime) * 1000)
	print("==================================================")
	print(`[CLIENT READY] Boot completed in {totalMs}ms`)
	print("==================================================")
end

return ClientLoader
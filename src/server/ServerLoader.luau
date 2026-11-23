--!strict
local ServerScriptService = game:GetService("ServerScriptService")

local servicesFolder = ServerScriptService:WaitForChild("services") :: Folder

local ServerLoader = {}

type ServerModule = {
	OnInit: (() -> ())?,
	OnStart: (() -> ())?,
}

type LoadedService = {
	name: string,
	module: ServerModule,
}

local INIT_TIMEOUT_SECONDS = 10

local SERVICE_PRIORITY: { [string]: number } = {
	RegionTracker = 1,
	DataManager = 2,
	CurrencyService = 3,
	SettingsServer = 4,
	InventoryService = 5,
	PetService = 6,
	EggService = 7,
	ServerOptimization = 8,
}

local function traceError(err: unknown): string
	return debug.traceback(tostring(err), 2)
end

local function runInitWithTimeout(moduleName: string, initFn: () -> ()): boolean
	local finished = false
	local timedOut = false
	local succeeded = false
	local callerThread = coroutine.running()

	local workerThread = task.spawn(function()
		local ok, err = xpcall(initFn, traceError)
		if timedOut then
			return
		end
		finished = true
		succeeded = ok
		if not ok then
			warn(`[INIT ERROR] '{moduleName}.OnInit' failed: {tostring(err)}`)
		end
		if coroutine.status(callerThread) == "suspended" then
			task.spawn(callerThread)
		end
	end)

	if finished then
		return succeeded
	end

	local timeoutThread = task.delay(INIT_TIMEOUT_SECONDS, function()
		if finished then
			return
		end
		timedOut = true
		warn(`[INIT TIMEOUT] '{moduleName}.OnInit' exceeded {INIT_TIMEOUT_SECONDS}s; continuing boot.`)
		pcall(task.cancel, workerThread)
		if coroutine.status(callerThread) == "suspended" then
			task.spawn(callerThread)
		end
	end)

	coroutine.yield()

	if not timedOut then
		pcall(task.cancel, timeoutThread)
	end

	return finished and succeeded
end

local function getServicePriority(name: string): number
	return SERVICE_PRIORITY[name] or 100
end

function ServerLoader.Boot(): ()
	local startTime = os.clock()
	local moduleScripts: { ModuleScript } = {}

	for _, instance in servicesFolder:GetChildren() do
		if instance:IsA("ModuleScript") then
			table.insert(moduleScripts, instance)
		end
	end

	table.sort(moduleScripts, function(a: ModuleScript, b: ModuleScript): boolean
		local pa = getServicePriority(a.Name)
		local pb = getServicePriority(b.Name)
		if pa ~= pb then
			return pa < pb
		end
		return a.Name < b.Name
	end)

	local initializedModules: { LoadedService } = {}

	print("==================================================")
	print("[SERVER BOOT] Starting Cubit World core services...")
	print("==================================================")

	-- Phase 1: Synchronous OnInit with timeout guard
	for _, moduleScript in moduleScripts do
		local requireSuccess, result = xpcall(require, traceError, moduleScript)
		if not requireSuccess then
			warn(`[CRITICAL REQUIRE ERROR] Failed to require '{moduleScript.Name}': {tostring(result)}`)
			continue
		end

		if typeof(result) ~= "table" then
			warn(`[BOOT WARN] Module '{moduleScript.Name}' did not return a table. Skipping.`)
			continue
		end

		local serverModule = result :: ServerModule
		local initFn = serverModule.OnInit

		if typeof(initFn) == "function" then
			local initSuccess = runInitWithTimeout(moduleScript.Name, initFn)
			if initSuccess then
				print(`[INIT] Ready: {moduleScript.Name}`)
				table.insert(initializedModules, {
					name = moduleScript.Name,
					module = serverModule,
				})
			end
		else
			table.insert(initializedModules, {
				name = moduleScript.Name,
				module = serverModule,
			})
		end
	end

	-- Phase 2: Asynchronous OnStart (only for modules that passed OnInit)
	for _, entry in initializedModules do
		local onStartFn = entry.module.OnStart
		if typeof(onStartFn) == "function" then
			task.spawn(function()
				local startSuccess, startError = xpcall(onStartFn, traceError)
				if not startSuccess then
					warn(`[RUNTIME ERROR] '{entry.name}.OnStart' failed: {tostring(startError)}`)
				end
			end)
		end
	end

	local totalMs = math.round((os.clock() - startTime) * 1000)
	print("==================================================")
	print(`[SERVER READY] Server booted in {totalMs}ms`)
	print("==================================================")
end

return ServerLoader
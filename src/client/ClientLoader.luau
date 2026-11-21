--!strict
local StarterPlayerScripts = script.Parent
local modulesFolder = StarterPlayerScripts:WaitForChild("modules") :: Folder
local uiFolder = modulesFolder:WaitForChild("ui") :: Folder
local inventoryFolder = modulesFolder:WaitForChild("Inventory") :: Folder
local optimizationFolder = StarterPlayerScripts:WaitForChild("Optimization") :: Folder -- DODANE

local ClientLoader = {}

type ClientModule = {
	OnInit: (() -> ())?,
	OnStart: (() -> ())?,
	[any]: any
}

function ClientLoader.Boot()
	local startTime = os.clock()
	local modulesToLoad: {ModuleScript} = {}
	
	local loadedModules: { [string]: ClientModule } = {}
	local moduleNamesOrder: {string} = {}

	print("==================================================")
	print("[⚡ CLIENT BOOT] Uruchamianie dwufazowego loadera Cubit World...")
	print("==================================================")

	-- 1. Zbierz moduły bezpośrednio z folderu 'modules'
	for _, child in modulesFolder:GetChildren() do
		if child:IsA("ModuleScript") then
			table.insert(modulesToLoad, child)
		end
	end

	-- 2. Zbierz moduły z subfolderu 'ui'
	for _, child in uiFolder:GetChildren() do
		if child:IsA("ModuleScript") then
			table.insert(modulesToLoad, child)
		end
	end
	
	-- 3. Zbierz moduły z subfolderu 'Inventory'
	for _, child in inventoryFolder:GetChildren() do
		if child:IsA("ModuleScript") then
			table.insert(modulesToLoad, child)
		end
	end

	-- 4. Zbierz moduły z folderu 'Optimization' (NOWOŚĆ)
	-- To załaduje TYLKO 'ClientOptimization', a zignoruje LocalScripts!
	for _, child in optimizationFolder:GetChildren() do
		if child:IsA("ModuleScript") then
			table.insert(modulesToLoad, child)
		end
	end

	-- Bezpieczne wykonanie require i rejestracja
	for _, moduleScript in modulesToLoad do
		local requireSuccess, module = pcall(require, moduleScript)

		if not requireSuccess then
			warn(`[❌ CLIENT REQUIRE ERROR] Nie można załadować: '{moduleScript.Name}'! Powód: {module}`)
			continue
		end

		if type(module) == "table" then
			loadedModules[moduleScript.Name] = module :: ClientModule
			table.insert(moduleNamesOrder, moduleScript.Name)
		else
			warn(`[⚠️ CLIENT WARN] Moduł '{moduleScript.Name}' nie zwraca tabeli danych.`)
		end
	end

	-- FAZA 1: OnInit
	print("[🔄 CLIENT PHASE 1] Uruchamianie fazy OnInit...")
	for _, name in moduleNamesOrder do
		local module = loadedModules[name]
		if type(module.OnInit) == "function" then
			local success, err = pcall(function(): any
				return module.OnInit()
			end)
			if success then
				print(`  ✔️ {name} -> zainicjalizowany (OnInit)`)
			else
				warn(`  ❌ [OnInit Error] W module '{name}': {err}`)
			end
		end
	end

	-- FAZA 2: OnStart
	print("[🔄 CLIENT PHASE 2] Uruchamianie fazy OnStart...")
	for _, name in moduleNamesOrder do
		local module = loadedModules[name]
		if type(module.OnStart) == "function" then
			task.spawn(function()
				local success, err = pcall(function(): any
					return module.OnStart()
				end)
				if success then
					print(`  ✔️ {name} -> wystartowany (OnStart)`)
				else
					warn(`  ❌ [OnStart Error] W module '{name}': {err}`)
				end
			end)
		end
	end

	local totalTime = math.round((os.clock() - startTime) * 1000)
	print("==================================================")
	print(`[🚀 CLIENT READY] Dwufazowy boot zakończony sukcesem! Czas: {totalTime}ms`)
	print("==================================================")
end

return ClientLoader
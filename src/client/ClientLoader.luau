--!strict
local StarterPlayerScripts = script.Parent
local modulesFolder = StarterPlayerScripts:WaitForChild("modules") :: Folder
local uiFolder = modulesFolder:WaitForChild("ui") :: Folder

local ClientLoader = {}

-- NOWY KONTRAKT: Moduły klienta używają teraz OnInit i OnStart zamiast starego init
type ClientModule = {
	OnInit: (() -> ())?,
	OnStart: (() -> ())?,
	[any]: any
}

function ClientLoader.Boot()
	local startTime = os.clock()
	local modulesToLoad: {ModuleScript} = {}
	
	-- Słownik przechowujący załadowane moduły i tablica zachowująca kolejność logowania
	local loadedModules: { [string]: ClientModule } = {}
	local moduleNamesOrder: {string} = {}

	print("==================================================")
	print("[⚡ CLIENT BOOT] Uruchamianie dwufazowego loadera Cubit World...")
	print("==================================================")

	-- 1. Zbierz moduły bezpośrednio z folderu 'modules' (ignoruje folder controllers)
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

	-- 3. Bezpieczne wykonanie require i rejestracja modułów w pamięci
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

	-- ==================================================
	-- FAZA 1: OnInit (Alokacja, przygotowanie zmiennych i eventów UI)
	-- ==================================================
	print("[🔄 CLIENT PHASE 1] Uruchamianie fazy OnInit...")
	for _, name in moduleNamesOrder do
		local module = loadedModules[name]
		if type(module.OnInit) == "function" then
			local success, err = pcall(module.OnInit)
			if success then
				print(`  ✔️ {name} -> zainicjalizowany (OnInit)`)
			else
				warn(`  ❌ [OnInit Error] W module '{name}': {err}`)
			end
		end
	end

	-- ==================================================
	-- FAZA 2: OnStart (Komunikacja między modułami, Blink, pełna gotowość)
	-- ==================================================
	print("[🔄 CLIENT PHASE 2] Uruchamianie fazy OnStart...")
for _, name in moduleNamesOrder do
	local module = loadedModules[name]
	if type(module.OnStart) == "function" then
		task.spawn(function()
			local success, err = pcall(module.OnStart)
			if success then
				print(`  ✔️ {name} -> wystartowany (OnStart)`)
			else
				warn(`  ❌ [OnStart Error] W module '{name}': {err}`)
			end
		end)
	end
end

	-- Podsumowanie działania
	local totalTime = math.round((os.clock() - startTime) * 1000)
	print("==================================================")
	print(`[🚀 CLIENT READY] Dwufazowy boot zakończony sukcesem! Czas: {totalTime}ms`)
	print("==================================================")
end

return ClientLoader
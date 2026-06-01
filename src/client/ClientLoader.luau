--!strict
local StarterPlayerScripts = script.Parent
local modulesFolder = StarterPlayerScripts:WaitForChild("modules") :: Folder
local uiFolder = modulesFolder:WaitForChild("ui") :: Folder

local ClientLoader = {}

-- Definicja kontraktu Luau dla modułów klienckich
type ClientModule = {
	init: (() -> ())?,
	[any]: any
}

function ClientLoader.Boot()
	local startTime = os.clock()
	local modulesToLoad: {ModuleScript} = {}

	print("==================================================")
	print("[⚡ CLIENT BOOT] Uruchamianie loadera Cubit World...")
	print("==================================================")

	-- 1. Zbierz moduły bezpośrednio z folderu 'modules'
	-- Ignoruje podfoldery, dzięki czemu folder 'controllers' zostanie całkowicie pominięty!
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

	-- 3. Bezpieczna pętla uruchamiająca zebrane systemy
	for _, moduleScript in modulesToLoad do
		local requireSuccess, module = pcall(require, moduleScript)

		if not requireSuccess then
			warn(`[❌ CLIENT REQUIRE ERROR] Nie można załadować: '{moduleScript.Name}'! Powód: {module}`)
			continue
		end

		if type(module) == "table" then
			local castedModule = module :: ClientModule
			
			-- Bezpieczne wywołanie Twojej dotychczasowej funkcji init()
			if type(castedModule.init) == "function" then
				local initSuccess, initError = pcall(castedModule.init)
				if initSuccess then
					print(`[🖥️ CLIENT INIT] Uruchomiono moduł: {moduleScript.Name}`)
				else
					warn(`[❌ CLIENT INIT ERROR] Wyjątek w init() modułu '{moduleScript.Name}': {initError}`)
				end
			end
		else
			warn(`[⚠️ CLIENT WARN] Moduł '{moduleScript.Name}' nie zwraca tabeli danych.`)
		end
	end

	-- Podsumowanie wydajnościowe ładowania interfejsów
	local totalTime = math.round((os.clock() - startTime) * 1000)
	print("==================================================")
	print(`[🚀 CLIENT READY] Systemy klienta stabilne. Gotowość w: {totalTime}ms`)
	print("==================================================")
end

return ClientLoader
--!strict
local ServerScriptService = game:GetService("ServerScriptService")
local servicesFolder = ServerScriptService:WaitForChild("services")

local ServerLoader = {}

-- Inteligentne otypowanie kontraktu dla modułów serwerowych
type ServerModule = {
	OnInit: (() -> ())?,
	OnStart: (() -> ())?,
	[any]: any
}

function ServerLoader.Boot()
	local startTime = os.clock()
	local initializedModules: {ServerModule} = {}
	
	print("==================================================")
	print("[⚡ SERVER BOOT] Uruchamianie centralnego silnika Cubit World...")
	print("==================================================")

	-- =======================================================
	-- FAZA 1: OnInit (Synchroniczna inicjalizacja stanów i eventów)
	-- =======================================================
	for _, instance in servicesFolder:GetChildren() do
		if not instance:IsA("ModuleScript") then continue end
		
		-- Bezpieczne sprawdzanie poprawności kodu wewnątrz modułu
		local requireSuccess, module = pcall(require, instance)
		
		if not requireSuccess then
			warn(`[❌ CRITICAL REQUIRE ERROR] Nie można załadować modułu '{instance.Name}'! Powód: {module}`)
			continue
		end
		
		if type(module) == "table" then
			table.insert(initializedModules, module :: ServerModule)
			
			-- Jeśli moduł posiada funkcję OnInit, wykonujemy ją synchronicznie
			if type(module.OnInit) == "function" then
				local initSuccess, initError = pcall(module.OnInit)
				if initSuccess then
					print(`[⚙️ INIT] Pomyślnie przygotowano: {instance.Name}`)
				else
					warn(`[❌ INIT ERROR] Błąd podczas OnInit w module '{instance.Name}': {initError}`)
				end
			end
		else
			warn(`[⚠️ BOOT WARN] Moduł '{instance.Name}' nie zwraca tabeli. Pomijam cykl życia loader'a.`)
		end
	end

	-- =======================================================
	-- FAZA 2: OnStart (Asynchroniczne odpalenie głównej logiki i Blink)
	-- =======================================================
	for _, module in initializedModules do
		if type(module.OnStart) == "function" then
			-- Odpalamy w osobnym wątku, by pętle/eventy jednego modułu nie blokowały kolejnych
			task.spawn(function()
				local startSuccess, startError = pcall(module.OnStart)
				if not startSuccess then
					warn(`[❌ RUNTIME ERROR] Krytyczny błąd wykonania w fazie OnStart: {startError}`)
				end
			end)
		end
	end

	-- Podsumowanie wydajnościowe bootowania serwera
	local totalTime = math.round((os.clock() - startTime) * 1000)
	print("==================================================")
	print(`[🚀 SERVER READY] Wszystkie systemy stabilne. Gotowość w: {totalTime}ms`)
	print("==================================================")
end

return ServerLoader